module GameBoy
  module Cartridge
    PRINTABLE_ASCII = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

    ROM_SIZE_BYTES = {
      0x00 => 32 * 1024,
      0x01 => 64 * 1024,
      0x02 => 128 * 1024,
      0x03 => 256 * 1024,
      0x04 => 512 * 1024,
      0x05 => 1024 * 1024,
      0x06 => 2 * 1024 * 1024,
      0x07 => 4 * 1024 * 1024,
      0x08 => 8 * 1024 * 1024
    }

    RAM_SIZE_BYTES = {
      0x00 => 0,
      0x01 => 2 * 1024,
      0x02 => 8 * 1024,
      0x03 => 32 * 1024,
      0x04 => 128 * 1024,
      0x05 => 64 * 1024
    }

    CARTRIDGE_TYPE_NAMES = {
      0x00 => 'ROM ONLY',
      0x01 => 'MBC1',
      0x02 => 'MBC1+RAM',
      0x03 => 'MBC1+RAM+BATTERY'
    }

    def self.build(source)
      rom_bytes = normalize_bytes(source)
      cartridge_type = byte_at(rom_bytes, 0x0147) || 0x00

      case cartridge_type
      when 0x00
        RomOnly.new(rom_bytes)
      when 0x01, 0x02, 0x03
        MBC1.new(rom_bytes)
      else
        raise UnsupportedCartridgeError, format('unsupported cartridge type 0x%02X', cartridge_type)
      end
    end

    def self.normalize_bytes(source)
      if source.is_a?(String)
        # mruby では大きい ROM を Integer 配列へ丸ごと展開すると重いので、
        # String のまま保持して必要なバイトだけ読む。
        source
      else
        bytes = []
        index = 0

        while index < source.length
          bytes << (source[index] & 0xFF)
          index += 1
        end

        bytes
      end
    end

    def self.byte_at(buffer, index)
      return nil if index < 0

      if buffer.is_a?(String)
        buffer.getbyte(index)
      else
        value = buffer[index]
        value.nil? ? nil : (value & 0xFF)
      end
    end

    def self.header(rom_bytes)
      rom_size_code = byte_at(rom_bytes, 0x0148) || 0x00
      ram_size_code = byte_at(rom_bytes, 0x0149) || 0x00
      cartridge_type = byte_at(rom_bytes, 0x0147) || 0x00

      {
        title: parse_title(rom_bytes),
        cartridge_type: cartridge_type,
        cartridge_type_name: CARTRIDGE_TYPE_NAMES[cartridge_type] || 'UNKNOWN',
        rom_size_code: rom_size_code,
        rom_size_bytes: rom_size_bytes(rom_size_code),
        ram_size_code: ram_size_code,
        ram_size_bytes: ram_size_bytes(ram_size_code),
        entry_point: [
          byte_at(rom_bytes, 0x0100) || 0,
          byte_at(rom_bytes, 0x0101) || 0,
          byte_at(rom_bytes, 0x0102) || 0,
          byte_at(rom_bytes, 0x0103) || 0
        ]
      }
    end

    def self.rom_size_bytes(code)
      ROM_SIZE_BYTES[code] || 0
    end

    def self.ram_size_bytes(code)
      RAM_SIZE_BYTES[code] || 0
    end

    def self.parse_title(rom_bytes)
      title = String.new
      index = 0x0134

      while index <= 0x0143
        byte = byte_at(rom_bytes, index) || 0
        break if byte == 0

        title += if byte >= 0x20 && byte <= 0x7E
                   PRINTABLE_ASCII[byte - 0x20, 1]
                 else
                   '?'
                 end
        index += 1
      end

      title
    end
  end
end
