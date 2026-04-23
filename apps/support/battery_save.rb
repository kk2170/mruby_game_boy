def battery_save_path_for_rom(rom_path)
  "#{rom_path}.sav"
end

def battery_dump_to_binary(dump)
  return dump if dump.is_a?(String)

  data = "\x00" * dump.length
  index = 0

  while index < dump.length
    data.setbyte(index, dump[index] & 0xFF)
    index += 1
  end

  data
end

def load_core_with_battery_save(rom_path)
  rom_data = File.open(rom_path, 'rb') { |file| file.read }
  gb = GameBoy::Core.new(rom_data)
  save_path = battery_save_path_for_rom(rom_path)

  if gb.battery_backed? && File.exist?(save_path)
    gb.load_battery_ram(File.open(save_path, 'rb') { |file| file.read })
    puts "loaded_battery=#{save_path}"
  end

  [gb, save_path]
end

def persist_core_battery_save(gb, save_path)
  dump = gb.dump_battery_ram
  return if dump.nil?

  File.open(save_path, 'wb') do |file|
    file.write(battery_dump_to_binary(dump))
  end

  puts "saved_battery=#{save_path}"
end
