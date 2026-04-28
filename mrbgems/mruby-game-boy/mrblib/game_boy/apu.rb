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
    ENVELOPE_REGISTERS = {
      0xFF12 => 0x01,
      0xFF17 => 0x02,
      0xFF21 => 0x08
    }.freeze
    READ_MASKS = {
      0xFF10 => 0x80,
      0xFF11 => 0x3F,
      0xFF12 => 0x00,
      0xFF13 => 0xFF,
      0xFF14 => 0xBF,
      0xFF15 => 0xFF,
      0xFF16 => 0x3F,
      0xFF17 => 0x00,
      0xFF18 => 0xFF,
      0xFF19 => 0xBF,
      0xFF1A => 0x7F,
      0xFF1B => 0xFF,
      0xFF1C => 0x9F,
      0xFF1D => 0xFF,
      0xFF1E => 0xBF,
      0xFF1F => 0xFF,
      0xFF20 => 0xFF,
      0xFF21 => 0x00,
      0xFF22 => 0x00,
      0xFF23 => 0xBF,
      0xFF24 => 0x00,
      0xFF25 => 0x00
    }.freeze

    def initialize
      reset
    end

    def reset
      @registers = {}
      @wave_ram = Array.new(0x10, 0x00)
      @power_on = false
      @channel_status = 0x00
      reset_envelopes
      reset_sweep
      reset_sequencer
      clear_registers
    end

    def load_boot_state(values)
      clear_registers
      @wave_ram = Array.new(0x10, 0x00)
      @channel_status = 0x00
      reset_envelopes
      reset_sweep
      reset_sequencer

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

    def tick(dots)
      return unless @power_on

      @frame_sequencer_dots += dots

      while @frame_sequencer_dots >= 8_192
        @frame_sequencer_dots -= 8_192
        advance_frame_sequencer
      end
    end

    def read_io(addr)
      case addr
      when 0xFF15, 0xFF1F, 0xFF27..0xFF2F
        0xFF
      when 0xFF10..0xFF25
        (@registers[addr] || 0x00) | (READ_MASKS[addr] || 0x00)
      when 0xFF26
        0x70 | (@power_on ? 0x80 : 0x00) | (@channel_status & 0x0F)
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
        return value if ch3_active?

        @wave_ram[addr - 0xFF30] = value
      when 0xFF15, 0xFF1F, 0xFF27..0xFF2F
        return value
      when 0xFF10..0xFF25
        return value unless @power_on

        @registers[addr] = value
        reload_length(addr, value)
        update_dac_status(addr)
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
        reset_envelopes
        reset_sweep
        reset_sequencer
        clear_registers
        return
      end

      unless @power_on
        clear_registers
        reset_envelopes
        reset_sweep
        reset_sequencer
      end

      @power_on = true
      @registers[0xFF26] = 0x80 | (@channel_status & 0x0F)
    end

    def trigger_channel(addr, value)
      return unless (value & 0x80) != 0

      status_bit = STATUS_BITS[addr]
      return unless status_bit
      return unless dac_enabled_for_trigger?(addr)

      reload_length_on_trigger(addr)
      trigger_envelope(addr)
      return unless trigger_sweep(addr)

      @channel_status |= status_bit
      @registers[0xFF26] = 0x80 | (@channel_status & 0x0F)
    end

    def reset_envelopes
      @envelope_volumes = {
        0x01 => 0,
        0x02 => 0,
        0x08 => 0
      }
      @envelope_timers = {
        0x01 => 0,
        0x02 => 0,
        0x08 => 0
      }
      @envelope_active = {
        0x01 => false,
        0x02 => false,
        0x08 => false
      }
    end

    def reset_sweep
      @sweep_timer = 0
      @sweep_shadow_frequency = 0
      @sweep_enabled = false
    end

    def reset_sequencer
      @frame_sequencer_dots = 0
      @frame_sequencer_step = 0
      @length_counters = {
        0xFF14 => 0,
        0xFF19 => 0,
        0xFF1E => 0,
        0xFF23 => 0
      }
    end

    def advance_frame_sequencer
      clock_length_counters if (@frame_sequencer_step & 0x01) == 0
      clock_sweep if @frame_sequencer_step == 2 || @frame_sequencer_step == 6
      clock_envelopes if @frame_sequencer_step == 7
      @frame_sequencer_step = (@frame_sequencer_step + 1) & 0x07
    end

    def clock_length_counters
      STATUS_BITS.keys.each do |addr|
        next unless length_enabled?(addr)
        next unless @length_counters[addr] > 0

        @length_counters[addr] -= 1
        disable_channel(addr) if @length_counters[addr] == 0
      end
    end

    def reload_length(addr, value)
      case addr
      when 0xFF11, 0xFF16
        @length_counters[channel_trigger_register(addr)] = 64 - (value & 0x3F)
      when 0xFF1B
        @length_counters[0xFF1E] = 256 - value
      when 0xFF20
        @length_counters[0xFF23] = 64 - (value & 0x3F)
      end
    end

    def reload_length_on_trigger(addr)
      return unless @length_counters[addr] == 0

      @length_counters[addr] = addr == 0xFF1E ? 256 : 64
    end

    def channel_trigger_register(addr)
      case addr
      when 0xFF11 then 0xFF14
      when 0xFF16 then 0xFF19
      else addr
      end
    end

    def length_enabled?(addr)
      (@registers[addr] & 0x40) != 0
    end

    def disable_channel(addr)
      @channel_status &= (~STATUS_BITS[addr]) & 0x0F
      @registers[0xFF26] = 0x80 | (@channel_status & 0x0F)
      @sweep_enabled = false if addr == 0xFF14
    end

    def trigger_envelope(addr)
      envelope_addr = envelope_register_for_trigger(addr)
      return unless envelope_addr

      channel_bit = STATUS_BITS[addr]
      @envelope_volumes[channel_bit] = (@registers[envelope_addr] >> 4) & 0x0F
      @envelope_timers[channel_bit] = envelope_period(@registers[envelope_addr])
      @envelope_active[channel_bit] = true
    end

    def trigger_sweep(addr)
      return true unless addr == 0xFF14

      @sweep_shadow_frequency = ch1_frequency
      @sweep_timer = sweep_period(@registers[0xFF10])
      @sweep_enabled = sweep_period_raw(@registers[0xFF10]) != 0 || sweep_shift(@registers[0xFF10]) != 0

      if sweep_shift(@registers[0xFF10]) != 0 && sweep_overflow?(calculate_sweep_frequency(@sweep_shadow_frequency))
        disable_channel(0xFF14)
        return false
      end

      true
    end

    def clock_sweep
      return unless @sweep_enabled

      @sweep_timer -= 1 if @sweep_timer > 0
      return unless @sweep_timer == 0

      @sweep_timer = sweep_period(@registers[0xFF10])
      shift = sweep_shift(@registers[0xFF10])
      return if shift == 0

      new_frequency = calculate_sweep_frequency(@sweep_shadow_frequency)
      if sweep_overflow?(new_frequency)
        disable_channel(0xFF14)
        return
      end

      @sweep_shadow_frequency = new_frequency
      set_ch1_frequency(new_frequency)

      disable_channel(0xFF14) if sweep_overflow?(calculate_sweep_frequency(@sweep_shadow_frequency))
    end

    def clock_envelopes
      ENVELOPE_REGISTERS.each do |addr, channel_bit|
        next unless @envelope_active[channel_bit]
        next if !channel_enabled?(channel_bit) || !dac_enabled?(addr)

        @envelope_timers[channel_bit] -= 1 if @envelope_timers[channel_bit] > 0
        next unless @envelope_timers[channel_bit] == 0

        @envelope_timers[channel_bit] = envelope_period(@registers[addr])
        step_envelope(channel_bit, @registers[addr])
      end
    end

    def step_envelope(channel_bit, value)
      direction_up = (value & 0x08) != 0
      volume = @envelope_volumes[channel_bit]

      if direction_up
        if volume < 15
          @envelope_volumes[channel_bit] = volume + 1
        else
          @envelope_active[channel_bit] = false
        end
      elsif volume > 0
        @envelope_volumes[channel_bit] = volume - 1
      else
        @envelope_active[channel_bit] = false
      end
    end

    def channel_enabled?(channel_bit)
      (@channel_status & channel_bit) != 0
    end

    def envelope_register_for_trigger(addr)
      case addr
      when 0xFF14 then 0xFF12
      when 0xFF19 then 0xFF17
      when 0xFF23 then 0xFF21
      end
    end

    def envelope_period(value)
      period = value & 0x07
      period == 0 ? 8 : period
    end

    def sweep_period_raw(value)
      (value >> 4) & 0x07
    end

    def sweep_period(value)
      period = sweep_period_raw(value)
      period == 0 ? 8 : period
    end

    def sweep_shift(value)
      value & 0x07
    end

    def sweep_negate?(value)
      (value & 0x08) != 0
    end

    def ch1_frequency
      ((@registers[0xFF14] & 0x07) << 8) | @registers[0xFF13]
    end

    def set_ch1_frequency(value)
      @registers[0xFF13] = value & 0xFF
      @registers[0xFF14] = (@registers[0xFF14] & 0xF8) | ((value >> 8) & 0x07)
    end

    def calculate_sweep_frequency(base_frequency)
      delta = base_frequency >> sweep_shift(@registers[0xFF10])
      if sweep_negate?(@registers[0xFF10])
        base_frequency - delta
      else
        base_frequency + delta
      end
    end

    def sweep_overflow?(frequency)
      frequency < 0 || frequency > 0x07FF
    end

    def ch3_active?
      (@channel_status & 0x04) != 0
    end

    def update_dac_status(addr)
      channel_bit = case addr
                    when 0xFF12 then 0x01
                    when 0xFF17 then 0x02
                    when 0xFF1A then 0x04
                    when 0xFF21 then 0x08
                    end
      return unless channel_bit
      return if dac_enabled?(addr)

      @channel_status &= (~channel_bit) & 0x0F
      @registers[0xFF26] = 0x80 | (@channel_status & 0x0F)
    end

    def dac_enabled_for_trigger?(addr)
      case addr
      when 0xFF14 then dac_enabled?(0xFF12)
      when 0xFF19 then dac_enabled?(0xFF17)
      when 0xFF1E then dac_enabled?(0xFF1A)
      when 0xFF23 then dac_enabled?(0xFF21)
      else
        true
      end
    end

    def dac_enabled?(addr)
      case addr
      when 0xFF12, 0xFF17, 0xFF21
        (@registers[addr] & 0xF8) != 0
      when 0xFF1A
        (@registers[addr] & 0x80) != 0
      else
        true
      end
    end
  end
end
