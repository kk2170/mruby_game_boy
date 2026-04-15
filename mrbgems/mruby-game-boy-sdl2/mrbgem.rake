MRuby::Gem::Specification.new('mruby-game-boy-sdl2') do |spec|
  spec.license = 'MIT'
  spec.authors = 'OpenAI'
  spec.summary = 'SDL2 host bridge for mruby_game_boy'
  spec.add_dependency 'mruby-game-boy'

  spec.linker.libraries << 'SDL2'
end
