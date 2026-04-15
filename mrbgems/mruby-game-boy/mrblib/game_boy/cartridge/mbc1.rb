module GameBoy
  module Cartridge
    class MBC1
      attr_reader :rom, :header

      def initialize(rom_bytes)
        # TobuTobuGirl は MBC1+RAM+BATTERY なので、最初の段階から
        # 最低限の MBC1 バンク切り替えを持っておく。
        @rom = rom_bytes
        @header = Cartridge.header(@rom)
        @rom_bank_count = [@header[:rom_size_bytes] / 0x4000, 1].max
        @ram_bank_count = [@header[:ram_size_bytes] / 0x2000, 1].max
        @ram = Array.new(@header[:ram_size_bytes], 0)

        reset_banks
      end

      def title
        @header[:title]
      end

      def read8(addr)
        addr &= 0xFFFF

        case addr
        when 0x0000..0x3FFF
          bank = lower_rom_bank
          Cartridge.byte_at(@rom, (bank * 0x4000) + addr) || 0xFF
        when 0x4000..0x7FFF
          bank = upper_rom_bank
          Cartridge.byte_at(@rom, (bank * 0x4000) + (addr - 0x4000)) || 0xFF
        when 0xA000..0xBFFF
          return 0xFF if @ram.empty? || !@ram_enabled

          ram_index = (ram_bank * 0x2000) + (addr - 0xA000)
          @ram[ram_index % @ram.length]
        else
          0xFF
        end
      end

      def write8(addr, value)
        addr &= 0xFFFF
        value &= 0xFF

        case addr
        when 0x0000..0x1FFF
          # 下位 nibble が 0xA のときだけ外部 RAM を有効化する。
          @ram_enabled = (value & 0x0F) == 0x0A
        when 0x2000..0x3FFF
          @rom_bank_low5 = value & 0x1F
          @rom_bank_low5 = 1 if @rom_bank_low5 == 0
        when 0x4000..0x5FFF
          @bank_high2 = value & 0x03
        when 0x6000..0x7FFF
          @mode = value & 0x01
        when 0xA000..0xBFFF
          if !@ram.empty? && @ram_enabled
            ram_index = (ram_bank * 0x2000) + (addr - 0xA000)
            @ram[ram_index % @ram.length] = value
          end
        end

        value
      end

      private

      def reset_banks
        @ram_enabled = false
        @rom_bank_low5 = 1
        @bank_high2 = 0
        @mode = 0
      end

      def lower_rom_bank
        return 0 unless advanced_banking? && @rom_bank_count > 32

        (@bank_high2 << 5) % @rom_bank_count
      end

      def upper_rom_bank
        # 4000-7FFF 側は mode 0 / mode 1 のどちらでも上位 2bit を使う。
        # mode 1 で変わるのは主に 0000-3FFF 側と RAM bank 側。
        bank = ((@bank_high2 << 5) | @rom_bank_low5) % @rom_bank_count
        bank = 1 if bank == 0 && @rom_bank_count > 1
        bank
      end

      def ram_bank
        return 0 unless advanced_banking? && @ram.length > 0x2000

        @bank_high2 % @ram_bank_count
      end

      def advanced_banking?
        @mode == 1
      end
    end
  end
end
