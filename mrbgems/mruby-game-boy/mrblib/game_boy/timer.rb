module GameBoy
  class Timer
    OVERFLOW_RELOAD_DELAY_DOTS = 4
    RELOAD_HOLD_DOTS = 4

    def initialize(interrupts)
      @interrupts = interrupts
      reset
    end

    def reset
      # DIV は 16bit の system counter 上位 8bit の見えている部分。
      # dot 単位で counter を進め、選択 bit の falling edge で TIMA を進める。
      @system_counter = 0
      @tima = 0
      @tma = 0
      @tac = 0
      @reload_delay_dots = 0
      @reload_hold_dots = 0
    end

    def load_boot_state(divider, tima, tma, tac)
      @system_counter = if divider > 0xFF
                          divider & 0xFFFF
                        else
                          (divider & 0xFF) << 8
                        end
      @tima = tima & 0xFF
      @tma = tma & 0xFF
      @tac = 0xF8 | (tac & 0x07)
      @reload_delay_dots = 0
      @reload_hold_dots = 0
    end

    def tick(dots)
      remaining = dots

      while remaining > 0
        advance_one_dot
        remaining -= 1
      end
    end

    def read_io(addr)
      case addr
      when 0xFF04 then div
      when 0xFF05 then @tima
      when 0xFF06 then @tma
      when 0xFF07 then 0xF8 | (@tac & 0x07)
      else 0xFF
      end
    end

    def write_io(addr, value)
      value &= 0xFF

      case addr
      when 0xFF04
        write_div
      when 0xFF05
        write_tima(value)
      when 0xFF06
        write_tma(value)
      when 0xFF07
        write_tac(value)
      end

      value
    end

    private

    def div
      (@system_counter >> 8) & 0xFF
    end

    def advance_one_dot
      old_timer_input = timer_input_high?
      @system_counter = (@system_counter + 1) & 0xFFFF
      detect_timer_falling_edge(old_timer_input, timer_input_high?)
      advance_reload_delay
    end

    def write_div
      old_timer_input = timer_input_high?
      @system_counter = 0
      detect_timer_falling_edge(old_timer_input, timer_input_high?)
    end

    def write_tac(value)
      old_timer_input = timer_input_high?
      @tac = 0xF8 | (value & 0x07)
      detect_timer_falling_edge(old_timer_input, timer_input_high?)
    end

    def detect_timer_falling_edge(old_input, new_input)
      timer_tick if old_input && !new_input
    end

    def timer_input_high?
      timer_enabled? && ((@system_counter & timer_bit_mask) != 0)
    end

    def timer_enabled?
      (@tac & 0x04) != 0
    end

    def timer_bit_mask
      1 << case @tac & 0x03
           when 0x00 then 9
           when 0x01 then 3
           when 0x02 then 5
           when 0x03 then 7
           else 9
           end
    end

    def timer_tick
      return if @reload_delay_dots > 0

      if @tima == 0xFF
        # 実機では overflow 直後の 1 M-cycle は TIMA=00 のままで、
        # その後に TMA がロードされて Timer interrupt が立つ。
        @tima = 0x00
        @reload_delay_dots = OVERFLOW_RELOAD_DELAY_DOTS
      else
        @tima = (@tima + 1) & 0xFF
      end
    end

    def advance_reload_delay
      if @reload_delay_dots > 0
        @reload_delay_dots -= 1
        return unless @reload_delay_dots == 0

        @tima = @tma
        @interrupts.request(Constants::INT_TIMER)
        @reload_hold_dots = RELOAD_HOLD_DOTS
      elsif @reload_hold_dots > 0
        @reload_hold_dots -= 1
      end
    end

    def write_tima(value)
      return if @reload_hold_dots > 0

      # Overflow 後の待機中に TIMA が書かれた場合は、reload と interrupt を打ち消す。
      @reload_delay_dots = 0
      @tima = value
    end

    def write_tma(value)
      @tma = value

      # Reload cycle B 中は TMA の書き換えが TIMA にも即時反映される。
      @tima = value if @reload_hold_dots > 0
    end
  end
end
