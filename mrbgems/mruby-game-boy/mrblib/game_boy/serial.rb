module GameBoy
  class Serial
    TRANSFER_DOTS = 4096

    def initialize(interrupts)
      @interrupts = interrupts
      reset
    end

    def reset
      @sb = 0x00
      @sc = 0x00
      @transfer_counter_dots = 0
    end

    def load_boot_state(sb, sc)
      @sb = sb & 0xFF
      @sc = sc & 0x81
      @transfer_counter_dots = 0
    end

    def tick(dots)
      return unless @sc == 0x81

      @transfer_counter_dots += dots
      return if @transfer_counter_dots < TRANSFER_DOTS

      @transfer_counter_dots = 0
      @sb = 0xFF
      @sc &= 0x01
      @interrupts.request(Constants::INT_SERIAL)
    end

    def read_io(addr)
      case addr
      when 0xFF01 then @sb
      when 0xFF02 then 0x7E | (@sc & 0x81)
      else 0xFF
      end
    end

    def write_io(addr, value)
      value &= 0xFF

      case addr
      when 0xFF01
        @sb = value
      when 0xFF02
        @sc = value & 0x81
        @transfer_counter_dots = 0
      end

      value
    end
  end
end
