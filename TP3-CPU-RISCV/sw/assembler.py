#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Ensamblador y Desensamblador RV32I para el Procesador RISC-V de 5 Etapas.

Traduce programas escritos en lenguaje ensamblador (.asm) a código máquina de
32 bits (Little-Endian / palabras uint32) listos para ser enviados a la FPGA
a través de la Debug Unit por UART (comando LOAD_PROG = 0x02).

Soporta:
- Las 33 instrucciones implementadas en el hardware:
  * Tipo R : add, sub, sll, slt, sltu, xor, srl, sra, or, and
  * Tipo I : addi, slti, sltiu, xori, ori, andi, slli, srli, srai
  * Loads  : lb, lh, lw, lbu, lhu
  * Stores : sb, sh, sw
  * Branch : beq, bne (con etiquetas simbólicas o desplazamientos numéricos)
  * Saltos : jal, jalr
  * Tipo U : lui
  * Sistema: ebreak / halt (0x00100073)
- Pseudoinstrucciones comunes (nop, mv, li, j, jr, ret).
- Nombres de registros arquitectónicos (x0..x31) y ABI (zero, ra, sp, t0..t6, a0..a7, s0..s11).
- Carga directa de archivos .hex si ya están en formato hexadecimal.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple


class AssemblerError(Exception):
    """Error sintáctico o semántico durante el ensamblado de una línea."""

    def __init__(self, message: str, line_num: Optional[int] = None, source_line: str = ""):
        self.line_num = line_num
        self.source_line = source_line
        prefix = f"Línea {line_num}: " if line_num is not None else ""
        super().__init__(f"{prefix}{message}" + (f" -> '{source_line.strip()}'" if source_line.strip() else ""))


@dataclass
class AssembledInstruction:
    """Representa una instrucción ya traducida a lenguaje máquina de 32 bits."""

    address: int          # Dirección de byte en memoria de programa (0x0000, 0x0004, ...)
    word: int             # Palabra de código máquina de 32 bits (uint32)
    source_line: str      #Texto original en ensamblador
    line_num: int         # Número de línea en el archivo .asm
    canonical_asm: str    # Instrucción desensamblada canónica
    inst_format: str      # Formato RV32I ('R', 'I', 'S', 'B', 'U', 'J', 'SYS', 'HEX')

    @property
    def hex_str(self) -> str:
        return f"0x{self.word:08X}"

    @property
    def le_bytes_str(self) -> str:
        b = self.word.to_bytes(4, byteorder="little")
        return f"{b[0]:02X} {b[1]:02X} {b[2]:02X} {b[3]:02X}"

    @property
    def bytes_le_str(self) -> str:
        return self.le_bytes_str

    @property
    def bin_fields_str(self) -> str:
        b = f"{self.word:032b}"
        if self.inst_format == "R":
            return f"{b[0:7]} {b[7:12]} {b[12:17]} {b[17:20]} {b[20:25]} {b[25:32]}"
        if self.inst_format in ("I", "SYS"):
            return f"{b[0:12]} {b[12:17]} {b[17:20]} {b[20:25]} {b[25:32]}"
        if self.inst_format == "S":
            return f"{b[0:7]} {b[7:12]} {b[12:17]} {b[17:20]} {b[20:25]} {b[25:32]}"
        if self.inst_format == "B":
            return f"{b[0:7]} {b[7:12]} {b[12:17]} {b[17:20]} {b[20:25]} {b[25:32]}"
        if self.inst_format in ("U", "J"):
            return f"{b[0:20]} {b[20:25]} {b[25:32]}"
        return f"{b[0:8]}_{b[8:16]}_{b[16:24]}_{b[24:32]}"

    @property
    def binary_fields_str(self) -> str:
        return self.bin_fields_str


# ==============================================================================
# Tablas del ISA RV32I
# ==============================================================================

ABI_NAMES: List[str] = [
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0",   "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6",   "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8",   "s9", "s10", "s11", "t3", "t4", "t5", "t6",
]
ABI_NAMES_BY_IDX: List[str] = ABI_NAMES

REG_MAP: Dict[str, int] = {f"x{i}": i for i in range(32)}
for idx, abi in enumerate(ABI_NAMES):
    REG_MAP[abi] = idx
REG_MAP["fp"] = 8  # s0 / fp

OPCODE_R_TYPE = 0b0110011
OPCODE_I_IMM  = 0b0010011
OPCODE_LOAD   = 0b0000011
OPCODE_STORE  = 0b0100011
OPCODE_BRANCH = 0b1100011
OPCODE_JALR   = 0b1100111
OPCODE_JAL    = 0b1101111
OPCODE_LUI    = 0b0110111
OPCODE_SYSTEM = 0b1110011

EBREAK_WORD = 0x00100073
NOP_WORD    = 0x00000013

R_INSTRUCTIONS: Dict[str, Tuple[int, int]] = {
    # mnemónico: (funct3, funct7)
    "add":  (0b000, 0b0000000),
    "sub":  (0b000, 0b0100000),
    "sll":  (0b001, 0b0000000),
    "slt":  (0b010, 0b0000000),
    "sltu": (0b011, 0b0000000),
    "xor":  (0b100, 0b0000000),
    "srl":  (0b101, 0b0000000),
    "sra":  (0b101, 0b0100000),
    "or":   (0b110, 0b0000000),
    "and":  (0b111, 0b0000000),
}

I_ALU_INSTRUCTIONS: Dict[str, int] = {
    # mnemónico: funct3
    "addi":  0b000,
    "slti":  0b010,
    "sltiu": 0b011,
    "xori":  0b100,
    "ori":   0b110,
    "andi":  0b111,
}

I_SHIFT_INSTRUCTIONS: Dict[str, Tuple[int, int]] = {
    # mnemónico: (funct3, funct7)
    "slli": (0b001, 0b0000000),
    "srli": (0b101, 0b0000000),
    "srai": (0b101, 0b0100000),
}

LOAD_INSTRUCTIONS: Dict[str, int] = {
    "lb":  0b000,
    "lh":  0b001,
    "lw":  0b010,
    "lbu": 0b100,
    "lhu": 0b101,
}

STORE_INSTRUCTIONS: Dict[str, int] = {
    "sb": 0b000,
    "sh": 0b001,
    "sw": 0b010,
}

BRANCH_INSTRUCTIONS: Dict[str, int] = {
    "beq": 0b000,
    "bne": 0b001,
}


# ==============================================================================
# Funciones de Codificación de Formatos RV32I
# ==============================================================================

def parse_register(token: str, line_num: Optional[int] = None, src: str = "") -> int:
    key = token.strip().lower()
    if key not in REG_MAP:
        raise AssemblerError(f"Registro inválido '{token}' (use x0..x31 o nombres ABI)", line_num, src)
    return REG_MAP[key]


def parse_immediate(token: str, line_num: Optional[int] = None, src: str = "") -> int:
    t = token.strip()
    try:
        return int(t, 0)
    except ValueError as exc:
        raise AssemblerError(f"Valor inmediato inválido '{token}'", line_num, src) from exc


def check_signed_range(val: int, bits: int, line_num: Optional[int] = None, src: str = "") -> None:
    min_val = -(1 << (bits - 1))
    max_val = (1 << (bits - 1)) - 1
    if not (min_val <= val <= max_val):
        raise AssemblerError(
            f"Inmediato {val} fuera de rango de {bits} bits con signo [{min_val}..{max_val}]",
            line_num,
            src,
        )


def encode_r_type(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int = OPCODE_R_TYPE) -> int:
    return (
        ((funct7 & 0x7F) << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x07) << 12)
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


def encode_i_type(imm12: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    return (
        ((imm12 & 0xFFF) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x07) << 12)
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


def encode_s_type(imm12: int, rs2: int, rs1: int, funct3: int, opcode: int = OPCODE_STORE) -> int:
    imm = imm12 & 0xFFF
    imm_11_5 = (imm >> 5) & 0x7F
    imm_4_0 = imm & 0x1F
    return (
        (imm_11_5 << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x07) << 12)
        | (imm_4_0 << 7)
        | (opcode & 0x7F)
    )


def encode_b_type(offset13: int, rs2: int, rs1: int, funct3: int, opcode: int = OPCODE_BRANCH) -> int:
    imm = offset13 & 0x1FFF
    b12 = (imm >> 12) & 0x1
    b11 = (imm >> 11) & 0x1
    b10_5 = (imm >> 5) & 0x3F
    b4_1 = (imm >> 1) & 0xF
    return (
        (b12 << 31)
        | (b10_5 << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x07) << 12)
        | (b4_1 << 8)
        | (b11 << 7)
        | (opcode & 0x7F)
    )


def encode_u_type(imm20: int, rd: int, opcode: int = OPCODE_LUI) -> int:
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)


def encode_j_type(offset21: int, rd: int, opcode: int = OPCODE_JAL) -> int:
    imm = offset21 & 0x1FFFFF
    b20 = (imm >> 20) & 0x1
    b19_12 = (imm >> 12) & 0xFF
    b11 = (imm >> 11) & 0x1
    b10_1 = (imm >> 1) & 0x3FF
    return (
        (b20 << 31)
        | (b10_1 << 21)
        | (b11 << 20)
        | (b19_12 << 12)
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


# ==============================================================================
# Desensamblador Inverso (uint32 -> texto ensamblador RV32I)
# ==============================================================================

def _sign_extend(value: int, bits: int) -> int:
    sign_bit = 1 << (bits - 1)
    return (value & (sign_bit - 1)) - (value & sign_bit)


def disassemble_word(word: int) -> str:
    """Convierte una palabra de 32 bits en su representación ensamblador legible."""
    word &= 0xFFFFFFFF
    if word == NOP_WORD:
        return "nop (addi x0, x0, 0)"
    if word == EBREAK_WORD:
        return "ebreak"
    if word == 0x00000000:
        return "0x00000000 (vacío)"

    opcode = word & 0x7F
    rd = (word >> 7) & 0x1F
    funct3 = (word >> 12) & 0x7
    rs1 = (word >> 15) & 0x1F
    rs2 = (word >> 20) & 0x1F
    funct7 = (word >> 25) & 0x7F

    if opcode == OPCODE_R_TYPE:
        for mnem, (f3, f7) in R_INSTRUCTIONS.items():
            if f3 == funct3 and f7 == funct7:
                return f"{mnem} x{rd}, x{rs1}, x{rs2}"

    elif opcode == OPCODE_I_IMM:
        if funct3 in (0b001, 0b101):
            shamt = rs2
            for mnem, (f3, f7) in I_SHIFT_INSTRUCTIONS.items():
                if f3 == funct3 and f7 == funct7:
                    return f"{mnem} x{rd}, x{rs1}, {shamt}"
        else:
            imm = _sign_extend(word >> 20, 12)
            for mnem, f3 in I_ALU_INSTRUCTIONS.items():
                if f3 == funct3:
                    return f"{mnem} x{rd}, x{rs1}, {imm}"

    elif opcode == OPCODE_LOAD:
        imm = _sign_extend(word >> 20, 12)
        for mnem, f3 in LOAD_INSTRUCTIONS.items():
            if f3 == funct3:
                return f"{mnem} x{rd}, {imm}(x{rs1})"

    elif opcode == OPCODE_STORE:
        imm12 = ((word >> 25) << 5) | ((word >> 7) & 0x1F)
        imm = _sign_extend(imm12, 12)
        for mnem, f3 in STORE_INSTRUCTIONS.items():
            if f3 == funct3:
                return f"{mnem} x{rs2}, {imm}(x{rs1})"

    elif opcode == OPCODE_BRANCH:
        b12 = (word >> 31) & 1
        b11 = (word >> 7) & 1
        b10_5 = (word >> 25) & 0x3F
        b4_1 = (word >> 8) & 0xF
        imm13 = (b12 << 12) | (b11 << 11) | (b10_5 << 5) | (b4_1 << 1)
        offset = _sign_extend(imm13, 13)
        for mnem, f3 in BRANCH_INSTRUCTIONS.items():
            if f3 == funct3:
                return f"{mnem} x{rs1}, x{rs2}, {offset}"

    elif opcode == OPCODE_LUI:
        imm20 = (word >> 12) & 0xFFFFF
        return f"lui x{rd}, 0x{imm20:X}"

    elif opcode == OPCODE_JAL:
        b20 = (word >> 31) & 1
        b10_1 = (word >> 21) & 0x3FF
        b11 = (word >> 20) & 1
        b19_12 = (word >> 12) & 0xFF
        imm21 = (b20 << 20) | (b19_12 << 12) | (b11 << 11) | (b10_1 << 1)
        offset = _sign_extend(imm21, 21)
        return f"jal x{rd}, {offset}"

    elif opcode == OPCODE_JALR:
        imm = _sign_extend(word >> 20, 12)
        return f"jalr x{rd}, x{rs1}, {imm}"

    return f"unk (0x{word:08X})"


# ==============================================================================
# Ensamblador de Dos Pasadas (.asm / .hex)
# ==============================================================================

_MEM_OPERAND_RE = re.compile(r"^([+-]?(?:0x[0-9a-fA-F]+|0b[01]+|\d+))\s*\(\s*([a-zA-Z0-9]+)\s*\)$")


def _strip_comments(line: str) -> str:
    for marker in ("#", "//", ";"):
        idx = line.find(marker)
        if idx != -1:
            line = line[:idx]
    return line.strip()


def _split_operands(operands_str: str) -> List[str]:
    if not operands_str.strip():
        return []
    return [op.strip() for op in operands_str.split(",") if op.strip()]


def _parse_mem_args(ops: List[str], line_num: int, src: str) -> Tuple[int, int, int]:
    """Soporta tanto 'lw rd, offset(rs1)' como 'lw rd, rs1, offset'."""
    if len(ops) == 2:
        rd = parse_register(ops[0], line_num, src)
        m = _MEM_OPERAND_RE.match(ops[1])
        if not m:
            raise AssemblerError(
                f"Operando de memoria inválido '{ops[1]}' (esperado: offset(rs1))",
                line_num,
                src,
            )
        offset = parse_immediate(m.group(1), line_num, src)
        rs1 = parse_register(m.group(2), line_num, src)
        return rd, rs1, offset
    if len(ops) == 3:
        rd = parse_register(ops[0], line_num, src)
        rs1 = parse_register(ops[1], line_num, src)
        offset = parse_immediate(ops[2], line_num, src)
        return rd, rs1, offset
    raise AssemblerError("Cantidad incorrecta de operandos para acceso a memoria", line_num, src)


def _resolve_branch_offset(
    token: str,
    current_pc: int,
    labels: Dict[str, int],
    bits: int,
    line_num: int,
    src: str,
) -> int:
    key = token.strip()
    if key in labels:
        offset = labels[key] - current_pc
    else:
        offset = parse_immediate(key, line_num, src)
    if offset % 2 != 0:
        raise AssemblerError(f"El desplazamiento de salto ({offset}) debe ser par", line_num, src)
    check_signed_range(offset, bits, line_num, src)
    return offset


def assemble_text(source_text: str, ensure_halt: bool = False) -> Tuple[List[AssembledInstruction], Dict[str, int]]:
    """
    Ensambla código fuente RV32I (.asm) o una lista de palabras en hexadecimal (.hex).

    Retorna:
      - Lista de objetos AssembledInstruction (uno por palabra de 32 bits).
      - Diccionario de etiquetas {nombre_etiqueta: direccion_byte}.
    """
    raw_lines = source_text.splitlines()

    # Pasada 1: Extraer etiquetas e identificar líneas ejecutables
    labels: Dict[str, int] = {}
    statements: List[Tuple[int, int, str, str]] = []  # (address, line_num, clean_stmt, raw_line)
    pc = 0

    for idx, raw_line in enumerate(raw_lines, start=1):
        clean = _strip_comments(raw_line)
        if not clean:
            continue

        # Ignorar directivas de ensamblador (.text, .globl, etc.)
        if clean.startswith("."):
            continue

        # Extraer una o más etiquetas al inicio de la línea (ej: "loop: add x1, x1, x2")
        while ":" in clean:
            label_part, rest = clean.split(":", 1)
            label_name = label_part.strip()
            if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", label_name):
                raise AssemblerError(f"Nombre de etiqueta inválido '{label_name}'", idx, raw_line)
            if label_name in labels:
                raise AssemblerError(f"Etiqueta duplicada '{label_name}'", idx, raw_line)
            labels[label_name] = pc
            clean = rest.strip()

        if clean:
            statements.append((pc, idx, clean, raw_line))
            pc += 4

    # Pasada 2: Codificar cada instrucción en una palabra de 32 bits
    program: List[AssembledInstruction] = []

    for addr, line_num, stmt, raw_line in statements:
        # Soporte directo para líneas .hex (ej: "01900093" o "0x01900093")
        if re.match(r"^(?:0x)?[0-9a-fA-F]{8}$", stmt):
            word = int(stmt, 16)
            program.append(
                AssembledInstruction(
                    address=addr,
                    word=word,
                    source_line=raw_line.strip(),
                    line_num=line_num,
                    canonical_asm=disassemble_word(word),
                    inst_format="HEX",
                )
            )
            continue

        parts = stmt.split(None, 1)
        mnem = parts[0].lower()
        ops_str = parts[1] if len(parts) > 1 else ""
        ops = _split_operands(ops_str)

        word: int
        fmt: str

        # --- Pseudoinstrucciones y Sistema ---
        if mnem == "nop":
            if ops:
                raise AssemblerError("'nop' no lleva operandos", line_num, raw_line)
            word, fmt = NOP_WORD, "I"

        elif mnem in ("ebreak", "halt"):
            if ops:
                raise AssemblerError(f"'{mnem}' no lleva operandos", line_num, raw_line)
            word, fmt = EBREAK_WORD, "SYS"

        elif mnem == "ret":
            if ops:
                raise AssemblerError("'ret' no lleva operandos", line_num, raw_line)
            word, fmt = encode_i_type(0, 1, 0b000, 0, OPCODE_JALR), "I"

        elif mnem == "jr":
            if len(ops) != 1:
                raise AssemblerError("Uso esperado: jr rs1", line_num, raw_line)
            rs1 = parse_register(ops[0], line_num, raw_line)
            word, fmt = encode_i_type(0, rs1, 0b000, 0, OPCODE_JALR), "I"

        elif mnem == "j":
            if len(ops) != 1:
                raise AssemblerError("Uso esperado: j etiqueta_o_offset", line_num, raw_line)
            offset = _resolve_branch_offset(ops[0], addr, labels, 21, line_num, raw_line)
            word, fmt = encode_j_type(offset, 0), "J"

        elif mnem == "mv":
            if len(ops) != 2:
                raise AssemblerError("Uso esperado: mv rd, rs1", line_num, raw_line)
            rd = parse_register(ops[0], line_num, raw_line)
            rs1 = parse_register(ops[1], line_num, raw_line)
            word, fmt = encode_i_type(0, rs1, 0b000, rd, OPCODE_I_IMM), "I"

        elif mnem == "li":
            if len(ops) != 2:
                raise AssemblerError("Uso esperado: li rd, imm12", line_num, raw_line)
            rd = parse_register(ops[0], line_num, raw_line)
            imm = parse_immediate(ops[1], line_num, raw_line)
            check_signed_range(imm, 12, line_num, raw_line)
            word, fmt = encode_i_type(imm, 0, 0b000, rd, OPCODE_I_IMM), "I"

        # --- Tipo R ---
        elif mnem in R_INSTRUCTIONS:
            if len(ops) != 3:
                raise AssemblerError(f"Uso esperado: {mnem} rd, rs1, rs2", line_num, raw_line)
            rd = parse_register(ops[0], line_num, raw_line)
            rs1 = parse_register(ops[1], line_num, raw_line)
            rs2 = parse_register(ops[2], line_num, raw_line)
            funct3, funct7 = R_INSTRUCTIONS[mnem]
            word, fmt = encode_r_type(funct7, rs2, rs1, funct3, rd), "R"

        # --- Tipo I (Aritméticas / Lógicas con Inmediato) ---
        elif mnem in I_ALU_INSTRUCTIONS:
            if len(ops) != 3:
                raise AssemblerError(f"Uso esperado: {mnem} rd, rs1, imm12", line_num, raw_line)
            rd = parse_register(ops[0], line_num, raw_line)
            rs1 = parse_register(ops[1], line_num, raw_line)
            imm = parse_immediate(ops[2], line_num, raw_line)
            check_signed_range(imm, 12, line_num, raw_line)
            funct3 = I_ALU_INSTRUCTIONS[mnem]
            word, fmt = encode_i_type(imm, rs1, funct3, rd, OPCODE_I_IMM), "I"

        # --- Tipo I (Shifts por inmediato de 5 bits) ---
        elif mnem in I_SHIFT_INSTRUCTIONS:
            if len(ops) != 3:
                raise AssemblerError(f"Uso esperado: {mnem} rd, rs1, shamt", line_num, raw_line)
            rd = parse_register(ops[0], line_num, raw_line)
            rs1 = parse_register(ops[1], line_num, raw_line)
            shamt = parse_immediate(ops[2], line_num, raw_line)
            if not (0 <= shamt <= 31):
                raise AssemblerError(f"shamt ({shamt}) debe estar entre 0 y 31", line_num, raw_line)
            funct3, funct7 = I_SHIFT_INSTRUCTIONS[mnem]
            imm12 = (funct7 << 5) | (shamt & 0x1F)
            word, fmt = encode_i_type(imm12, rs1, funct3, rd, OPCODE_I_IMM), "I"

        # --- Tipo I (Loads) ---
        elif mnem in LOAD_INSTRUCTIONS:
            rd, rs1, offset = _parse_mem_args(ops, line_num, raw_line)
            check_signed_range(offset, 12, line_num, raw_line)
            funct3 = LOAD_INSTRUCTIONS[mnem]
            word, fmt = encode_i_type(offset, rs1, funct3, rd, OPCODE_LOAD), "I"

        # --- Tipo S (Stores) ---
        elif mnem in STORE_INSTRUCTIONS:
            rs2, rs1, offset = _parse_mem_args(ops, line_num, raw_line)
            check_signed_range(offset, 12, line_num, raw_line)
            funct3 = STORE_INSTRUCTIONS[mnem]
            word, fmt = encode_s_type(offset, rs2, rs1, funct3), "S"

        # --- Tipo B (Branches) ---
        elif mnem in BRANCH_INSTRUCTIONS:
            if len(ops) != 3:
                raise AssemblerError(f"Uso esperado: {mnem} rs1, rs2, etiqueta_o_offset", line_num, raw_line)
            rs1 = parse_register(ops[0], line_num, raw_line)
            rs2 = parse_register(ops[1], line_num, raw_line)
            offset = _resolve_branch_offset(ops[2], addr, labels, 13, line_num, raw_line)
            funct3 = BRANCH_INSTRUCTIONS[mnem]
            word, fmt = encode_b_type(offset, rs2, rs1, funct3), "B"

        # --- Tipo U (LUI) ---
        elif mnem == "lui":
            if len(ops) != 2:
                raise AssemblerError("Uso esperado: lui rd, imm20", line_num, raw_line)
            rd = parse_register(ops[0], line_num, raw_line)
            imm20 = parse_immediate(ops[1], line_num, raw_line)
            if not (-0x80000 <= imm20 <= 0xFFFFF):
                raise AssemblerError(f"Inmediato LUI ({imm20}) fuera de rango de 20 bits", line_num, raw_line)
            word, fmt = encode_u_type(imm20, rd), "U"

        # --- Tipo J (JAL) ---
        elif mnem == "jal":
            if len(ops) == 1:
                rd = 1  # ra (x1) por defecto
                target_tok = ops[0]
            elif len(ops) == 2:
                rd = parse_register(ops[0], line_num, raw_line)
                target_tok = ops[1]
            else:
                raise AssemblerError("Uso esperado: jal [rd,] etiqueta_o_offset", line_num, raw_line)
            offset = _resolve_branch_offset(target_tok, addr, labels, 21, line_num, raw_line)
            word, fmt = encode_j_type(offset, rd), "J"

        # --- Tipo I (JALR) ---
        elif mnem == "jalr":
            if len(ops) == 1:
                rd, rs1, offset = 1, parse_register(ops[0], line_num, raw_line), 0
            elif len(ops) in (2, 3):
                rd, rs1, offset = _parse_mem_args(ops, line_num, raw_line)
            else:
                raise AssemblerError("Uso esperado: jalr rd, rs1, imm12  o  jalr rd, imm12(rs1)", line_num, raw_line)
            check_signed_range(offset, 12, line_num, raw_line)
            word, fmt = encode_i_type(offset, rs1, 0b000, rd, OPCODE_JALR), "I"

        else:
            raise AssemblerError(f"Instrucción desconocida o no soportada '{mnem}'", line_num, raw_line)

        program.append(
            AssembledInstruction(
                address=addr,
                word=word,
                source_line=raw_line.strip(),
                line_num=line_num,
                canonical_asm=disassemble_word(word),
                inst_format=fmt,
            )
        )

    if ensure_halt and program and not any(inst.word == EBREAK_WORD for inst in program):
        next_addr = program[-1].address + 4
        program.append(
            AssembledInstruction(
                address=next_addr,
                word=EBREAK_WORD,
                source_line="ebreak  # [Agregado automáticamente como parada]",
                line_num=len(raw_lines) + 1,
                canonical_asm="ebreak",
                inst_format="SYS",
            )
        )

    return program, labels


def assemble_file(file_path: str | Path, ensure_halt: bool = False) -> Tuple[List[AssembledInstruction], Dict[str, int]]:
    path = Path(file_path)
    text = path.read_text(encoding="utf-8")
    return assemble_text(text, ensure_halt=ensure_halt)


def format_translation_table(program: List[AssembledInstruction], labels: Optional[Dict[str, int]] = None) -> str:
    """Genera una tabla legible con la traducción Ensamblador -> Lenguaje Máquina."""
    inv_labels: Dict[int, List[str]] = {}
    if labels:
        for name, addr in labels.items():
            inv_labels.setdefault(addr, []).append(name)

    lines = [
        "=" * 108,
        f"{'PC':^8} | {'Hex (32b)':^10} | {'Bytes UART (LE)':^15} | {'Fmt':^4} | {'Campos Binarios (MSB -> LSB)':^37} | {'Instrucción Ensamblador'}",
        "=" * 108,
    ]
    for inst in program:
        if inst.address in inv_labels:
            lbl_str = ", ".join(f"{l}:" for l in inv_labels[inst.address])
            lines.append(f"         |            |                 |      |                                       | {lbl_str}")
        lines.append(
            f"0x{inst.address:04X}   | {inst.hex_str:^10} | {inst.le_bytes_str:^15} | {inst.inst_format:^4} | "
            f"{inst.bin_fields_str:<37} | {inst.canonical_asm}   [{inst.source_line}]"
        )
    lines.append("=" * 108)
    lines.append(f"Total: {len(program)} instrucciones ({len(program) * 4} bytes).")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Ensamblador RV32I a Lenguaje Máquina para Debug Unit UART")
    parser.add_argument("input", help="Archivo de entrada (.asm o .hex)")
    parser.add_argument("-o", "--output", help="Guardar salida hexadecimal en archivo (.hex)")
    parser.add_argument("--ensure-halt", action="store_true", help="Agregar 'ebreak' al final si no está presente")
    args = parser.parse_args()

    try:
        program, labels = assemble_file(args.input, ensure_halt=args.ensure_halt)
    except (OSError, AssemblerError) as err:
        print(f"[ERROR ENSAMBLADOR] {err}", file=sys.stderr)
        return 1

    print(format_translation_table(program, labels))

    if args.output:
        out_path = Path(args.output)
        out_text = "\n".join(f"{inst.word:08x}" for inst in program) + "\n"
        out_path.write_text(out_text, encoding="utf-8")
        print(f"\nArchivo hexadecimal guardado en: {out_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
