begin
  GameBoy::Core
rescue NameError
  load File.expand_path('support/load_game_boy.rb', File.dirname(__FILE__))
end

rom_path = ARGV[0] || 'test_roms/tobutobugirl/tobu.gb'
step_count = (ARGV[1] || '0').to_i

rom_data = File.open(rom_path, 'rb') { |file| file.read }
gb = GameBoy::Core.new(rom_data)
header = gb.header

puts '== ROM =='
puts "path: #{rom_path}"
puts "title: #{header[:title]}"
puts format('cartridge_type: 0x%02X', header[:cartridge_type])
puts "rom_size_bytes: #{header[:rom_size_bytes]}"
puts "ram_size_bytes: #{header[:ram_size_bytes]}"
puts "entry_point: #{header[:entry_point].map { |byte| format('%02X', byte) }.join(' ')}"

puts '== BOOT STATE =='
puts gb.cpu.register_dump

if step_count > 0
  executed = 0

  begin
    while executed < step_count
      gb.step
      executed += 1
    end

    puts '== EXECUTION =='
    puts "executed_steps: #{executed}"
    puts gb.cpu.register_dump
  rescue GameBoy::UnsupportedOpcodeError => e
    puts '== EXECUTION STOPPED =='
    puts e.message
    puts "executed_steps: #{executed}"
    puts gb.cpu.register_dump
    exit 2
  end
end
