module GameBoy
  class Timer
    def initialize(interrupts)
      @interrupts = interrupts
      reset
    end

    def reset
      @div = 0
      @tima = 0
      @tma = 0
      @tac = 0
      @div_counter_dots = 0
      @tima_counter_dots = 0
    end

    def load_boot_state(div, tima, tma, tac)
      @div = div & 0xFF
      @tima = tima & 0xFF
      @tma = tma & 0xFF
      @tac = tac & 0xFF
      @div_counter_dots = 0
      @tima_counter_dots = 0
    end

    def tick(dots)
      @div_counter_dots += dots

      while @div_counter_dots >= 256
        @div_counter_dots -= 256
        @div = (@div + 1) & 0xFF
      end

      return unless timer_enabled?

      @tima_counter_dots += dots
      period = tima_period_dots

      while @tima_counter_dots >= period
        @tima_counter_dots -= period

        if @tima == 0xFF
          @tima = @tma
          @interrupts.request(Constants::INT_TIMER)
        else
          @tima = (@tima + 1) & 0xFF
        end
      end
    end

    def read_io(addr)
      case addr
      when 0xFF04 then @div
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
        @div = 0
        @div_counter_dots = 0
      when 0xFF05
        @tima = value
      when 0xFF06
        @tma = value
      when 0xFF07
        @tac = 0xF8 | (value & 0x07)
        @tima_counter_dots = 0
      end

      value
    end

    private

    def timer_enabled?
      (@tac & 0x04) != 0
    end

    def tima_period_dots
      case @tac & 0x03
      when 0x00 then 1024
      when 0x01 then 16
      when 0x02 then 64
      when 0x03 then 256
      else 1024
      end
    end
  end
end
