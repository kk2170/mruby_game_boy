script_dir = File.dirname(__FILE__)
root = File.expand_path('../..', script_dir)

eval_support_file = lambda do |path|
  eval(File.open(path, 'rb') { |file| file.read }, binding, path)
end

game_boy_loaded = true

begin
  GameBoy::Core
rescue NameError
  game_boy_loaded = false
end

unless game_boy_loaded
  eval_support_file.call(File.join(root, 'mrbgems/mruby-game-boy/mrblib/game_boy.rb'))

  Dir.glob(File.join(root, 'mrbgems/mruby-game-boy/mrblib/game_boy/**/*.rb')).sort.each do |path|
    eval_support_file.call(path)
  end
end

eval_support_file.call(File.join(script_dir, 'battery_save.rb'))

mbc3_loaded = true

begin
  GameBoy::Cartridge::MBC3
rescue NameError
  mbc3_loaded = false
end

if mbc3_loaded
  GameBoy::Cartridge::MBC3.time_source = lambda do
    begin
      ::Time.now.to_i
    rescue NameError
      0
    end
  end
end
