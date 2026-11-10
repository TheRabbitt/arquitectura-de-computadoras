#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Interfaz de Consola Interactiva (CLI) para la Debug Unit del Procesador RISC-V.

Permite operar íntegramente el procesador desde la terminal:
- Traducir programas en ensamblador (.asm) a código máquina de 32 bits.
- Programar y reprogramar dinámicamente la memoria de instrucciones por UART.
- Ejecutar en Modo Continuo (RUN = 0x10) mostrando al finalizar los 32 registros,
  los 4 latches intermedios y la memoria de datos usada (con pipeline vacío).
- Ejecutar en Modo Paso a Paso (STEP = 0x11) mostrando en cada ciclo de reloj
  todos los valores indicados por la consigna.
"""

from __future__ import annotations

import os
import shlex
import sys
from pathlib import Path
from typing import List, Optional, Sequence

try:
    from .assembler import (
        ABI_NAMES_BY_IDX,
        AssembledInstruction,
        AssemblerError,
        assemble_file,
        disassemble_word,
        format_translation_table,
    )
    from .protocol import (
        DEFAULT_BAUDRATE,
        RSP_HALTED,
        DebugUnitClient,
        DmemEntry,
        LatchesSnapshot,
        ProcessorSnapshot,
        ProtocolError,
        list_serial_ports,
        to_signed32,
    )
except ImportError:
    from assembler import (
        ABI_NAMES_BY_IDX,
        AssembledInstruction,
        AssemblerError,
        assemble_file,
        disassemble_word,
        format_translation_table,
    )
    from protocol import (
        DEFAULT_BAUDRATE,
        RSP_HALTED,
        DebugUnitClient,
        DmemEntry,
        LatchesSnapshot,
        ProcessorSnapshot,
        ProtocolError,
        list_serial_ports,
        to_signed32,
    )


def _enable_windows_ansi() -> None:
    """Habilita secuencias ANSI en terminales de Windows 10/11."""
    if os.name == "nt":
        os.system("")


# ==============================================================================
# Formateadores de Tablas para Consola (Registros, Latches y Memoria de Datos)
# ==============================================================================
def format_latches_table(latches: LatchesSnapshot) -> str:
    """Formatea los 4 latches intermedios (IF/ID, ID/EX, EX/MEM, MEM/WB) para pantalla."""
    lines: List[str] = []
    sep = "=" * 100
    sub = "-" * 100

    if_id = latches.if_id
    id_ex = latches.id_ex
    ex_mem = latches.ex_mem
    mem_wb = latches.mem_wb

    lines.append(sep)
    empty_tag = "SÍ (4 latches en valid=0)" if latches.pipeline_empty else "NO (instrucciones en vuelo)"
    lines.append(f" LATCHES INTERMEDIOS DEL PIPELINE  |  Pipeline vacío: {empty_tag}")
    lines.append(sep)

    # 1. IF/ID
    st_ifid = "VALID (1)" if if_id.valid else "VACÍO (0)"
    lines.append(
        f" [1] IF/ID   | Estado: {st_ifid:<10} | PC: 0x{if_id.pc:08X} | PC+4: 0x{if_id.pc_plus_4:08X}"
    )
    lines.append(
        f"             | Inst  : 0x{if_id.instruction:08X} -> {if_id.disasm}"
    )
    lines.append(sub)

    # 2. ID/EX
    st_idex = "VALID (1)" if id_ex.valid else "VACÍO (0)"
    lines.append(
        f" [2] ID/EX   | Estado: {st_idex:<10} | PC: 0x{id_ex.pc:08X} | PC+4: 0x{id_ex.pc_plus_4:08X}"
    )
    lines.append(
        f"             | Datos : rs1_data=0x{id_ex.rs1_data:08X} ({to_signed32(id_ex.rs1_data)}) | "
        f"rs2_data=0x{id_ex.rs2_data:08X} ({to_signed32(id_ex.rs2_data)}) | "
        f"Imm=0x{id_ex.imm:08X} ({to_signed32(id_ex.imm)})"
    )
    lines.append(
        f"             | Índices: rs1={id_ex.rs1_name} | rs2={id_ex.rs2_name} | rd={id_ex.rd_name} | "
        f"funct3=0x{id_ex.funct3:X} | funct7[5]={id_ex.funct7_5}"
    )
    lines.append(
        f"             | Control: {id_ex.active_controls_str()}"
    )
    lines.append(sub)

    # 3. EX/MEM
    st_exmem = "VALID (1)" if ex_mem.valid else "VACÍO (0)"
    lines.append(
        f" [3] EX/MEM  | Estado: {st_exmem:<10} | ALUResult: 0x{ex_mem.alu_result:08X} ({to_signed32(ex_mem.alu_result)}) | "
        f"WriteData(rs2): 0x{ex_mem.rs2_data:08X}"
    )
    lines.append(
        f"             | Destino: rd={ex_mem.rd_name:<9} | funct3=0x{ex_mem.funct3:X} | PC+4: 0x{ex_mem.pc_plus_4:08X} | "
        f"Control: {ex_mem.active_controls_str()}"
    )
    lines.append(sub)

    # 4. MEM/WB
    st_memwb = "VALID (1)" if mem_wb.valid else "VACÍO (0)"
    lines.append(
        f" [4] MEM/WB  | Estado: {st_memwb:<10} | ReadData : 0x{mem_wb.read_data:08X} ({to_signed32(mem_wb.read_data)}) | "
        f"ALUResult: 0x{mem_wb.alu_result:08X} ({to_signed32(mem_wb.alu_result)})"
    )
    lines.append(
        f"             | Destino: rd={mem_wb.rd_name:<9} | Fuente WB: {mem_wb.wb_source_str}=0x{mem_wb.wb_value:08X} | "
        f"Control: {mem_wb.active_controls_str()}"
    )
    lines.append(sep)
    return "\n".join(lines)


def format_registers_table(
    regs: Sequence[int],
    prev_regs: Optional[Sequence[int]] = None,
) -> str:
    """
    Formatea los 32 registros (x0..x31) en una tabla de 4 columnas.
    Marca con '*' aquellos registros que cambiaron respecto al paso previo.
    """
    lines: List[str] = []
    sep = "=" * 100
    lines.append(sep)
    lines.append(" BANCO DE 32 REGISTROS (x0 .. x31)  [* indica registro modificado en el último paso]")
    lines.append(sep)

    for row in range(8):
        cols: List[str] = []
        for col in range(4):
            idx = row + col * 8
            val = regs[idx] & 0xFFFFFFFF
            sval = to_signed32(val)
            abi = ABI_NAMES_BY_IDX[idx]
            changed = prev_regs is not None and (prev_regs[idx] & 0xFFFFFFFF) != val
            mark = "*" if changed else " "
            reg_label = f"x{idx:<2}({abi:<4})"
            cols.append(f"{mark}{reg_label}: 0x{val:08X} ({sval:>6})")
        lines.append(" | ".join(cols))
    lines.append(sep)
    return "\n".join(lines)


def format_dmem_table(entries: Sequence[DmemEntry], title: str = "MEMORIA DE DATOS USADA (DUMP_DMEM_USED)") -> str:
    """Formatea las entradas de la Memoria de Datos."""
    lines: List[str] = []
    sep = "=" * 100
    lines.append(sep)
    lines.append(f" {title}  (Total: {len(entries)} palabra(s) de 32 bits)")
    lines.append(sep)
    if not entries:
        lines.append("  (Sin posiciones de memoria de datos escritas hasta el momento)")
    else:
        lines.append(
            f" {'Palabra':<10} | {'Dir. Byte':<12} | {'Valor Hex (32b)':<16} | {'Bytes (LE)':<14} | {'Valor Decimal (con signo)'}"
        )
        lines.append("-" * 100)
        for e in entries:
            lines.append(
                f" Word[{e.word_addr:<4}] | 0x{e.byte_addr:08X}   | 0x{e.data:08X}       | "
                f"{e.bytes_le_str:<14} | {e.signed_data}"
            )
    lines.append(sep)
    return "\n".join(lines)


def format_full_snapshot(
    snap: ProcessorSnapshot,
    prev_regs: Optional[Sequence[int]] = None,
    step_num: Optional[int] = None,
    mode_label: str = "",
) -> str:
    """Genera el reporte completo de estado exigido por la consigna."""
    lines: List[str] = []
    sep = "#" * 100
    lines.append(sep)
    header = " ESTADO DEL PROCESADOR RISC-V (5 ETAPAS)"
    if mode_label:
        header += f"  —  {mode_label}"
    if step_num is not None:
        header += f"  [Ciclo #{step_num}]"
    lines.append(header)
    lines.append(
        f" PC Actual: 0x{snap.pc:08X}  |  STATUS: {snap.status.summary_str()}  |  "
        f"Pipeline Vacío: {'SÍ' if snap.latches.pipeline_empty else 'NO'}"
    )
    lines.append(sep)
    lines.append(format_latches_table(snap.latches))
    lines.append(format_registers_table(snap.regs, prev_regs=prev_regs))
    lines.append(format_dmem_table(snap.dmem_used))
    return "\n".join(lines)


# ==============================================================================
# Consola Interactiva (CLI)
# ==============================================================================
class DebugUnitCLI:
    """Consola interactiva de línea de comandos para controlar la Debug Unit."""

    def __init__(
        self,
        port: Optional[str] = None,
        baudrate: int = DEFAULT_BAUDRATE,
        verbose_uart: bool = False,
    ):
        _enable_windows_ansi()
        self.verbose_uart = verbose_uart
        self.client = DebugUnitClient(
            baudrate=baudrate,
            log_callback=self._on_uart_log,
        )
        self.prev_regs: Optional[List[int]] = None
        self.step_count: int = 0
        self.current_program: List[AssembledInstruction] = []

        if port:
            try:
                self.client.connect(port, baudrate)
                print(f"[OK] Conectado a {port} @ {baudrate} baudios.")
            except ProtocolError as exc:
                print(f"[AVISO] {exc}")

    def _on_uart_log(self, direction: str, message: str) -> None:
        if self.verbose_uart or direction == "INFO":
            print(f"  [UART {direction}] {message}")

    def print_banner(self) -> None:
        print("=" * 100)
        print("  CONSOLA DE DEPURACIÓN Y PROGRAMACIÓN UART — PROCESADOR RISC-V 5 ETAPAS (RV32I)")
        print("  Escriba 'help' para ver la lista de comandos o 'exit' para salir.")
        print("=" * 100)

    def print_help(self) -> None:
        print(
            """
Comandos disponibles:
  ports                        Lista los puertos serie (COM / ttyUSB) detectados en la PC.
  connect <COMx> [baud]        Abre la conexión serie con la FPGA (por defecto 115200 8N1).
  disconnect                   Cierra la conexión serie actual.
  verbose [on|off]             Activa o desactiva la traza detallada de bytes UART TX/RX.

  asm <archivo.asm|.hex>       Ensambla el archivo y muestra la tabla de traducción a código máquina.
  load <archivo.asm|.hex>      Ensambla y programa/reprograma el procesador por UART (0x02 LOAD_PROG).
  reset                        Reinicia el procesador y limpia registros/latches/memoria (0x01 RESET).

  run                          MODO CONTINUO (0x10 RUN): ejecuta hasta el final del programa (ebreak)
                               con el pipeline vacío y muestra registros, latches y memoria usada.
  step [N]                     MODO PASO A PASO (0x11 STEP): avanza 1 ciclo de clock (o N ciclos)
                               mostrando en cada paso registros, latches intermedios y memoria usada.

  state                        Consulta y muestra el estado completo actual (PC, latches, regs, DMEM).
  regs                         Muestra los 32 registros (0x20 DUMP_REGS).
  latches                      Muestra los 4 latches intermedios (0x21 DUMP_LATCHES).
  dmem [offset count]          Sin argumentos muestra la memoria de datos usada (0x25 DUMP_DMEM_USED);
                               con 'offset count' lee ese rango de palabras (0x22 DUMP_DMEM).
  help                         Muestra esta ayuda.
  exit / quit                  Cierra la consola.
""".strip()
        )

    # ------------------------------------------------------------------
    # Acciones principales
    # ------------------------------------------------------------------
    def cmd_ports(self) -> None:
        ports = list_serial_ports()
        if not ports:
            print("  No se detectaron puertos serie activos en el sistema.")
            return
        print("  Puertos serie detectados:")
        for dev, desc in ports:
            print(f"    - {desc}")

    def cmd_assemble(self, filepath: str) -> Optional[List[AssembledInstruction]]:
        path = Path(filepath)
        if not path.exists():
            # Buscar también relativo a sw/programas/
            alt = Path(__file__).resolve().parent / "programas" / filepath
            if alt.exists():
                path = alt
        try:
            program, labels = assemble_file(path)
            print(f"\n[ENSAMBLADOR RV32I] Archivo '{path.name}' traducido correctamente:")
            print(format_translation_table(program, labels))
            self.current_program = program
            return program
        except Exception as exc:
            print(f"[ERROR DE ENSAMBLADO] {exc}")
            return None

    def cmd_load(self, filepath: str) -> None:
        program = self.cmd_assemble(filepath)
        if not program:
            return
        words = [inst.word for inst in program]
        self.client.load_program(words)
        self.step_count = 0
        self.prev_regs = None
        snap = self.client.read_full_snapshot()
        self.prev_regs = list(snap.regs)
        print(
            format_full_snapshot(
                snap,
                prev_regs=None,
                step_num=0,
                mode_label=f"PROGRAMA CARGADO ({len(words)} instrucciones)",
            )
        )

    def cmd_reset(self) -> None:
        self.client.reset()
        self.step_count = 0
        self.prev_regs = None
        snap = self.client.read_full_snapshot()
        self.prev_regs = list(snap.regs)
        print(format_full_snapshot(snap, prev_regs=None, step_num=0, mode_label="RESET COMPLETADO"))

    def cmd_run(self) -> None:
        print("  Enviando comando RUN (0x10) y aguardando fin de programa + vaciado del pipeline (0xF1)...")
        self.client.run(run_timeout=15.0)
        snap = self.client.read_full_snapshot()
        print(
            format_full_snapshot(
                snap,
                prev_regs=self.prev_regs,
                step_num=None,
                mode_label="MODO CONTINUO FINALIZADO (HALTED 0xF1 - PIPELINE VACÍO)",
            )
        )
        self.prev_regs = list(snap.regs)

    def cmd_step(self, count: int = 1) -> None:
        for _ in range(max(1, count)):
            rsp = self.client.step()
            self.step_count += 1
            snap = self.client.read_full_snapshot()
            tag = (
                "MODO PASO A PASO (HALTED 0xF1 - FIN DE PROGRAMA Y PIPELINE VACÍO)"
                if rsp == RSP_HALTED
                else "MODO PASO A PASO (1 CICLO DE RELOJ EJECUTADO)"
            )
            print(
                format_full_snapshot(
                    snap,
                    prev_regs=self.prev_regs,
                    step_num=self.step_count,
                    mode_label=tag,
                )
            )
            self.prev_regs = list(snap.regs)
            if rsp == RSP_HALTED:
                print("  [INFO] El procesador alcanzó el final del programa y el pipeline está vacío.")
                break

    def cmd_state(self) -> None:
        snap = self.client.read_full_snapshot()
        print(
            format_full_snapshot(
                snap,
                prev_regs=self.prev_regs,
                step_num=self.step_count,
                mode_label="CONSULTA DE ESTADO ACTUAL",
            )
        )
        self.prev_regs = list(snap.regs)

    def run_interactive(self) -> None:
        self.print_banner()
        while True:
            port_tag = self.client.port_name if self.client.is_connected else "sin-conexion"
            try:
                raw_line = input(f"\ndebug-riscv ({port_tag})> ").strip()
            except (EOFError, KeyboardInterrupt):
                print("\nSaliendo...")
                break

            if not raw_line:
                continue

            try:
                parts = shlex.split(raw_line)
            except ValueError as exc:
                print(f"[ERROR] {exc}")
                continue

            cmd = parts[0].lower()
            args = parts[1:]

            try:
                if cmd in ("exit", "quit", "q"):
                    break
                elif cmd in ("help", "?"):
                    self.print_help()
                elif cmd == "ports":
                    self.cmd_ports()
                elif cmd == "connect":
                    if not args:
                        print("Uso: connect <COMx> [baudrate]")
                        continue
                    baud = int(args[1]) if len(args) > 1 else self.client.baudrate
                    self.client.connect(args[0], baud)
                elif cmd == "disconnect":
                    self.client.disconnect()
                elif cmd == "verbose":
                    if args and args[0].lower() in ("on", "1", "true"):
                        self.verbose_uart = True
                    elif args and args[0].lower() in ("off", "0", "false"):
                        self.verbose_uart = False
                    else:
                        self.verbose_uart = not self.verbose_uart
                    print(f"  Traza UART detallada: {'ACTIVADA' if self.verbose_uart else 'DESACTIVADA'}")
                elif cmd == "asm":
                    if not args:
                        print("Uso: asm <archivo.asm>")
                        continue
                    self.cmd_assemble(args[0])
                elif cmd == "load":
                    if not args:
                        print("Uso: load <archivo.asm|.hex>")
                        continue
                    self.cmd_load(args[0])
                elif cmd == "reset":
                    self.cmd_reset()
                elif cmd == "run":
                    self.cmd_run()
                elif cmd in ("step", "s"):
                    n_steps = int(args[0]) if args else 1
                    self.cmd_step(n_steps)
                elif cmd in ("state", "status"):
                    self.cmd_state()
                elif cmd == "regs":
                    regs = self.client.dump_regs()
                    print(format_registers_table(regs, prev_regs=self.prev_regs))
                    self.prev_regs = list(regs)
                elif cmd == "latches":
                    latches = self.client.dump_latches()
                    print(format_latches_table(latches))
                elif cmd == "dmem":
                    if len(args) >= 2:
                        offset = int(args[0], 0)
                        count = int(args[1], 0)
                        entries = self.client.dump_dmem(offset, count)
                        print(
                            format_dmem_table(
                                entries,
                                title=f"MEMORIA DE DATOS (Rango Word[{offset}..{offset + count - 1}])",
                            )
                        )
                    else:
                        entries = self.client.dump_dmem_used()
                        print(format_dmem_table(entries))
                else:
                    print(f"Comando desconocido: '{cmd}'. Escriba 'help' para ver los comandos.")
            except (ProtocolError, AssemblerError, ValueError) as exc:
                print(f"[ERROR] {exc}")
        self.client.disconnect()
