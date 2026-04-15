begin
  GameBoy::Core
rescue NameError
  script_dir = File.dirname(__FILE__)
  root = File.expand_path('../..', script_dir)
  load File.join(root, 'mrbgems/mruby-game-boy/mrblib/game_boy.rb')

  Dir.glob(File.join(root, 'mrbgems/mruby-game-boy/mrblib/game_boy/**/*.rb')).sort.each do |path|
    load path
  end
end
