app_support_path = File.expand_path('support/load_game_boy.rb', File.dirname(__FILE__))
eval(File.open(app_support_path, 'rb') { |file| file.read }, binding, app_support_path)

rom_path = ARGV[0] || 'test_roms/tobutobugirl/tobu.gb'
output_dir = ARGV[1] || 'tmp/linux_x_preview'
warmup_frames = (ARGV[2] || '20').to_i
capture_frames = (ARGV[3] || '10').to_i
scale = (ARGV[4] || '3').to_i

gb, save_path = load_core_with_battery_save(rom_path)

begin
  # 最初の数フレームは初期化中で真っ黒なことが多いので、少し暖機してから保存する。
  warmup_frames.times do
    gb.run_frame(200_000)
  end

  # Linux/X 向けの最小プレビュー手段として、連番 PPM を吐き出す。
  # 生成したファイルは feh / display / xdg-open など任意の X アプリで見られる。
  capture_frames.times do |index|
    result = gb.run_frame(200_000)
    path = File.join(output_dir, format('frame_%03d.ppm', index))
    GameBoy::FrameExporter.write_ppm(path, gb.frame_buffer, scale)

    puts "frame=#{index} dots=#{result[:dots]} steps=#{result[:steps]} ready=#{result[:frame_ready]} pc=%04X file=#{path}" % gb.cpu.pc
  end

  puts "linux_x_hint: feh --reload 0.1 #{File.join(output_dir, 'frame_*.ppm')}"
ensure
  persist_core_battery_save(gb, save_path)
end
