module GameBoy
  class FrameExporter
    DMG_RGB = [
      [224, 248, 208],
      [136, 192, 112],
      [52, 104, 86],
      [8, 24, 32]
    ].freeze

    ASCII_SHADES = [' ', '.', '*', '#'].freeze

    def self.write_ppm(path, frame_buffer, scale = 1)
      # 依存を増やさず Linux/X で見やすいよう、最初の画像出力は PPM にする。
      scale = 1 if scale < 1
      ensure_directory(File.dirname(path))

      File.open(path, 'wb') do |file|
        file.write(to_ppm(frame_buffer, scale))
      end
    end

    def self.to_ppm(frame_buffer, scale = 1)
      width = Constants::SCREEN_WIDTH * scale
      height = Constants::SCREEN_HEIGHT * scale
      output = "P3\n#{width} #{height}\n255\n"

      y = 0
      while y < Constants::SCREEN_HEIGHT
        scaled_line = String.new
        x = 0

        while x < Constants::SCREEN_WIDTH
          r, g, b = DMG_RGB[frame_buffer[y * Constants::SCREEN_WIDTH + x] || 0]
          pixel = "#{r} #{g} #{b}\n"
          repeat = 0
          while repeat < scale
            scaled_line += pixel
            repeat += 1
          end
          x += 1
        end

        repeat_y = 0
        while repeat_y < scale
          output += scaled_line
          repeat_y += 1
        end

        y += 1
      end

      output
    end

    def self.to_ascii(frame_buffer, x_step = 2, y_step = 2)
      # ターミナル確認用の簡易プレビュー。
      lines = []
      y = 0

      while y < Constants::SCREEN_HEIGHT
        line = String.new
        x = 0
        while x < Constants::SCREEN_WIDTH
          shade = frame_buffer[y * Constants::SCREEN_WIDTH + x] || 0
          line += ASCII_SHADES[shade]
          x += x_step
        end
        lines << line
        y += y_step
      end

      lines.join("\n")
    end

    def self.ensure_directory(path)
      return if path == '.' || Dir.exist?(path)

      parent = File.dirname(path)
      ensure_directory(parent) if parent != path
      Dir.mkdir(path) unless Dir.exist?(path)
    end
  end
end
