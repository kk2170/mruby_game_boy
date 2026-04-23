module GameBoy
  class Core
    attr_reader :bus, :cpu, :cartridge, :ppu, :timer, :interrupts, :joypad, :dma, :apu, :serial

    def initialize(rom_source)
      # Core は各デバイスを束ねる配線役。
      # 実際の時間進行は step で CPU -> DMA/Timer/PPU の順に進める。
      @interrupts = Interrupts.new
      @cartridge = Cartridge.build(rom_source)
      @ppu = PPU.new(@interrupts)
      @timer = Timer.new(@interrupts)
      @joypad = Joypad.new(@interrupts)
      @dma = DMA.new(@ppu)
      @apu = APU.new
      @serial = Serial.new(@interrupts)
      @bus = Bus.new(@cartridge, @ppu, @timer, @interrupts, @joypad, @dma, @apu, @serial)
      @cpu = CPU.new(@bus, @interrupts)

      reset
    end

    def reset
      # Boot ROM は走らせず、reset 後に BootState で DMG post-boot state (PC=0x0100 など) を直接適用する。
      @cartridge.reset
      @bus.reset
      @cpu.reset
      @interrupts.reset
      @timer.reset
      @joypad.reset
      @ppu.reset
      @dma.reset
      @apu.reset
      @serial.reset
      BootState.apply!(self)
    end

    def header
      @cartridge.header
    end

    def battery_backed?
      @cartridge.battery_backed?
    end

    def dump_battery_ram
      @cartridge.dump_battery_ram
    end

    def load_battery_ram(bytes)
      @cartridge.load_battery_ram(bytes)
    end

    def step
      falling_edge = @joypad.consume_falling_edge?
      @cpu.wake_stop if @joypad.wake_condition_met? || falling_edge

      # CPU が消費した dot 数を、周辺デバイスへそのまま配る。
      dots = @cpu.step
      @dma.tick(dots)
      @timer.tick(dots)
      @serial.tick(dots)
      @ppu.tick(dots)
      dots
    end

    def run_steps(step_count)
      index = 0

      while index < step_count
        step
        index += 1
      end
    end

    def run_frame(max_steps = nil)
      @ppu.clear_frame_ready!
      total_dots = 0
      steps = 0

      until @ppu.frame_ready?
        dots = step
        total_dots += dots
        steps += 1
        break if dots == 0
        break if max_steps && steps >= max_steps
      end

      {
        dots: total_dots,
        steps: steps,
        frame_ready: @ppu.frame_ready?
      }
    end

    def frame_buffer
      @ppu.frame_buffer
    end

    def press_button(name)
      @joypad.press(name)
    end

    def release_button(name)
      @joypad.release(name)
    end
  end
end
