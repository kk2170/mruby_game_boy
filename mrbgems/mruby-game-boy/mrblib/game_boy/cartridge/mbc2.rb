module GameBoy
  module Cartridge
    class MBC2
      INTERNAL_RAM_SIZE = 0x0200

      attr_reader :rom, :header

      def initialize(rom_bytes)
        @rom = rom_bytes
        @header = Cartridge.header(@rom)
        @rom_bank_count = [@header[:rom_size_bytes] / 0x4000, 1].max
        @ram = Array.new(INTERNAL_RAM_SIZE, 0)

        reset
      end

      def title
        @header[:title]
      end

      def reset
        @ram_enabled = false
        @rom_bank = 1
      end

      def battery_backed?
        @header[:cartridge_type] == 0x06
      end

      def dump_battery_ram
        return nil unless battery_backed?

        @ram.dup
      end

      def load_battery_ram(bytes)
        return unless battery_backed?

        dump = Cartridge.normalize_bytes(bytes)
        index = 0

        while index < @ram.length
          @ram[index] = (Cartridge.byte_at(dump, index) || 0) & 0x0F
          index += 1
        end
      end

      def read8(addr)
        addr &= 0xFFFF

        case addr
        when 0x0000..0x3FFF
          Cartridge.byte_at(@rom, addr) || 0xFF
        when 0x4000..0x7FFF
          bank_addr = (selected_rom_bank * 0x4000) + (addr - 0x4000)
          Cartridge.byte_at(@rom, bank_addr) || 0xFF
        when 0xA000..0xBFFF
          return 0xFF unless @ram_enabled

          0xF0 | @ram[ram_index(addr)]
        else
          0xFF
        end
      end

      def write8(addr, value)
        addr &= 0xFFFF
        value &= 0xFF

        case addr
        when 0x0000..0x3FFF
          if (addr & 0x0100) == 0
            @ram_enabled = (value & 0x0F) == 0x0A
          else
            @rom_bank = value & 0x0F
            @rom_bank = 1 if @rom_bank == 0
          end
        when 0xA000..0xBFFF
          @ram[ram_index(addr)] = value & 0x0F if @ram_enabled
        end

        value
      end

      private

      def selected_rom_bank
        @rom_bank % @rom_bank_count
      end

      def ram_index(addr)
        (addr - 0xA000) & 0x01FF
      end
    end
  end
end
