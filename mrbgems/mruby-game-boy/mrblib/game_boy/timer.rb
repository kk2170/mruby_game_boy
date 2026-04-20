module GameBoy
  class Timer
    OVERFLOW_RELOAD_DELAY_DOTS = 4

    def initialize(interrupts)
      @interrupts = interrupts
      reset
    end

    def reset
      @divider = 0
      @tima = 0
      @tma = 0
      @tac = 0
      @overflow_reload_delay = nil
    end

    def load_boot_state(divider, tima, tma, tac)
      @divider = if divider > 0xFF
                   divider & 0xFFFF
                 else
                   (divider & 0xFF) << 8
                 end
      @tima = tima & 0xFF
      @tma = tma & 0xFF
      @tac = tac & 0xFF
      @overflow_reload_delay = nil
    end

    def tick(dots)
      while dots > 0
        process_pending_reload
        previous_input = timer_input_high?
        @divider = (@divider + 1) & 0xFFFF
        increment_tima_on_falling_edge(previous_input)
        dots -= 1
      end
    end

    def read_io(addr)
      case addr
      when 0xFF04 then (@divider >> 8) & 0xFF
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
        previous_input = timer_input_high?
        @divider = 0
        increment_tima_on_falling_edge(previous_input)
      when 0xFF05
        @tima = value
        @overflow_reload_delay = nil
      when 0xFF06
        @tma = value
      when 0xFF07
        previous_input = timer_input_high?
        @tac = 0xF8 | (value & 0x07)
        increment_tima_on_falling_edge(previous_input)
      end

      value
    end

    private

    def timer_enabled?
      (@tac & 0x04) != 0
    end

    def timer_input_high?
      return false unless timer_enabled?

      ((@divider >> divider_bit_index) & 0x01) != 0
    end

    def increment_tima_on_falling_edge(previous_input)
      increment_tima if previous_input && !timer_input_high?
    end

    def increment_tima
      if @tima == 0xFF
        @tima = 0x00
        @overflow_reload_delay = OVERFLOW_RELOAD_DELAY_DOTS
      else
        @tima = (@tima + 1) & 0xFF
      end
    end

    def process_pending_reload
      return unless @overflow_reload_delay

      @overflow_reload_delay -= 1
      return unless @overflow_reload_delay == 0

      @overflow_reload_delay = nil
      @tima = @tma
      @interrupts.request(Constants::INT_TIMER)
    end

    def divider_bit_index
      case @tac & 0x03
      when 0x00 then 9
      when 0x01 then 3
      when 0x02 then 5
      when 0x03 then 7
      else 9
      end
    end
  end
end
