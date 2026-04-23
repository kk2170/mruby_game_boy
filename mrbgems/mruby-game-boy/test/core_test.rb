def build_test_ppu(lcdc: 0x82, obp0: 0xE4, obp1: 0x1B)
  interrupts = GameBoy::Interrupts.new
  ppu = GameBoy::PPU.new(interrupts)
  ppu.load_boot_state(
    lcdc: lcdc,
    stat_select: 0x00,
    mode: 0,
    coincidence: false,
    scy: 0x00,
    scx: 0x00,
    ly: 0x00,
    lyc: 0x00,
    bgp: 0xE4,
    obp0: obp0,
    obp1: obp1,
    wy: 0x00,
    wx: 0x07
  )
  ppu
end

def write_test_sprite_tile(ppu, tile_index, lo_byte, hi_byte = 0x00)
  base = 0x8000 + tile_index * 16
  8.times do |line|
    ppu.write_vram(base + line * 2, lo_byte)
    ppu.write_vram(base + line * 2 + 1, hi_byte)
  end
end

class GameBoy::PPU
  def render_scanline_for_test
    render_scanline
  end

  def render_sprites_for_test(line, offset, bg_color_ids)
    render_sprites(line, offset, bg_color_ids)
  end
end

def build_test_rom(size, bytes = {})
  rom = "\x00" * size
  index = 0

  while index < size
    rom.setbyte(index, bytes[index] || 0)
    index += 1
  end

  rom
end

def build_test_mbc1_rom(cartridge_type: 0x03, rom_size_code: 0x03, ram_size_code: 0x03, bytes: {})
  build_test_rom(
    GameBoy::Cartridge::ROM_SIZE_BYTES[rom_size_code],
    {
      0x0147 => cartridge_type,
      0x0148 => rom_size_code,
      0x0149 => ram_size_code
    }.merge(bytes)
  )
end

def build_test_mbc2_rom(cartridge_type: 0x06, rom_size_code: 0x03, bytes: {})
  build_test_rom(
    GameBoy::Cartridge::ROM_SIZE_BYTES[rom_size_code],
    {
      0x0147 => cartridge_type,
      0x0148 => rom_size_code,
      0x0149 => 0x00
    }.merge(bytes)
  )
end

def build_test_timer
  interrupts = GameBoy::Interrupts.new
  [GameBoy::Timer.new(interrupts), interrupts]
end

assert('GameBoy::Cartridge parses Tobu-style header fields') do
  rom = Array.new(0x8000, 0)
  title = 'TOBU'
  index = 0

  while index < title.length
    rom[0x0134 + index] = title.getbyte(index)
    index += 1
  end

  rom[0x0147] = 0x00
  rom[0x0148] = 0x00
  rom[0x0149] = 0x00

  cart = GameBoy::Cartridge.build(rom)
  header = cart.header

  assert_equal 'TOBU', header[:title]
  assert_equal 0x00, header[:cartridge_type]
  assert_equal 32 * 1024, header[:rom_size_bytes]
  assert_equal 0, header[:ram_size_bytes]
end

assert('GameBoy::Core boots into DMG post-boot register state') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00

  core = GameBoy::Core.new(rom)

  assert_equal 0x01B0, core.cpu.af
  assert_equal 0x0013, core.cpu.bc
  assert_equal 0x00D8, core.cpu.de
  assert_equal 0x014D, core.cpu.hl
  assert_equal 0xFFFE, core.cpu.sp
  assert_equal 0x0100, core.cpu.pc
end

assert('GameBoy::Bus routes APU register reads from boot state') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  assert_equal 0x80, core.bus.read8(0xFF10)
  assert_equal 0xF3, core.bus.read8(0xFF25)
  assert_equal 0xF1, core.bus.read8(0xFF26)
  assert_equal 0xFF, core.bus.read8(0xFF27)
end

assert('GameBoy::Serial exposes boot state without io stub fallback') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  assert_equal 0x00, core.bus.read8(0xFF01)
  assert_equal 0x7E, core.bus.read8(0xFF02)
end

assert('GameBoy::Bus returns 0xFF for unused IO holes and ignores writes') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  [0xFF03, 0xFF08, 0xFF09, 0xFF0A, 0xFF0B, 0xFF0C, 0xFF0D, 0xFF0E].each do |addr|
    core.bus.write8(addr, 0x12)
    assert_equal 0xFF, core.bus.read8(addr)
  end
end

assert('GameBoy::Bus treats representative CGB-only registers as DMG-unused') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  [0xFF4D, 0xFF4F, 0xFF55, 0xFF70].each do |addr|
    core.bus.write8(addr, 0x12)
    assert_equal 0xFF, core.bus.read8(addr)
  end
end

assert('GameBoy::Bus exposes FF50 as a one-way boot disable latch') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  assert_equal 0x01, core.bus.read8(0xFF50)

  core.bus.write8(0xFF50, 0x00)
  assert_equal 0x01, core.bus.read8(0xFF50)

  core.bus.write8(0xFF50, 0x42)
  assert_equal 0x01, core.bus.read8(0xFF50)
end

assert('GameBoy::Serial completes internal clock transfer after 4096 dots') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  core.interrupts.write_if(0xE0)
  core.bus.write8(0xFF01, 0x42)
  core.bus.write8(0xFF02, 0x81)

  core.run_steps(1023)
  assert_equal 0x42, core.bus.read8(0xFF01)
  assert_equal 0x00, core.interrupts.read_if & 0x08

  core.step

  assert_equal 0xFF, core.bus.read8(0xFF01)
  assert_equal 0x7F, core.bus.read8(0xFF02)
  assert_equal 0x08, core.interrupts.read_if & 0x08
end

assert('GameBoy::Serial services internal clock interrupt on the following step') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0xFB

  core = GameBoy::Core.new(rom)
  core.interrupts.write_ie(0x08)
  core.interrupts.write_if(0xE0)
  core.bus.write8(0xFF01, 0x42)
  core.bus.write8(0xFF02, 0x81)

  core.step
  core.run_steps(1022)

  assert_equal 0x00, core.interrupts.read_if & 0x08

  core.step

  assert_equal 0x0500, core.cpu.pc
  assert_equal 0x08, core.interrupts.read_if & 0x08

  cycles = core.step

  assert_equal 20, cycles
  assert_equal 0x0058, core.cpu.pc
  assert_equal 0xFFFC, core.cpu.sp
  assert_equal 0x00, core.bus.read8(0xFFFC)
  assert_equal 0x05, core.bus.read8(0xFFFD)
  assert_equal 0xE0, core.interrupts.read_if
end

assert('GameBoy::Serial resets internal clock transfer timing on FF02 rewrite') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  core.interrupts.write_if(0xE0)
  core.bus.write8(0xFF01, 0x42)
  core.bus.write8(0xFF02, 0x81)

  core.run_steps(512)
  core.bus.write8(0xFF02, 0x81)
  core.run_steps(1023)

  assert_equal 0x42, core.bus.read8(0xFF01)
  assert_equal 0x00, core.interrupts.read_if & 0x08

  core.step

  assert_equal 0xFF, core.bus.read8(0xFF01)
  assert_equal 0x7F, core.bus.read8(0xFF02)
  assert_equal 0x08, core.interrupts.read_if & 0x08
end

assert('GameBoy::Serial leaves IF pending when transfer completes with IME disabled') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  core.interrupts.write_ie(0x08)
  core.interrupts.write_if(0xE0)
  core.bus.write8(0xFF01, 0x42)
  core.bus.write8(0xFF02, 0x81)
  core.run_steps(1023)

  core.step

  assert_equal 0x0500, core.cpu.pc
  assert_equal 0x08, core.interrupts.read_if & 0x08

  cycles = core.step

  assert_equal 4, cycles
  assert_equal 0x0501, core.cpu.pc
  assert_equal 0xFFFE, core.cpu.sp
  assert_equal 0x08, core.interrupts.read_if & 0x08
end

assert('GameBoy::Serial does not advance external clock transfer') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  core.interrupts.write_if(0xE0)
  core.bus.write8(0xFF01, 0x42)
  core.bus.write8(0xFF02, 0x80)
  core.run_steps(1024)

  assert_equal 0x42, core.bus.read8(0xFF01)
  assert_equal 0xFE, core.bus.read8(0xFF02)
  assert_equal 0x00, core.interrupts.read_if & 0x08
end

assert('GameBoy::Timer increments DIV every 256 dots') do
  timer = GameBoy::Timer.new(GameBoy::Interrupts.new)

  timer.tick(255)
  assert_equal 0x00, timer.read_io(0xFF04)

  timer.tick(1)
  assert_equal 0x01, timer.read_io(0xFF04)

  timer.tick(256)
  assert_equal 0x02, timer.read_io(0xFF04)
end

assert('GameBoy::Timer increments TIMA on selected divider bit falling edge') do
  frequencies = {
    0x00 => 1024,
    0x01 => 16,
    0x02 => 64,
    0x03 => 256
  }

  frequencies.each do |select, period|
    timer = GameBoy::Timer.new(GameBoy::Interrupts.new)
    timer.write_io(0xFF07, 0x04 | select)

    timer.tick(period - 1)
    assert_equal 0x00, timer.read_io(0xFF05)

    timer.tick(1)
    assert_equal 0x01, timer.read_io(0xFF05)
  end
end

assert('GameBoy::Timer delays TIMA reload and TIMER IF request by 4 dots after overflow') do
  interrupts = GameBoy::Interrupts.new
  timer = GameBoy::Timer.new(interrupts)

  timer.write_io(0xFF06, 0xAB)
  timer.write_io(0xFF05, 0xFF)
  timer.write_io(0xFF07, 0x05)
  interrupts.write_if(0xE0)

  timer.tick(16)
  assert_equal 0x00, timer.read_io(0xFF05)
  assert_equal 0x00, interrupts.read_if & 0x04

  timer.tick(3)
  assert_equal 0x00, timer.read_io(0xFF05)
  assert_equal 0x00, interrupts.read_if & 0x04

  timer.tick(1)
  assert_equal 0xAB, timer.read_io(0xFF05)
  assert_equal 0x04, interrupts.read_if & 0x04
end

assert('GameBoy::Timer keeps FF07 falling-edge glitch while delaying overflow reload') do
  interrupts = GameBoy::Interrupts.new
  timer = GameBoy::Timer.new(interrupts)

  timer.write_io(0xFF06, 0xCD)
  timer.write_io(0xFF05, 0xFF)
  timer.write_io(0xFF07, 0x05)
  interrupts.write_if(0xE0)

  timer.tick(8)
  timer.write_io(0xFF07, 0x00)

  assert_equal 0x00, timer.read_io(0xFF05)
  assert_equal 0x00, interrupts.read_if & 0x04

  timer.tick(4)
  assert_equal 0xCD, timer.read_io(0xFF05)
  assert_equal 0x04, interrupts.read_if & 0x04
end

assert('GameBoy::Timer resets divider phase on DIV write') do
  timer = GameBoy::Timer.new(GameBoy::Interrupts.new)
  timer.write_io(0xFF07, 0x05)

  timer.tick(4)
  timer.write_io(0xFF04, 0x12)

  assert_equal 0x00, timer.read_io(0xFF04)

  timer.tick(15)
  assert_equal 0x00, timer.read_io(0xFF05)

  timer.tick(1)
  assert_equal 0x01, timer.read_io(0xFF05)
end

assert('GameBoy::Core preserves post-boot timer divider phase') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  core.bus.write8(0xFF07, 0x05)
  assert_equal 0x00, core.bus.read8(0xFF05)

  assert_equal 4, core.step
  assert_equal 0x01, core.bus.read8(0xFF05)
end

assert('GameBoy::APU stores wave RAM through bus') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  core.bus.write8(0xFF30, 0x12)
  core.bus.write8(0xFF3F, 0x34)

  assert_equal 0x12, core.bus.read8(0xFF30)
  assert_equal 0x34, core.bus.read8(0xFF3F)
end

assert('GameBoy::APU updates NR52 status on DAC-aware trigger and power off') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  core.bus.write8(0xFF26, 0x00)
  core.bus.write8(0xFF26, 0x80)
  core.bus.write8(0xFF12, 0x00)
  core.bus.write8(0xFF14, 0x80)

  assert_equal 0xF0, core.bus.read8(0xFF26)

  core.bus.write8(0xFF12, 0x77)
  core.bus.write8(0xFF17, 0x77)
  core.bus.write8(0xFF14, 0x80)
  core.bus.write8(0xFF19, 0x80)

  assert_equal 0xF3, core.bus.read8(0xFF26)

  core.bus.write8(0xFF12, 0x00)

  assert_equal 0xF2, core.bus.read8(0xFF26)

  core.bus.write8(0xFF12, 0x77)
  core.bus.write8(0xFF26, 0x00)

  assert_equal 0x70, core.bus.read8(0xFF26)
  assert_equal 0x00, core.bus.read8(0xFF12)

  core.bus.write8(0xFF12, 0x99)
  assert_equal 0x00, core.bus.read8(0xFF12)
end

assert('GameBoy::APU updates NR52 status for CH3 and CH4 DAC-aware triggers') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  core.bus.write8(0xFF26, 0x00)
  core.bus.write8(0xFF26, 0x80)
  core.bus.write8(0xFF1A, 0x00)
  core.bus.write8(0xFF1E, 0x80)

  assert_equal 0xF0, core.bus.read8(0xFF26)

  core.bus.write8(0xFF1A, 0x80)
  core.bus.write8(0xFF1E, 0x80)

  assert_equal 0xF4, core.bus.read8(0xFF26)

  core.bus.write8(0xFF1A, 0x00)

  assert_equal 0xF0, core.bus.read8(0xFF26)

  core.bus.write8(0xFF21, 0x00)
  core.bus.write8(0xFF23, 0x80)

  assert_equal 0xF0, core.bus.read8(0xFF26)

  core.bus.write8(0xFF21, 0x08)
  core.bus.write8(0xFF23, 0x80)

  assert_equal 0xF8, core.bus.read8(0xFF26)

  core.bus.write8(0xFF21, 0x00)

  assert_equal 0xF0, core.bus.read8(0xFF26)
end

assert('GameBoy::APU returns 0xFF for unused hole registers and ignores writes') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  assert_equal 0xFF, core.bus.read8(0xFF15)
  assert_equal 0xFF, core.bus.read8(0xFF1F)

  core.bus.write8(0xFF26, 0x80)
  core.bus.write8(0xFF15, 0x12)
  core.bus.write8(0xFF1F, 0x34)

  assert_equal 0xFF, core.bus.read8(0xFF15)
  assert_equal 0xFF, core.bus.read8(0xFF1F)
end

assert('GameBoy::Cartridge builds basic MBC1 cartridges') do
  rom = build_test_rom(
    0x8000,
    0x0147 => 0x03,
    0x0148 => 0x03,
    0x0149 => 0x02,
    0x4000 => 0x42
  )

  cart = GameBoy::Cartridge.build(rom)

  assert_equal 'GameBoy::Cartridge::MBC1', cart.class.to_s
  assert_equal 0x42, cart.read8(0x4000)
end

assert('GameBoy::Cartridge::MBC1 keeps raw low5 bank bits before ROM-size masking') do
  rom = "\x77" +
        ("\x00" * 0x0146) +
        "\x01" +
        "\x03" +
        ("\x00" * (0x4000 - 0x0149)) +
        "\x42" +
        ("\x00" * (0x40000 - 0x4001))

  cart = GameBoy::Cartridge.build(rom)

  assert_equal 0x42, cart.read8(0x4000)

  cart.write8(0x2000, 0x00)
  assert_equal 0x42, cart.read8(0x4000)

  cart.write8(0x2000, 0x10)
  assert_equal 0x77, cart.read8(0x4000)
end

assert('GameBoy::Core#reset resets MBC1 bank state without clearing RAM') do
  rom = build_test_mbc1_rom(bytes: {
    0x0000 => 0x44,
    0x4000 => 0x11,
    0x8000 => 0x22,
    0xC000 => 0x33
  })
  core = GameBoy::Core.new(rom)

  core.bus.write8(0x0000, 0x0A)
  core.bus.write8(0x2000, 0x02)
  core.bus.write8(0x4000, 0x01)
  core.bus.write8(0x6000, 0x01)
  core.bus.write8(0xA000, 0x5A)

  assert_equal 0x22, core.bus.read8(0x4000)
  assert_equal 0x5A, core.bus.read8(0xA000)

  core.reset

  # reset 後は bank 0 / mode 0 に戻るので、lower bank 側の内容が見える。
  assert_equal 0x44, core.bus.read8(0x0000)
  assert_equal 0x11, core.bus.read8(0x4000)
  assert_equal 0xFF, core.bus.read8(0xA000)

  core.bus.write8(0x0000, 0x0A)
  core.bus.write8(0x4000, 0x01)
  core.bus.write8(0x6000, 0x01)

  assert_equal 0x5A, core.bus.read8(0xA000)
end

assert('GameBoy::Cartridge::MBC1 battery RAM dump/load roundtrips for type 0x03') do
  rom = build_test_mbc1_rom
  cart = GameBoy::Cartridge.build(rom)

  assert_true cart.battery_backed?

  cart.write8(0x0000, 0x0A)
  cart.write8(0xA000, 0x12)
  cart.write8(0xA001, 0x34)

  dump = cart.dump_battery_ram
  restored = GameBoy::Cartridge.build(rom)

  restored.load_battery_ram(dump)
  restored.write8(0x0000, 0x0A)

  assert_equal 0x12, restored.read8(0xA000)
  assert_equal 0x34, restored.read8(0xA001)
end

assert('GameBoy::Core#reset resets MBC2 bank state without clearing internal RAM') do
  rom = build_test_mbc2_rom(bytes: {
    0x4000 => 0x11,
    0x8000 => 0x22
  })
  core = GameBoy::Core.new(rom)

  core.bus.write8(0x0000, 0x0A)
  core.bus.write8(0x2100, 0x02)
  core.bus.write8(0xA000, 0x5A)

  assert_equal 0x22, core.bus.read8(0x4000)
  assert_equal 0xFA, core.bus.read8(0xA000)

  core.reset

  assert_equal 0x11, core.bus.read8(0x4000)
  assert_equal 0xFF, core.bus.read8(0xA000)

  core.bus.write8(0x0000, 0x0A)

  assert_equal 0xFA, core.bus.read8(0xA000)
end

assert('GameBoy::Core battery RAM roundtrips through binary string data') do
  core = GameBoy::Core.new(build_test_mbc2_rom)

  core.bus.write8(0x0000, 0x0A)
  core.bus.write8(0xA000, 0x12)
  core.bus.write8(0xA001, 0x34)

  dump = core.dump_battery_ram
  binary_dump = "\x00" * dump.length
  index = 0

  while index < dump.length
    binary_dump.setbyte(index, dump[index] & 0xFF)
    index += 1
  end

  restored = GameBoy::Core.new(build_test_mbc2_rom)
  restored.load_battery_ram(binary_dump)
  restored.bus.write8(0x0000, 0x0A)

  assert_equal 0xF2, restored.bus.read8(0xA000)
  assert_equal 0xF4, restored.bus.read8(0xA001)
end

assert('GameBoy::Cartridge builds basic MBC2 cartridges') do
  rom = build_test_mbc2_rom(
    cartridge_type: 0x05,
    bytes: {
      0x4000 => 0x11,
      0x8000 => 0x22
    }
  )

  cart = GameBoy::Cartridge.build(rom)

  assert_equal 'GameBoy::Cartridge::MBC2', cart.class.to_s
  assert_equal 'MBC2', cart.header[:cartridge_type_name]
  assert_equal 0x11, cart.read8(0x4000)

  cart.write8(0x2100, 0x02)
  assert_equal 0x22, cart.read8(0x4000)

  cart.write8(0x2100, 0x00)
  assert_equal 0x11, cart.read8(0x4000)
end

assert('GameBoy::Cartridge::MBC2 uses address bit 8 to split RAM enable and ROM banking') do
  rom = build_test_mbc2_rom(bytes: {
    0x4000 => 0x11,
    0x28000 => 0xAA
  })
  cart = GameBoy::Cartridge.build(rom)

  cart.write8(0x0000, 0x0A)
  cart.write8(0xA000, 0x3C)

  assert_equal 0xFC, cart.read8(0xA000)

  cart.write8(0x0100, 0x0A)

  assert_equal 0xAA, cart.read8(0x4000)
  assert_equal 0xFC, cart.read8(0xA000)

  cart.write8(0x0000, 0x00)

  assert_equal 0xFF, cart.read8(0xA000)
end

assert('GameBoy::Cartridge::MBC2 battery RAM dump/load roundtrips for type 0x06') do
  rom = build_test_mbc2_rom
  cart = GameBoy::Cartridge.build(rom)

  assert_true cart.battery_backed?

  cart.write8(0x0000, 0x0A)
  cart.write8(0xA000, 0x12)
  cart.write8(0xA123, 0x3F)

  dump = cart.dump_battery_ram
  restored = GameBoy::Cartridge.build(rom)

  restored.load_battery_ram(dump)
  restored.write8(0x0000, 0x0A)

  assert_equal 0xF2, restored.read8(0xA000)
  assert_equal 0xFF, restored.read8(0xA123)
end

assert('GameBoy::Core delegates battery-backed cartridge APIs') do
  core = GameBoy::Core.new(build_test_mbc1_rom)

  assert_true core.battery_backed?

  core.load_battery_ram([0x12, 0x34])
  core.bus.write8(0x0000, 0x0A)

  assert_equal 0x12, core.bus.read8(0xA000)
  assert_equal 0x34, core.bus.read8(0xA001)
  assert_equal 0x12, core.dump_battery_ram[0]
  assert_equal 0x34, core.dump_battery_ram[1]
end

assert('GameBoy::Cartridge::RomOnly battery API stays inert') do
  rom = build_test_rom(0x8000, 0x0147 => 0x00)
  cart = GameBoy::Cartridge.build(rom)

  assert_false cart.battery_backed?
  assert_equal nil, cart.dump_battery_ram

  cart.load_battery_ram([0x12, 0x34])

  assert_equal 0xFF, cart.read8(0xA000)
end

assert('GameBoy::CPU JR uses post-immediate PC as base') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0x18
  rom[0x0101] = 0x02

  core = GameBoy::Core.new(rom)
  core.step

  assert_equal 0x0104, core.cpu.pc
end

assert('GameBoy::Bus routes FF46 writes to DMA over time') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  0x00A0.times do |index|
    core.bus.write8(0xC000 + index, index & 0xFF)
  end

  core.bus.write8(0xFF46, 0xC0)

  assert_equal 0x00, core.ppu.read_oam(0xFE00)

  core.dma.tick(4)
  assert_equal 0x00, core.ppu.read_oam(0xFE00)

  core.dma.tick(4)
  assert_equal 0x01, core.ppu.read_oam(0xFE01)

  core.dma.tick(632)
  assert_equal 0x9F, core.ppu.read_oam(0xFE9F)
  assert_equal false, core.dma.active?
end

assert('GameBoy::DMA can read source bytes from FF00 page registers') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  core.bus.write8(0xFF07, 0x05)
  core.bus.write8(0xFF0F, 0x1F)
  core.bus.write8(0xFFFF, 0x12)
  core.bus.write8(0xFF46, 0xFF)
  core.dma.tick(640)

  assert_equal core.bus.read8(0xFF00), core.ppu.read_oam(0xFE00)
  assert_equal core.bus.read8(0xFF07), core.ppu.read_oam(0xFE07)
  assert_equal core.bus.read8(0xFF0F), core.ppu.read_oam(0xFE0F)
  assert_equal 0xFF, core.ppu.read_oam(0xFE7F)
end

assert('GameBoy::FrameExporter outputs PPM header') do
  frame = Array.new(GameBoy::Constants::SCREEN_WIDTH * GameBoy::Constants::SCREEN_HEIGHT, 0)
  ppm = GameBoy::FrameExporter.to_ppm(frame, 1)
  header = "P3\n160 144\n255\n"

  assert_equal header, ppm[0, header.length]
end

assert('GameBoy::PPU ignores writes to LY') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  before = core.bus.read8(0xFF44)
  core.bus.write8(0xFF44, 0x99)

  assert_equal before, core.bus.read8(0xFF44)
end

assert('GameBoy::PPU counts off-screen X sprites toward 10 sprite limit') do
  ppu = build_test_ppu
  write_test_sprite_tile(ppu, 0, 0xFF)

  10.times do |index|
    base = 0xFE00 + index * 4
    ppu.write_oam(base, 16)
    ppu.write_oam(base + 1, 0)
    ppu.write_oam(base + 2, 0)
    ppu.write_oam(base + 3, 0)
  end

  base = 0xFE00 + 10 * 4
  ppu.write_oam(base, 16)
  ppu.write_oam(base + 1, 8)
  ppu.write_oam(base + 2, 0)
  ppu.write_oam(base + 3, 0)

  ppu.render_scanline_for_test

  assert_equal 0, ppu.frame_buffer[0]
end

assert('GameBoy::PPU gives smaller X sprite higher DMG priority') do
  ppu = build_test_ppu
  write_test_sprite_tile(ppu, 0, 0xFF)
  write_test_sprite_tile(ppu, 1, 0xFF)

  # 先に大きい X の sprite を置き、後ろに小さい X の sprite を置く。
  # DMG では小さい X が優先されるので、重なり部分では後者が見えるべき。
  ppu.write_oam(0xFE00, 16)
  ppu.write_oam(0xFE01, 12)
  ppu.write_oam(0xFE02, 0)
  ppu.write_oam(0xFE03, 0x00)

  ppu.write_oam(0xFE04, 16)
  ppu.write_oam(0xFE05, 8)
  ppu.write_oam(0xFE06, 1)
  ppu.write_oam(0xFE07, 0x10)

  ppu.render_scanline_for_test

  assert_equal 2, ppu.frame_buffer[4]
end

assert('GameBoy::PPU uses earlier OAM sprite when X is tied') do
  ppu = build_test_ppu
  write_test_sprite_tile(ppu, 0, 0xFF)
  write_test_sprite_tile(ppu, 1, 0xFF)

  ppu.write_oam(0xFE00, 16)
  ppu.write_oam(0xFE01, 8)
  ppu.write_oam(0xFE02, 0)
  ppu.write_oam(0xFE03, 0x00)

  ppu.write_oam(0xFE04, 16)
  ppu.write_oam(0xFE05, 8)
  ppu.write_oam(0xFE06, 1)
  ppu.write_oam(0xFE07, 0x10)

  ppu.render_scanline_for_test

  assert_equal 1, ppu.frame_buffer[0]
end

assert('GameBoy::PPU bg-over-obj masks lower priority sprites too') do
  ppu = build_test_ppu
  write_test_sprite_tile(ppu, 0, 0xFF)
  write_test_sprite_tile(ppu, 1, 0xFF)
  bg_color_ids = Array.new(GameBoy::Constants::SCREEN_WIDTH, 1)

  # 先頭 OAM の sprite が優先されるが、BG over OBJ が立っているので
  # 背景色 1-3 の上には出ない。下位優先 sprite も見えてはいけない。
  ppu.write_oam(0xFE00, 16)
  ppu.write_oam(0xFE01, 8)
  ppu.write_oam(0xFE02, 0)
  ppu.write_oam(0xFE03, 0x80)

  ppu.write_oam(0xFE04, 16)
  ppu.write_oam(0xFE05, 8)
  ppu.write_oam(0xFE06, 1)
  ppu.write_oam(0xFE07, 0x10)

  ppu.render_sprites_for_test(0, 0, bg_color_ids)

  assert_equal 0, ppu.frame_buffer[0]
end

assert('GameBoy::Bus blocks VRAM access during PPU mode 3') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  core.ppu.write_vram(0x8000, 0x12)
  core.ppu.load_boot_state(
    lcdc: 0x91,
    stat_select: 0x00,
    mode: 3,
    coincidence: false,
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

  assert_equal 0xFF, core.bus.read8(0x8000)
  core.bus.write8(0x8000, 0x34)
  assert_equal 0x12, core.ppu.read_vram(0x8000)
end

assert('GameBoy::Bus blocks OAM access during DMA') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  core.ppu.write_oam(0xFE00, 0x56)
  core.bus.write8(0xFF46, 0xC0)

  assert_equal 0xFF, core.bus.read8(0xFE00)
  core.bus.write8(0xFE00, 0x78)
  assert_equal 0x56, core.ppu.read_oam(0xFE00)

  core.dma.tick(640)
  core.bus.write8(0xFE00, 0x78)
  assert_equal 0x78, core.ppu.read_oam(0xFE00)
end

assert('GameBoy::CPU implements HALT bug when IME is off and interrupt is pending') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0x76
  rom[0x0101] = 0x06
  rom[0x0102] = 0x12
  rom[0x0103] = 0x00

  core = GameBoy::Core.new(rom)
  core.interrupts.write_ie(0x01)
  core.interrupts.request(GameBoy::Constants::INT_VBLANK)

  core.step
  core.step

  assert_equal 0x0600, core.cpu.bc & 0xFF00
  assert_equal 0x0102, core.cpu.pc
end

assert('GameBoy::CPU STOP consumes trailing byte') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0x10
  rom[0x0101] = 0x99

  core = GameBoy::Core.new(rom)
  cycles = core.step

  assert_equal 4, cycles
  assert_equal 0x0102, core.cpu.pc
end

assert('GameBoy::CPU STOP returns 0 dots while stopped') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0x10
  rom[0x0101] = 0x00

  core = GameBoy::Core.new(rom)
  core.step
  cycles = core.step

  assert_equal 0, cycles
  assert_equal 0x0102, core.cpu.pc
end

assert('GameBoy::CPU STOP wakes on selected joypad line falling edge') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0x10
  rom[0x0101] = 0x00
  rom[0x0102] = 0x04

  core = GameBoy::Core.new(rom)
  core.step

  assert_equal 0, core.step

  core.press_button(:a)
  cycles = core.step

  assert_equal 4, cycles
  assert_equal 0x0113, core.cpu.bc
  assert_equal 0x0103, core.cpu.pc
end

assert('GameBoy::CPU STOP wake services joypad interrupt before next opcode') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0xFB
  rom[0x0101] = 0x10
  rom[0x0102] = 0x00

  core = GameBoy::Core.new(rom)
  core.interrupts.write_ie(0x10)
  core.interrupts.write_if(0xE0)

  core.step
  core.step

  assert_equal 0, core.step

  core.press_button(:a)

  assert_equal 0x10, core.interrupts.read_if & 0x10

  cycles = core.step

  assert_equal 20, cycles
  assert_equal 0x0060, core.cpu.pc
  assert_equal 0xFFFC, core.cpu.sp
  assert_equal 0x03, core.bus.read8(0xFFFC)
  assert_equal 0x01, core.bus.read8(0xFFFD)
  assert_equal 0xE0, core.interrupts.read_if
end

assert('GameBoy::CPU STOP stays stopped for unselected joypad press') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0x10
  rom[0x0101] = 0x00
  rom[0x0102] = 0x04

  core = GameBoy::Core.new(rom)
  core.bus.write8(0xFF00, 0x20)
  core.step

  core.press_button(:a)

  assert_equal 0, core.step
  assert_equal 0x0102, core.cpu.pc
end

assert('GameBoy::CPU STOP does not remain stopped when wake condition is already met') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0x10
  rom[0x0101] = 0x00
  rom[0x0102] = 0x06
  rom[0x0103] = 0x12

  core = GameBoy::Core.new(rom)
  core.bus.write8(0xFF00, 0x10)
  core.press_button(:a)

  assert_equal 4, core.step

  cycles = core.step

  assert_equal 8, cycles
  assert_equal 0x12, core.cpu.b
  assert_equal 0x0104, core.cpu.pc
end

assert('GameBoy::Joypad requests interrupt on selected line falling edge from P1 write') do
  core = GameBoy::Core.new(Array.new(0x8000, 0))
  core.bus.write8(0xFF00, 0x30)
  core.press_button(:a)
  core.interrupts.write_if(0xE0)

  core.bus.write8(0xFF00, 0x10)

  assert_equal 0x10, core.interrupts.read_if & 0x10
end

assert('GameBoy::Core#run_frame stops when CPU is stopped') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0x10
  rom[0x0101] = 0x00

  core = GameBoy::Core.new(rom)
  result = core.run_frame

  assert_equal 4, result[:dots]
  assert_equal 2, result[:steps]
  assert_false result[:frame_ready]
end

assert('GameBoy::CPU CALL NZ,a16 pushes return address when taken') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0xC4
  rom[0x0101] = 0x34
  rom[0x0102] = 0x12

  core = GameBoy::Core.new(rom)
  core.cpu.af = 0x0000
  cycles = core.step

  assert_equal 24, cycles
  assert_equal 0x1234, core.cpu.pc
  assert_equal 0xFFFC, core.cpu.sp
  assert_equal 0x03, core.bus.read8(0xFFFC)
  assert_equal 0x01, core.bus.read8(0xFFFD)
end

assert('GameBoy::CPU CALL NZ,a16 skips call when not taken') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0xC4
  rom[0x0101] = 0x34
  rom[0x0102] = 0x12

  core = GameBoy::Core.new(rom)
  core.cpu.af = 0x0080
  cycles = core.step

  assert_equal 12, cycles
  assert_equal 0x0103, core.cpu.pc
  assert_equal 0xFFFE, core.cpu.sp
end

assert('GameBoy::CPU CALL Z,a16 pushes return address when taken') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0xCC
  rom[0x0101] = 0x34
  rom[0x0102] = 0x12

  core = GameBoy::Core.new(rom)
  core.cpu.af = 0x0080
  cycles = core.step

  assert_equal 24, cycles
  assert_equal 0x1234, core.cpu.pc
  assert_equal 0xFFFC, core.cpu.sp
  assert_equal 0x03, core.bus.read8(0xFFFC)
  assert_equal 0x01, core.bus.read8(0xFFFD)
end

assert('GameBoy::CPU CALL Z,a16 skips call when not taken') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0xCC
  rom[0x0101] = 0x34
  rom[0x0102] = 0x12

  core = GameBoy::Core.new(rom)
  core.cpu.af = 0x0000
  cycles = core.step

  assert_equal 12, cycles
  assert_equal 0x0103, core.cpu.pc
  assert_equal 0xFFFE, core.cpu.sp
end

assert('GameBoy::CPU CALL NC,a16 pushes return address when taken') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0xD4
  rom[0x0101] = 0x34
  rom[0x0102] = 0x12

  core = GameBoy::Core.new(rom)
  core.cpu.af = 0x0000
  cycles = core.step

  assert_equal 24, cycles
  assert_equal 0x1234, core.cpu.pc
  assert_equal 0xFFFC, core.cpu.sp
  assert_equal 0x03, core.bus.read8(0xFFFC)
  assert_equal 0x01, core.bus.read8(0xFFFD)
end

assert('GameBoy::CPU CALL NC,a16 skips call when not taken') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0xD4
  rom[0x0101] = 0x34
  rom[0x0102] = 0x12

  core = GameBoy::Core.new(rom)
  core.cpu.af = 0x0010
  cycles = core.step

  assert_equal 12, cycles
  assert_equal 0x0103, core.cpu.pc
  assert_equal 0xFFFE, core.cpu.sp
end

assert('GameBoy::CPU CALL C,a16 pushes return address when taken') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0xDC
  rom[0x0101] = 0x34
  rom[0x0102] = 0x12

  core = GameBoy::Core.new(rom)
  core.cpu.af = 0x0010
  cycles = core.step

  assert_equal 24, cycles
  assert_equal 0x1234, core.cpu.pc
  assert_equal 0xFFFC, core.cpu.sp
  assert_equal 0x03, core.bus.read8(0xFFFC)
  assert_equal 0x01, core.bus.read8(0xFFFD)
end

assert('GameBoy::CPU CALL C,a16 skips call when not taken') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  rom[0x0100] = 0xDC
  rom[0x0101] = 0x34
  rom[0x0102] = 0x12

  core = GameBoy::Core.new(rom)
  core.cpu.af = 0x0000
  cycles = core.step

  assert_equal 12, cycles
  assert_equal 0x0103, core.cpu.pc
  assert_equal 0xFFFE, core.cpu.sp
end

assert('GameBoy::Timer DIV reset can tick TIMA on falling edge') do
  timer, interrupts = build_test_timer
  timer.write_io(0xFF07, 0x05)
  timer.tick(8)

  assert_equal 0x00, timer.read_io(0xFF05)

  timer.write_io(0xFF04, 0x00)

  assert_equal 0x01, timer.read_io(0xFF05)
  assert_equal 0xE0, interrupts.read_if
end

assert('GameBoy::Timer TAC write can tick TIMA when selected bit falls') do
  timer, _interrupts = build_test_timer
  timer.write_io(0xFF07, 0x05)
  timer.tick(8)

  timer.write_io(0xFF07, 0x06)

  assert_equal 0x01, timer.read_io(0xFF05)
end

assert('GameBoy::Timer overflow reloads TMA one M-cycle later') do
  timer, interrupts = build_test_timer
  timer.write_io(0xFF06, 0xAB)
  timer.write_io(0xFF05, 0xFF)
  timer.write_io(0xFF07, 0x05)

  timer.tick(16)

  assert_equal 0x00, timer.read_io(0xFF05)
  assert_equal 0xE0, interrupts.read_if

  timer.tick(3)
  assert_equal 0x00, timer.read_io(0xFF05)
  assert_equal 0xE0, interrupts.read_if

  timer.tick(1)
  assert_equal 0xAB, timer.read_io(0xFF05)
  assert_equal 0xE4, interrupts.read_if
end

assert('GameBoy::Timer TIMA write during pending reload cancels reload and interrupt') do
  timer, interrupts = build_test_timer
  timer.write_io(0xFF06, 0xAB)
  timer.write_io(0xFF05, 0xFF)
  timer.write_io(0xFF07, 0x05)

  timer.tick(16)
  timer.write_io(0xFF05, 0x66)
  timer.tick(4)

  assert_equal 0x66, timer.read_io(0xFF05)
  assert_equal 0xE0, interrupts.read_if
end

assert('GameBoy::Timer TIMA write during reload cycle is ignored') do
  timer, _interrupts = build_test_timer
  timer.write_io(0xFF06, 0xAB)
  timer.write_io(0xFF05, 0xFF)
  timer.write_io(0xFF07, 0x05)

  timer.tick(20)
  timer.write_io(0xFF05, 0x66)

  assert_equal 0xAB, timer.read_io(0xFF05)

  timer.tick(4)
  timer.write_io(0xFF05, 0x66)
  assert_equal 0x66, timer.read_io(0xFF05)
end

assert('GameBoy::Timer TMA write during reload cycle also updates TIMA') do
  timer, _interrupts = build_test_timer
  timer.write_io(0xFF06, 0xAB)
  timer.write_io(0xFF05, 0xFF)
  timer.write_io(0xFF07, 0x05)

  timer.tick(20)
  timer.write_io(0xFF06, 0x77)

  assert_equal 0x77, timer.read_io(0xFF06)
  assert_equal 0x77, timer.read_io(0xFF05)
end
