#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Mini-Juego RPG Interactivo — "Duelo en la Mazmorra" (Ejecutado en CPU RISC-V).

Interfaz gráfica en Tkinter donde el jugador elige sus acciones turno a turno
(Ataque Normal, Golpe Poderoso o Curar/Recargar) y TODA la lógica del combate
se ensambla a código máquina RV32I (usando las 32 instrucciones de la consigna
+ EBREAK) y se ejecuta directamente en:
  - La FPGA conectada por UART mediante `DebugUnitClient` (`0x02 LOAD_PROG` +
    `0x10 RUN` + `0x22 DUMP_DMEM` + `0x20 DUMP_REGS`), o
  - Un simulador RV32I local integrado (para probar/exponer sin placa conectada).

Uso:
  python sw/juego_rpg.py
  python sw/juego_rpg.py --port COM3
"""

from __future__ import annotations

import argparse
import random
import struct
import sys
import tkinter as tk
from dataclasses import dataclass, field
from pathlib import Path
from tkinter import messagebox, ttk
from typing import Dict, List, Optional, Tuple

try:
    from .assembler import assemble_text
    from .protocol import DEFAULT_BAUDRATE, DebugUnitClient, ProtocolError, to_signed32
except ImportError:
    from assembler import assemble_text
    from protocol import DEFAULT_BAUDRATE, DebugUnitClient, ProtocolError, to_signed32


# ==============================================================================
# Constantes visuales (tema oscuro coherente con sw/gui.py)
# ==============================================================================
BG_DARK = "#121622"
BG_PANEL = "#1B2133"
BG_CARD = "#232B42"
FG_TEXT = "#E6ECF8"
FG_MUTED = "#94A3B8"
ACCENT_BLUE = "#38BDF8"
ACCENT_GREEN = "#22C55E"
ACCENT_YELLOW = "#FACC15"
ACCENT_ORANGE = "#FB923C"
ACCENT_RED = "#EF4444"
ACCENT_PURPLE = "#A855F7"

# Acciones del jugador
ACTION_ATTACK = 0
ACTION_POWER = 1
ACTION_HEAL = 2

RESULT_ONGOING = 0x00000000
RESULT_VICTORY = 0xCAFE0001
RESULT_DEFEAT = 0xDEAD0000


# ==============================================================================
# Estado del Juego
# ==============================================================================
@dataclass
class GameState:
    hp_hero: int = 30
    max_hp_hero: int = 30
    energy: int = 16
    max_energy: int = 20
    score: int = 0

    hp_monster: int = 75
    max_hp_monster: int = 75
    defense: int = 8
    flags: int = 0x02  # bit0=Furia, bit1=Escudo, bit2=Herido

    seed: int = field(default_factory=lambda: random.SystemRandom().randint(1, 0x7FFFFFFF))
    turn: int = 1
    result: int = RESULT_ONGOING

    # Info del último turno ejecutado en el RISC-V
    last_dice: int = 0
    last_dmg: int = 0
    last_counter: int = 0
    last_events: int = 0  # b0=Crit, b1=EscudoRoto, b2=Curacion, b3=Poderoso
    last_dmem: List[int] = None  # type: ignore[assignment]
    last_regs: List[int] = None  # type: ignore[assignment]
    last_asm_words: int = 0

    def __post_init__(self) -> None:
        if self.last_dmem is None:
            self.last_dmem = [0] * 6
        if self.last_regs is None:
            self.last_regs = [0] * 32


# ==============================================================================
# Generador del Kernel RV32I de 1 Turno (cubre las 32 instrucciones + ebreak)
# ==============================================================================
def _emit_load_u32(reg: str, val: int) -> List[str]:
    """Emite instrucciones RV32I exactas para cargar cualquier uint32 en `reg`."""
    val &= 0xFFFFFFFF
    lo12 = val & 0xFFF
    if val < 0x800:
        return [f"    addi {reg}, x0, {val}"]
    if lo12 < 0x800:
        hi20 = (val >> 12) & 0xFFFFF
        return [
            f"    lui  {reg}, 0x{hi20:X}",
            f"    ori  {reg}, {reg}, 0x{lo12:X}",
        ]
    hi20_adj = ((val + 0x800) >> 12) & 0xFFFFF
    lo12_signed = lo12 - 0x1000
    return [
        f"    lui  {reg}, 0x{hi20_adj:X}",
        f"    addi {reg}, {reg}, {lo12_signed}",
    ]


def build_turn_asm(state: GameState, action: int) -> str:
    """
    Genera el programa ensamblador RV32I que resuelve exactamente 1 turno del
    combate según el estado actual y la acción elegida por el jugador:
      - action = 0 : Ataque Normal
      - action = 1 : Golpe Poderoso (cuesta 6 energía, daño x2)
      - action = 2 : Curar / Recargar (+8 HP, +6 energía, mitiga contraataque)

    Utiliza las 32 instrucciones RV32I de la consigna + `ebreak`.
    """
    seed_lines = "\n".join(_emit_load_u32("x5", state.seed))
    score_lines = "\n".join(_emit_load_u32("x5", state.score & 0xFFFF))

    return f"""# ==============================================================================
# Turno {state.turn} — Kernel Interactivo RV32I (Acción jugador = {action})
# ==============================================================================
    # 1. Cargar estado actual en DMEM[0..2]
    addi x5,  x0, {state.hp_hero}
    sb   x5,  0(x0)             # DMEM[0][7:0]   = HP_Heroe
    addi x5,  x0, {state.energy}
    sb   x5,  1(x0)             # DMEM[0][15:8]  = Energia
{score_lines}
    sh   x5,  2(x0)             # DMEM[0][31:16] = Score

    addi x5,  x0, {state.hp_monster}
    sh   x5,  4(x0)             # DMEM[1][15:0]  = HP_Monstruo
    addi x5,  x0, {state.defense}
    sb   x5,  6(x0)             # DMEM[1][23:16] = Defensa
    addi x5,  x0, {state.flags}
    sb   x5,  7(x0)             # DMEM[1][31:24] = Flags

{seed_lines}
    sw   x5,  8(x0)             # DMEM[2]        = Semilla PRNG
    sw   x0,  12(x0)            # DMEM[3]        = Resultado (0 = en curso)
    sw   x0,  20(x0)            # DMEM[5]        = Eventos del turno (0)

    # Registros preservados (ABI)
    addi x9,  x0, {state.turn}  # x9  (s1) = turno actual
    addi x18, x0, {action}      # x18 (s2) = acción elegida (0=Atq, 1=Poder, 2=Curar)
    addi x19, x0, 0             # x19 (s3) = eventos del turno
    addi x14, x0, 0             # x14 (a4) = daño infligido al monstruo

    # 2. Tirar el dado (subrutina PRNG xorshift: retorna 1..8 en x10)
    jal  x1, tirar_dado

    # Cargar Energía del Héroe
    lbu  x11, 1(x0)             # x11 = Energia (unsigned byte)

    # 3. Ramificar según la acción elegida por el jugador
    addi x5,  x0, 2
    beq  x18, x5, accion_curar  # si action == 2 -> Curar y recargar

    # --- ATAQUE NORMAL (0) o GOLPE PODEROSO (1) ---
    addi x5,  x0, 2
    srl  x12, x11, x5           # x12 = Energia >> 2 (bonus energía)
    addi x6,  x0, 1
    andi x7,  x9,  1            # turno mod 2 (bonus de combo balanceado: +1 o +2)
    sll  x13, x6,  x7           # x13 = 1 << (turno & 1)
    add  x14, x10, x12          # x14 = dado + bonus_energia
    add  x14, x14, x13          # x14 = ataque bruto

    # ¿El jugador eligió Golpe Poderoso (action == 1) y tiene Energia >= 6?
    addi x5,  x0, 1
    bne  x18, x5, check_critico
    sltiu x6, x11, 6            # x6 = 1 si Energia < 6
    bne  x6,  x0, check_critico # si no alcanza energía, hace ataque normal
    slli x14, x14, 1            # Golpe Poderoso: ataque x2
    addi x11, x11, -6           # gasta 6 de energía
    ori  x19, x19, 8            # evento bit 3 = Golpe Poderoso
    jal  x0,  energia_lista

check_critico:
    # Gasto normal de energía (-2, sin bajar de 0)
    sltiu x6, x11, 2
    bne  x6,  x0, energia_cero
    addi x11, x11, -2
    jal  x0,  energia_lista
energia_cero:
    addi x11, x0, 0

energia_lista:
    sb   x11, 1(x0)             # guarda nueva Energía en DMEM[0][15:8]

    # Comprobar Golpe Crítico (dado >= 7 -> 25% de probabilidad)
    sltiu x5, x10, 7            # x5 = 1 si dado < 7
    bne  x5,  x0, sin_critico
    slli x14, x14, 1            # ¡CRÍTICO! duplica ataque
    ori  x19, x19, 1            # evento bit 0 = Crítico

sin_critico:
    # Restar Defensa del Monstruo y asegurar daño mínimo = 1
    lbu  x15, 6(x0)             # x15 = Defensa
    sub  x14, x14, x15          # daño neto = ataque - defensa
    slti x5,  x14, 1            # ¿daño < 1? (con signo)
    beq  x5,  x0, danio_ok
    addi x14, x0, 1             # daño mínimo = 1

danio_ok:
    # Aplicar daño al Monstruo (signed 16-bit)
    lh   x28, 4(x0)             # x28 = HP_Monstruo (extensión de signo)
    sub  x28, x28, x14          # HP_Monstruo -= daño
    sh   x28, 4(x0)             # guarda HP_Monstruo

    # Actualizar Flags del Monstruo (Furia, Escudo, Herido)
    lbu  x29, 7(x0)
    xori x29, x29, 1            # alterna bit 0 (Furia)
    ori  x29, x29, 4            # activa bit 2 (Herido)
    sltu x5,  x15, x14          # ¿Defensa < Daño? (sin signo)
    beq  x5,  x0, guardar_flags
    andi x6,  x29, 2            # ¿tenía escudo activo?
    beq  x6,  x0, guardar_flags
    addi x6,  x0, 5             # máscara 0b101 -> apaga bit 1 (Escudo)
    and  x29, x29, x6
    sb   x0,  6(x0)             # Defensa -> 0
    ori  x19, x19, 2            # evento bit 1 = Escudo roto

guardar_flags:
    sb   x29, 7(x0)

    # Sumar Score (+8 por cada punto de daño)
    lhu  x30, 2(x0)
    slli x5,  x14, 3
    add  x30, x30, x5
    sh   x30, 2(x0)

    # ¿Cayó el Monstruo? (HP_Monstruo < 1 con signo)
    addi x5,  x0, 1
    slt  x6,  x28, x5
    bne  x6,  x0, victoria
    jal  x0,  contraataque

    # --- ACCIÓN 2: CURAR / RECARGAR ---
accion_curar:
    lb   x7,  0(x0)             # HP_Heroe (signed byte)
    addi x7,  x7,  10           # +10 HP
    slti x5,  x7,  31           # tope máximo 30
    bne  x5,  x0, hp_ok
    addi x7,  x0,  30
hp_ok:
    sb   x7,  0(x0)

    addi x11, x11, 6            # +6 Energía
    sltiu x5, x11, 21           # tope máximo 20
    bne  x5,  x0, eng_ok
    addi x11, x0,  20
eng_ok:
    sb   x11, 1(x0)
    ori  x19, x19, 4            # evento bit 2 = Curación

    # 4. Contraataque del Monstruo (aritmética con signo: srai y sra)
contraataque:
    # Base del contraataque: -24 (normal -> -6 HP) o -40 (en Furia -> -10 HP)
    lbu  x29, 7(x0)
    andi x6,  x29, 1
    addi x5,  x0, -24
    beq  x6,  x0, sin_furia
    addi x5,  x0, -40           # en Furia pega mucho más fuerte (-10 HP)!
sin_furia:
    srai x5,  x5, 1             # -24 >> 1 = -12 (o -40 >> 1 = -20)
    addi x6,  x0, 1             # mitigación base = 1
    addi x7,  x0, 2
    bne  x18, x7, aplicar_sra
    addi x6,  x0, 2             # si el Héroe se curó/defendió, mitiga a la mitad (>> 2)
aplicar_sra:
    sra  x5,  x5, x6            # daño negativo final (-6/-10 normal, -3/-5 mitigado)

    lb   x7,  0(x0)             # HP_Heroe actual (con signo)
    add  x7,  x7, x5            # HP_Heroe += daño_negativo
    sb   x7,  0(x0)             # guarda nuevo HP_Heroe

    sub  x20, x0, x5            # x20 = magnitud positiva del contraataque

    # Guardar Log del turno en DMEM[4] y Eventos en DMEM[5]
    slli x5,  x9,  24           # turno << 24
    slli x6,  x10, 16           # dado  << 16
    or   x5,  x5,  x6
    slli x6,  x14, 8            # daño  << 8
    or   x5,  x5,  x6
    andi x6,  x20, 0xFF         # contraataque
    or   x5,  x5,  x6
    sw   x5,  16(x0)            # DMEM[4] = Log del turno
    sw   x19, 20(x0)            # DMEM[5] = Eventos

    # ¿Cayó el Héroe? (HP_Heroe < 1 con signo)
    slti x6,  x7, 1
    bne  x6,  x0, derrota
    jal  x0,  fin_turno

derrota:
    lui  x31, 0xDEAD0           # Firma de DERROTA = 0xDEAD0000
    sw   x31, 12(x0)            # DMEM[3]
    jal  x0,  fin_turno

victoria:
    # Guardar Log y Eventos antes de cerrar con victoria
    slli x5,  x9,  24
    slli x6,  x10, 16
    or   x5,  x5,  x6
    slli x6,  x14, 8
    or   x5,  x5,  x6
    sw   x5,  16(x0)            # DMEM[4] = Log (contraataque = 0)
    sw   x19, 20(x0)            # DMEM[5] = Eventos

    lh   x10, 4(x0)             # Lee HP final del Monstruo con signo (<= 0)
    lui  x31, 0xCAFE0
    ori  x31, x31, 1            # Firma de VICTORIA = 0xCAFE0001
    sw   x31, 12(x0)            # DMEM[3]

fin_turno:
    ebreak                      # Fin del turno -> Drena pipeline y envía HALTED

    # --------------------------------------------------------------------------
    # Subrutina: tirar_dado (PRNG xorshift -> retorna 1..8 en x10 / a0)
    # --------------------------------------------------------------------------
tirar_dado:
    lw   x5,  8(x0)
    slli x6,  x5, 13
    xor  x5,  x5, x6
    srli x6,  x5, 17
    xor  x5,  x5, x6
    slli x6,  x5, 5
    xor  x5,  x5, x6
    sw   x5,  8(x0)
    andi x10, x5, 7
    addi x10, x10, 1
    jalr x0,  0(x1)
"""


# ==============================================================================
# Simulador RV32I Exacto Local (fallback cuando no hay FPGA conectada)
# ==============================================================================
def _sext(val: int, bits: int) -> int:
    sign = 1 << (bits - 1)
    return (val & (sign - 1)) - (val & sign)


def simulate_rv32i(words: List[int], max_steps: int = 2000) -> Tuple[List[int], List[int]]:
    """
    Ejecuta código máquina RV32I de 32 bits exactamente igual que el hardware
    (`riscv_core.v`) hasta `ebreak`. Retorna `(regs[0..31], dmem_words[0..7])`.
    """
    regs = [0] * 32
    dmem = bytearray(1024)
    pc = 0

    for _ in range(max_steps):
        idx = pc >> 2
        if idx < 0 or idx >= len(words):
            break
        w = words[idx] & 0xFFFFFFFF
        if w == 0x00100073:  # EBREAK
            break

        opcode = w & 0x7F
        rd = (w >> 7) & 0x1F
        f3 = (w >> 12) & 0x7
        rs1 = (w >> 15) & 0x1F
        rs2 = (w >> 20) & 0x1F
        f7 = (w >> 25) & 0x7F
        next_pc = (pc + 4) & 0xFFFFFFFF

        v1 = regs[rs1] & 0xFFFFFFFF
        v2 = regs[rs2] & 0xFFFFFFFF
        s1 = to_signed32(v1)
        s2 = to_signed32(v2)

        if opcode == 0b0110011:  # R-Type
            sh = v2 & 0x1F
            if f3 == 0b000:
                res = (v1 - v2) if (f7 == 0b0100000) else (v1 + v2)
            elif f3 == 0b001:
                res = v1 << sh
            elif f3 == 0b010:
                res = 1 if s1 < s2 else 0
            elif f3 == 0b011:
                res = 1 if v1 < v2 else 0
            elif f3 == 0b100:
                res = v1 ^ v2
            elif f3 == 0b101:
                res = (s1 >> sh) if (f7 == 0b0100000) else (v1 >> sh)
            elif f3 == 0b110:
                res = v1 | v2
            elif f3 == 0b111:
                res = v1 & v2
            else:
                res = 0
            if rd:
                regs[rd] = res & 0xFFFFFFFF

        elif opcode == 0b0010011:  # I-ALU / I-Shift
            imm = _sext(w >> 20, 12)
            imm_u = imm & 0xFFFFFFFF
            sh = rs2
            if f3 == 0b000:
                res = v1 + imm
            elif f3 == 0b010:
                res = 1 if s1 < imm else 0
            elif f3 == 0b011:
                res = 1 if v1 < imm_u else 0
            elif f3 == 0b100:
                res = v1 ^ imm_u
            elif f3 == 0b110:
                res = v1 | imm_u
            elif f3 == 0b111:
                res = v1 & imm_u
            elif f3 == 0b001:
                res = v1 << sh
            elif f3 == 0b101:
                res = (s1 >> sh) if (f7 == 0b0100000) else (v1 >> sh)
            else:
                res = 0
            if rd:
                regs[rd] = res & 0xFFFFFFFF

        elif opcode == 0b0000011:  # Loads
            addr = (v1 + _sext(w >> 20, 12)) & 0x3FF
            if f3 == 0b000:  # lb
                res = _sext(dmem[addr], 8)
            elif f3 == 0b001:  # lh
                res = struct.unpack_from("<h", dmem, addr)[0]
            elif f3 == 0b010:  # lw
                res = struct.unpack_from("<I", dmem, addr)[0]
            elif f3 == 0b100:  # lbu
                res = dmem[addr]
            elif f3 == 0b101:  # lhu
                res = struct.unpack_from("<H", dmem, addr)[0]
            else:
                res = 0
            if rd:
                regs[rd] = res & 0xFFFFFFFF

        elif opcode == 0b0100011:  # Stores
            imm12 = ((w >> 25) << 5) | ((w >> 7) & 0x1F)
            addr = (v1 + _sext(imm12, 12)) & 0x3FF
            if f3 == 0b000:  # sb
                dmem[addr] = v2 & 0xFF
            elif f3 == 0b001:  # sh
                struct.pack_into("<H", dmem, addr, v2 & 0xFFFF)
            elif f3 == 0b010:  # sw
                struct.pack_into("<I", dmem, addr, v2 & 0xFFFFFFFF)

        elif opcode == 0b1100011:  # Branches
            b12 = (w >> 31) & 1
            b11 = (w >> 7) & 1
            b10_5 = (w >> 25) & 0x3F
            b4_1 = (w >> 8) & 0xF
            off = _sext((b12 << 12) | (b11 << 11) | (b10_5 << 5) | (b4_1 << 1), 13)
            take = (v1 == v2) if f3 == 0b000 else (v1 != v2)
            if take:
                next_pc = (pc + off) & 0xFFFFFFFF

        elif opcode == 0b0110111:  # LUI
            if rd:
                regs[rd] = w & 0xFFFFF000

        elif opcode == 0b1101111:  # JAL
            b20 = (w >> 31) & 1
            b10_1 = (w >> 21) & 0x3FF
            b11 = (w >> 20) & 1
            b19_12 = (w >> 12) & 0xFF
            off = _sext((b20 << 20) | (b19_12 << 12) | (b11 << 11) | (b10_1 << 1), 21)
            if rd:
                regs[rd] = next_pc
            next_pc = (pc + off) & 0xFFFFFFFF

        elif opcode == 0b1100111:  # JALR
            off = _sext(w >> 20, 12)
            target = (v1 + off) & 0xFFFFFFFE
            if rd:
                regs[rd] = next_pc
            next_pc = target

        regs[0] = 0
        pc = next_pc

    dmem_words = [struct.unpack_from("<I", dmem, i * 4)[0] for i in range(6)]
    return regs, dmem_words


# ==============================================================================
# Interfaz Gráfica del Juego (Tkinter + Canvas con Dibujos y Animaciones)
# ==============================================================================
class DungeonRPGApp:
    def __init__(self, root: tk.Tk, initial_port: Optional[str] = None) -> None:
        self.root = root
        self.root.title("Duelo en la Mazmorra — Juego RPG en Procesador RISC-V (RV32I)")
        self.root.configure(bg=BG_DARK)
        self.root.geometry("1040x680")
        self.root.minsize(960, 640)

        self.client = DebugUnitClient()
        self.use_fpga = False
        self.is_busy = False
        self.state = GameState()
        self.anim_effect: Optional[str] = None
        self.anim_banner: str = "¡Elegí tu acción para comenzar el duelo!"
        self.anim_banner_color: str = ACCENT_BLUE

        self._configure_styles()
        self._build_ui()

        if initial_port:
            self.port_var.set(initial_port)
            self._connect_fpga()
        else:
            self._refresh_ports()

        self._render_all()

    def _configure_styles(self) -> None:
        style = ttk.Style(self.root)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("TFrame", background=BG_DARK)
        style.configure("Panel.TFrame", background=BG_PANEL)
        style.configure("TLabel", background=BG_DARK, foreground=FG_TEXT, font=("Segoe UI", 10))
        style.configure("Panel.TLabel", background=BG_PANEL, foreground=FG_TEXT, font=("Segoe UI", 10))
        style.configure("Title.TLabel", background=BG_DARK, foreground=ACCENT_BLUE, font=("Segoe UI", 15, "bold"))
        style.configure("Sub.TLabel", background=BG_PANEL, foreground=FG_MUTED, font=("Consolas", 9))

    def _build_ui(self) -> None:
        # ------------------------------------------------------------------
        # Barra superior: título + conexión FPGA / Simulador
        # ------------------------------------------------------------------
        top = tk.Frame(self.root, bg=BG_PANEL, padx=14, pady=10)
        top.pack(fill=tk.X)

        tk.Label(
            top,
            text="⚔️  DUELO EN LA MAZMORRA — RISC-V RV32I",
            bg=BG_PANEL,
            fg=ACCENT_BLUE,
            font=("Segoe UI", 14, "bold"),
        ).pack(side=tk.LEFT)

        conn_frame = tk.Frame(top, bg=BG_PANEL)
        conn_frame.pack(side=tk.RIGHT)

        self.mode_badge = tk.Label(
            conn_frame,
            text=" ● SIMULADOR RV32I ",
            bg="#2D3748",
            fg=ACCENT_YELLOW,
            font=("Consolas", 9, "bold"),
            padx=8,
            pady=4,
        )
        self.mode_badge.pack(side=tk.LEFT, padx=(0, 8))

        self.port_var = tk.StringVar(value="")
        self.port_combo = ttk.Combobox(conn_frame, textvariable=self.port_var, width=12, state="readonly")
        self.port_combo.pack(side=tk.LEFT, padx=3)

        tk.Button(
            conn_frame,
            text="↻",
            command=self._refresh_ports,
            bg=BG_CARD,
            fg=FG_TEXT,
            relief=tk.FLAT,
            padx=6,
            cursor="hand2",
        ).pack(side=tk.LEFT, padx=2)

        self.btn_connect = tk.Button(
            conn_frame,
            text="Conectar FPGA",
            command=self._toggle_fpga,
            bg="#2563EB",
            fg="white",
            font=("Segoe UI", 9, "bold"),
            relief=tk.FLAT,
            padx=10,
            pady=3,
            cursor="hand2",
        )
        self.btn_connect.pack(side=tk.LEFT, padx=4)

        tk.Button(
            conn_frame,
            text="Nueva Partida",
            command=self._reset_game,
            bg="#334155",
            fg=FG_TEXT,
            font=("Segoe UI", 9, "bold"),
            relief=tk.FLAT,
            padx=10,
            pady=3,
            cursor="hand2",
        ).pack(side=tk.LEFT, padx=(6, 0))

        # ------------------------------------------------------------------
        # Cuerpo principal: Izquierda (Arena + Controles) | Derecha (Inspector RISC-V)
        # ------------------------------------------------------------------
        body = tk.Frame(self.root, bg=BG_DARK, padx=12, pady=10)
        body.pack(fill=tk.BOTH, expand=True)

        left = tk.Frame(body, bg=BG_DARK)
        left.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 10))

        # Canvas de la Arena de Combate
        self.canvas = tk.Canvas(
            left,
            width=640,
            height=380,
            bg="#0B1020",
            highlightthickness=2,
            highlightbackground="#334155",
        )
        self.canvas.pack(fill=tk.BOTH, expand=True)
        self.canvas.bind("<Configure>", lambda _e: self._draw_arena())

        # Botones de Acción del Jugador
        actions = tk.Frame(left, bg=BG_PANEL, padx=12, pady=10)
        actions.pack(fill=tk.X, pady=(10, 0))

        self.btn_attack = tk.Button(
            actions,
            text="⚔️  ATAQUE NORMAL\n(Costo: 2 Energía)",
            command=lambda: self._play_turn(ACTION_ATTACK),
            bg="#1D4ED8",
            fg="white",
            activebackground="#2563EB",
            font=("Segoe UI", 10, "bold"),
            relief=tk.FLAT,
            padx=12,
            pady=8,
            cursor="hand2",
        )
        self.btn_attack.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 6))

        self.btn_power = tk.Button(
            actions,
            text="🔥  GOLPE PODEROSO\n(Costo: 6 Energía | Daño x2)",
            command=lambda: self._play_turn(ACTION_POWER),
            bg="#B91C1C",
            fg="white",
            activebackground="#DC2626",
            font=("Segoe UI", 10, "bold"),
            relief=tk.FLAT,
            padx=12,
            pady=8,
            cursor="hand2",
        )
        self.btn_power.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=6)

        self.btn_heal = tk.Button(
            actions,
            text="🛡️  CURAR / DEFENDER\n(+10 HP | +6 Energía | Mitiga 50%)",
            command=lambda: self._play_turn(ACTION_HEAL),
            bg="#15803D",
            fg="white",
            activebackground="#16A34A",
            font=("Segoe UI", 10, "bold"),
            relief=tk.FLAT,
            padx=12,
            pady=8,
            cursor="hand2",
        )
        self.btn_heal.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(6, 0))

        # Log de combate debajo de los botones
        log_box = tk.Frame(left, bg=BG_PANEL, padx=8, pady=6)
        log_box.pack(fill=tk.X, pady=(8, 0))
        tk.Label(
            log_box,
            text="📜 Historial de Combate",
            bg=BG_PANEL,
            fg=FG_MUTED,
            font=("Segoe UI", 9, "bold"),
        ).pack(anchor=tk.W)
        self.log_text = tk.Text(
            log_box,
            height=5,
            bg="#0F172A",
            fg=FG_TEXT,
            font=("Consolas", 9),
            relief=tk.FLAT,
            state=tk.DISABLED,
            wrap=tk.WORD,
        )
        self.log_text.pack(fill=tk.X, pady=(4, 0))

        # ------------------------------------------------------------------
        # Panel Derecho: Inspector RISC-V en Vivo (para la exposición!)
        # ------------------------------------------------------------------
        right = tk.Frame(body, bg=BG_PANEL, width=320, padx=12, pady=10)
        right.pack(side=tk.RIGHT, fill=tk.Y)
        right.pack_propagate(False)

        tk.Label(
            right,
            text="🔬 INSPECTOR RISC-V (EN VIVO)",
            bg=BG_PANEL,
            fg=ACCENT_BLUE,
            font=("Segoe UI", 11, "bold"),
        ).pack(anchor=tk.W)

        tk.Label(
            right,
            text="Cada botón ensambla 32 instrucciones RV32I,\nlas carga en IMEM, ejecuta hasta EBREAK\ny lee DMEM + Registros de la CPU.",
            bg=BG_PANEL,
            fg=FG_MUTED,
            font=("Segoe UI", 8),
            justify=tk.LEFT,
        ).pack(anchor=tk.W, pady=(2, 10))

        self.hw_info_lbl = tk.Label(
            right,
            text="Esperando primer turno...",
            bg=BG_CARD,
            fg=ACCENT_YELLOW,
            font=("Consolas", 9),
            anchor=tk.W,
            padx=8,
            pady=6,
            justify=tk.LEFT,
        )
        self.hw_info_lbl.pack(fill=tk.X, pady=(0, 10))

        tk.Label(
            right,
            text="Memoria de Datos (DMEM[0..5])",
            bg=BG_PANEL,
            fg=FG_TEXT,
            font=("Segoe UI", 9, "bold"),
        ).pack(anchor=tk.W)

        self.dmem_text = tk.Text(
            right,
            height=11,
            bg="#0F172A",
            fg="#7DD3FC",
            font=("Consolas", 9),
            relief=tk.FLAT,
            state=tk.DISABLED,
        )
        self.dmem_text.pack(fill=tk.X, pady=(4, 10))

        tk.Label(
            right,
            text="Registros Clave (ABI RISC-V)",
            bg=BG_PANEL,
            fg=FG_TEXT,
            font=("Segoe UI", 9, "bold"),
        ).pack(anchor=tk.W)

        self.regs_text = tk.Text(
            right,
            height=9,
            bg="#0F172A",
            fg="#86EFAC",
            font=("Consolas", 9),
            relief=tk.FLAT,
            state=tk.DISABLED,
        )
        self.regs_text.pack(fill=tk.BOTH, expand=True, pady=(4, 0))

    # ------------------------------------------------------------------
    # Conexión UART / FPGA
    # ------------------------------------------------------------------
    def _refresh_ports(self) -> None:
        ports = DebugUnitClient.list_available_ports()
        names = [p[0] for p in ports]
        self.port_combo["values"] = names
        if names and not self.port_var.get():
            self.port_var.set(names[0])

    def _toggle_fpga(self) -> None:
        if self.use_fpga:
            self.client.disconnect()
            self.use_fpga = False
            self.btn_connect.config(text="Conectar FPGA", bg="#2563EB")
            self.mode_badge.config(text=" ● SIMULADOR RV32I ", fg=ACCENT_YELLOW)
            self._append_log("[INFO] Desconectado de la FPGA. Usando Simulador RV32I local.")
        else:
            self._connect_fpga()

    def _connect_fpga(self) -> None:
        port = self.port_var.get().strip()
        if not port:
            messagebox.showwarning("Puerto COM", "Seleccioná un puerto serie primero (o jugá en Simulador RV32I).")
            return
        try:
            self.client.connect(port, DEFAULT_BAUDRATE)
            self.use_fpga = True
            self.btn_connect.config(text="Desconectar", bg="#DC2626")
            self.mode_badge.config(text=f" ● FPGA ({port}) ", fg=ACCENT_GREEN)
            if self.client.resync():
                self._append_log(f"[UART] Conectado y sincronizado con la FPGA en {port} @ {DEFAULT_BAUDRATE} bps.")
            else:
                self._append_log(
                    f"[AVISO] Puerto {port} abierto pero la FPGA no respondió al RESET. "
                    "Presioná el botón central BTNC en la placa Nexys 4 si estaba trabada."
                )
        except ProtocolError as exc:
            self.use_fpga = False
            messagebox.showerror("Error UART", str(exc))

    def _run_turn_on_fpga(self, words: List[int]) -> Tuple[List[int], List[int]]:
        """Ejecuta LOAD_PROG + RUN + DUMP_DMEM + DUMP_REGS con reintento automático."""
        last_exc: Optional[Exception] = None
        for attempt in range(2):
            try:
                # CMD_LOAD_PROG ya resetea el core y borra DMEM automáticamente en la FPGA
                self.client.load_program(words)
                self.client.run(run_timeout=5.0)
                dmem_entries = self.client.dump_dmem(offset_word=0, count_words=6)
                dmem_words = [e.data for e in dmem_entries]
                regs = self.client.dump_regs()
                return regs, dmem_words
            except ProtocolError as exc:
                last_exc = exc
                if attempt == 0:
                    self._append_log("[UART] Timeout detectado, intentando resincronizar Debug Unit...")
                    self.root.update_idletasks()
                    if self.client.resync():
                        continue
                break
        raise ProtocolError(
            f"{last_exc}\n\n"
            "Si la Debug Unit quedó esperando bytes de una trama anterior, "
            "presioná una vez el botón físico central BTNC (Reset) en la placa Nexys 4 y reintentá."
        )

    # ------------------------------------------------------------------
    # Ejecución de un Turno en el Procesador RISC-V
    # ------------------------------------------------------------------
    def _play_turn(self, action: int) -> None:
        if self.is_busy or self.state.result != RESULT_ONGOING:
            return

        asm_src = build_turn_asm(self.state, action)
        try:
            program, _ = assemble_text(asm_src)
        except Exception as exc:
            messagebox.showerror("Error ensamblando turno", str(exc))
            return

        words = [inst.word for inst in program]
        self.state.last_asm_words = len(words)

        self.is_busy = True
        self.btn_attack.config(state=tk.DISABLED)
        self.btn_power.config(state=tk.DISABLED)
        self.btn_heal.config(state=tk.DISABLED)
        self.root.update_idletasks()

        try:
            if self.use_fpga:
                regs, dmem_words = self._run_turn_on_fpga(words)
            else:
                regs, dmem_words = simulate_rv32i(words)
        except Exception as exc:
            self._append_log(f"[ERROR UART] {exc}")
            messagebox.showerror("Error ejecutando en RISC-V", str(exc))
            self._render_all()
            return
        finally:
            self.is_busy = False

        # Desempaquetar estado resultante leído directamente desde DMEM[0..5]
        w0, w1, w2, w3, w4, w5 = dmem_words
        self.state.last_dmem = dmem_words
        self.state.last_regs = regs

        self.state.hp_hero = _sext(w0 & 0xFF, 8)
        self.state.energy = (w0 >> 8) & 0xFF
        self.state.score = (w0 >> 16) & 0xFFFF

        self.state.hp_monster = _sext(w1 & 0xFFFF, 16)
        self.state.defense = (w1 >> 16) & 0xFF
        self.state.flags = (w1 >> 24) & 0xFF

        self.state.seed = w2
        self.state.result = w3

        self.state.last_dice = (w4 >> 16) & 0xFF
        self.state.last_dmg = (w4 >> 8) & 0xFF
        self.state.last_counter = w4 & 0xFF
        self.state.last_events = w5

        # Mensaje narrativo + animación visual
        ev = w5
        crit = bool(ev & 1)
        shield_broke = bool(ev & 2)
        healed = bool(ev & 4)
        powered = bool(ev & 8)

        if healed:
            self.anim_effect = "heal"
            msg = f"Turno {self.state.turn}: 🛡️ Curación (+10 HP, +6 EN). Contraataque mitigado: -{self.state.last_counter} HP."
            self.anim_banner = f"🛡️ ¡CURACIÓN! (+10 HP / +6 EN)  |  Escudo levantado..."
            self.anim_banner_color = ACCENT_GREEN
        else:
            tags = []
            if powered:
                tags.append("🔥 PODEROSO")
            if crit:
                tags.append("💥 ¡CRÍTICO!")
            if shield_broke:
                tags.append("🛡️ ¡ESCUDO ROTO!")
            tag_str = (" [" + " ".join(tags) + "]") if tags else ""
            self.anim_effect = "crit" if (crit or powered) else "attack"
            msg = (
                f"Turno {self.state.turn}: Dado={self.state.last_dice} → "
                f"Daño={self.state.last_dmg}{tag_str} | "
                f"HP Monstruo={self.state.hp_monster}"
            )
            if self.state.last_counter > 0:
                msg += f" | Contraataque=-{self.state.last_counter} HP"
            self.anim_banner = (
                f"Dado: {self.state.last_dice}  →  ¡{self.state.last_dmg} de DAÑO!{tag_str}"
            )
            self.anim_banner_color = ACCENT_YELLOW if crit else ACCENT_ORANGE

        if self.state.result == RESULT_VICTORY:
            self.anim_effect = "victory"
            self.anim_banner = "🏆 ¡VICTORIA! Firma RISC-V: 0xCAFE0001 🏆"
            self.anim_banner_color = ACCENT_GREEN
            msg += "  >>> ¡VICTORIA (0xCAFE0001)!"
        elif self.state.result == RESULT_DEFEAT:
            msg += "  >>> DERROTA (0xDEAD0000)"
        else:
            self.state.turn += 1

        self._append_log(msg)
        self._render_all()

        # Animación en 2 fases: primero acción del Héroe (550 ms), luego llamarada del Dragón (650 ms)
        if self.state.last_counter > 0 and self.state.result != RESULT_VICTORY:
            self.is_busy = True
            self.btn_attack.config(state=tk.DISABLED)
            self.btn_power.config(state=tk.DISABLED)
            self.btn_heal.config(state=tk.DISABLED)
            self.root.after(550, lambda h=healed: self._play_dragon_counter_anim(h))
        elif self.state.result == RESULT_ONGOING:
            self.root.after(650, self._clear_flash)

    def _play_dragon_counter_anim(self, was_healed: bool) -> None:
        self.anim_effect = "dragon_attack"
        if self.state.result == RESULT_DEFEAT:
            self.anim_banner = f"🔥 ¡EL DRAGÓN TE DERRIBÓ (-{self.state.last_counter} HP)! 💀 DERROTA (0xDEAD0000)"
            self.anim_banner_color = ACCENT_RED
        elif was_healed:
            self.anim_banner = f"🔥 ¡CONTRAATAQUE DEL DRAGÓN! -{self.state.last_counter} HP (mitigado por tu escudo)"
            self.anim_banner_color = ACCENT_ORANGE
        else:
            furia = " EN FURIA" if (self.state.flags & 1) else ""
            self.anim_banner = f"🔥 ¡EL DRAGÓN{furia} CONTRAATACA! -{self.state.last_counter} HP"
            self.anim_banner_color = ACCENT_RED
        self._draw_arena()
        self.root.after(700, self._finish_turn_anim)

    def _finish_turn_anim(self) -> None:
        self.is_busy = False
        if self.state.result == RESULT_DEFEAT:
            self.anim_effect = "defeat"
        elif self.state.result == RESULT_ONGOING:
            self.anim_effect = None
        self._render_all()

    def _clear_flash(self) -> None:
        if self.state.result == RESULT_ONGOING:
            self.anim_effect = None
            self._draw_arena()

    def _reset_game(self) -> None:
        if self.is_busy:
            return
        self.state = GameState()
        self.anim_effect = None
        self.anim_banner = "¡Nuevo Duelo! Elegí tu acción para comenzar."
        self.anim_banner_color = ACCENT_BLUE
        self.log_text.config(state=tk.NORMAL)
        self.log_text.delete("1.0", tk.END)
        self.log_text.config(state=tk.DISABLED)
        if self.use_fpga:
            if self.client.resync():
                self._append_log("[UART] FPGA reseteada y lista para la nueva partida.")
            else:
                self._append_log("[AVISO] La FPGA no respondió al reset. Presioná el botón BTNC en la placa.")
        self._append_log("[JUEGO] Nueva partida iniciada. Héroe (30 HP) vs Dragón (75 HP, Escudo=8).")
        self._render_all()

    def _append_log(self, line: str) -> None:
        self.log_text.config(state=tk.NORMAL)
        self.log_text.insert(tk.END, line + "\n")
        self.log_text.see(tk.END)
        self.log_text.config(state=tk.DISABLED)

    # ------------------------------------------------------------------
    # Renderizado de Canvas (Dibujitos + Barras + Dado + Efectos)
    # ------------------------------------------------------------------
    def _render_all(self) -> None:
        self._draw_arena()
        self._update_inspector()

        ended = self.state.result != RESULT_ONGOING
        btn_state = tk.DISABLED if ended else tk.NORMAL
        self.btn_attack.config(state=btn_state)
        self.btn_heal.config(state=btn_state)
        if ended or self.state.energy < 6:
            self.btn_power.config(state=tk.DISABLED)
        else:
            self.btn_power.config(state=tk.NORMAL)

    def _draw_bar(
        self,
        c: tk.Canvas,
        x: int,
        y: int,
        w: int,
        h: int,
        val: int,
        max_val: int,
        color: str,
        label: str,
    ) -> None:
        c.create_rectangle(x, y, x + w, y + h, fill="#1E293B", outline="#475569", width=2)
        ratio = max(0.0, min(1.0, val / max(1, max_val)))
        if ratio > 0:
            c.create_rectangle(x + 2, y + 2, x + 2 + int((w - 4) * ratio), y + h - 2, fill=color, outline="")
        c.create_text(
            x + w // 2,
            y + h // 2,
            text=label,
            fill="white",
            font=("Consolas", 9, "bold"),
        )

    def _draw_hero(self, c: tk.Canvas, cx: int, cy: int) -> None:
        dead = self.state.hp_hero <= 0
        body_col = "#475569" if dead else "#3B82F6"
        cape_col = "#334155" if dead else "#1D4ED8"

        # Sombra en el piso
        c.create_oval(cx - 42, cy + 52, cx + 42, cy + 68, fill="#060913", outline="")

        # Aura de curación
        if self.anim_effect == "heal":
            c.create_oval(cx - 58, cy - 68, cx + 58, cy + 62, outline=ACCENT_GREEN, width=3, dash=(6, 4))

        # Capa
        c.create_polygon(cx - 28, cy - 10, cx - 50, cy + 48, cx - 10, cy + 44, fill=cape_col, outline="")

        # Piernas
        c.create_rectangle(cx - 18, cy + 28, cx - 4, cy + 56, fill="#1E293B", outline="#64748B")
        c.create_rectangle(cx + 4, cy + 28, cx + 18, cy + 56, fill="#1E293B", outline="#64748B")

        # Armadura / Torso
        c.create_rectangle(cx - 24, cy - 14, cx + 24, cy + 30, fill=body_col, outline="#93C5FD", width=2)
        c.create_line(cx, cy - 12, cx, cy + 28, fill="#DBEAFE", width=2)

        # Casco / Cabeza
        c.create_oval(cx - 20, cy - 52, cx + 20, cy - 12, fill="#CBD5E1", outline="#64748B", width=2)
        # Visor
        c.create_rectangle(cx - 10, cy - 36, cx + 16, cy - 26, fill="#0F172A", outline="")
        # Ojos
        if not dead:
            c.create_oval(cx - 4, cy - 34, cx + 1, cy - 29, fill=ACCENT_BLUE, outline="")
            c.create_oval(cx + 6, cy - 34, cx + 11, cy - 29, fill=ACCENT_BLUE, outline="")
        # Penacho rojo del casco
        c.create_polygon(cx - 6, cy - 52, cx + 4, cy - 70, cx + 12, cy - 52, fill=ACCENT_RED, outline="")

        # Escudo en brazo izquierdo
        c.create_polygon(
            cx - 38, cy - 6,
            cx - 18, cy - 6,
            cx - 18, cy + 16,
            cx - 28, cy + 28,
            cx - 38, cy + 16,
            fill="#0EA5E9",
            outline="#E0F2FE",
            width=2,
        )

        # Espada en mano derecha
        sword_dx = 16 if self.anim_effect in ("attack", "crit") else 0
        c.create_rectangle(cx + 24 + sword_dx, cy + 4, cx + 38 + sword_dx, cy + 12, fill="#F59E0B", outline="")
        c.create_polygon(
            cx + 36 + sword_dx, cy + 10,
            cx + 76 + sword_dx, cy - 28,
            cx + 82 + sword_dx, cy - 32,
            cx + 70 + sword_dx, cy - 18,
            cx + 32 + sword_dx, cy + 4,
            fill="#E2E8F0",
            outline="#94A3B8",
            width=1,
        )

    def _draw_monster(self, c: tk.Canvas, cx: int, cy: int) -> None:
        dead = self.state.hp_monster <= 0
        enraged = bool(self.state.flags & 1)
        shielded = bool(self.state.flags & 2)

        body_col = "#334155" if dead else ("#DC2626" if enraged else "#991B1B")
        belly_col = "#475569" if dead else "#F59E0B"

        # Sombra
        c.create_oval(cx - 56, cy + 52, cx + 56, cy + 70, fill="#060913", outline="")

        # Aura de Furia
        if enraged and not dead:
            c.create_oval(cx - 68, cy - 72, cx + 68, cy + 64, outline=ACCENT_RED, width=2, dash=(4, 4))

        # Alas de dragón
        c.create_polygon(cx + 10, cy - 10, cx + 72, cy - 58, cx + 58, cy + 18, fill="#7F1D1D", outline="#EF4444")
        c.create_polygon(cx - 10, cy - 10, cx - 64, cy - 54, cx - 50, cy + 14, fill="#7F1D1D", outline="#EF4444")

        # Cuerpo
        c.create_oval(cx - 38, cy - 24, cx + 38, cy + 46, fill=body_col, outline="#FCA5A5", width=2)
        c.create_oval(cx - 22, cy - 4, cx + 22, cy + 38, fill=belly_col, outline="")

        # Cabeza + Cuernos
        c.create_oval(cx - 32, cy - 58, cx + 24, cy - 10, fill=body_col, outline="#FCA5A5", width=2)
        c.create_polygon(cx - 18, cy - 54, cx - 32, cy - 80, cx - 6, cy - 58, fill="#E2E8F0", outline="")
        c.create_polygon(cx + 6, cy - 54, cx + 24, cy - 80, cx + 18, cy - 50, fill="#E2E8F0", outline="")

        # Ojos
        if dead:
            c.create_text(cx - 14, cy - 36, text="X", fill="white", font=("Consolas", 13, "bold"))
            c.create_text(cx + 2, cy - 36, text="X", fill="white", font=("Consolas", 13, "bold"))
        else:
            eye_col = ACCENT_YELLOW if enraged else "#FDE047"
            c.create_oval(cx - 20, cy - 42, cx - 8, cy - 30, fill=eye_col, outline="#450A0A")
            c.create_oval(cx - 2, cy - 42, cx + 10, cy - 30, fill=eye_col, outline="#450A0A")

        # Colmillos
        c.create_polygon(cx - 18, cy - 16, cx - 13, cy - 6, cx - 8, cy - 16, fill="white", outline="")
        c.create_polygon(cx - 2, cy - 16, cx + 3, cy - 6, cx + 8, cy - 16, fill="white", outline="")

        # Burbuja de Escudo activo
        if shielded and not dead:
            c.create_oval(cx - 60, cy - 64, cx + 56, cy + 56, outline=ACCENT_BLUE, width=3)
            c.create_text(
                cx, cy - 88, text=f"🛡️ ESCUDO (DEF={self.state.defense})",
                fill=ACCENT_BLUE, font=("Consolas", 9, "bold"),
            )
        elif enraged and not dead:
            c.create_text(cx, cy - 88, text="🔥 ¡EN FURIA!", fill=ACCENT_RED, font=("Consolas", 9, "bold"))

    def _draw_arena(self) -> None:
        c = self.canvas
        c.delete("all")
        w = max(620, c.winfo_width())
        h = max(360, c.winfo_height())

        # Fondo de mazmorra: cielo + pared de piedra + piso
        c.create_rectangle(0, 0, w, int(h * 0.68), fill="#0D1326", outline="")
        c.create_rectangle(0, int(h * 0.68), w, h, fill="#1A2238", outline="#334155", width=2)

        # Antorchas decorativas en la pared
        for tx in (int(w * 0.14), int(w * 0.86)):
            c.create_rectangle(tx - 4, int(h * 0.28), tx + 4, int(h * 0.40), fill="#78350F", outline="")
            c.create_oval(tx - 10, int(h * 0.21), tx + 10, int(h * 0.30), fill="#F97316", outline="#FACC15", width=2)

        # Encabezado superior del tablero (Turno + Score)
        c.create_text(
            w // 2, 22,
            text=f"TURNO {self.state.turn}   |   SCORE: {self.state.score} pts",
            fill=FG_TEXT, font=("Segoe UI", 12, "bold"),
        )

        # Posiciones de Héroe y Monstruo
        hx, hy = int(w * 0.24), int(h * 0.56)
        mx, my = int(w * 0.76), int(h * 0.56)

        self._draw_hero(c, hx, hy)
        self._draw_monster(c, mx, my)

        # Efecto visual de ataque / crítico del Héroe
        if self.anim_effect in ("attack", "crit"):
            col = ACCENT_YELLOW if self.anim_effect == "crit" else ACCENT_ORANGE
            c.create_line(hx + 75, hy - 18, mx - 45, my - 10, fill=col, width=5, arrow=tk.LAST)
            c.create_text(
                mx, my - 10,
                text=f"-{self.state.last_dmg}",
                fill=col,
                font=("Segoe UI", 22, "bold"),
            )
        # Efecto visual de curación del Héroe
        elif self.anim_effect == "heal":
            c.create_text(
                hx, hy - 82,
                text="+10 HP  +6 EN",
                fill=ACCENT_GREEN,
                font=("Segoe UI", 13, "bold"),
            )
        # Efecto visual del contraataque del Dragón (llamarada hacia el Héroe)
        elif self.anim_effect == "dragon_attack":
            # Destello rojo de impacto alrededor del Héroe
            c.create_oval(hx - 56, hy - 66, hx + 56, hy + 60, outline=ACCENT_RED, width=4)
            # Llamarada desde la boca del Dragón hacia el Héroe
            c.create_line(mx - 36, my - 22, hx + 36, hy - 10, fill=ACCENT_RED, width=10, arrow=tk.LAST)
            c.create_line(mx - 36, my - 22, hx + 36, hy - 10, fill=ACCENT_ORANGE, width=5)
            c.create_line(mx - 36, my - 22, hx + 36, hy - 10, fill=ACCENT_YELLOW, width=2)
            # Bola de fuego en el punto de impacto
            c.create_oval(hx + 14, hy - 28, hx + 52, hy + 10, fill=ACCENT_ORANGE, outline=ACCENT_YELLOW, width=3)
            c.create_text(
                hx, hy - 84,
                text=f"-{self.state.last_counter} HP",
                fill=ACCENT_RED,
                font=("Segoe UI", 22, "bold"),
            )

        # Dado central
        dx, dy = w // 2, int(h * 0.44)
        c.create_rectangle(dx - 28, dy - 28, dx + 28, dy + 28, fill=BG_CARD, outline=ACCENT_BLUE, width=2)
        c.create_text(dx, dy - 38, text="DADO PRNG", fill=FG_MUTED, font=("Consolas", 8, "bold"))
        dice_txt = str(self.state.last_dice) if self.state.last_dice > 0 else "?"
        c.create_text(dx, dy, text=dice_txt, fill=ACCENT_YELLOW, font=("Segoe UI", 20, "bold"))

        # Barras de stats del Héroe
        bar_w = 175
        self._draw_bar(
            c, hx - bar_w // 2, int(h * 0.76), bar_w, 20,
            self.state.hp_hero, self.state.max_hp_hero,
            ACCENT_GREEN if self.state.hp_hero > 10 else ACCENT_RED,
            f"HP HÉROE: {self.state.hp_hero}/{self.state.max_hp_hero}",
        )
        self._draw_bar(
            c, hx - bar_w // 2, int(h * 0.84), bar_w, 18,
            self.state.energy, self.state.max_energy,
            ACCENT_BLUE,
            f"ENERGÍA: {self.state.energy}/{self.state.max_energy}",
        )

        # Barras de stats del Monstruo
        self._draw_bar(
            c, mx - bar_w // 2, int(h * 0.76), bar_w, 20,
            self.state.hp_monster, self.state.max_hp_monster,
            ACCENT_RED,
            f"HP DRAGÓN: {self.state.hp_monster}/{self.state.max_hp_monster}",
        )
        c.create_text(
            mx, int(h * 0.87),
            text=f"DEF: {self.state.defense}  |  FLAGS: 0x{self.state.flags:02X}",
            fill=FG_MUTED, font=("Consolas", 9, "bold"),
        )

        # Banner inferior con mensaje del turno
        c.create_rectangle(14, h - 34, w - 14, h - 8, fill="#111827", outline="#334155")
        c.create_text(
            w // 2, h - 21,
            text=self.anim_banner,
            fill=self.anim_banner_color,
            font=("Segoe UI", 10, "bold"),
        )

    def _update_inspector(self) -> None:
        src = f"FPGA ({self.client.port_name})" if self.use_fpga else "Simulador RV32I Local"
        self.hw_info_lbl.config(
            text=f"Backend : {src}\n"
                 f"Programa: {self.state.last_asm_words} inst. RV32I (32/32 ops)\n"
                 f"Estado  : {'VICTORIA' if self.state.result == RESULT_VICTORY else ('DERROTA' if self.state.result == RESULT_DEFEAT else 'EN COMBATE')}"
        )

        d = self.state.last_dmem
        dmem_str = (
            f"DMEM[0] 0x00: 0x{d[0]:08X}\n"
            f"  HP={self.state.hp_hero} EN={self.state.energy} SC={self.state.score}\n"
            f"DMEM[1] 0x04: 0x{d[1]:08X}\n"
            f"  HP_M={self.state.hp_monster} DEF={self.state.defense} FL=0x{self.state.flags:02X}\n"
            f"DMEM[2] 0x08: 0x{d[2]:08X} (PRNG)\n"
            f"DMEM[3] 0x0C: 0x{d[3]:08X} (FIN)\n"
            f"DMEM[4] 0x10: 0x{d[4]:08X} (LOG)\n"
            f"DMEM[5] 0x14: 0x{d[5]:08X} (EVT)\n"
        )
        self.dmem_text.config(state=tk.NORMAL)
        self.dmem_text.delete("1.0", tk.END)
        self.dmem_text.insert("1.0", dmem_str)
        self.dmem_text.config(state=tk.DISABLED)

        r = self.state.last_regs
        regs_str = (
            f"x1  (ra) = 0x{r[1]:08X}\n"
            f"x9  (s1) = 0x{r[9]:08X} (turno)\n"
            f"x10 (a0) = 0x{r[10]:08X} ({to_signed32(r[10])})\n"
            f"x14 (a4) = 0x{r[14]:08X} (daño)\n"
            f"x18 (s2) = 0x{r[18]:08X} (acción)\n"
            f"x28 (t3) = 0x{r[28]:08X} (HP_M)\n"
            f"x30 (t5) = 0x{r[30]:08X} (score)\n"
            f"x31 (t6) = 0x{r[31]:08X} (firma)\n"
        )
        self.regs_text.config(state=tk.NORMAL)
        self.regs_text.delete("1.0", tk.END)
        self.regs_text.insert("1.0", regs_str)
        self.regs_text.config(state=tk.DISABLED)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Mini-Juego RPG Interactivo ejecutado en el procesador RISC-V (FPGA o Simulador)."
    )
    parser.add_argument("-p", "--port", default=None, help="Puerto COM de la FPGA (opcional).")
    args = parser.parse_args()

    root = tk.Tk()
    DungeonRPGApp(root, initial_port=args.port)
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
