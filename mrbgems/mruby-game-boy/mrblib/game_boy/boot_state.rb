module GameBoy
  class BootState
    # Boot ROM をまだ実行しない段階なので、DMG の起動直後に近い値を直接入れる。
    IO_DEFAULTS = {
      0xFF10 => 0x80,
      0xFF11 => 0xBF,
      0xFF12 => 0xF3,
      0xFF13 => 0xFF,
      0xFF14 => 0xBF,
      0xFF16 => 0x3F,
      0xFF17 => 0x00,
      0xFF18 => 0xFF,
      0xFF19 => 0xBF,
      0xFF1A => 0x7F,
      0xFF1B => 0xFF,
      0xFF1C => 0x9F,
      0xFF1D => 0xFF,
      0xFF1E => 0xBF,
      0xFF20 => 0xFF,
      0xFF21 => 0x00,
      0xFF22 => 0x00,
      0xFF23 => 0xBF,
      0xFF24 => 0x77,
      0xFF25 => 0xF3,
      0xFF26 => 0xF1
    }

    APU_DEFAULT_RANGE = [
      (0xFF10..0xFF26),
      (0xFF30..0xFF3F)
    ].freeze

    def self.apply!(core)
      core.cpu.load_boot_state(
        af: 0x01B0,
        bc: 0x0013,
        de: 0x00D8,
        hl: 0x014D,
        sp: 0xFFFE,
        pc: 0x0100,
        ime: false
      )

      core.interrupts.load_boot_state(0xE1, 0x00)
      core.timer.load_boot_state(0xAB, 0x00, 0x00, 0xF8)
      core.joypad.load_boot_state(0xCF)
      core.dma.load_boot_state(0xFF, 0)
      core.apu.load_boot_state(apu_defaults)
      core.serial.load_boot_state(0x00, 0x7E)
      core.ppu.load_boot_state(
        lcdc: 0x91,
        stat_select: 0x00,
        mode: 1,
        coincidence: true,
        scy: 0x00,
        scx: 0x00,
        ly: 0x00,
        lyc: 0x00,
        bgp: 0xFC,
        obp0: 0xFF,
        obp1: 0xFF,
        wy: 0x00,
        wx: 0x00
      )
      core.bus.load_boot_stub_io(non_apu_defaults)
    end

    def self.apu_defaults
      filter_defaults(true)
    end

    def self.non_apu_defaults
      filter_defaults(false)
    end

    def self.filter_defaults(apu)
      filtered = {}
      keys = IO_DEFAULTS.keys
      index = 0

      while index < keys.length
        addr = keys[index]
        in_apu_range = apu_address?(addr)
        filtered[addr] = IO_DEFAULTS[addr] if in_apu_range == apu
        index += 1
      end

      filtered
    end

    def self.apu_address?(addr)
      index = 0

      while index < APU_DEFAULT_RANGE.length
        return true if APU_DEFAULT_RANGE[index].include?(addr)

        index += 1
      end

      false
    end
  end
end
