module GameBoy
  module Cartridge
    class RomOnly
      attr_reader :rom, :header

      def initialize(rom_bytes)
        @rom = rom_bytes
        @header = Cartridge.header(@rom)
        ram_size = @header[:ram_size_bytes]
        @ram = Array.new(ram_size, 0)
      end

      def title
        @header[:title]
      end

      def reset
      end

      def battery_backed?
        false
      end

      def dump_battery_ram
        nil
      end

      def load_battery_ram(_bytes)
      end

      def read8(addr)
        case addr & 0xFFFF
        when 0x0000..0x7FFF
          Cartridge.byte_at(@rom, addr & 0x7FFF) || 0xFF
        when 0xA000..0xBFFF
          return 0xFF if @ram.empty?

          @ram[(addr - 0xA000) % @ram.length]
        else
          0xFF
        end
      end

      def write8(addr, value)
        addr &= 0xFFFF
        value &= 0xFF

        @ram[(addr - 0xA000) % @ram.length] = value if (0xA000..0xBFFF).include?(addr) && !@ram.empty?

        value
      end
    end
  end
end
