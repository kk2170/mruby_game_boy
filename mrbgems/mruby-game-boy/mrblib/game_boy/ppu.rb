module GameBoy
  class PPU
    def initialize(interrupts)
      @interrupts = interrupts
      @frame_buffer = Array.new(Constants::SCREEN_WIDTH * Constants::SCREEN_HEIGHT, 0)
      @vram = Array.new(0x2000, 0)
      @oam = Array.new(0x00A0, 0)
      reset
    end

    def reset
      @lcdc = 0x00
      @stat_select = 0x00
      @mode = 0
      @mode_dots = 0
      @coincidence = false

      @scy = 0
      @scx = 0
      @ly = 0
      @lyc = 0
      @bgp = 0
      @obp0 = 0
      @obp1 = 0
      @wy = 0
      @wx = 0

      @frame_ready = false
      clear_frame
      update_coincidence(false)
    end

    def load_boot_state(values)
      @lcdc = values[:lcdc] & 0xFF
      @stat_select = values[:stat_select] & 0x78
      @mode = values[:mode] & 0x03
      @mode_dots = 0
      @coincidence = !!values[:coincidence]
      @scy = values[:scy] & 0xFF
      @scx = values[:scx] & 0xFF
      @ly = values[:ly] & 0xFF
      @lyc = values[:lyc] & 0xFF
      @bgp = values[:bgp] & 0xFF
      @obp0 = values[:obp0] & 0xFF
      @obp1 = values[:obp1] & 0xFF
      @wy = values[:wy] & 0xFF
      @wx = values[:wx] & 0xFF
      @frame_ready = false
      clear_frame
    end

    def tick(dots)
      return unless lcd_enabled?

      remaining = dots

      while remaining > 0
        case @mode
        when 2
          consumed = consume_mode_dots(remaining, 80)
          remaining -= consumed
          set_mode(3) if @mode_dots == 0
        when 3
          consumed = consume_mode_dots(remaining, 172)
          remaining -= consumed
          if @mode_dots == 0
            render_scanline if @ly < Constants::SCREEN_HEIGHT
            set_mode(0)
          end
        when 0
          consumed = consume_mode_dots(remaining, 204)
          remaining -= consumed
          advance_visible_line if @mode_dots == 0
        when 1
          consumed = consume_mode_dots(remaining, Constants::DOTS_PER_LINE)
          remaining -= consumed
          advance_vblank_line if @mode_dots == 0
        else
          set_mode(0)
        end
      end
    end

    def frame_ready?
      @frame_ready
    end

    def clear_frame_ready!
      @frame_ready = false
    end

    attr_reader :frame_buffer

    def vram_accessible?
      !lcd_enabled? || @mode != 3
    end

    def oam_accessible?(dma_active = false)
      return false if dma_active

      !lcd_enabled? || (@mode != 2 && @mode != 3)
    end

    def read_vram(addr)
      @vram[(addr - 0x8000) & 0x1FFF]
    end

    def write_vram(addr, value)
      @vram[(addr - 0x8000) & 0x1FFF] = value & 0xFF
    end

    def read_oam(addr)
      @oam[(addr - 0xFE00) & 0x00FF]
    end

    def write_oam(addr, value)
      index = addr - 0xFE00
      return if index < 0 || index >= @oam.length

      @oam[index] = value & 0xFF
    end

    def read_io(addr)
      case addr
      when 0xFF40 then @lcdc
      when 0xFF41 then 0x80 | @stat_select | (@coincidence ? 0x04 : 0x00) | (@mode & 0x03)
      when 0xFF42 then @scy
      when 0xFF43 then @scx
      when 0xFF44 then @ly
      when 0xFF45 then @lyc
      when 0xFF47 then @bgp
      when 0xFF48 then @obp0
      when 0xFF49 then @obp1
      when 0xFF4A then @wy
      when 0xFF4B then @wx
      else 0xFF
      end
    end

    def write_io(addr, value)
      value &= 0xFF

      case addr
      when 0xFF40
        was_enabled = lcd_enabled?
        @lcdc = value

        if was_enabled && !lcd_enabled?
          @ly = 0
          @mode_dots = 0
          set_mode(0)
          update_coincidence(false)
        elsif !was_enabled && lcd_enabled?
          @ly = 0
          @mode_dots = 0
          set_mode(2)
          update_coincidence(true)
        end
      when 0xFF41
        @stat_select = value & 0x78
      when 0xFF42
        @scy = value
      when 0xFF43
        @scx = value
      when 0xFF44
        # LY は read-only として扱い、書き込みは無視する。
      when 0xFF45
        @lyc = value
        update_coincidence(true)
      when 0xFF47
        @bgp = value
      when 0xFF48
        @obp0 = value
      when 0xFF49
        @obp1 = value
      when 0xFF4A
        @wy = value
      when 0xFF4B
        @wx = value
      end

      value
    end

    private

    def lcd_enabled?
      (@lcdc & 0x80) != 0
    end

    def consume_mode_dots(remaining, target)
      needed = target - @mode_dots
      consumed = remaining < needed ? remaining : needed
      @mode_dots += consumed

      @mode_dots = 0 if @mode_dots >= target

      consumed
    end

    def advance_visible_line
      @ly = (@ly + 1) & 0xFF

      if @ly == Constants::SCREEN_HEIGHT
        @frame_ready = true
        @interrupts.request(Constants::INT_VBLANK)
        set_mode(1)
      else
        set_mode(2)
      end

      update_coincidence(true)
    end

    def advance_vblank_line
      @ly = (@ly + 1) & 0xFF

      if @ly > 153
        @ly = 0
        set_mode(2)
      end

      update_coincidence(true)
    end

    def set_mode(mode)
      @mode = mode & 0x03

      case @mode
      when 0
        @interrupts.request(Constants::INT_LCD) if (@stat_select & 0x08) != 0
      when 1
        @interrupts.request(Constants::INT_LCD) if (@stat_select & 0x10) != 0
      when 2
        @interrupts.request(Constants::INT_LCD) if (@stat_select & 0x20) != 0
      end
    end

    def update_coincidence(may_interrupt)
      previous = @coincidence
      @coincidence = (@ly == @lyc)

      return unless may_interrupt && !previous && @coincidence && (@stat_select & 0x40) != 0

      @interrupts.request(Constants::INT_LCD)
    end

    def render_scanline
      line = @ly
      offset = line * Constants::SCREEN_WIDTH
      bg_color_ids = Array.new(Constants::SCREEN_WIDTH, 0)

      # まず BG / Window を描き、その後に Sprite を重ねる。
      if bg_enabled?
        render_background_and_window(line, bg_color_ids)
      else
        fill_line_colors(bg_color_ids, 0)
      end

      x = 0
      while x < Constants::SCREEN_WIDTH
        @frame_buffer[offset + x] = palette_color(@bgp, bg_color_ids[x])
        x += 1
      end

      render_sprites(line, offset, bg_color_ids) if obj_enabled?
    end

    def render_background_and_window(line, bg_color_ids)
      # Window が有効かつ現在の走査線に入ったら、BG の代わりに Window 座標で読む。
      map_base = (@lcdc & 0x08) != 0 ? 0x1C00 : 0x1800
      window_map_base = (@lcdc & 0x40) != 0 ? 0x1C00 : 0x1800
      tile_base_signed = (@lcdc & 0x10) == 0
      window_enabled_for_line = window_enabled? && line >= @wy
      window_x = @wx - 7

      x = 0
      while x < Constants::SCREEN_WIDTH
        if window_enabled_for_line && x >= window_x
          source_x = x - window_x
          source_y = line - @wy
          current_map_base = window_map_base
        else
          source_x = (x + @scx) & 0xFF
          source_y = (line + @scy) & 0xFF
          current_map_base = map_base
        end

        tile_x = (source_x >> 3) & 0x1F
        tile_y = (source_y >> 3) & 0x1F
        tile_line = source_y & 0x07
        tile_pixel = source_x & 0x07
        tile_id = @vram[current_map_base + tile_y * 32 + tile_x] || 0
        bg_color_ids[x] = read_tile_pixel(tile_id, tile_line, tile_pixel, tile_base_signed)
        x += 1
      end
    end

    def render_sprites(line, offset, bg_color_ids)
      # DMG の sprite 合成。
      # まず OAM scan で選ばれた最大 10 個を対象に、各 pixel ごとに
      # 「X が小さい sprite が優先、同じ X なら OAM の若い順が優先」
      # で最上位の sprite pixel を 1 個だけ選ぶ。
      # BG over OBJ は、その後で選ばれた pixel に対してだけ適用する。
      sprite_bases = visible_sprite_bases_for_line(line)
      draw_order = sprite_bases.sort_by { |base| [@oam[base + 1], base] }
      sprite_height = obj_height

      screen_x = 0
      while screen_x < Constants::SCREEN_WIDTH
        chosen = nil
        index = 0

        while index < draw_order.length
          sprite = sprite_pixel_at(draw_order[index], line, screen_x, sprite_height)
          if sprite
            chosen = sprite
            break
          end

          index += 1
        end

        if chosen && !sprite_hidden_by_bg?(chosen[:attributes], bg_color_ids[screen_x])
          @frame_buffer[offset + screen_x] = palette_color(chosen[:palette], chosen[:color_id])
        end

        screen_x += 1
      end
    end

    def sprite_pixel_at(base, line, screen_x, sprite_height)
      sprite_y = (@oam[base] || 0) - 16
      sprite_x = (@oam[base + 1] || 0) - 8
      return nil if screen_x < sprite_x || screen_x >= sprite_x + 8

      tile_index = @oam[base + 2] || 0
      attributes = @oam[base + 3] || 0
      palette = (attributes & 0x10) != 0 ? @obp1 : @obp0
      sprite_line = line - sprite_y
      sprite_line = (sprite_height - 1) - sprite_line if (attributes & 0x40) != 0

      if sprite_height == 16
        tile_index &= 0xFE
        if sprite_line >= 8
          tile_index += 1
          sprite_line -= 8
        end
      end

      pixel_x = screen_x - sprite_x
      tile_pixel = (attributes & 0x20) != 0 ? pixel_x : 7 - pixel_x
      color_id = read_tile_pixel(tile_index, sprite_line, tile_pixel, false)
      return nil if color_id == 0

      {
        color_id: color_id,
        palette: palette,
        attributes: attributes
      }
    end

    def tile_data_address(tile_id, signed_mode)
      if signed_mode
        signed_id = tile_id < 128 ? tile_id : tile_id - 256
        0x1000 + signed_id * 16
      else
        tile_id * 16
      end
    end

    def read_tile_pixel(tile_id, tile_line, tile_pixel, signed_mode)
      tile_addr = tile_data_address(tile_id, signed_mode)
      lo = @vram[tile_addr + tile_line * 2] || 0
      hi = @vram[tile_addr + tile_line * 2 + 1] || 0
      bit = 7 - tile_pixel
      (((hi >> bit) & 0x01) << 1) | ((lo >> bit) & 0x01)
    end

    def palette_color(palette, color_id)
      (palette >> (color_id * 2)) & 0x03
    end

    def bg_enabled?
      (@lcdc & 0x01) != 0
    end

    def window_enabled?
      (@lcdc & 0x20) != 0
    end

    def obj_enabled?
      (@lcdc & 0x02) != 0
    end

    def obj_height
      (@lcdc & 0x04) != 0 ? 16 : 8
    end

    def visible_sprite_bases_for_line(line)
      bases = []
      base = 0
      height = obj_height

      while base < @oam.length && bases.length < 10
        sprite_y = (@oam[base] || 0) - 16

        # OAM scan は Y だけで選別する。
        # X=0 や X>=168 の sprite も 10 個制限にはカウントされる。
        bases << base if line >= sprite_y && line < sprite_y + height

        base += 4
      end

      bases
    end

    def sprite_hidden_by_bg?(attributes, bg_color_id)
      (attributes & 0x80) != 0 && bg_color_id != 0
    end

    def fill_line_colors(buffer, value)
      x = 0
      while x < buffer.length
        buffer[x] = value
        x += 1
      end
    end

    def clear_frame
      index = 0
      while index < @frame_buffer.length
        @frame_buffer[index] = 0
        index += 1
      end
    end

    def fill_scanline(offset, value)
      x = 0
      while x < Constants::SCREEN_WIDTH
        @frame_buffer[offset + x] = value
        x += 1
      end
    end
  end
end
