module GameBoy
  class Interrupts
    VECTORS = [0x40, 0x48, 0x50, 0x58, 0x60]

    def initialize
      reset
    end

    def reset
      @interrupt_flag = 0xE0
      @interrupt_enable = 0x00
    end

    def load_boot_state(interrupt_flag, interrupt_enable)
      @interrupt_flag = sanitize(interrupt_flag)
      @interrupt_enable = interrupt_enable & 0x1F
    end

    def request(bit)
      @interrupt_flag = sanitize(@interrupt_flag | (1 << bit))
    end

    def clear(bit)
      @interrupt_flag = sanitize(@interrupt_flag & ~(1 << bit))
    end

    def any_requested?
      (@interrupt_flag & 0x1F) != 0
    end

    def pending?(ime)
      ime && serviceable_mask != 0
    end

    def serviceable?
      serviceable_mask != 0
    end

    def service_next!
      mask = serviceable_mask
      return nil if mask == 0

      bit = 0
      while bit < 5
        if (mask & (1 << bit)) != 0
          clear(bit)
          return VECTORS[bit]
        end

        bit += 1
      end

      nil
    end

    def read_if
      @interrupt_flag
    end

    def write_if(value)
      @interrupt_flag = sanitize(value)
    end

    def read_ie
      @interrupt_enable
    end

    def write_ie(value)
      @interrupt_enable = value & 0x1F
    end

    private

    def sanitize(value)
      0xE0 | (value & 0x1F)
    end

    def serviceable_mask
      (@interrupt_enable & @interrupt_flag) & 0x1F
    end
  end
end
