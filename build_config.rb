MRuby::Build.new do |conf|
  toolchain :gcc

  conf.gembox 'default'
  conf.gem File.expand_path('mrbgems/mruby-game-boy', __dir__)
  conf.gem File.expand_path('mrbgems/mruby-game-boy-sdl2', __dir__) if ENV['GAME_BOY_ENABLE_SDL2'] == '1'

  conf.enable_test
end
