module GameBoy
  class CPU
    attr_reader :a, :f, :b, :c, :d, :e, :h, :l, :sp, :pc

    def initialize(bus, interrupts)
      @bus = bus
      @interrupts = interrupts
      reset
    end

    def reset
      @a = 0
      @f = 0
      @b = 0
      @c = 0
      @d = 0
      @e = 0
      @h = 0
      @l = 0
      @sp = 0
      @pc = 0
      @ime = false
      @halted = false
      @halt_bug = false
      # EI は「次の命令の後」で IME を立てるため遅延を持つ。
      @ime_enable_delay = 0
    end

    def load_boot_state(values)
      self.af = values[:af]
      self.bc = values[:bc]
      self.de = values[:de]
      self.hl = values[:hl]
      @sp = values[:sp] & 0xFFFF
      @pc = values[:pc] & 0xFFFF
      @ime = values[:ime] ? true : false
      @halted = false
      @halt_bug = false
      @ime_enable_delay = 0
    end

    def register_dump
      format('AF=%04X BC=%04X DE=%04X HL=%04X SP=%04X PC=%04X IME=%d HALT=%d', af, bc, de, hl, @sp, @pc, @ime ? 1 : 0,
             @halted ? 1 : 0)
    end

    def step
      # HALT 中は割り込み要求が来るまで 1 命令分の空き時間だけ進める。
      if @halted
        return 4 unless @interrupts.serviceable?

        @halted = false
      end

      # IME が立っていれば、命令を読む前に割り込みを受理する。
      if @ime
        vector = @interrupts.service_next!
        if vector
          @ime = false
          @ime_enable_delay = 0
          push16(@pc)
          @pc = vector
          return 20
        end
      end

      opcode_pc = @pc
      opcode = fetch8
      cycles = execute_opcode(opcode_pc, opcode)
      advance_ime_delay
      cycles
    end

    def af
      (@a << 8) | (@f & 0xF0)
    end

    def af=(value)
      value &= 0xFFFF
      @a = (value >> 8) & 0xFF
      @f = value & 0xF0
    end

    def bc
      (@b << 8) | @c
    end

    def bc=(value)
      value &= 0xFFFF
      @b = (value >> 8) & 0xFF
      @c = value & 0xFF
    end

    def de
      (@d << 8) | @e
    end

    def de=(value)
      value &= 0xFFFF
      @d = (value >> 8) & 0xFF
      @e = value & 0xFF
    end

    def hl
      (@h << 8) | @l
    end

    def hl=(value)
      value &= 0xFFFF
      @h = (value >> 8) & 0xFF
      @l = value & 0xFF
    end

    private

    def execute_opcode(opcode_pc, opcode)
      case opcode
      when 0x00 then 4
      when 0x01 then op_ld_rr_d16(:bc)
      when 0x02 then op_ld_indirect_rr_a(:bc)
      when 0x03 then op_inc_rr(:bc)
      when 0x07 then op_rlca
      when 0x08 then op_ld_a16_sp
      when 0x09 then op_add_hl_rr(bc)
      when 0x0A then op_ld_a_indirect_rr(:bc)
      when 0x0B then op_dec_rr(:bc)
      when 0x0F then op_rrca
      when 0x11 then op_ld_rr_d16(:de)
      when 0x12 then op_ld_indirect_rr_a(:de)
      when 0x13 then op_inc_rr(:de)
      when 0x17 then op_rla
      when 0x18 then op_jr_r8
      when 0x19 then op_add_hl_rr(de)
      when 0x1A then op_ld_a_indirect_rr(:de)
      when 0x1B then op_dec_rr(:de)
      when 0x1F then op_rra
      when 0x20 then op_jr_cond_r8(:nz)
      when 0x21 then op_ld_rr_d16(:hl)
      when 0x22 then op_ldi_hl_a
      when 0x23 then op_inc_rr(:hl)
      when 0x27 then op_daa
      when 0x28 then op_jr_cond_r8(:z)
      when 0x29 then op_add_hl_rr(hl)
      when 0x2A then op_ldi_a_hl
      when 0x2B then op_dec_rr(:hl)
      when 0x2F then op_cpl
      when 0x30 then op_jr_cond_r8(:nc)
      when 0x31 then op_ld_sp_d16
      when 0x32 then op_ldd_hl_a
      when 0x33 then op_inc_rr(:sp)
      when 0x37 then op_scf
      when 0x38 then op_jr_cond_r8(:c)
      when 0x39 then op_add_hl_rr(@sp)
      when 0x3A then op_ldd_a_hl
      when 0x3B then op_dec_rr(:sp)
      when 0x3F then op_ccf
      when 0x76 then op_halt
      when 0xC7 then op_rst(0x00)
      when 0xC0 then op_ret_cond(:nz)
      when 0xC1 then op_pop_rr(:bc)
      when 0xC2 then op_jp_cond_a16(:nz)
      when 0xC3 then op_jp_a16
      when 0xC5 then op_push_rr(bc)
      when 0xC6 then op_add_a_n(fetch8)
      when 0xC8 then op_ret_cond(:z)
      when 0xC9 then op_ret
      when 0xCA then op_jp_cond_a16(:z)
      when 0xCD then op_call_a16
      when 0xCE then op_adc_a_n(fetch8)
      when 0xCB then execute_cb(fetch8)
      when 0xCF then op_rst(0x08)
      when 0xD0 then op_ret_cond(:nc)
      when 0xD1 then op_pop_rr(:de)
      when 0xD2 then op_jp_cond_a16(:nc)
      when 0xD5 then op_push_rr(de)
      when 0xD6 then op_sub_a_n(fetch8)
      when 0xD8 then op_ret_cond(:c)
      when 0xD9 then op_reti
      when 0xDA then op_jp_cond_a16(:c)
      when 0xDE then op_sbc_a_n(fetch8)
      when 0xD7 then op_rst(0x10)
      when 0xDF then op_rst(0x18)
      when 0xE0 then op_ldh_a8_a
      when 0xE1 then op_pop_rr(:hl)
      when 0xE2 then op_ld_ff00_c_a
      when 0xE8 then op_add_sp_r8
      when 0xE9 then op_jp_hl
      when 0xE5 then op_push_rr(hl)
      when 0xE6 then op_and_a_n(fetch8)
      when 0xE7 then op_rst(0x20)
      when 0xEA then op_ld_a16_a
      when 0xEE then op_xor_a_n(fetch8)
      when 0xEF then op_rst(0x28)
      when 0xF0 then op_ldh_a_a8
      when 0xF1 then op_pop_rr(:af)
      when 0xF2 then op_ld_a_ff00_c
      when 0xF3 then op_di
      when 0xF5 then op_push_rr(af)
      when 0xF6 then op_or_a_n(fetch8)
      when 0xF7 then op_rst(0x30)
      when 0xF8 then op_ld_hl_sp_r8
      when 0xF9 then op_ld_sp_hl
      when 0xFA then op_ld_a_a16
      when 0xFB then op_ei
      when 0xFE then op_cp_a_n(fetch8)
      when 0xFF then op_rst(0x38)
      else
        if (opcode & 0xC7) == 0x04
          op_inc_r8((opcode >> 3) & 0x07)
        elsif (opcode & 0xC7) == 0x05
          op_dec_r8((opcode >> 3) & 0x07)
        elsif (opcode & 0xC7) == 0x06
          op_ld_r8_d8((opcode >> 3) & 0x07)
        elsif (0x40..0x7F).include?(opcode)
          op_ld_r8_r8((opcode >> 3) & 0x07, opcode & 0x07)
        elsif (0x80..0x87).include?(opcode)
          op_add_a_r8(opcode & 0x07)
        elsif (0x88..0x8F).include?(opcode)
          op_adc_a_r8(opcode & 0x07)
        elsif (0x90..0x97).include?(opcode)
          op_sub_a_r8(opcode & 0x07)
        elsif (0x98..0x9F).include?(opcode)
          op_sbc_a_r8(opcode & 0x07)
        elsif (0xA0..0xA7).include?(opcode)
          op_and_a_r8(opcode & 0x07)
        elsif (0xA8..0xAF).include?(opcode)
          op_xor_a_r8(opcode & 0x07)
        elsif (0xB0..0xB7).include?(opcode)
          op_or_a_r8(opcode & 0x07)
        elsif (0xB8..0xBF).include?(opcode)
          op_cp_a_r8(opcode & 0x07)
        else
          raise UnsupportedOpcodeError.new(opcode_pc, opcode)
        end
      end
    end

    def fetch8
      value = @bus.read8(@pc)
      if @halt_bug
        # HALT bug 中は、次の opcode fetch だけ PC の自動インクリメントが起きない。
        @halt_bug = false
      else
        @pc = (@pc + 1) & 0xFFFF
      end
      value
    end

    def fetch16
      lo = fetch8
      hi = fetch8
      lo | (hi << 8)
    end

    def push16(value)
      value &= 0xFFFF
      @sp = (@sp - 1) & 0xFFFF
      @bus.write8(@sp, (value >> 8) & 0xFF)
      @sp = (@sp - 1) & 0xFFFF
      @bus.write8(@sp, value & 0xFF)
    end

    def pop16
      lo = @bus.read8(@sp)
      @sp = (@sp + 1) & 0xFFFF
      hi = @bus.read8(@sp)
      @sp = (@sp + 1) & 0xFFFF
      lo | (hi << 8)
    end

    def signed8(value)
      value < 0x80 ? value : value - 0x100
    end

    def advance_ime_delay
      return unless @ime_enable_delay > 0

      @ime_enable_delay -= 1
      @ime = true if @ime_enable_delay == 0
    end

    def set_flags(z, n, h, c)
      @f = 0
      @f |= 0x80 if z
      @f |= 0x40 if n
      @f |= 0x20 if h
      @f |= 0x10 if c
    end

    def flag_z?
      (@f & 0x80) != 0
    end

    def flag_c?
      (@f & 0x10) != 0
    end

    # 汎用 8bit レジスタアクセス。
    # code の並びは LR35902 の命令エンコーディングに合わせている。
    def read_r8(code)
      case code
      when 0 then @b
      when 1 then @c
      when 2 then @d
      when 3 then @e
      when 4 then @h
      when 5 then @l
      when 6 then @bus.read8(hl)
      when 7 then @a
      else 0
      end
    end

    def write_r8(code, value)
      value &= 0xFF

      case code
      when 0 then @b = value
      when 1 then @c = value
      when 2 then @d = value
      when 3 then @e = value
      when 4 then @h = value
      when 5 then @l = value
      when 6 then @bus.write8(hl, value)
      when 7 then @a = value
      end
    end

    def set_rr(symbol, value)
      case symbol
      when :bc then self.bc = value
      when :de then self.de = value
      when :hl then self.hl = value
      when :sp then @sp = value & 0xFFFF
      when :af then self.af = value
      end
    end

    def read_rr(symbol)
      case symbol
      when :bc then bc
      when :de then de
      when :hl then hl
      when :sp then @sp
      when :af then af
      else 0
      end
    end

    def condition_true?(condition)
      case condition
      when :nz then !flag_z?
      when :z then flag_z?
      when :nc then !flag_c?
      when :c then flag_c?
      else false
      end
    end

    def op_ld_rr_d16(symbol)
      set_rr(symbol, fetch16)
      12
    end

    def op_ld_r8_d8(code)
      write_r8(code, fetch8)
      code == 6 ? 12 : 8
    end

    def op_ld_r8_r8(dest, src)
      write_r8(dest, read_r8(src))
      dest == 6 || src == 6 ? 8 : 4
    end

    def op_inc_r8(code)
      original = read_r8(code)
      result = (original + 1) & 0xFF
      write_r8(code, result)
      set_flags(result == 0, false, (original & 0x0F) == 0x0F, flag_c?)
      code == 6 ? 12 : 4
    end

    def op_dec_r8(code)
      original = read_r8(code)
      result = (original - 1) & 0xFF
      write_r8(code, result)
      set_flags(result == 0, true, (original & 0x0F) == 0, flag_c?)
      code == 6 ? 12 : 4
    end

    def op_inc_rr(symbol)
      set_rr(symbol, (read_rr(symbol) + 1) & 0xFFFF)
      8
    end

    def op_dec_rr(symbol)
      set_rr(symbol, (read_rr(symbol) - 1) & 0xFFFF)
      8
    end

    def op_ld_indirect_rr_a(symbol)
      @bus.write8(read_rr(symbol), @a)
      8
    end

    def op_ld_a_indirect_rr(symbol)
      @a = @bus.read8(read_rr(symbol))
      8
    end

    def op_ld_a16_sp
      address = fetch16
      @bus.write16(address, @sp)
      20
    end

    def op_add_hl_rr(value)
      left = hl
      result = left + value
      half = ((left & 0x0FFF) + (value & 0x0FFF)) > 0x0FFF
      carry = result > 0xFFFF
      self.hl = result
      set_flags(flag_z?, false, half, carry)
      8
    end

    def op_rla
      carry_in = flag_c? ? 1 : 0
      carry_out = (@a & 0x80) != 0
      @a = ((@a << 1) | carry_in) & 0xFF
      set_flags(false, false, false, carry_out)
      4
    end

    def op_rlca
      carry_out = (@a & 0x80) != 0
      @a = ((@a << 1) | (carry_out ? 1 : 0)) & 0xFF
      set_flags(false, false, false, carry_out)
      4
    end

    def op_rrca
      carry_out = (@a & 0x01) != 0
      @a = ((@a >> 1) | (carry_out ? 0x80 : 0)) & 0xFF
      set_flags(false, false, false, carry_out)
      4
    end

    def op_rra
      carry_in = flag_c? ? 0x80 : 0
      carry_out = (@a & 0x01) != 0
      @a = ((@a >> 1) | carry_in) & 0xFF
      set_flags(false, false, false, carry_out)
      4
    end

    def op_jr_r8
      # fetch8 が PC を進めるので、先に offset を取り出してから加算する。
      offset = signed8(fetch8)
      @pc = (@pc + offset) & 0xFFFF
      12
    end

    def op_jr_cond_r8(condition)
      offset = signed8(fetch8)

      if condition_true?(condition)
        @pc = (@pc + offset) & 0xFFFF
        12
      else
        8
      end
    end

    def op_ldi_hl_a
      @bus.write8(hl, @a)
      self.hl = (hl + 1) & 0xFFFF
      8
    end

    def op_ldi_a_hl
      @a = @bus.read8(hl)
      self.hl = (hl + 1) & 0xFFFF
      8
    end

    def op_ld_sp_d16
      @sp = fetch16
      12
    end

    def op_ldd_hl_a
      @bus.write8(hl, @a)
      self.hl = (hl - 1) & 0xFFFF
      8
    end

    def op_ldd_a_hl
      @a = @bus.read8(hl)
      self.hl = (hl - 1) & 0xFFFF
      8
    end

    def op_daa
      adjust = 0
      carry = flag_c?

      if (@f & 0x40) == 0
        adjust |= 0x06 if (@f & 0x20) != 0 || (@a & 0x0F) > 0x09
        if carry || @a > 0x99
          adjust |= 0x60
          carry = true
        end
        @a = (@a + adjust) & 0xFF
      else
        adjust |= 0x06 if (@f & 0x20) != 0
        adjust |= 0x60 if carry
        @a = (@a - adjust) & 0xFF
      end

      set_flags(@a == 0, (@f & 0x40) != 0, false, carry)
      4
    end

    def op_cpl
      @a = (~@a) & 0xFF
      set_flags(flag_z?, true, true, flag_c?)
      4
    end

    def op_scf
      set_flags(flag_z?, false, false, true)
      4
    end

    def op_ccf
      set_flags(flag_z?, false, false, !flag_c?)
      4
    end

    def op_halt
      if !@ime && @interrupts.serviceable?
        # IME=0 かつ serviceable interrupt がある場合は HALT bug が起きる。
        @halt_bug = true
      else
        @halted = true
      end
      4
    end

    def op_add_a_r8(code)
      op_add_a_n(read_r8(code), code == 6 ? 8 : 4)
    end

    def op_adc_a_r8(code)
      op_adc_a_n(read_r8(code), code == 6 ? 8 : 4)
    end

    def op_sub_a_r8(code)
      op_sub_a_n(read_r8(code), code == 6 ? 8 : 4)
    end

    def op_sbc_a_r8(code)
      op_sbc_a_n(read_r8(code), code == 6 ? 8 : 4)
    end

    def op_and_a_r8(code)
      op_and_a_n(read_r8(code), code == 6 ? 8 : 4)
    end

    def op_xor_a_r8(code)
      op_xor_a_n(read_r8(code), code == 6 ? 8 : 4)
    end

    def op_or_a_r8(code)
      op_or_a_n(read_r8(code), code == 6 ? 8 : 4)
    end

    def op_cp_a_r8(code)
      op_cp_a_n(read_r8(code), code == 6 ? 8 : 4)
    end

    def op_add_a_n(value, cycles = 8)
      original = @a
      result = original + value
      @a = result & 0xFF
      set_flags(@a == 0, false, ((original & 0x0F) + (value & 0x0F)) > 0x0F, result > 0xFF)
      cycles
    end

    def op_adc_a_n(value, cycles = 8)
      carry = flag_c? ? 1 : 0
      original = @a
      result = original + value + carry
      half = ((original & 0x0F) + (value & 0x0F) + carry) > 0x0F
      @a = result & 0xFF
      set_flags(@a == 0, false, half, result > 0xFF)
      cycles
    end

    def op_sub_a_n(value, cycles = 8)
      original = @a
      result = (original - value) & 0xFF
      @a = result
      set_flags(result == 0, true, (original & 0x0F) < (value & 0x0F), original < value)
      cycles
    end

    def op_sbc_a_n(value, cycles = 8)
      carry = flag_c? ? 1 : 0
      original = @a
      subtrahend = value + carry
      result = (original - subtrahend) & 0xFF
      @a = result
      set_flags(result == 0, true, (original & 0x0F) < ((value & 0x0F) + carry), original < subtrahend)
      cycles
    end

    def op_and_a_n(value, cycles = 8)
      @a &= value
      set_flags(@a == 0, false, true, false)
      cycles
    end

    def op_xor_a_n(value, cycles = 8)
      @a ^= value
      @a &= 0xFF
      set_flags(@a == 0, false, false, false)
      cycles
    end

    def op_or_a_n(value, cycles = 8)
      @a |= value
      @a &= 0xFF
      set_flags(@a == 0, false, false, false)
      cycles
    end

    def op_cp_a_n(value, cycles = 8)
      original = @a
      result = (original - value) & 0xFF
      set_flags(result == 0, true, (original & 0x0F) < (value & 0x0F), original < value)
      cycles
    end

    def op_pop_rr(symbol)
      set_rr(symbol, pop16)
      12
    end

    def op_push_rr(value)
      push16(value)
      16
    end

    def op_ret_cond(condition)
      if condition_true?(condition)
        @pc = pop16
        20
      else
        8
      end
    end

    def op_jp_cond_a16(condition)
      address = fetch16

      if condition_true?(condition)
        @pc = address
        16
      else
        12
      end
    end

    def op_jp_a16
      @pc = fetch16
      16
    end

    def op_ret
      @pc = pop16
      16
    end

    def op_call_a16
      address = fetch16
      push16(@pc)
      @pc = address
      24
    end

    def op_reti
      @pc = pop16
      @ime = true
      @ime_enable_delay = 0
      16
    end

    def op_rst(vector)
      push16(@pc)
      @pc = vector & 0xFFFF
      16
    end

    def op_ldh_a8_a
      address = 0xFF00 | fetch8
      @bus.write8(address, @a)
      12
    end

    def op_add_sp_r8
      offset_byte = fetch8
      offset = signed8(offset_byte)
      result = (@sp + offset) & 0xFFFF
      half = ((@sp & 0x0F) + (offset_byte & 0x0F)) > 0x0F
      carry = ((@sp & 0xFF) + offset_byte) > 0xFF
      @sp = result
      set_flags(false, false, half, carry)
      16
    end

    def op_jp_hl
      @pc = hl
      4
    end

    def op_ldh_a_a8
      @a = @bus.read8(0xFF00 | fetch8)
      12
    end

    def op_ld_a_ff00_c
      @a = @bus.read8(0xFF00 | @c)
      8
    end

    def op_ld_ff00_c_a
      @bus.write8(0xFF00 | @c, @a)
      8
    end

    def op_ld_a16_a
      address = fetch16
      @bus.write8(address, @a)
      16
    end

    def op_ld_a_a16
      @a = @bus.read8(fetch16)
      16
    end

    def op_ld_hl_sp_r8
      offset_byte = fetch8
      offset = signed8(offset_byte)
      result = (@sp + offset) & 0xFFFF
      half = ((@sp & 0x0F) + (offset_byte & 0x0F)) > 0x0F
      carry = ((@sp & 0xFF) + offset_byte) > 0xFF
      self.hl = result
      set_flags(false, false, half, carry)
      12
    end

    def op_ld_sp_hl
      @sp = hl
      8
    end

    def op_di
      @ime = false
      @ime_enable_delay = 0
      4
    end

    def op_ei
      # EI の直後ではなく、その次の命令が終わった後で有効化する。
      @ime_enable_delay = 2
      4
    end

    def execute_cb(opcode)
      register = opcode & 0x07
      group = opcode >> 6
      index = (opcode >> 3) & 0x07

      case group
      when 0
        execute_cb_rotate_shift(index, register)
      when 1
        execute_cb_bit(index, register)
      when 2
        execute_cb_res(index, register)
      when 3
        execute_cb_set(index, register)
      else
        raise UnsupportedOpcodeError.new((@pc - 2) & 0xFFFF, 0xCB)
      end
    end

    def execute_cb_rotate_shift(index, register)
      value = read_r8(register)
      result = 0
      carry = false

      case index
      when 0 # RLC
        carry = (value & 0x80) != 0
        result = ((value << 1) | (carry ? 1 : 0)) & 0xFF
      when 1 # RRC
        carry = (value & 0x01) != 0
        result = ((value >> 1) | (carry ? 0x80 : 0)) & 0xFF
      when 2 # RL
        carry = (value & 0x80) != 0
        result = ((value << 1) | (flag_c? ? 1 : 0)) & 0xFF
      when 3 # RR
        carry = (value & 0x01) != 0
        result = ((value >> 1) | (flag_c? ? 0x80 : 0)) & 0xFF
      when 4 # SLA
        carry = (value & 0x80) != 0
        result = (value << 1) & 0xFF
      when 5 # SRA
        carry = (value & 0x01) != 0
        result = ((value >> 1) | (value & 0x80)) & 0xFF
      when 6 # SWAP
        result = ((value & 0x0F) << 4) | ((value >> 4) & 0x0F)
      when 7 # SRL
        carry = (value & 0x01) != 0
        result = (value >> 1) & 0xFF
      end

      write_r8(register, result)
      set_flags(result == 0, false, false, carry)
      register == 6 ? 16 : 8
    end

    def execute_cb_bit(bit, register)
      value = read_r8(register)
      zero = (value & (1 << bit)) == 0
      set_flags(zero, false, true, flag_c?)
      register == 6 ? 12 : 8
    end

    def execute_cb_res(bit, register)
      write_r8(register, read_r8(register) & ~(1 << bit))
      register == 6 ? 16 : 8
    end

    def execute_cb_set(bit, register)
      write_r8(register, read_r8(register) | (1 << bit))
      register == 6 ? 16 : 8
    end
  end
end
