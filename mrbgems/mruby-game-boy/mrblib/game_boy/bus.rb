module GameBoy
  class Bus
    def initialize(cartridge, ppu, timer, interrupts, joypad, dma, apu, serial)
      # CPU はメモリを直接触らず、必ず Bus 経由でアクセスする。
      # ここでアドレス空間を各デバイスに振り分ける。
      @cartridge = cartridge
      @ppu = ppu
      @timer = timer
      @interrupts = interrupts
      @joypad = joypad
      @dma = dma
      @apu = apu
      @serial = serial

      reset
    end

    def reset
      @wram = Array.new(0x2000, 0)
      @hram = Array.new(0x007F, 0)
      @io_stub = Array.new(0x0080, 0xFF)
      @boot_rom_disabled = false
    end

    def disable_boot_rom
      # 現状の FF50 は compatibility latch only。実際の Boot ROM mapping 切り替えはまだしていない。
      @boot_rom_disabled = true
    end

    def load_boot_stub_io(values)
      # まだ個別実装していない IO は、起動後相当の値だけ先に入れておく。
      keys = values.keys
      index = 0

      while index < keys.length
        addr = keys[index]
        @io_stub[addr - 0xFF00] = values[addr] & 0xFF
        index += 1
      end
    end

    def read8(addr)
      addr &= 0xFFFF

      case addr
      when 0x0000..0x7FFF, 0xA000..0xBFFF
        @cartridge.read8(addr)
      when 0x8000..0x9FFF
        @ppu.vram_accessible? ? @ppu.read_vram(addr) : 0xFF
      when 0xC000..0xDFFF
        @wram[addr - 0xC000]
      when 0xE000..0xFDFF
        @wram[addr - 0xE000]
      when 0xFE00..0xFE9F
        @ppu.oam_accessible?(@dma.active?) ? @ppu.read_oam(addr) : 0xFF
      when 0xFEA0..0xFEFF
        0xFF
      when 0xFF00
        @joypad.read_p1
      when 0xFF01..0xFF02
        @serial.read_io(addr)
      when 0xFF03, 0xFF08..0xFF0E
        0xFF
      when 0xFF04..0xFF07
        @timer.read_io(addr)
      when 0xFF0F
        @interrupts.read_if
      when 0xFF10..0xFF3F
        @apu.read_io(addr)
      when 0xFF46
        # FF46 は PPU レジスタ帯の中に見えるが、実際は DMA 起動レジスタ。
        @dma.read_io(addr)
      when 0xFF40..0xFF4B
        @ppu.read_io(addr)
      when 0xFF50
        @boot_rom_disabled ? 0x01 : 0x00
      when 0xFF4C..0xFF7F
        0xFF
      when 0xFF80..0xFFFE
        @hram[addr - 0xFF80]
      when 0xFFFF
        @interrupts.read_ie
      when 0xFF00..0xFF7F
        @io_stub[addr - 0xFF00] || 0xFF
      else
        0xFF
      end
    end

    def read_dma_source8(addr)
      addr &= 0xFFFF

      case addr
      when 0x0000..0x7FFF, 0xA000..0xBFFF
        @cartridge.read8(addr)
      when 0x8000..0x9FFF
        @ppu.read_vram(addr)
      when 0xC000..0xDFFF
        @wram[addr - 0xC000]
      when 0xE000..0xFDFF
        @wram[addr - 0xE000]
      when 0xFE00..0xFE9F
        @ppu.read_oam(addr)
      when 0xFEA0..0xFEFF
        0xFF
      when 0xFF00
        @joypad.read_p1
      when 0xFF04..0xFF07
        @timer.read_io(addr)
      when 0xFF0F
        @interrupts.read_if
      when 0xFF46
        @dma.read_io(addr)
      when 0xFF40..0xFF4B
        @ppu.read_io(addr)
      when 0xFF80..0xFFFE
        @hram[addr - 0xFF80]
      when 0xFFFF
        @interrupts.read_ie
      when 0xFF00..0xFF7F
        @io_stub[addr - 0xFF00] || 0xFF
      else
        0xFF
      end
    end

    def write8(addr, value)
      addr &= 0xFFFF
      value &= 0xFF

      case addr
      when 0x0000..0x7FFF, 0xA000..0xBFFF
        @cartridge.write8(addr, value)
      when 0x8000..0x9FFF
        @ppu.write_vram(addr, value) if @ppu.vram_accessible?
      when 0xC000..0xDFFF
        @wram[addr - 0xC000] = value
      when 0xE000..0xFDFF
        @wram[addr - 0xE000] = value
      when 0xFE00..0xFE9F
        @ppu.write_oam(addr, value) if @ppu.oam_accessible?(@dma.active?)
      when 0xFF00
        @joypad.write_p1(value)
      when 0xFF01..0xFF02
        @serial.write_io(addr, value)
      when 0xFF03, 0xFF08..0xFF0E
        nil
      when 0xFF04..0xFF07
        @timer.write_io(addr, value)
      when 0xFF0F
        @interrupts.write_if(value)
      when 0xFF10..0xFF3F
        @apu.write_io(addr, value)
      when 0xFF46
        # OAM DMA は FF46 への書き込みで開始する。
        @dma.start(value, self)
      when 0xFF40..0xFF4B
        @ppu.write_io(addr, value)
      when 0xFF50
        @boot_rom_disabled = true if value != 0
      when 0xFF4C..0xFF7F
        nil
      when 0xFF80..0xFFFE
        @hram[addr - 0xFF80] = value
      when 0xFFFF
        @interrupts.write_ie(value)
      when 0xFF00..0xFF7F
        @io_stub[addr - 0xFF00] = value
      end

      value
    end

    def read16(addr)
      lo = read8(addr)
      hi = read8((addr + 1) & 0xFFFF)
      lo | (hi << 8)
    end

    def write16(addr, value)
      write8(addr, value & 0xFF)
      write8((addr + 1) & 0xFFFF, (value >> 8) & 0xFF)
      value & 0xFFFF
    end
  end
end
