module GameBoy
  module Cartridge
    class MBC3
      RTC_REGISTERS = [0x08, 0x09, 0x0A, 0x0B, 0x0C].freeze

      class << self
        attr_writer :time_source

        def current_unix_time
          if @time_source
            @time_source.call.to_i
          else
            0
          end
        end
      end

      attr_reader :rom, :header

      def initialize(rom_bytes)
        @rom = rom_bytes
        @header = Cartridge.header(@rom)
        @rom_bank_count = [@header[:rom_size_bytes] / 0x4000, 1].max
        @ram_bank_count = [@header[:ram_size_bytes] / 0x2000, 1].max
        @ram = Array.new(@header[:ram_size_bytes], 0)
        initialize_rtc_state

        reset
      end

      def title
        @header[:title]
      end

      def reset
        @ram_enabled = false
        @rom_bank = 1
        @ram_select = 0
        @latched_rtc_registers = @rtc_registers.dup
        @rtc_latched = false
        @rtc_latch_value = 0
      end

      def battery_backed?
        [0x0F, 0x10, 0x13].include?(@header[:cartridge_type])
      end

      def dump_battery_ram
        return nil unless battery_backed?

        sync_rtc!

        dump = @ram.dup

        RTC_REGISTERS.each do |register|
          dump << (@rtc_registers[register] || 0)
        end

        RTC_REGISTERS.each do |register|
          dump << (@latched_rtc_registers[register] || 0)
        end

        dump << (@rtc_latched ? 1 : 0)
        dump << (@rtc_latch_value & 0x01)
        append_u32_le(dump, @rtc_reference_unix)
        dump
      end

      def load_battery_ram(bytes)
        return unless battery_backed?

        dump = Cartridge.normalize_bytes(bytes)
        index = 0

        while index < @ram.length
          @ram[index] = Cartridge.byte_at(dump, index) || 0
          index += 1
        end

        RTC_REGISTERS.each do |register|
          @rtc_registers[register] = normalize_rtc_value(register, Cartridge.byte_at(dump, index) || 0)
          index += 1
        end

        RTC_REGISTERS.each do |register|
          @latched_rtc_registers[register] = normalize_rtc_value(register, Cartridge.byte_at(dump, index) || 0)
          index += 1
        end

        @rtc_latched = (Cartridge.byte_at(dump, index) || 0) != 0
        index += 1
        @rtc_latch_value = (Cartridge.byte_at(dump, index) || 0) & 0x01
        index += 1

        persisted_reference = read_u32_le(dump, index)
        @rtc_reference_unix = if persisted_reference.nil?
                                self.class.current_unix_time
                              else
                                persisted_reference
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
          sync_rtc!
          return read_rtc_register if rtc_selected?
          return 0xFF if @ram.empty? || !ram_bank_selected?

          @ram[ram_index(addr)]
        else
          0xFF
        end
      end

      def write8(addr, value)
        addr &= 0xFFFF
        value &= 0xFF

        case addr
        when 0x0000..0x1FFF
          @ram_enabled = (value & 0x0F) == 0x0A
        when 0x2000..0x3FFF
          @rom_bank = value & 0x7F
          @rom_bank = 1 if @rom_bank == 0
        when 0x4000..0x5FFF
          @ram_select = value & 0x0F
        when 0x6000..0x7FFF
          sync_rtc!
          latch_rtc(value)
        when 0xA000..0xBFFF
          sync_rtc!
          write_rtc_register(value) if @ram_enabled && rtc_selected?
          @ram[ram_index(addr)] = value if !@ram.empty? && @ram_enabled && ram_bank_selected?
        end

        value
      end

      private

      def selected_rom_bank
        @rom_bank % @rom_bank_count
      end

      def initialize_rtc_state
        @rtc_registers = {
          0x08 => 0x00,
          0x09 => 0x00,
          0x0A => 0x00,
          0x0B => 0x00,
          0x0C => 0x00
        }
        @rtc_reference_unix = self.class.current_unix_time
      end

      def selected_ram_bank
        return 0 unless @ram.length > 0x2000

        @ram_select % @ram_bank_count
      end

      def ram_bank_selected?
        @ram_select <= 0x03
      end

      def rtc_supported?
        [0x0F, 0x10].include?(@header[:cartridge_type])
      end

      def rtc_selected?
        rtc_supported? && RTC_REGISTERS.include?(@ram_select)
      end

      def read_rtc_register
        source = @rtc_latched ? @latched_rtc_registers : @rtc_registers
        source[@ram_select] || 0xFF
      end

      def write_rtc_register(value)
        return unless rtc_selected?

        current_time = self.class.current_unix_time
        @rtc_registers[@ram_select] = normalize_rtc_value(@ram_select, value)
        @rtc_reference_unix = current_time
      end

      def latch_rtc(value)
        next_value = value & 0x01

        if @rtc_latch_value == 0 && next_value == 1 && rtc_supported?
          @latched_rtc_registers = @rtc_registers.dup
          @rtc_latched = true
        elsif next_value == 0
          @rtc_latched = false
        end

        @rtc_latch_value = next_value
      end

      def normalize_rtc_value(register, value)
        case register
        when 0x08, 0x09 then value & 0x3F
        when 0x0A then value & 0x1F
        when 0x0B then value & 0xFF
        when 0x0C then value & 0xC1
        else value & 0xFF
        end
      end

      def ram_index(addr)
        ((selected_ram_bank * 0x2000) + (addr - 0xA000)) % @ram.length
      end

      def sync_rtc!
        return unless rtc_supported?
        return if rtc_halted?

        current_time = self.class.current_unix_time
        elapsed = current_time - @rtc_reference_unix
        if elapsed < 0
          @rtc_reference_unix = current_time
          return
        end
        return unless elapsed > 0

        advance_rtc_seconds(elapsed)
        @rtc_reference_unix = current_time
      end

      def rtc_halted?
        (@rtc_registers[0x0C] & 0x40) != 0
      end

      def rtc_day_carry?
        (@rtc_registers[0x0C] & 0x80) != 0
      end

      def rtc_total_seconds
        days = @rtc_registers[0x0B] | ((@rtc_registers[0x0C] & 0x01) << 8)
        ((days * 24 + @rtc_registers[0x0A]) * 60 + @rtc_registers[0x09]) * 60 + @rtc_registers[0x08]
      end

      def advance_rtc_seconds(elapsed)
        total_seconds = rtc_total_seconds + elapsed
        days = total_seconds / 86_400
        remainder = total_seconds % 86_400
        carry = rtc_day_carry?

        if days >= 512
          carry = true
          days %= 512
        end

        @rtc_registers[0x08] = remainder % 60
        remainder /= 60
        @rtc_registers[0x09] = remainder % 60
        remainder /= 60
        @rtc_registers[0x0A] = remainder % 24
        @rtc_registers[0x0B] = days & 0xFF

        halt_bit = @rtc_registers[0x0C] & 0x40
        high_day_bit = (days >> 8) & 0x01
        carry_bit = carry ? 0x80 : 0x00
        @rtc_registers[0x0C] = halt_bit | carry_bit | high_day_bit
      end

      def append_u32_le(buffer, value)
        packed = value.to_i & 0xFFFF_FFFF
        4.times do
          buffer << (packed & 0xFF)
          packed >>= 8
        end
      end

      def read_u32_le(buffer, index)
        byte0 = Cartridge.byte_at(buffer, index)
        return nil if byte0.nil?

        value = 0
        shift = 0

        4.times do |offset|
          byte = Cartridge.byte_at(buffer, index + offset) || 0
          value |= byte << shift
          shift += 8
        end

        value
      end
    end
  end
end
