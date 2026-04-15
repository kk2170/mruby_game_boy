module GameBoy
  class Error < StandardError
  end

  class UnsupportedCartridgeError < Error
  end

  class UnsupportedOpcodeError < Error
    attr_reader :pc, :opcode

    def initialize(pc, opcode)
      @pc = pc & 0xFFFF
      @opcode = opcode & 0xFF
      super(format('unsupported opcode %02X at %04X', @opcode, @pc))
    end
  end
end
