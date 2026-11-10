#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Interfaz Gráfica de Escritorio (GUI) para la Debug Unit del Procesador RISC-V.

Desarrollada con `tkinter` / `ttk` (incluido en la biblioteca estándar de Python)
con tema oscuro profesional. Permite:
  1. Escribir o cargar programas en ensamblador RV32I (`.asm`) y traducirlos a
     lenguaje máquina de 32 bits visualizando cada campo binario y sus bytes UART.
  2. Programar y reprogramar dinámicamente la FPGA por UART (`0x02 LOAD_PROG`).
  3. Ejecutar en Modo Continuo (`0x10 RUN`) hasta fin de programa (`ebreak`) con
     el pipeline vacío (`0xF1 HALTED`) y mostrar automáticamente:
       - El contenido de los 32 registros (`x0..x31`).
       - El contenido de los 4 latches intermedios (`IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`).
       - El contenido de la memoria de datos usada (`DUMP_DMEM_USED`).
  4. Ejecutar en Modo Paso a Paso (`0x11 STEP`), avanzando 1 ciclo de clock por
     comando y actualizando en pantalla todos los valores indicados en cada paso.
"""

from __future__ import annotations

import queue
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from typing import Dict, List, Optional, Sequence, Tuple

try:
    from .assembler import (
        ABI_NAMES_BY_IDX,
        AssembledInstruction,
        AssemblerError,
        assemble_text,
        disassemble_word,
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
        assemble_text,
        disassemble_word,
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


# ==============================================================================
# Paleta de Colores (Dark Slate Theme)
# ==============================================================================
BG_MAIN       = "#0f172a"
BG_PANEL      = "#1e293b"
BG_CARD       = "#0b1120"
BG_INPUT      = "#090d16"
FG_TEXT       = "#f8fafc"
FG_MUTED      = "#94a3b8"
ACCENT_BLUE   = "#0284c7"
ACCENT_GREEN  = "#16a34a"
ACCENT_AMBER  = "#d97706"
ACCENT_PURPLE = "#7c3aed"
ACCENT_RED    = "#dc2626"
BORDER_COLOR  = "#334155"


class DebugUnitGUI:
    """Aplicación gráfica principal para controlar la Debug Unit del RISC-V."""

    def __init__(self, root: tk.Tk, initial_port: Optional[str] = None):
        self.root = root
        self.root.title("RISC-V 5-Stage Pipeline — Debug Unit & RV32I Assembler (UART 115200 8N1)")
        self.root.geometry("1520x920")
        self.root.minsize(1240, 760)
        self.root.configure(bg=BG_MAIN)

        self.log_queue: "queue.Queue[Tuple[str, str]]" = queue.Queue()
        self.client = DebugUnitClient(log_callback=self._enqueue_uart_log)

        self.assembled_program: List[AssembledInstruction] = []
        self.assembled_labels: Dict[str, int] = {}
        self.prev_regs: Optional[List[int]] = None
        self.step_count: int = 0
        self.is_busy: bool = False

        self.programas_dir = Path(__file__).resolve().parent / "programas"

        self._configure_styles()
        self._build_layout()
        self._populate_ports()
        self._populate_examples()
        self._init_empty_tables()

        if initial_port:
            self.port_var.set(initial_port)
            self._on_connect_toggle()

        self.root.after(80, self._poll_log_queue)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    # ------------------------------------------------------------------
    # Configuración de estilos TTK
    # ------------------------------------------------------------------
    def _configure_styles(self) -> None:
        style = ttk.Style(self.root)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass

        style.configure(".", background=BG_MAIN, foreground=FG_TEXT, font=("Segoe UI", 9))
        style.configure("TFrame", background=BG_MAIN)
        style.configure("Panel.TFrame", background=BG_PANEL)
        style.configure("Card.TFrame", background=BG_CARD)

        style.configure(
            "TLabelframe",
            background=BG_PANEL,
            foreground=FG_TEXT,
            bordercolor=BORDER_COLOR,
            relief="solid",
        )
        style.configure(
            "TLabelframe.Label",
            background=BG_PANEL,
            foreground="#38bdf8",
            font=("Segoe UI", 9, "bold"),
        )

        style.configure("TLabel", background=BG_PANEL, foreground=FG_TEXT)
        style.configure("Main.TLabel", background=BG_MAIN, foreground=FG_TEXT)
        style.configure("Muted.TLabel", background=BG_PANEL, foreground=FG_MUTED)

        style.configure(
            "Treeview",
            background=BG_INPUT,
            fieldbackground=BG_INPUT,
            foreground=FG_TEXT,
            rowheight=23,
            bordercolor=BORDER_COLOR,
            font=("Consolas", 9),
        )
        style.configure(
            "Treeview.Heading",
            background="#1e293b",
            foreground="#e2e8f0",
            font=("Segoe UI", 9, "bold"),
            relief="flat",
        )
        style.map(
            "Treeview",
            background=[("selected", "#1d4ed8")],
            foreground=[("selected", "#ffffff")],
        )

        style.configure(
            "TCombobox",
            fieldbackground=BG_INPUT,
            background=BG_PANEL,
            foreground=FG_TEXT,
            arrowcolor=FG_TEXT,
        )

    # ------------------------------------------------------------------
    # Construcción de la Interfaz
    # ------------------------------------------------------------------
    def _build_layout(self) -> None:
        # 1. Barra Superior de Conexión y Comandos UART
        self._build_top_toolbar()

        # 2. Barra Visual de Estado y Tarjetas del Pipeline (IF/ID, ID/EX, EX/MEM, MEM/WB)
        self._build_pipeline_banner()

        # 3. Área Central Dividida: Izquierda (Ensamblador) | Derecha (Estado del Procesador)
        main_paned = tk.PanedWindow(
            self.root,
            orient=tk.HORIZONTAL,
            bg=BORDER_COLOR,
            sashwidth=5,
            bd=0,
        )
        main_paned.pack(fill=tk.BOTH, expand=True, padx=8, pady=(2, 4))

        left_frame = ttk.Frame(main_paned, style="Panel.TFrame")
        right_frame = ttk.Frame(main_paned, style="Panel.TFrame")
        main_paned.add(left_frame, width=620, minsize=460)
        main_paned.add(right_frame, width=880, minsize=560)

        self._build_left_assembler_pane(left_frame)
        self._build_right_inspector_pane(right_frame)

        # 4. Consola Inferior de Tramas UART (TX / RX)
        self._build_bottom_uart_log()

    def _make_btn(
        self,
        parent: tk.Widget,
        text: str,
        command,
        bg: str = ACCENT_BLUE,
        fg: str = "#ffffff",
        width: Optional[int] = None,
    ) -> tk.Button:
        btn = tk.Button(
            parent,
            text=text,
            command=command,
            bg=bg,
            fg=fg,
            activebackground=bg,
            activeforeground=fg,
            relief=tk.FLAT,
             bd=0,
            padx=10,
            pady=5,
            cursor="hand2",
            font=("Segoe UI", 9, "bold"),
        )
        if width:
            btn.configure(width=width)
        return btn

    def _build_top_toolbar(self) -> None:
        bar = tk.Frame(self.root, bg=BG_PANEL, highlightthickness=1, highlightbackground=BORDER_COLOR)
        bar.pack(fill=tk.X, padx=8, pady=(8, 4))

        # --- Bloque Puerto Serie ---
        conn_frame = tk.Frame(bar, bg=BG_PANEL)
        conn_frame.pack(side=tk.LEFT, padx=8, pady=6)

        tk.Label(
            conn_frame, text="Puerto UART:", bg=BG_PANEL, fg=FG_TEXT, font=("Segoe UI", 9, "bold")
        ).pack(side=tk.LEFT, padx=(0, 4))

        self.port_var = tk.StringVar(value="COM3")
        self.port_combo = ttk.Combobox(conn_frame, textvariable=self.port_var, width=14)
        self.port_combo.pack(side=tk.LEFT, padx=2)

        self._make_btn(conn_frame, "↻", self._populate_ports, bg="#334155").pack(side=tk.LEFT, padx=2)

        tk.Label(conn_frame, text="Baud:", bg=BG_PANEL, fg=FG_MUTED, font=("Segoe UI", 9)).pack(
            side=tk.LEFT, padx=(6, 2)
        )
        self.baud_var = tk.StringVar(value=str(DEFAULT_BAUDRATE))
        baud_combo = ttk.Combobox(
            conn_frame,
            textvariable=self.baud_var,
            values=["115200", "57600", "38400", "9600"],
            width=8,
            state="readonly",
        )
        baud_combo.pack(side=tk.LEFT, padx=2)

        self.btn_connect = self._make_btn(
            conn_frame, "Conectar FPGA", self._on_connect_toggle, bg=ACCENT_BLUE
        )
        self.btn_connect.pack(side=tk.LEFT, padx=6)

        self.lbl_conn_badge = tk.Label(
            conn_frame,
            text=" DESCONECTADO ",
            bg="#7f1d1d",
            fg="#fecaca",
            font=("Consolas", 9, "bold"),
            padx=6,
            pady=3,
        )
        self.lbl_conn_badge.pack(side=tk.LEFT, padx=4)

        # Separador vertical
        tk.Frame(bar, bg=BORDER_COLOR, width=2, height=30).pack(side=tk.LEFT, padx=8, pady=4)

        # --- Bloque Comandos de Programación y Ejecución ---
        cmd_frame = tk.Frame(bar, bg=BG_PANEL)
        cmd_frame.pack(side=tk.LEFT, padx=4, pady=6)

        self.btn_translate = self._make_btn(
            cmd_frame,
            "⚙ Traducir ASM → Máquina",
            self._on_assemble_click,
            bg="#475569",
        )
        self.btn_translate.pack(side=tk.LEFT, padx=3)

        self.btn_load = self._make_btn(
            cmd_frame,
            "⬇ Programar FPGA (LOAD 0x02)",
            self._on_load_prog_click,
            bg=ACCENT_PURPLE,
        )
        self.btn_load.pack(side=tk.LEFT, padx=3)

        self.btn_run = self._make_btn(
            cmd_frame,
            "▶ Modo Continuo (RUN 0x10)",
            self._on_run_click,
            bg=ACCENT_GREEN,
        )
        self.btn_run.pack(side=tk.LEFT, padx=3)

        self.btn_step = self._make_btn(
            cmd_frame,
            "⏭ Paso a Paso (STEP 0x11)",
            self._on_step_click,
            bg=ACCENT_AMBER,
        )
        self.btn_step.pack(side=tk.LEFT, padx=3)

        tk.Label(cmd_frame, text="N:", bg=BG_PANEL, fg=FG_MUTED, font=("Segoe UI", 9)).pack(
            side=tk.LEFT, padx=(4, 2)
        )
        self.step_n_var = tk.StringVar(value="1")
        step_spin = tk.Spinbox(
            cmd_frame,
            from_=1,
            to=200,
            textvariable=self.step_n_var,
            width=4,
            bg=BG_INPUT,
            fg=FG_TEXT,
            insertbackground=FG_TEXT,
            relief=tk.FLAT,
            font=("Consolas", 9),
        )
        step_spin.pack(side=tk.LEFT, padx=(0, 6))

        self.btn_reset = self._make_btn(
            cmd_frame,
            "↺ Reset (0x01)",
            self._on_reset_click,
            bg=ACCENT_RED,
        )
        self.btn_reset.pack(side=tk.LEFT, padx=3)

        self.btn_refresh = self._make_btn(
            cmd_frame,
            "🔍 Leer Estado",
            self._on_read_state_click,
            bg="#0f766e",
        )
        self.btn_refresh.pack(side=tk.LEFT, padx=3)

    def _build_pipeline_banner(self) -> None:
        banner = tk.Frame(self.root, bg=BG_PANEL, highlightthickness=1, highlightbackground=BORDER_COLOR)
        banner.pack(fill=tk.X, padx=8, pady=(0, 4))

        # Fila superior: PC, Ciclo, Badges de STATUS y Pipeline Vacío
        top_row = tk.Frame(banner, bg=BG_PANEL)
        top_row.pack(fill=tk.X, padx=10, pady=(6, 4))

        self.lbl_pc = tk.Label(
            top_row,
            text="PC: 0x00000000",
            bg="#0f172a",
            fg="#38bdf8",
            font=("Consolas", 11, "bold"),
            padx=10,
            pady=3,
        )
        self.lbl_pc.pack(side=tk.LEFT, padx=(0, 8))

        self.lbl_step = tk.Label(
            top_row,
            text="Ciclos Ejecutados: 0",
            bg="#0f172a",
            fg="#e2e8f0",
            font=("Consolas", 10, "bold"),
            padx=10,
            pady=3,
        )
        self.lbl_step.pack(side=tk.LEFT, padx=(0, 12))

        self.badge_prog = self._create_status_badge(top_row, "PROG_LOADED: 0")
        self.badge_run = self._create_status_badge(top_row, "RUNNING: 0")
        self.badge_drain = self._create_status_badge(top_row, "DRAINING: 0")
        self.badge_halt = self._create_status_badge(top_row, "HALTED: 0")
        self.badge_empty = self._create_status_badge(top_row, "PIPELINE VACÍO: SÍ")

        # Fila inferior: 4 Tarjetas visuales de los Latches Intermedios
        cards_row = tk.Frame(banner, bg=BG_PANEL)
        cards_row.pack(fill=tk.X, padx=10, pady=(2, 8))

        self.stage_cards: Dict[str, Dict[str, tk.Label]] = {}
        stages = [
            ("IF/ID", "Etapa 1 → 2 (Fetch / Decode)"),
            ("ID/EX", "Etapa 2 → 3 (Decode / Execute)"),
            ("EX/MEM", "Etapa 3 → 4 (Execute / Memory)"),
            ("MEM/WB", "Etapa 4 → 5 (Memory / Writeback)"),
        ]
        for idx, (code, subtitle) in enumerate(stages):
            card = tk.Frame(
                cards_row,
                bg=BG_CARD,
                highlightthickness=1,
                highlightbackground=BORDER_COLOR,
                padx=8,
                pady=5,
            )
            card.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0 if idx == 0 else 6, 0))

            hdr = tk.Frame(card, bg=BG_CARD)
            hdr.pack(fill=tk.X)

            lbl_title = tk.Label(
                hdr,
                text=f"Latch {code}",
                bg=BG_CARD,
                fg="#38bdf8",
                font=("Segoe UI", 9, "bold"),
            )
            lbl_title.pack(side=tk.LEFT)

            lbl_valid = tk.Label(
                hdr,
                text="VACÍO (0)",
                bg="#334155",
                fg="#cbd5e1",
                font=("Consolas", 8, "bold"),
                padx=5,
                pady=1,
            )
            lbl_valid.pack(side=tk.RIGHT)

            lbl_sub = tk.Label(
                card,
                text=subtitle,
                bg=BG_CARD,
                fg=FG_MUTED,
                font=("Segoe UI", 8),
                anchor="w",
            )
            lbl_sub.pack(fill=tk.X)

            lbl_main = tk.Label(
                card,
                text="Sin instrucción válida (burbuja)",
                bg=BG_CARD,
                fg=FG_TEXT,
                font=("Consolas", 9, "bold"),
                anchor="w",
            )
            lbl_main.pack(fill=tk.X, pady=(2, 0))

            lbl_detail = tk.Label(
                card,
                text="PC: 0x00000000 | Control: Inactivo",
                bg=BG_CARD,
                fg=FG_MUTED,
                font=("Consolas", 8),
                anchor="w",
            )
            lbl_detail.pack(fill=tk.X)

            self.stage_cards[code] = {
                "frame": card,  # type: ignore[dict-item]
                "valid": lbl_valid,
                "main": lbl_main,
                "detail": lbl_detail,
            }

    def _create_status_badge(self, parent: tk.Widget, text: str) -> tk.Label:
        lbl = tk.Label(
            parent,
            text=f" {text} ",
            bg="#334155",
            fg="#cbd5e1",
            font=("Consolas", 9, "bold"),
            padx=6,
            pady=3,
        )
        lbl.pack(side=tk.LEFT, padx=3)
        return lbl

    def _build_left_assembler_pane(self, parent: ttk.Frame) -> None:
        v_paned = tk.PanedWindow(parent, orient=tk.VERTICAL, bg=BORDER_COLOR, sashwidth=5, bd=0)
        v_paned.pack(fill=tk.BOTH, expand=True)

        editor_box = ttk.LabelFrame(
            v_paned,
            text=" 1. Programa en Ensamblador RV32I (.asm / .hex) — Finalizar con 'ebreak' ",
        )
        table_box = ttk.LabelFrame(
            v_paned,
            text=" 2. Traducción a Lenguaje Máquina (32 bits / Bytes UART Little-Endian) ",
        )
        v_paned.add(editor_box, height=340, minsize=200)
        v_paned.add(table_box, height=280, minsize=180)

        # Barra de herramientas del editor
        ed_bar = tk.Frame(editor_box, bg=BG_PANEL)
        ed_bar.pack(fill=tk.X, padx=6, pady=4)

        tk.Label(
            ed_bar, text="Ejemplo:", bg=BG_PANEL, fg=FG_TEXT, font=("Segoe UI", 9, "bold")
        ).pack(side=tk.LEFT, padx=(0, 4))

        self.example_var = tk.StringVar()
        self.example_combo = ttk.Combobox(
            ed_bar, textvariable=self.example_var, width=32, state="readonly"
        )
        self.example_combo.pack(side=tk.LEFT, padx=2)
        self.example_combo.bind("<<ComboboxSelected>>", self._on_example_selected)

        self._make_btn(ed_bar, "📂 Abrir...", self._on_open_file, bg="#334155").pack(
            side=tk.LEFT, padx=4
        )
        self._make_btn(ed_bar, "💾 Guardar...", self._on_save_file, bg="#334155").pack(
            side=tk.LEFT, padx=2
        )

        # Editor de código fuente
        ed_container = tk.Frame(editor_box, bg=BG_INPUT)
        ed_container.pack(fill=tk.BOTH, expand=True, padx=6, pady=(0, 6))

        ed_scroll = ttk.Scrollbar(ed_container, orient=tk.VERTICAL)
        self.asm_text = tk.Text(
            ed_container,
            bg=BG_INPUT,
            fg="#e2e8f0",
            insertbackground="#38bdf8",
            selectbackground="#1d4ed8",
            font=("Consolas", 10),
            undo=True,
            wrap=tk.NONE,
            yscrollcommand=ed_scroll.set,
            padx=8,
            pady=6,
            relief=tk.FLAT,
        )
        ed_scroll.config(command=self.asm_text.yview)
        ed_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.asm_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        # Tabla de traducción a código máquina
        tbl_container = tk.Frame(table_box, bg=BG_PANEL)
        tbl_container.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        cols = ("pc", "hex", "bytes_le", "fmt", "binary", "asm")
        self.tree_mach = ttk.Treeview(tbl_container, columns=cols, show="headings", height=9)
        self.tree_mach.heading("pc", text="PC")
        self.tree_mach.heading("hex", text="Código Máquina")
        self.tree_mach.heading("bytes_le", text="Bytes UART (LE)")
        self.tree_mach.heading("fmt", text="Fmt")
        self.tree_mach.heading("binary", text="Campos Binarios (31..0)")
        self.tree_mach.heading("asm", text="Instrucción Ensamblador")

        self.tree_mach.column("pc", width=68, anchor="center", stretch=False)
        self.tree_mach.column("hex", width=105, anchor="center", stretch=False)
        self.tree_mach.column("bytes_le", width=115, anchor="center", stretch=False)
        self.tree_mach.column("fmt", width=45, anchor="center", stretch=False)
        self.tree_mach.column("binary", width=275, anchor="center", stretch=False)
        self.tree_mach.column("asm", width=220, anchor="w", stretch=True)

        self.tree_mach.tag_configure("active_pc", background="#1e3a8a", foreground="#ffffff")
        self.tree_mach.tag_configure("ebreak_row", foreground="#fcd34d")

        mach_scroll_y = ttk.Scrollbar(tbl_container, orient=tk.VERTICAL, command=self.tree_mach.yview)
        mach_scroll_x = ttk.Scrollbar(tbl_container, orient=tk.HORIZONTAL, command=self.tree_mach.xview)
        self.tree_mach.configure(yscrollcommand=mach_scroll_y.set, xscrollcommand=mach_scroll_x.set)

        mach_scroll_y.pack(side=tk.RIGHT, fill=tk.Y)
        mach_scroll_x.pack(side=tk.BOTTOM, fill=tk.X)
        self.tree_mach.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

    def _build_right_inspector_pane(self, parent: ttk.Frame) -> None:
        right_v_paned = tk.PanedWindow(parent, orient=tk.VERTICAL, bg=BORDER_COLOR, sashwidth=5, bd=0)
        right_v_paned.pack(fill=tk.BOTH, expand=True)

        # Arriba: Detalle de los 4 Latches Intermedios
        latches_box = ttk.LabelFrame(
            right_v_paned,
            text=" 3. Contenido de los Latches Intermedios (IF/ID, ID/EX, EX/MEM, MEM/WB — 0x21 DUMP_LATCHES) ",
        )
        # Abajo: Mitad izquierda 32 Registros | Mitad derecha Memoria de Datos Usada
        bottom_split = tk.PanedWindow(
            right_v_paned, orient=tk.HORIZONTAL, bg=BORDER_COLOR, sashwidth=5, bd=0
        )

        right_v_paned.add(latches_box, height=225, minsize=165)
        right_v_paned.add(bottom_split, height=400, minsize=240)

        # --- Tabla Detallada de Latches Intermedios ---
        l_container = tk.Frame(latches_box, bg=BG_PANEL)
        l_container.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        l_cols = ("latch", "valid", "pc", "datapath", "regs", "control")
        self.tree_latches = ttk.Treeview(l_container, columns=l_cols, show="headings", height=6)
        self.tree_latches.heading("latch", text="Latch")
        self.tree_latches.heading("valid", text="Estado")
        self.tree_latches.heading("pc", text="PC / PC+4")
        self.tree_latches.heading("datapath", text="Instrucción / Datos del Camino de Datos")
        self.tree_latches.heading("regs", text="Registros (rs1 / rs2 / rd)")
        self.tree_latches.heading("control", text="Señales de Control Activas")

        self.tree_latches.column("latch", width=72, anchor="center", stretch=False)
        self.tree_latches.column("valid", width=85, anchor="center", stretch=False)
        self.tree_latches.column("pc", width=165, anchor="center", stretch=False)
        self.tree_latches.column("datapath", width=290, anchor="w", stretch=True)
        self.tree_latches.column("regs", width=190, anchor="w", stretch=False)
        self.tree_latches.column("control", width=240, anchor="w", stretch=True)

        self.tree_latches.tag_configure("valid_row", foreground="#4ade80")
        self.tree_latches.tag_configure("empty_row", foreground="#64748b")

        l_scroll = ttk.Scrollbar(l_container, orient=tk.VERTICAL, command=self.tree_latches.yview)
        self.tree_latches.configure(yscrollcommand=l_scroll.set)
        l_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.tree_latches.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        # --- Sub-panel Izquierdo Inferior: Los 32 Registros (x0..x31) ---
        regs_box = ttk.LabelFrame(
            bottom_split,
            text=" 4. Contenido de los 32 Registros (x0..x31 — 0x20 DUMP_REGS) ",
        )
        # --- Sub-panel Derecho Inferior: Memoria de Datos Usada ---
        dmem_box = ttk.LabelFrame(
            bottom_split,
            text=" 5. Memoria de Datos Usada (0x25 DUMP_DMEM_USED) ",
        )
        bottom_split.add(regs_box, width=440, minsize=320)
        bottom_split.add(dmem_box, width=430, minsize=300)

        r_container = tk.Frame(regs_box, bg=BG_PANEL)
        r_container.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        r_cols = ("reg", "abi", "hex", "dec", "state")
        self.tree_regs = ttk.Treeview(r_container, columns=r_cols, show="headings", height=16)
        self.tree_regs.heading("reg", text="Reg")
        self.tree_regs.heading("abi", text="ABI")
        self.tree_regs.heading("hex", text="Valor Hex (32b)")
        self.tree_regs.heading("dec", text="Decimal")
        self.tree_regs.heading("state", text="Cambio")

        self.tree_regs.column("reg", width=55, anchor="center", stretch=False)
        self.tree_regs.column("abi", width=60, anchor="center", stretch=False)
        self.tree_regs.column("hex", width=115, anchor="center", stretch=False)
        self.tree_regs.column("dec", width=95, anchor="e", stretch=False)
        self.tree_regs.column("state", width=90, anchor="center", stretch=True)

        self.tree_regs.tag_configure("changed", background="#064e3b", foreground="#6ee7b7")
        self.tree_regs.tag_configure("nonzero", foreground="#f8fafc")
        self.tree_regs.tag_configure("zero", foreground="#64748b")

        r_scroll = ttk.Scrollbar(r_container, orient=tk.VERTICAL, command=self.tree_regs.yview)
        self.tree_regs.configure(yscrollcommand=r_scroll.set)
        r_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.tree_regs.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        # --- Tabla y Controles de Memoria de Datos ---
        dmem_ctrl = tk.Frame(dmem_box, bg=BG_PANEL)
        dmem_ctrl.pack(fill=tk.X, padx=6, pady=(4, 2))

        self._make_btn(
            dmem_ctrl,
            "Ver Memoria Usada (0x25)",
            self._on_dump_dmem_used_click,
            bg="#0f766e",
        ).pack(side=tk.LEFT, padx=(0, 6))

        tk.Label(dmem_ctrl, text="Offset:", bg=BG_PANEL, fg=FG_MUTED).pack(side=tk.LEFT)
        self.dmem_off_var = tk.StringVar(value="0")
        tk.Entry(
            dmem_ctrl,
            textvariable=self.dmem_off_var,
            width=5,
            bg=BG_INPUT,
            fg=FG_TEXT,
            insertbackground=FG_TEXT,
            relief=tk.FLAT,
            font=("Consolas", 9),
        ).pack(side=tk.LEFT, padx=3)

        tk.Label(dmem_ctrl, text="Palabras:", bg=BG_PANEL, fg=FG_MUTED).pack(side=tk.LEFT)
        self.dmem_cnt_var = tk.StringVar(value="16")
        tk.Entry(
            dmem_ctrl,
            textvariable=self.dmem_cnt_var,
            width=5,
            bg=BG_INPUT,
            fg=FG_TEXT,
            insertbackground=FG_TEXT,
            relief=tk.FLAT,
            font=("Consolas", 9),
        ).pack(side=tk.LEFT, padx=3)

        self._make_btn(
            dmem_ctrl,
            "Leer Rango (0x22)",
            self._on_dump_dmem_range_click,
            bg="#334155",
        ).pack(side=tk.LEFT, padx=4)

        d_container = tk.Frame(dmem_box, bg=BG_PANEL)
        d_container.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        d_cols = ("word", "byte_addr", "hex", "bytes_le", "dec")
        self.tree_dmem = ttk.Treeview(d_container, columns=d_cols, show="headings", height=14)
        self.tree_dmem.heading("word", text="Palabra")
        self.tree_dmem.heading("byte_addr", text="Dir. Byte")
        self.tree_dmem.heading("hex", text="Valor Hex (32b)")
        self.tree_dmem.heading("bytes_le", text="Bytes (LE)")
        self.tree_dmem.heading("dec", text="Decimal")

        self.tree_dmem.column("word", width=75, anchor="center", stretch=False)
        self.tree_dmem.column("byte_addr", width=85, anchor="center", stretch=False)
        self.tree_dmem.column("hex", width=105, anchor="center", stretch=False)
        self.tree_dmem.column("bytes_le", width=105, anchor="center", stretch=False)
        self.tree_dmem.column("dec", width=85, anchor="e", stretch=True)

        self.tree_dmem.tag_configure("used_word", foreground="#38bdf8")

        d_scroll = ttk.Scrollbar(d_container, orient=tk.VERTICAL, command=self.tree_dmem.yview)
        self.tree_dmem.configure(yscrollcommand=d_scroll.set)
        d_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.tree_dmem.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

    def _build_bottom_uart_log(self) -> None:
        log_box = ttk.LabelFrame(
            self.root,
            text=" Consola de Comunicación UART (Tramas Binarias TX / RX con la Debug Unit) ",
        )
        log_box.pack(fill=tk.X, padx=8, pady=(0, 8))

        container = tk.Frame(log_box, bg=BG_INPUT)
        container.pack(fill=tk.X, padx=6, pady=4)

        scroll = ttk.Scrollbar(container, orient=tk.VERTICAL)
        self.log_text = tk.Text(
            container,
            height=5,
            bg=BG_INPUT,
            fg="#cbd5e1",
            font=("Consolas", 9),
            yscrollcommand=scroll.set,
            relief=tk.FLAT,
            padx=6,
            pady=4,
            state=tk.DISABLED,
        )
        self.log_text.tag_configure("TX", foreground="#38bdf8")
        self.log_text.tag_configure("RX", foreground="#4ade80")
        self.log_text.tag_configure("INFO", foreground="#facc15")
        self.log_text.tag_configure("ERR", foreground="#f87171")

        scroll.config(command=self.log_text.yview)
        scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.log_text.pack(side=tk.LEFT, fill=tk.X, expand=True)

    # ------------------------------------------------------------------
    # Inicialización de Datos y Ejemplos
    # ------------------------------------------------------------------
    def _populate_ports(self) -> None:
        ports = list_serial_ports()
        dev_names = [dev for dev, _ in ports]
        if not dev_names:
            dev_names = ["COM1", "COM3", "COM4", "/dev/ttyUSB0", "/dev/ttyUSB1"]
        self.port_combo["values"] = dev_names
        if ports and (not self.port_var.get() or self.port_var.get() not in dev_names):
            self.port_var.set(ports[0][0])

    def _populate_examples(self) -> None:
        examples: List[str] = []
        if self.programas_dir.exists():
            for p in sorted(self.programas_dir.glob("*.asm")):
                examples.append(p.name)
        self.example_combo["values"] = examples
        if examples:
            self.example_var.set(examples[0])
            self._load_example_file(self.programas_dir / examples[0])

    def _load_example_file(self, path: Path) -> None:
        try:
            text = path.read_text(encoding="utf-8")
            self.asm_text.delete("1.0", tk.END)
            self.asm_text.insert("1.0", text)
            self._on_assemble_click(silent=True)
        except Exception as exc:
            self._append_log("ERR", f"No se pudo cargar el ejemplo '{path.name}': {exc}")

    def _init_empty_tables(self) -> None:
        # Inicializa los 32 registros en 0
        for i in range(32):
            abi = ABI_NAMES_BY_IDX[i]
            self.tree_regs.insert(
                "",
                tk.END,
                iid=f"reg_{i}",
                values=(f"x{i}", abi, "0x00000000", "0", "—"),
                tags=("zero",),
            )

        # Inicializa las 4 filas de latches intermedios
        for name in ("IF/ID", "ID/EX", "EX/MEM", "MEM/WB"):
            self.tree_latches.insert(
                "",
                tk.END,
                iid=f"latch_{name}",
                values=(name, "VACÍO (0)", "0x00000000", "nop (burbuja)", "—", "Inactivo"),
                tags=("empty_row",),
            )

    # ------------------------------------------------------------------
    # Eventos de Interfaz y Comunicación UART
    # ------------------------------------------------------------------
    def _enqueue_uart_log(self, direction: str, message: str) -> None:
        self.log_queue.put((direction, message))

    def _poll_log_queue(self) -> None:
        while not self.log_queue.empty():
            direction, msg = self.log_queue.get_nowait()
            self._append_log(direction, msg)
        self.root.after(80, self._poll_log_queue)

    def _append_log(self, tag: str, message: str) -> None:
        self.log_text.configure(state=tk.NORMAL)
        self.log_text.insert(tk.END, f"[{tag}] {message}\n", (tag,))
        self.log_text.see(tk.END)
        self.log_text.configure(state=tk.DISABLED)

    def _on_example_selected(self, _event=None) -> None:
        name = self.example_var.get()
        if name:
            self._load_example_file(self.programas_dir / name)

    def _on_open_file(self) -> None:
        initial = str(self.programas_dir if self.programas_dir.exists() else Path.cwd())
        filepath = filedialog.askopenfilename(
            title="Abrir programa en ensamblador o hexadecimal",
            initialdir=initial,
            filetypes=[("Programas RISC-V", "*.asm *.s *.hex"), ("Todos los archivos", "*.*")],
        )
        if filepath:
            path = Path(filepath)
            self.asm_text.delete("1.0", tk.END)
            self.asm_text.insert("1.0", path.read_text(encoding="utf-8"))
            self._on_assemble_click()

    def _on_save_file(self) -> None:
        initial = str(self.programas_dir if self.programas_dir.exists() else Path.cwd())
        filepath = filedialog.asksaveasfilename(
            title="Guardar programa en ensamblador",
            initialdir=initial,
            defaultextension=".asm",
            filetypes=[("Ensamblador RISC-V (*.asm)", "*.asm"), ("Hexadecimal (*.hex)", "*.hex")],
        )
        if filepath:
            Path(filepath).write_text(self.asm_text.get("1.0", tk.END), encoding="utf-8")
            self._append_log("INFO", f"Programa guardado en '{filepath}'")

    def _on_connect_toggle(self) -> None:
        if self.client.is_connected:
            self.client.disconnect()
            self.btn_connect.configure(text="Conectar FPGA", bg=ACCENT_BLUE)
            self.lbl_conn_badge.configure(text=" DESCONECTADO ", bg="#7f1d1d", fg="#fecaca")
            return

        port = self.port_var.get().strip()
        if not port:
            messagebox.showwarning("Puerto requerido", "Seleccione o escriba un puerto serie (ej. COM3).")
            return
        try:
            baud = int(self.baud_var.get())
            self.client.connect(port, baudrate=baud)
            self.btn_connect.configure(text="Desconectar", bg="#475569")
            self.lbl_conn_badge.configure(
                text=f" CONECTADO ({port}) ", bg="#14532d", fg="#bbf7d0"
            )
            # Intentamos leer el estado inicial al conectar
            try:
                snap = self.client.read_full_snapshot()
                self._update_ui_from_snapshot(snap)
            except ProtocolError as exc:
                self._append_log("INFO", f"Puerto abierto (sin respuesta inmediata de FPGA): {exc}")
        except Exception as exc:
            messagebox.showerror("Error de conexión UART", str(exc))

    def _on_assemble_click(self, silent: bool = False) -> bool:
        source = self.asm_text.get("1.0", tk.END)
        try:
            program, labels = assemble_text(source)
        except AssemblerError as exc:
            self._append_log("ERR", f"Error de ensamblado: {exc}")
            if not silent:
                messagebox.showerror("Error en el Ensamblador RV32I", str(exc))
            return False

        self.assembled_program = program
        self.assembled_labels = labels

        for item in self.tree_mach.get_children():
            self.tree_mach.delete(item)

        for inst in program:
            tags = ("ebreak_row",) if inst.word == 0x00100073 else ()
            self.tree_mach.insert(
                "",
                tk.END,
                iid=f"pc_{inst.address}",
                values=(
                    f"0x{inst.address:04X}",
                    inst.hex_str,
                    inst.bytes_le_str,
                    inst.inst_format,
                    inst.binary_fields_str,
                    inst.canonical_asm,
                ),
                tags=tags,
            )

        if not silent:
            has_ebreak = any(i.word == 0x00100073 for i in program)
            msg = f"Ensamblado exitoso: {len(program)} instrucciones ({len(program) * 4} bytes)."
            if not has_ebreak:
                msg += " [ADVERTENCIA: No se incluyó instrucción 'ebreak' al final del programa]."
            self._append_log("INFO", msg)
        return True

    def _on_load_prog_click(self) -> None:
        if self.is_busy:
            return
        if not self._on_assemble_click(silent=False):
            return
        if not self.assembled_program:
            messagebox.showwarning("Programa vacío", "El editor no contiene instrucciones para cargar.")
            return
        if not self.client.is_connected:
            messagebox.showwarning(
                "Sin conexión UART",
                "El código fue traducido a lenguaje máquina en la tabla inferior.\n"
                "Conéctese a un puerto COM para enviarlo a la FPGA (LOAD_PROG 0x02).",
            )
            return

        try:
            words = [inst.word for inst in self.assembled_program]
            self.client.load_program(words)
            self.step_count = 0
            self.prev_regs = None
            snap = self.client.read_full_snapshot()
            self._update_ui_from_snapshot(snap)
            self.prev_regs = list(snap.regs)
        except Exception as exc:
            self._append_log("ERR", str(exc))
            messagebox.showerror("Error al programar FPGA", str(exc))

    def _on_reset_click(self) -> None:
        if self.is_busy or not self._ensure_connected():
            return
        try:
            self.client.reset()
            self.step_count = 0
            self.prev_regs = None
            snap = self.client.read_full_snapshot()
            self._update_ui_from_snapshot(snap)
            self.prev_regs = list(snap.regs)
        except Exception as exc:
            self._append_log("ERR", str(exc))
            messagebox.showerror("Error en RESET", str(exc))

    def _on_step_click(self) -> None:
        if self.is_busy or not self._ensure_connected():
            return
        try:
            n_steps = max(1, int(self.step_n_var.get()))
        except ValueError:
            n_steps = 1

        try:
            for _ in range(n_steps):
                rsp = self.client.step()
                self.step_count += 1
                snap = self.client.read_full_snapshot()
                self._update_ui_from_snapshot(snap)
                self.prev_regs = list(snap.regs)
                self.root.update_idletasks()
                if rsp == RSP_HALTED:
                    self._append_log(
                        "INFO",
                        "Fin de programa alcanzado en Modo Paso a Paso (HALTED 0xF1 — Pipeline vacío).",
                    )
                    break
        except Exception as exc:
            self._append_log("ERR", str(exc))
            messagebox.showerror("Error en STEP", str(exc))

    def _on_run_click(self) -> None:
        if self.is_busy or not self._ensure_connected():
            return

        self.is_busy = True
        self._set_buttons_state(tk.DISABLED)
        self._append_log(
            "INFO",
            "Iniciando Modo Continuo (RUN 0x10)... esperando HALTED (0xF1) con pipeline vacío.",
        )

        def worker() -> None:
            try:
                self.client.run(run_timeout=15.0)
                snap = self.client.read_full_snapshot()
                self.root.after(0, lambda: self._on_run_finished(snap, None))
            except Exception as exc:
                self.root.after(0, lambda e=exc: self._on_run_finished(None, e))

        threading.Thread(target=worker, daemon=True).start()

    def _on_run_finished(
        self,
        snap: Optional[ProcessorSnapshot],
        error: Optional[Exception],
    ) -> None:
        self.is_busy = False
        self._set_buttons_state(tk.NORMAL)
        if error is not None:
            self._append_log("ERR", f"Error en Modo Continuo: {error}")
            messagebox.showerror("Error en Modo Continuo (RUN)", str(error))
            return
        if snap is not None:
            self._update_ui_from_snapshot(snap)
            self.prev_regs = list(snap.regs)

    def _on_read_state_click(self) -> None:
        if self.is_busy or not self._ensure_connected():
            return
        try:
            snap = self.client.read_full_snapshot()
            self._update_ui_from_snapshot(snap)
            self.prev_regs = list(snap.regs)
        except Exception as exc:
            self._append_log("ERR", str(exc))
            messagebox.showerror("Error al leer estado", str(exc))

    def _on_dump_dmem_used_click(self) -> None:
        if self.is_busy or not self._ensure_connected():
            return
        try:
            entries = self.client.dump_dmem_used()
            self._populate_dmem_tree(entries)
        except Exception as exc:
            self._append_log("ERR", str(exc))
            messagebox.showerror("Error en DUMP_DMEM_USED", str(exc))

    def _on_dump_dmem_range_click(self) -> None:
        if self.is_busy or not self._ensure_connected():
            return
        try:
            off = int(self.dmem_off_var.get(), 0)
            cnt = int(self.dmem_cnt_var.get(), 0)
            entries = self.client.dump_dmem(off, cnt)
            self._populate_dmem_tree(entries)
        except Exception as exc:
            self._append_log("ERR", str(exc))
            messagebox.showerror("Error en DUMP_DMEM", str(exc))

    def _ensure_connected(self) -> bool:
        if not self.client.is_connected:
            messagebox.showwarning(
                "No conectado",
                "Conéctese primero al puerto serie de la FPGA desde la barra superior.",
            )
            return False
        return True

    def _set_buttons_state(self, state: str) -> None:
        for btn in (self.btn_load, self.btn_run, self.btn_step, self.btn_reset, self.btn_refresh):
            btn.configure(state=state)

    # ------------------------------------------------------------------
    # Actualización Visual Completa del Estado del Procesador
    # ------------------------------------------------------------------
    def _update_ui_from_snapshot(self, snap: ProcessorSnapshot) -> None:
        # 1. PC y contador de ciclos
        self.lbl_pc.configure(text=f"PC: 0x{snap.pc:08X}")
        self.lbl_step.configure(text=f"Ciclos Paso a Paso: {self.step_count}")

        # 2. Badges de STATUS
        st = snap.status
        self._update_badge(self.badge_prog, f"PROG_LOADED: {int(st.prog_loaded)}", st.prog_loaded, "#0369a1")
        self._update_badge(self.badge_run, f"RUNNING: {int(st.running)}", st.running, "#15803d")
        self._update_badge(self.badge_drain, f"DRAINING: {int(st.draining)}", st.draining, "#b45309")
        self._update_badge(self.badge_halt, f"HALTED: {int(st.halted)}", st.halted, "#7c3aed")

        empty = snap.latches.pipeline_empty
        self._update_badge(
            self.badge_empty,
            f"PIPELINE VACÍO: {'SÍ (4/4)' if empty else 'NO'}",
            empty,
            "#0f766e" if empty else "#475569",
        )

        # 3. Resaltar instrucción actual en la Tabla de Lenguaje Máquina
        for iid in self.tree_mach.get_children():
            inst_tags = list(self.tree_mach.item(iid, "tags"))
            if "active_pc" in inst_tags:
                inst_tags.remove("active_pc")
            self.tree_mach.item(iid, tags=tuple(inst_tags))

        active_iid = f"pc_{snap.pc}"
        if self.tree_mach.exists(active_iid):
            cur_tags = list(self.tree_mach.item(active_iid, "tags"))
            cur_tags.append("active_pc")
            self.tree_mach.item(active_iid, tags=tuple(cur_tags))
            self.tree_mach.see(active_iid)

        # 4. Actualizar Tarjetas Visuales y Tabla de los 4 Latches Intermedios
        self._update_latches_view(snap.latches)

        # 5. Actualizar Tabla de los 32 Registros (x0..x31)
        self._update_registers_view(snap.regs)

        # 6. Actualizar Tabla de Memoria de Datos Usada
        self._populate_dmem_tree(snap.dmem_used)

    def _update_badge(self, lbl: tk.Label, text: str, active: bool, active_bg: str) -> None:
        if active:
            lbl.configure(text=f" {text} ", bg=active_bg, fg="#ffffff")
        else:
            lbl.configure(text=f" {text} ", bg="#334155", fg="#94a3b8")

    def _update_latches_view(self, latches: LatchesSnapshot) -> None:
        if_id = latches.if_id
        id_ex = latches.id_ex
        ex_mem = latches.ex_mem
        mem_wb = latches.mem_wb

        # Actualizar tarjetas superiores
        self._set_stage_card(
            "IF/ID",
            if_id.valid,
            if_id.disasm if if_id.valid else "nop (burbuja / vacío)",
            f"PC: 0x{if_id.pc:08X} | Inst: 0x{if_id.instruction:08X}",
        )
        self._set_stage_card(
            "ID/EX",
            id_ex.valid,
            f"{id_ex.rs1_name}, {id_ex.rs2_name} → {id_ex.rd_name}" if id_ex.valid else "nop (burbuja / vacío)",
            f"PC: 0x{id_ex.pc:08X} | {id_ex.active_controls_str()}",
        )
        self._set_stage_card(
            "EX/MEM",
            ex_mem.valid,
            f"ALU: 0x{ex_mem.alu_result:08X} → {ex_mem.rd_name}" if ex_mem.valid else "nop (burbuja / vacío)",
            f"WriteData: 0x{ex_mem.rs2_data:08X} | {ex_mem.active_controls_str()}",
        )
        self._set_stage_card(
            "MEM/WB",
            mem_wb.valid,
            f"{mem_wb.wb_source_str}: 0x{mem_wb.wb_value:08X} → {mem_wb.rd_name}"
            if mem_wb.valid
            else "nop (burbuja / vacío)",
            f"ReadData: 0x{mem_wb.read_data:08X} | {mem_wb.active_controls_str()}",
        )

        # Actualizar tabla detallada de los 4 latches
        rows = [
            (
                "IF/ID",
                if_id.valid,
                f"PC=0x{if_id.pc:08X} | PC+4=0x{if_id.pc_plus_4:08X}",
                f"Inst=0x{if_id.instruction:08X} ({if_id.disasm})",
                "—",
                "Fetch → Decode" if if_id.valid else "VACÍO (valid=0)",
            ),
            (
                "ID/EX",
                id_ex.valid,
                f"PC=0x{id_ex.pc:08X} | PC+4=0x{id_ex.pc_plus_4:08X}",
                f"rs1=0x{id_ex.rs1_data:08X} | rs2=0x{id_ex.rs2_data:08X} | Imm=0x{id_ex.imm:08X}",
                f"rs1={id_ex.rs1_name} rs2={id_ex.rs2_name} rd={id_ex.rd_name}",
                id_ex.active_controls_str(),
            ),
            (
                "EX/MEM",
                ex_mem.valid,
                f"PC+4=0x{ex_mem.pc_plus_4:08X}",
                f"ALURes=0x{ex_mem.alu_result:08X} ({to_signed32(ex_mem.alu_result)}) | rs2=0x{ex_mem.rs2_data:08X}",
                f"rd={ex_mem.rd_name} | funct3=0x{ex_mem.funct3:X}",
                ex_mem.active_controls_str(),
            ),
            (
                "MEM/WB",
                mem_wb.valid,
                f"PC+4=0x{mem_wb.pc_plus_4:08X}",
                f"ReadData=0x{mem_wb.read_data:08X} | ALURes=0x{mem_wb.alu_result:08X} | WB=0x{mem_wb.wb_value:08X}",
                f"rd={mem_wb.rd_name}",
                mem_wb.active_controls_str(),
            ),
        ]
        for name, valid, pc_str, data_str, regs_str, ctrl_str in rows:
            self.tree_latches.item(
                f"latch_{name}",
                values=(
                    name,
                    "VALID (1)" if valid else "VACÍO (0)",
                    pc_str,
                    data_str,
                    regs_str,
                    ctrl_str,
                ),
                tags=("valid_row",) if valid else ("empty_row",),
            )

    def _set_stage_card(self, code: str, valid: bool, main_txt: str, detail_txt: str) -> None:
        widgets = self.stage_cards[code]
        frame: tk.Frame = widgets["frame"]  # type: ignore[assignment]
        if valid:
            frame.configure(highlightbackground="#0284c7")
            widgets["valid"].configure(text="VALID (1)", bg="#0369a1", fg="#ffffff")
            widgets["main"].configure(text=main_txt, fg="#f8fafc")
        else:
            frame.configure(highlightbackground=BORDER_COLOR)
            widgets["valid"].configure(text="VACÍO (0)", bg="#334155", fg="#94a3b8")
            widgets["main"].configure(text=main_txt, fg="#64748b")
        widgets["detail"].configure(text=detail_txt)

    def _update_registers_view(self, regs: Sequence[int]) -> None:
        for i in range(32):
            val = regs[i] & 0xFFFFFFFF
            sval = to_signed32(val)
            abi = ABI_NAMES_BY_IDX[i]
            changed = self.prev_regs is not None and (self.prev_regs[i] & 0xFFFFFFFF) != val
            if changed:
                tag = "changed"
                state_str = "★ MODIFICADO"
            elif val != 0:
                tag = "nonzero"
                state_str = "Activo"
            else:
                tag = "zero"
                state_str = "—"

            self.tree_regs.item(
                f"reg_{i}",
                values=(f"x{i}", abi, f"0x{val:08X}", str(sval), state_str),
                tags=(tag,),
            )

    def _populate_dmem_tree(self, entries: Sequence[DmemEntry]) -> None:
        for item in self.tree_dmem.get_children():
            self.tree_dmem.delete(item)

        for e in entries:
            self.tree_dmem.insert(
                "",
                tk.END,
                values=(
                    f"Word[{e.word_addr}]",
                    f"0x{e.byte_addr:08X}",
                    f"0x{e.data:08X}",
                    e.bytes_le_str,
                    str(e.signed_data),
                ),
                tags=("used_word",),
            )

    def _on_close(self) -> None:
        try:
            self.client.disconnect()
        finally:
            self.root.destroy()


def launch_gui(port: Optional[str] = None) -> None:
    """Inicia la ventana principal de la interfaz gráfica."""
    root = tk.Tk()
    DebugUnitGUI(root, initial_port=port)
    root.mainloop()


if __name__ == "__main__":
    launch_gui()
