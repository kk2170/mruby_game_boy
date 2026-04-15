module GameBoy
  class DMA
    TRANSFER_DOTS = 640
    BYTES_PER_TRANSFER = 0x00A0
    DOTS_PER_BYTE = 4

    def initialize(ppu)
      @ppu = ppu
      reset
    end

    def reset
      @last_source_high = 0xFF
      @source = 0xFF00
      @elapsed_dots = 0
      @bytes_copied = 0
      @bus = nil
    end

    def load_boot_state(source_high, remaining_dots)
      @last_source_high = source_high & 0xFF
      @source = @last_source_high << 8
      @elapsed_dots = remaining_dots > TRANSFER_DOTS ? TRANSFER_DOTS : remaining_dots
      @bytes_copied = [@elapsed_dots / DOTS_PER_BYTE, BYTES_PER_TRANSFER].min
      @bus = nil
    end

    def start(high_byte, bus)
      # OAM DMA は 160 byte を 4 dot ごとに 1 byte ずつ進める。
      # ここでは即時コピーせず、tick に応じて順次 OAM を更新する。
      @last_source_high = high_byte & 0xFF
      @source = @last_source_high << 8
      @elapsed_dots = 0
      @bytes_copied = 0
      @bus = bus
    end

    def tick(dots)
      return unless active?

      @elapsed_dots += dots
      @elapsed_dots = TRANSFER_DOTS if @elapsed_dots > TRANSFER_DOTS

      target_bytes = @elapsed_dots / DOTS_PER_BYTE
      while @bytes_copied < target_bytes && @bytes_copied < BYTES_PER_TRANSFER
        addr = (@source + @bytes_copied) & 0xFFFF
        @ppu.write_oam(0xFE00 + @bytes_copied, @bus.read_dma_source8(addr))
        @bytes_copied += 1
      end

      @bus = nil unless active?
    end

    def active?
      !@bus.nil? && @elapsed_dots < TRANSFER_DOTS
    end

    def read_io(addr)
      addr == 0xFF46 ? @last_source_high : 0xFF
    end
  end
end
