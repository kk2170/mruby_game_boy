module GameBoy
  class APU
    APU_REGISTERS = (0xFF10..0xFF26).freeze
    WAVE_RAM = (0xFF30..0xFF3F).freeze
    STATUS_BITS = {
      0xFF14 => 0x01,
      0xFF19 => 0x02,
      0xFF1E => 0x04,
      0xFF23 => 0x08
    }.freeze

    def initialize
      reset
    end

    def reset
      @registers = {}
      @wave_ram = Array.new(0x10, 0x00)
      @power_on = false
      @channel_status = 0x00
      clear_registers
    end

    def load_boot_state(values)
      clear_registers
      @wave_ram = Array.new(0x10, 0x00)
      @channel_status = 0x00

      keys = values.keys
      index = 0

      while index < keys.length
        addr = keys[index]
        value = values[addr] & 0xFF

        if APU_REGISTERS.include?(addr)
          @registers[addr] = value
        elsif WAVE_RAM.include?(addr)
          @wave_ram[addr - 0xFF30] = value
        end

        index += 1
      end

      @power_on = (@registers[0xFF26] & 0x80) != 0
      @channel_status = @registers[0xFF26] & 0x0F
    end

    def read_io(addr)
      case addr
      when 0xFF10..0xFF25
        @registers[addr]
      when 0xFF26
        0x70 | (@power_on ? 0x80 : 0x00) | (@channel_status & 0x0F)
      when 0xFF27..0xFF2F
        0xFF
      when 0xFF30..0xFF3F
        @wave_ram[addr - 0xFF30]
      else
        0xFF
      end
    end

    def write_io(addr, value)
      value &= 0xFF

      case addr
      when 0xFF26
        write_nr52(value)
      when 0xFF30..0xFF3F
        @wave_ram[addr - 0xFF30] = value
      when 0xFF10..0xFF25
        return value unless @power_on

        @registers[addr] = value
        trigger_channel(addr, value)
      end

      value
    end

    private

    def clear_registers
      addr = 0xFF10

      while addr <= 0xFF25
        @registers[addr] = 0x00
        addr += 1
      end

      @registers[0xFF26] = 0x00
    end

    def write_nr52(value)
      if (value & 0x80) == 0
        @power_on = false
        @channel_status = 0x00
        clear_registers
        return
      end

      clear_registers unless @power_on

      @power_on = true
      @registers[0xFF26] = 0x80 | (@channel_status & 0x0F)
    end

    def trigger_channel(addr, value)
      return unless (value & 0x80) != 0

      status_bit = STATUS_BITS[addr]
      return unless status_bit

      @channel_status |= status_bit
      @registers[0xFF26] = 0x80 | (@channel_status & 0x0F)
    end
  end
end
