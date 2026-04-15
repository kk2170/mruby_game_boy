begin
  GameBoy::Core
rescue NameError
  load File.expand_path('support/load_game_boy.rb', File.dirname(__FILE__))
end

rom_path = ARGV[0] || 'test_roms/tobutobugirl/tobu.gb'
output_path = ARGV[1] || 'tmp/tobutobugirl/frame.ppm'
frame_count = (ARGV[2] || '30').to_i
scale = (ARGV[3] || '2').to_i

rom_data = File.open(rom_path, 'rb') { |file| file.read }
gb = GameBoy::Core.new(rom_data)

# 指定フレーム数だけ進めて、最後のフレームバッファを PPM として保存する。
frame_count.times do |index|
  result = gb.run_frame(200_000)
  puts "frame=#{index} dots=#{result[:dots]} steps=#{result[:steps]} ready=#{result[:frame_ready]} pc=%04X" % gb.cpu.pc
end

GameBoy::FrameExporter.write_ppm(output_path, gb.frame_buffer, scale)

puts "saved_ppm=#{output_path}"
puts 'ascii_preview:'
puts GameBoy::FrameExporter.to_ascii(gb.frame_buffer)
