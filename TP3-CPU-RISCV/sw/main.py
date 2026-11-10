#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Punto de Entrada Principal del Software de Control y Depuración (PC <-> FPGA).

Modos de ejecución:
  1. Interfaz Gráfica de Escritorio (por defecto):
       python sw/main.py
       python sw/main.py --gui --port COM3

  2. Consola Interactiva de Línea de Comandos (CLI):
       python sw/main.py --cli
       python sw/main.py --cli --port COM3 --verbose

  3. Ensamblador / Traductor de Assembly a Código Máquina independiente:
       python sw/main.py --asm sw/programas/demo_1_riesgos_y_saltos.asm
       python sw/main.py --asm sw/programas/demo_1_riesgos_y_saltos.asm -o salida.hex
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from .assembler import assemble_file, format_translation_table
    from .cli import DebugUnitCLI
    from .gui import launch_gui
    from .protocol import DEFAULT_BAUDRATE
except ImportError:
    from assembler import assemble_file, format_translation_table
    from cli import DebugUnitCLI
    from gui import launch_gui
    from protocol import DEFAULT_BAUDRATE


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Interfaz PC (GUI / CLI / Ensamblador RV32I) para la Debug Unit del Procesador RISC-V."
    )
    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument(
        "--gui",
        action="store_true",
        help="Inicia la interfaz gráfica de escritorio (modo por defecto).",
    )
    mode_group.add_argument(
        "--cli",
        action="store_true",
        help="Inicia la consola interactiva de línea de comandos en la terminal.",
    )
    mode_group.add_argument(
        "--asm",
        metavar="ARCHIVO_ASM",
        help="Traduce un archivo .asm a lenguaje máquina de 32 bits y muestra la tabla detallada.",
    )

    parser.add_argument(
        "-p",
        "--port",
        default=None,
        help="Puerto serie a conectar al iniciar (ej. COM3 o /dev/ttyUSB0).",
    )
    parser.add_argument(
        "-b",
        "--baud",
        type=int,
        default=DEFAULT_BAUDRATE,
        help=f"Velocidad en baudios UART (por defecto: {DEFAULT_BAUDRATE}).",
    )
    parser.add_argument(
        "-o",
        "--output",
        default=None,
        help="Archivo .hex de salida cuando se utiliza --asm.",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Muestra las tramas binarias UART TX/RX en la consola CLI.",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    # Modo 1: Traductor directo de Ensamblador a Lenguaje Máquina
    if args.asm:
        path = Path(args.asm)
        if not path.exists():
            alt = Path(__file__).resolve().parent / "programas" / args.asm
            if alt.exists():
                path = alt
        try:
            program, labels = assemble_file(path)
        except Exception as exc:
            print(f"[ERROR] {exc}", file=sys.stderr)
            return 1

        print(format_translation_table(program, labels))
        if args.output:
            out_path = Path(args.output)
            hex_lines = [f"{inst.word:08x}" for inst in program]
            out_path.write_text("\n".join(hex_lines) + "\n", encoding="utf-8")
            print(f"\n[OK] Código máquina guardado en '{out_path}' ({len(program)} palabras de 32 bits).")
        return 0

    # Modo 2: Consola Interactiva (CLI)
    if args.cli:
        cli = DebugUnitCLI(port=args.port, baudrate=args.baud, verbose_uart=args.verbose)
        cli.run_interactive()
        return 0

    # Modo 3 (por defecto): Interfaz Gráfica de Escritorio (GUI)
    launch_gui(port=args.port)
    return 0


if __name__ == "__main__":
    sys.exit(main())
