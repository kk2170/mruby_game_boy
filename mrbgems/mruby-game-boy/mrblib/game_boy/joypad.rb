module GameBoy
  class Joypad
    ACTION_BITS = {
      a: 0x01,
      b: 0x02,
      select: 0x04,
      start: 0x08
    }

    DPAD_BITS = {
      right: 0x01,
      left: 0x02,
      up: 0x04,
      down: 0x08
    }

    def initialize(interrupts)
      @interrupts = interrupts
      reset
    end

    def reset
      @select_mask = 0x30
      @action_state = 0x00
      @dpad_state = 0x00
      @falling_edge = false
    end

    def load_boot_state(p1)
      @select_mask = p1 & 0x30
      @falling_edge = false
    end

    def press(name)
      before = read_p1 & 0x0F

      if ACTION_BITS.key?(name)
        @action_state |= ACTION_BITS[name]
      elsif DPAD_BITS.key?(name)
        @dpad_state |= DPAD_BITS[name]
      else
        raise ArgumentError, "unknown button #{name}"
      end

      after = read_p1 & 0x0F
      request_falling_edge(before, after)
    end

    def release(name)
      if ACTION_BITS.key?(name)
        @action_state &= (~ACTION_BITS[name]) & 0x0F
      elsif DPAD_BITS.key?(name)
        @dpad_state &= (~DPAD_BITS[name]) & 0x0F
      else
        raise ArgumentError, "unknown button #{name}"
      end
    end

    def read_p1
      low = 0x0F

      low &= (~@action_state) & 0x0F if (@select_mask & 0x20) == 0
      low &= (~@dpad_state) & 0x0F if (@select_mask & 0x10) == 0

      0xC0 | @select_mask | low
    end

    def write_p1(value)
      before = read_p1 & 0x0F
      @select_mask = value & 0x30
      request_falling_edge(before, read_p1 & 0x0F)
    end

    def wake_condition_met?
      (read_p1 & 0x0F) != 0x0F
    end

    def consume_falling_edge?
      falling_edge = @falling_edge
      @falling_edge = false
      falling_edge
    end

    private

    def request_falling_edge(before, after)
      falling_edge = ((before & ~after) & 0x0F) != 0
      @falling_edge ||= falling_edge
      @interrupts.request(Constants::INT_JOYPAD) if falling_edge
    end
  end
end
