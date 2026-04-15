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

rom_path = ARGV[0] || 'test_roms/tobutobugirl/tobu.gb'
scale = (ARGV[1] || '4').to_i
scale = 1 if scale < 1
title = ARGV[2] || 'mruby_game_boy'

rom_data = File.open(rom_path, 'rb') { |file| file.read }
gb = GameBoy::Core.new(rom_data)
host = GameBoy::SDL2Host.new(title, GameBoy::Constants::SCREEN_WIDTH, GameBoy::Constants::SCREEN_HEIGHT, scale)

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

begin
  until host.quit_requested?
    current_mask = host.poll
    sync_buttons(gb, previous_mask, current_mask)
    previous_mask = current_mask

    gb.run_frame(200_000)
    host.render(gb.frame_buffer)
    host.delay(1)
  end
ensure
  host.close if host
end
