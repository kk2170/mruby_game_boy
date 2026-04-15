module GameBoy
  class DMA
    def initialize(ppu)
      @ppu = ppu
      reset
    end

    def reset
      @last_source_high = 0xFF
      @remaining_dots = 0
    end

    def load_boot_state(source_high, remaining_dots)
      @last_source_high = source_high & 0xFF
      @remaining_dots = remaining_dots
    end

    def start(high_byte, bus)
      @last_source_high = high_byte & 0xFF
      source = @last_source_high << 8

      index = 0
      while index < 0x00A0
        @ppu.write_oam(0xFE00 + index, bus.read8((source + index) & 0xFFFF))
        index += 1
      end

      @remaining_dots = 640
    end

    def tick(dots)
      return unless @remaining_dots > 0

      @remaining_dots -= dots
      @remaining_dots = 0 if @remaining_dots < 0
    end

    def active?
      @remaining_dots > 0
    end

    def read_io(addr)
      addr == 0xFF46 ? @last_source_high : 0xFF
    end
  end
end
