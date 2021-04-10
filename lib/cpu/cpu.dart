library cpu;

import "dart:typed_data";

import "cpu_enum.dart";
export "cpu_enum.dart";

import "package:flutter_nes/memory.dart";
import "package:flutter_nes/util.dart";

// emualtor for 6502 CPU
class NesCPU {
  NesCPU();

  NesCPUMemory _memory = NesCPUMemory();

  static const double FREQUENCY = 1.789773; // frequency per microsecond

  // this is registers
  // see https://en.wikipedia.org/wiki/MOS_Technology_6502#Registers
  int _regPC = 0; // Program Counter, the only 16-bit register, others are 8-bit
  Int8 _regSP = Int8(0x1ff); // Stack Pointer register
  Int8 _regPS = Int8(); // Processor Status register
  Int8 _regA = Int8(); // Accumulator register
  Int8 _regX = Int8(); // Index register, used for indexed addressing mode
  Int8 _regY = Int8(); // Index register

  // execute one instruction
  emulate(Op op, Uint8List nextBytes) {
    int addr = 0; // memory address will used in operator instruction.
    Int8 M = Int8(); // the value in memory address of addr
    int extraCycles = 0;
    int extraBytes = 0;

    switch (op.addrMode) {
      case AddrMode.ZeroPage:
        addr = nextBytes[0];
        M = Int8(_memory.read(addr));
        break;

      case AddrMode.ZeroPageX:
        addr = nextBytes[0] + _regX.value;
        M = Int8(_memory.read(addr));
        break;

      case AddrMode.ZeroPageY:
        addr = nextBytes[0] + _regY.value;
        M = Int8(_memory.read(addr));
        break;

      case AddrMode.Absolute:
        addr = to16Bit(nextBytes);
        M = Int8(_memory.read(addr));
        break;

      case AddrMode.AbsoluteX:
        addr = to16Bit(nextBytes) + _regX.value;
        M = Int8(_memory.read(addr));

        if (isPageCrossed(addr, addr - _regX.value)) {
          extraCycles++;
        }

        break;

      case AddrMode.AbsoluteY:
        addr = to16Bit(nextBytes) + _regY.value;
        M = Int8(_memory.read(addr));

        if (isPageCrossed(addr, addr - _regY.value)) {
          extraCycles++;
        }

        break;

      case AddrMode.Indirect:
        addr = _memory.read16Bit(to16Bit(nextBytes));
        M = Int8(_memory.read(addr));
        break;

      // this addressing mode not need to access memory
      case AddrMode.Implied:
        break;

      // this addressing mode is directly access the accumulator (register)
      case AddrMode.Accumulator:
        M = Int8(_regA.value);
        break;

      case AddrMode.Immediate:
        M = Int8(nextBytes[0]);
        break;

      case AddrMode.Relative:
        M = Int8(nextBytes[0]);
        break;

      case AddrMode.IndexedIndirect:
        addr = _memory.read16Bit(nextBytes[0] + _regX.value);
        M = Int8(_memory.read(addr));

        if (isPageCrossed(addr, addr - _regX.value)) {
          extraCycles++;
        }
        break;

      case AddrMode.IndirectIndexed:
        addr = _memory.read16Bit(nextBytes[0]) + _regY.value;
        M = Int8(_memory.read(addr));
        break;
    }

    switch (op.instr) {
      case Instr.ADC:
        _regA += M + Int8(_getCarryFlag());

        _setCarryFlag(_regA.isOverflow());
        _setOverflowFlag(_regA.isOverflow());
        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.AND:
        _regA &= M;

        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.ASL:
        M <<= 1;

        if (op.addrMode == AddrMode.Accumulator) {
          _regA = M;
        } else {
          _memory.write(addr, M.value);
        }

        _setCarryFlag(M.getBit(7));
        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(M.isNegative());
        break;

      case Instr.BCC:
        if (_getCarryFlag() == 0) {
          extraBytes = M.value;
          extraCycles++;
        }
        break;

      case Instr.BCS:
        if (_getCarryFlag() == 1) {
          extraBytes = M.value;
          extraCycles++;
        }
        break;

      case Instr.BEQ:
        if (_getZeroFlag() == 1) {
          extraBytes = M.value;
          extraCycles++;
        }
        break;

      case Instr.BIT:
        Int8 test = M & _regA;

        _setZeroFlag(test.isZero());
        _setOverflowFlag(M.getBit(6));
        _setNegativeFlag(M.isNegative());
        break;

      case Instr.BMI:
        if (_getNegativeFlag() == 1) {
          extraBytes = M.value;
          extraCycles++;
        }
        break;

      case Instr.BNE:
        if (_getZeroFlag() == 0) {
          extraBytes = M.value;
          extraCycles++;
        }
        break;

      case Instr.BPL:
        if (_getNegativeFlag() == 0) {
          extraBytes = M.value;
          extraCycles++;
        }
        break;

      case Instr.BRK:
        // IRQ is ignored when interrupt disable flag is set.
        if (_getInterruptDisableFlag() == 1) break;

        _push16BitStack(_regPC);
        _pushStack(_regPS.value);

        _regPC = to16Bit([_memory.read(0xfffe), _memory.read(0xffff)]);
        _setBreakCommandFlag(1);
        break;

      case Instr.BVC:
        if (_getOverflowFlag() == 0) {
          extraBytes = M.value;
          extraCycles++;
        }
        break;

      case Instr.BVS:
        if (_getOverflowFlag() == 1) {
          extraBytes = M.value;
          extraCycles++;
        }
        break;

      case Instr.CLC:
        _setCarryFlag(0);
        break;

      case Instr.CLD:
        _setDecimalModeFlag(0);
        break;

      case Instr.CLI:
        _setInterruptDisableFlag(0);
        break;

      case Instr.CLV:
        _setOverflowFlag(0);
        break;

      case Instr.CMP:
        _setCarryFlag(_regA >= M ? 1 : 0);
        _setZeroFlag((_regA - M).isZero());
        _setNegativeFlag((_regA - M).isNegative());
        break;

      case Instr.CPX:
        _setCarryFlag(_regX >= M ? 1 : 0);
        _setZeroFlag((_regX - M).isZero());
        _setNegativeFlag((_regX - M).isNegative());
        break;

      case Instr.CPY:
        _setCarryFlag(_regY >= M ? 1 : 0);
        _setZeroFlag((_regY - M).isZero());
        _setNegativeFlag((_regY - M).isNegative());
        break;

      case Instr.DEC:
        M -= Int8(1);
        _memory.write(addr, M.value);

        _setZeroFlag(M.isZero());
        _setNegativeFlag(M.isNegative());
        break;

      case Instr.DEX:
        _regX -= Int8(1);

        _setZeroFlag(_regX.isZero());
        _setNegativeFlag(_regX.isNegative());
        break;

      case Instr.DEY:
        _regY -= Int8(1);

        _setZeroFlag(_regY.isZero());
        _setNegativeFlag(_regY.isNegative());
        break;

      case Instr.EOR:
        _regA ^= M;

        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.INC:
        M += Int8(1);
        _memory.write(addr, M.value);

        _setZeroFlag(M.isZero());
        _setNegativeFlag(M.isNegative());
        break;

      case Instr.INX:
        _regX += Int8(1);

        _setZeroFlag(_regX.isZero());
        _setNegativeFlag(_regX.isNegative());
        break;

      case Instr.INY:
        _regY += Int8(1);

        _setZeroFlag(_regY.isZero());
        _setNegativeFlag(_regY.isNegative());
        break;

      case Instr.JMP:
        _regPC = M.value;
        break;

      case Instr.JSR:
        _push16BitStack(_regPC - 1);
        _regPC = addr;
        break;

      case Instr.LDA:
        _regA = M;

        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.LDX:
        _regX = M;

        _setZeroFlag(_regX.isZero());
        _setNegativeFlag(_regX.isNegative());
        break;

      case Instr.LDY:
        _regY = M;

        _setZeroFlag(_regY.isZero());
        _setNegativeFlag(_regY.isNegative());
        break;

      case Instr.LSR:
        M >>= 1;

        if (op.addrMode == AddrMode.Accumulator) {
          _regA = M;
        } else {
          _memory.write(addr, M.value);
        }

        _setCarryFlag(M.getBit(0));
        _setZeroFlag(M.isZero());
        _setNegativeFlag(M.isNegative());
        break;

      // NOPs
      case Instr.NOP:
      case Instr.SKB:
      case Instr.IGN:
        break;

      case Instr.ORA:
        _regA |= M;

        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.PHA:
        _pushStack(_regA.value);
        break;

      case Instr.PHP:
        _pushStack(_regPS.value);
        break;

      case Instr.PLA:
        _regA = Int8(_popStack());
        break;

      case Instr.PLP:
        _regPS = Int8(_popStack());
        break;

      case Instr.ROL:
        M = (M << 1).setBit(0, _getCarryFlag());

        if (op.addrMode == AddrMode.Accumulator) {
          _regA = M;
        } else {
          _memory.write(addr, M.value);
        }

        _setCarryFlag(M.getBit(7));
        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(M.isNegative());
        break;

      case Instr.ROR:
        M = (M >> 1).setBit(7, _getCarryFlag());

        if (op.addrMode == AddrMode.Accumulator) {
          _regA = M;
        } else {
          _memory.write(addr, M.value);
        }

        _setCarryFlag(M.getBit(7));
        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(M.isNegative());
        break;

      case Instr.RTI:
        _regPS = Int8(_popStack());
        _regPC = _pop16BitStack();

        _setInterruptDisableFlag(0);
        break;

      case Instr.RTS:
        _regPC = _pop16BitStack() + 1;
        break;

      case Instr.SBC:
        _regA -= M + Int8(1 - _getCarryFlag());

        _setCarryFlag(_regA.isOverflow() == 1 ? 0 : 1);
        _setZeroFlag(_regA.isZero());
        _setOverflowFlag(_regA.isOverflow());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.SEC:
        _setCarryFlag(1);
        break;

      case Instr.SED:
        _setDecimalModeFlag(1);
        break;

      case Instr.SEI:
        _setInterruptDisableFlag(1);
        break;

      case Instr.STA:
        _memory.write(addr, _regA.value);
        break;

      case Instr.STX:
        _memory.write(addr, _regX.value);
        break;

      case Instr.STY:
        _memory.write(addr, _regY.value);
        break;

      case Instr.TAX:
        _regX = _regA;

        _setZeroFlag(_regX.isZero());
        _setNegativeFlag(_regX.isNegative());
        break;

      case Instr.TAY:
        _regY = _regA;

        _setZeroFlag(_regY.isZero());
        _setNegativeFlag(_regY.isNegative());
        break;

      case Instr.TSX:
        _regX = _regSP;

        _setZeroFlag(_regX.isZero());
        _setNegativeFlag(_regX.isNegative());
        break;

      case Instr.TXA:
        _regA = _regX;

        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.TXS:
        _regSP = _regX;
        break;

      case Instr.TYA:
        _regA = _regY;

        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.ALR:
        _regA = (_regA & M) >> 1;

        _setCarryFlag(M.getBit(0));
        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.ANC:
        _regA &= M;

        _setCarryFlag(_regA.getBit(7));
        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.ARR:
        _regA = ((_regA & M) >> 1).setBit(7, _getCarryFlag());

        _setOverflowFlag(_regA.getBit(6) ^ _regA.getBit(5));
        _setCarryFlag(_regA.getBit(6));
        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.AXS:
        _regX &= _regA;

        _setCarryFlag(_regX.isOverflow());
        _setZeroFlag(_regX.isZero());
        _setNegativeFlag(_regX.isNegative());
        break;

      case Instr.LAX:
        _regX = _regA = M;

        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.SAX:
        _regX &= _regA;
        _memory.write(addr, _regX.value);
        break;

      case Instr.DCP:
        // DEC
        M -= Int8(1);
        _memory.write(addr, M.value);

        // CMP
        _setCarryFlag(_regA >= M ? 1 : 0);
        _setZeroFlag((_regA - M).isZero());
        _setNegativeFlag((_regA - M).isNegative());
        break;

      case Instr.ISC:
        // INC
        M += Int8(1);
        _memory.write(addr, M.value);

        // SBC
        _regA -= M + Int8(1 - _getCarryFlag());

        _setCarryFlag(_regA.isOverflow() == 1 ? 0 : 1);
        _setZeroFlag(_regA.isZero());
        _setOverflowFlag(_regA.isOverflow());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.RLA:
        // ROL
        M = (M << 1).setBit(0, _getCarryFlag());
        _memory.write(addr, M.value);

        // AND
        _regA &= M;

        _setCarryFlag(M.getBit(7));
        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.RRA:
        // ROR
        M = (M >> 1).setBit(7, _getCarryFlag());
        _memory.write(addr, M.value);

        // ADC
        _regA += M + Int8(_getCarryFlag());

        _setCarryFlag(_regA.isOverflow());
        _setOverflowFlag(_regA.isOverflow());
        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.SLO:
        // ASL
        M <<= 1;
        _memory.write(addr, M.value);

        // ORA
        _regA |= M;

        _setCarryFlag(M.getBit(7));
        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      case Instr.SRE:
        // LSR
        M >>= 1;
        _memory.write(addr, M.value);

        // EOR
        _regA ^= M;

        _setCarryFlag(M.getBit(0));
        _setZeroFlag(_regA.isZero());
        _setNegativeFlag(_regA.isNegative());
        break;

      default:
        throw ("cpu emulate: ${op.instr} is an unknown instruction.");
    }

    _regPC += op.bytes + extraBytes;
    return op.cycles + extraCycles;
  }

  int inspectMemory(int addr) => _memory.read(addr);

  int getPC() => _regPC;
  int getSP() => _regSP.value;
  int getPS() => _regPS.value;
  int getACC() => _regA.value;
  int getX() => _regX.value;
  int getY() => _regY.value;

  int _getCarryFlag() => _regPS.getBit(0);
  int _getZeroFlag() => _regPS.getBit(1);
  int _getInterruptDisableFlag() => _regPS.getBit(2);
  int _getDecimalModeFlag() => _regPS.getBit(3);
  int _getBreakCommandFlag() => _regPS.getBit(4);
  int _getOverflowFlag() => _regPS.getBit(6);
  int _getNegativeFlag() => _regPS.getBit(7);

  void _setCarryFlag(int value) {
    _regPS.setBit(0, value);
  }

  void _setZeroFlag(int value) {
    _regPS.setBit(1, value);
  }

  void _setInterruptDisableFlag(int value) {
    _regPS.setBit(2, value);
  }

  void _setDecimalModeFlag(int value) {
    _regPS.setBit(3, value);
  }

  void _setBreakCommandFlag(int value) {
    _regPS.setBit(4, value);
  }

  void _setOverflowFlag(int value) {
    _regPS.setBit(6, value);
  }

  void _setNegativeFlag(int value) {
    _regPS.setBit(7, value);
  }

  // stack works top-down, see NESDoc page 12.
  _pushStack(int value) {
    _validateSP();

    _memory.write(_regSP.value, value);
    _regSP -= Int8(1);
  }

  int _popStack() {
    _validateSP();

    int value = _memory.read(_regSP.value);
    _regSP += Int8(1);

    return value;
  }

  void _push16BitStack(int value) {
    _pushStack(value >> 2 & 0xff);
    _pushStack(value & 0xff);
  }

  int _pop16BitStack() {
    return _popStack() | _popStack() << 2;
  }

  _validateSP() {
    if (_regSP.value < 0x100 || _regSP.value > 0x1ff) {
      throw ("stack pointer ${_regSP.value.toHex()} is overflow!!!");
    }
  }
}
