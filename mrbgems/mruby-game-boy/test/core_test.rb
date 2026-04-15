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

assert('GameBoy::Cartridge builds basic MBC1 cartridges') do
  rom = Array.new(256 * 1024, 0)
  rom[0x0147] = 0x03
  rom[0x0148] = 0x03
  rom[0x0149] = 0x02
  rom[0x4000] = 0x42

  cart = GameBoy::Cartridge.build(rom)

  assert_equal 'GameBoy::Cartridge::MBC1', cart.class.to_s
  assert_equal 0x42, cart.read8(0x4000)
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

assert('GameBoy::Bus routes FF46 writes to DMA') do
  rom = Array.new(0x8000, 0)
  rom[0x0147] = 0x00
  core = GameBoy::Core.new(rom)

  0x00A0.times do |index|
    core.bus.write8(0xC000 + index, index & 0xFF)
  end

  core.bus.write8(0xFF46, 0xC0)

  assert_equal 0x00, core.ppu.read_oam(0xFE00)
  assert_equal 0x9F, core.ppu.read_oam(0xFE9F)
end

assert('GameBoy::FrameExporter outputs PPM header') do
  frame = Array.new(GameBoy::Constants::SCREEN_WIDTH * GameBoy::Constants::SCREEN_HEIGHT, 0)
  ppm = GameBoy::FrameExporter.to_ppm(frame, 1)

  assert_true ppm.start_with?("P6\n160 144\n255\n")
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

  ppu.send(:render_scanline)

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

  ppu.send(:render_scanline)

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

  ppu.send(:render_scanline)

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

  ppu.send(:render_sprites, 0, 0, bg_color_ids)

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
  assert_equal 0x00, core.ppu.read_oam(0xFE00)

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
