begin
  GameBoy::Core
rescue NameError
  load File.expand_path('support/load_game_boy.rb', File.dirname(__FILE__))
end

begin
  GameBoy::SDL2Host
rescue NameError
  puts 'このフロントエンドは mruby + SDL2 用です。'
  puts 'まず Docker かローカルで GAME_BOY_ENABLE_SDL2=1 を付けて mruby をビルドしてください。'
  exit 1
end

BUTTONS = [
  [:right, GameBoy::SDL2Host::BUTTON_RIGHT],
  [:left, GameBoy::SDL2Host::BUTTON_LEFT],
  [:up, GameBoy::SDL2Host::BUTTON_UP],
  [:down, GameBoy::SDL2Host::BUTTON_DOWN],
  [:a, GameBoy::SDL2Host::BUTTON_A],
  [:b, GameBoy::SDL2Host::BUTTON_B],
  [:select, GameBoy::SDL2Host::BUTTON_SELECT],
  [:start, GameBoy::SDL2Host::BUTTON_START]
].freeze

ROOT_DIR = File.expand_path('..', File.dirname(__FILE__))

def frontend_root_path(*parts)
  File.join(ROOT_DIR, *parts)
end

def collect_rom_paths(dir, paths)
  Dir.entries(dir).sort.each do |entry|
    next if ['.', '..'].include?(entry)

    path = File.join(dir, entry)
    if File.directory?(path)
      collect_rom_paths(path, paths)
    elsif path.end_with?('.gb')
      paths << path
    end
  end
end

def available_rom_paths
  rom_root = frontend_root_path('test_roms')
  return [] unless File.directory?(rom_root)

  rom_paths = []
  collect_rom_paths(rom_root, rom_paths)
  rom_paths
end

def select_rom_path(argv_path)
  return argv_path if argv_path

  rom_paths = available_rom_paths

  if rom_paths.empty?
    puts 'ROM が見つかりませんでした。引数で ROM パスを指定してください。'
    raise 'ROM not found'
  end

  return rom_paths.first if rom_paths.length == 1

  puts '利用する ROM を選択してください:'
  rom_paths.each_with_index do |path, index|
    puts format('%d) %s', index + 1, path)
  end

  selected_index = nil
  while selected_index.nil?
    print '> '
    input = $stdin.gets
    raise 'ROM selection canceled' if input.nil?

    choice = input.strip.to_i
    next if choice <= 0 || choice > rom_paths.length

    selected_index = choice - 1
  end

  rom_paths[selected_index]
end

def build_core(rom_path)
  rom_data = File.open(rom_path, 'rb') { |file| file.read }
  [rom_data, GameBoy::Core.new(rom_data)]
end

def apply_hotkeys(host, hotkeys_mask, speed_multiplier)
  paused = false
  reset = false

  paused = true if (hotkeys_mask & host.class::HOTKEY_PAUSE) != 0

  reset = true if (hotkeys_mask & host.class::HOTKEY_RESET) != 0

  if (hotkeys_mask & host.class::HOTKEY_SPEED) != 0
    speed_multiplier = speed_multiplier == 1 ? 2 : 1
    puts "speed: #{speed_multiplier}x"
  end

  [paused, reset, speed_multiplier]
end

rom_path = select_rom_path(ARGV[0])
scale = (ARGV[1] || '4').to_i
scale = 1 if scale < 1
title = ARGV[2] || 'mruby_game_boy'

_, gb = build_core(rom_path)
host = GameBoy::SDL2Host.new(title, GameBoy::Constants::SCREEN_WIDTH, GameBoy::Constants::SCREEN_HEIGHT, scale)

def sync_buttons(gb, previous_mask, current_mask)
  BUTTONS.each do |name, bit|
    before = (previous_mask & bit) != 0
    after = (current_mask & bit) != 0

    if !before && after
      gb.press_button(name)
    elsif before && !after
      gb.release_button(name)
    end
  end
end

previous_mask = 0
paused = false
speed_multiplier = 1

begin
  until host.quit_requested?
    current_mask = host.poll
    hotkeys_mask = host.hotkeys_mask

    toggle_pause, reset_requested, speed_multiplier = apply_hotkeys(host, hotkeys_mask, speed_multiplier)
    if toggle_pause
      paused = !paused
      puts(paused ? 'paused' : 'resumed')
    end

    if reset_requested
      _, gb = build_core(rom_path)
      previous_mask = 0
      puts 'reset'
    end

    sync_buttons(gb, previous_mask, current_mask)
    previous_mask = current_mask

    unless paused
      speed_multiplier.times do
        gb.run_frame(200_000)
      end
    end

    host.render(gb.frame_buffer)
    host.delay(1)
  end
ensure
  host.close if host
end
