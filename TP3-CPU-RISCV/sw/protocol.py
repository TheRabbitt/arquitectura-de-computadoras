#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Cliente de Protocolo Binario UART para la Debug Unit del Procesador RISC-V.

Implementa la comunicación serie (115200 baudios, 8N1, Little-Endian) contra el
módulo hardware `rtl/debug_unit/debug_unit.v` según la especificación definida
en `docs/protocolo_uart.md`.

Comandos soportados (PC -> FPGA):
  - 0x01 RESET          : Reinicia PC, registros, latches y máscara de memoria usada.
  - 0x02 LOAD_PROG      : Programa/reprograma dinámicamente la memoria de instrucciones.
  - 0x10 RUN            : Inicia ejecución continua hasta `ebreak` y vaciado del pipeline.
  - 0x11 STEP           : Avanza exactamente 1 ciclo de reloj del procesador.
  - 0x20 DUMP_REGS      : Recibe los 32 registros del banco (x0..x31, 128 bytes).
  - 0x21 DUMP_LATCHES   : Recibe los 4 latches intermedios (IF/ID, ID/EX, EX/MEM, MEM/WB, 72 bytes).
  - 0x22 DUMP_DMEM      : Recibe una ventana arbitraria de memoria de datos.
  - 0x23 DUMP_PC        : Recibe el valor actual del Program Counter (4 bytes).
  - 0x24 STATUS         : Recibe el byte de estado (running, halted, draining, prog_loaded).
  - 0x25 DUMP_DMEM_USED : Recibe únicamente las posiciones de memoria de datos escritas.
"""

from __future__ import annotations

import struct
import time
from dataclasses import dataclass
from typing import Callable, List, Optional, Sequence, Tuple

try:
    import serial
    import serial.tools.list_ports
except ImportError:  # pragma: no cover
    serial = None  # Se informa claramente al intentar abrir un puerto serie

try:
    from .assembler import ABI_NAMES_BY_IDX, disassemble_word
except ImportError:
    from assembler import ABI_NAMES_BY_IDX, disassemble_word


# ==============================================================================
# Constantes del Protocolo Binario UART (Little-Endian)
# ==============================================================================
DEFAULT_BAUDRATE = 115200
IMEM_MAX_WORDS = 1024
DMEM_MAX_WORDS = 1024

CMD_RESET          = 0x01
CMD_LOAD_PROG      = 0x02
CMD_RUN            = 0x10
CMD_STEP           = 0x11
CMD_DUMP_REGS      = 0x20
CMD_DUMP_LATCHES   = 0x21
CMD_DUMP_DMEM      = 0x22
CMD_DUMP_PC        = 0x23
CMD_STATUS         = 0x24
CMD_DUMP_DMEM_USED = 0x25

RSP_ACK            = 0xA5
RSP_NAK            = 0x5A
RSP_HALTED         = 0xF1


class ProtocolError(Exception):
    """Excepción producida ante errores de comunicación, timeout o trama inválida."""


def to_signed32(val: int) -> int:
    """Convierte un entero uint32 a su representación con signo en complemento a 2."""
    val &= 0xFFFFFFFF
    return val - 0x100000000 if (val & 0x80000000) else val


# ==============================================================================
# Estructuras de Datos Desempaquetadas del Procesador
# ==============================================================================
@dataclass
class StatusFlags:
    """Estado del procesador reportado por el comando `0x24 STATUS`."""

    raw: int

    @property
    def running(self) -> bool:
        return bool(self.raw & 0x01)

    @property
    def halted(self) -> bool:
        return bool(self.raw & 0x02)

    @property
    def draining(self) -> bool:
        return bool(self.raw & 0x04)

    @property
    def prog_loaded(self) -> bool:
        return bool(self.raw & 0x08)

    def summary_str(self) -> str:
        flags = []
        if self.running:
            flags.append("RUNNING")
        if self.draining:
            flags.append("DRAINING")
        if self.halted:
            flags.append("HALTED")
        if self.prog_loaded:
            flags.append("PROG_LOADED")
        if not flags:
            flags.append("IDLE")
        return f"0x{self.raw:02X} ({' | '.join(flags)})"


@dataclass
class IfIdLatch:
    """Contenido desempaquetado del latch intermedio IF/ID (palabras 0..3)."""

    pc: int
    pc_plus_4: int
    instruction: int
    valid: bool

    @property
    def disasm(self) -> str:
        if not self.valid:
            return "nop (burbuja / vacío)"
        return disassemble_word(self.instruction)


@dataclass
class IdExLatch:
    """Contenido desempaquetado del latch intermedio ID/EX (palabras 4..9)."""

    pc: int
    pc_plus_4: int
    rs1_data: int
    rs2_data: int
    imm: int
    rs1: int
    rs2: int
    rd: int
    funct3: int
    funct7_5: int
    alu_op: int
    alu_src: int
    mem_read: int
    mem_write: int
    reg_write: int
    mem_to_reg: int
    wb_jump: int
    valid: bool
    raw_ctrl_word: int

    @property
    def rs1_name(self) -> str:
        return f"x{self.rs1}({ABI_NAMES_BY_IDX[self.rs1]})"

    @property
    def rs2_name(self) -> str:
        return f"x{self.rs2}({ABI_NAMES_BY_IDX[self.rs2]})"

    @property
    def rd_name(self) -> str:
        return f"x{self.rd}({ABI_NAMES_BY_IDX[self.rd]})"

    @property
    def alu_op_str(self) -> str:
        mapping = {0: "00(LUI/MEM)", 1: "01(BRANCH)", 2: "10(R-TYPE)", 3: "11(I-ALU)"}
        return mapping.get(self.alu_op, f"{self.alu_op:02b}")

    def active_controls_str(self) -> str:
        if not self.valid:
            return "VACÍO (valid=0)"
        ctrls = [f"ALUOp={self.alu_op:02b}"]
        if self.alu_src:
            ctrls.append("ALUSrc=Imm")
        else:
            ctrls.append("ALUSrc=Reg")
        if self.mem_read:
            ctrls.append("MemRead")
        if self.mem_write:
            ctrls.append("MemWrite")
        if self.reg_write:
            ctrls.append("RegWrite")
        if self.mem_to_reg:
            ctrls.append("MemToReg")
        if self.wb_jump:
            ctrls.append("WBJump")
        return ", ".join(ctrls)


@dataclass
class ExMemLatch:
    """Contenido desempaquetado del latch intermedio EX/MEM (palabras 10..13)."""

    alu_result: int
    rs2_data: int
    pc_plus_4: int
    rd: int
    funct3: int
    mem_read: int
    mem_write: int
    reg_write: int
    mem_to_reg: int
    wb_jump: int
    valid: bool
    raw_ctrl_word: int

    @property
    def rd_name(self) -> str:
        return f"x{self.rd}({ABI_NAMES_BY_IDX[self.rd]})"

    def active_controls_str(self) -> str:
        if not self.valid:
            return "VACÍO (valid=0)"
        ctrls = []
        if self.mem_read:
            ctrls.append("MemRead")
        if self.mem_write:
            ctrls.append("MemWrite")
        if self.reg_write:
            ctrls.append("RegWrite")
        if self.mem_to_reg:
            ctrls.append("MemToReg")
        if self.wb_jump:
            ctrls.append("WBJump")
        return ", ".join(ctrls) if ctrls else "Ninguno (NOP)"


@dataclass
class MemWbLatch:
    """Contenido desempaquetado del latch intermedio MEM/WB (palabras 14..17)."""

    read_data: int
    alu_result: int
    pc_plus_4: int
    rd: int
    reg_write: int
    mem_to_reg: int
    wb_jump: int
    valid: bool
    raw_ctrl_word: int

    @property
    def rd_name(self) -> str:
        return f"x{self.rd}({ABI_NAMES_BY_IDX[self.rd]})"

    @property
    def wb_value(self) -> int:
        if self.wb_jump:
            return self.pc_plus_4
        if self.mem_to_reg:
            return self.read_data
        return self.alu_result

    @property
    def wb_source_str(self) -> str:
        if self.wb_jump:
            return "PC+4 (Jump)"
        if self.mem_to_reg:
            return "MemReadData"
        return "ALUResult"

    def active_controls_str(self) -> str:
        if not self.valid:
            return "VACÍO (valid=0)"
        ctrls = []
        if self.reg_write:
            ctrls.append("RegWrite")
        if self.mem_to_reg:
            ctrls.append("MemToReg")
        if self.wb_jump:
            ctrls.append("WBJump")
        return ", ".join(ctrls) if ctrls else "Ninguno (Store/Branch/NOP)"


@dataclass
class LatchesSnapshot:
    """Conjunto completo de los 4 latches intermedios (18 palabras = 72 bytes)."""

    if_id: IfIdLatch
    id_ex: IdExLatch
    ex_mem: ExMemLatch
    mem_wb: MemWbLatch
    raw_words: Tuple[int, ...]

    @property
    def pipeline_empty(self) -> bool:
        return not (
            self.if_id.valid
            or self.id_ex.valid
            or self.ex_mem.valid
            or self.mem_wb.valid
        )

    @classmethod
    def from_words(cls, words: Sequence[int]) -> "LatchesSnapshot":
        if len(words) != 18:
            raise ValueError(f"Se esperaban 18 palabras para DUMP_LATCHES, recibidas {len(words)}")

        # IF/ID (words 0..3)
        w3 = words[3]
        if_id = IfIdLatch(
            pc=words[0],
            pc_plus_4=words[1],
            instruction=words[2],
            valid=bool(w3 & 0x1),
        )

        # ID/EX (words 4..9)
        w9 = words[9]
        id_ex = IdExLatch(
            pc=words[4],
            pc_plus_4=words[5],
            rs1_data=words[6],
            rs2_data=words[7],
            imm=words[8],
            rs1=(w9 >> 0) & 0x1F,
            rs2=(w9 >> 5) & 0x1F,
            rd=(w9 >> 10) & 0x1F,
            funct3=(w9 >> 15) & 0x7,
            funct7_5=(w9 >> 18) & 0x1,
            alu_op=(w9 >> 19) & 0x3,
            alu_src=(w9 >> 22) & 0x1,
            mem_read=(w9 >> 23) & 0x1,
            mem_write=(w9 >> 24) & 0x1,
            reg_write=(w9 >> 25) & 0x1,
            mem_to_reg=(w9 >> 26) & 0x1,
            wb_jump=(w9 >> 27) & 0x1,
            valid=bool((w9 >> 28) & 0x1),
            raw_ctrl_word=w9,
        )

        # EX/MEM (words 10..13)
        w13 = words[13]
        ex_mem = ExMemLatch(
            alu_result=words[10],
            rs2_data=words[11],
            pc_plus_4=words[12],
            rd=(w13 >> 0) & 0x1F,
            funct3=(w13 >> 5) & 0x7,
            mem_read=(w13 >> 8) & 0x1,
            mem_write=(w13 >> 9) & 0x1,
            reg_write=(w13 >> 10) & 0x1,
            mem_to_reg=(w13 >> 11) & 0x1,
            wb_jump=(w13 >> 12) & 0x1,
            valid=bool((w13 >> 13) & 0x1),
            raw_ctrl_word=w13,
        )

        # MEM/WB (words 14..17)
        w17 = words[17]
        mem_wb = MemWbLatch(
            read_data=words[14],
            alu_result=words[15],
            pc_plus_4=words[16],
            rd=(w17 >> 0) & 0x1F,
            reg_write=(w17 >> 5) & 0x1,
            mem_to_reg=(w17 >> 6) & 0x1,
            wb_jump=(w17 >> 7) & 0x1,
            valid=bool((w17 >> 8) & 0x1),
            raw_ctrl_word=w17,
        )

        return cls(
            if_id=if_id,
            id_ex=id_ex,
            ex_mem=ex_mem,
            mem_wb=mem_wb,
            raw_words=tuple(words),
        )


@dataclass
class DmemEntry:
    """Entrada de una palabra de 32 bits en la Memoria de Datos."""

    word_addr: int
    data: int

    @property
    def byte_addr(self) -> int:
        return self.word_addr * 4

    @property
    def signed_data(self) -> int:
        return to_signed32(self.data)

    @property
    def bytes_le_str(self) -> str:
        b = struct.pack("<I", self.data & 0xFFFFFFFF)
        return " ".join(f"{x:02X}" for x in b)


@dataclass
class ProcessorSnapshot:
    """Fotografía completa del procesador (PC, Status, 32 Registros, 4 Latches y Memoria usada)."""

    pc: int
    status: StatusFlags
    regs: List[int]
    latches: LatchesSnapshot
    dmem_used: List[DmemEntry]


# ==============================================================================
# Utilidad para listar puertos serie disponibles en el sistema
# ==============================================================================
def list_serial_ports() -> List[Tuple[str, str]]:
    """Retorna una lista de tuplas `(device, description)` con los puertos COM/tty detectados."""
    if serial is None:
        return []
    ports = []
    for p in serial.tools.list_ports.comports():
        ports.append((p.device, f"{p.device} - {p.description}"))
    return ports


# ==============================================================================
# Cliente de Comunicación Serie con la Debug Unit
# ==============================================================================
class DebugUnitClient:
    """
    Cliente UART sincrónico para controlar y depurar el procesador RISC-V en FPGA.
    """

    def __init__(
        self,
        port: Optional[str] = None,
        baudrate: int = DEFAULT_BAUDRATE,
        timeout: float = 2.0,
        log_callback: Optional[Callable[[str, str], None]] = None,
    ):
        self.port_name = port
        self.baudrate = baudrate
        self.timeout = timeout
        self.log_callback = log_callback
        self._ser: Optional["serial.Serial"] = None

        if port:
            self.connect(port, baudrate, timeout)

    # ------------------------------------------------------------------
    # Gestión de conexión serie
    # ------------------------------------------------------------------
    @property
    def is_connected(self) -> bool:
        return self._ser is not None and bool(self._ser.is_open)

    def _log(self, direction: str, message: str) -> None:
        if self.log_callback:
            self.log_callback(direction, message)

    def connect(
        self,
        port: str,
        baudrate: int = DEFAULT_BAUDRATE,
        timeout: float = 2.0,
    ) -> None:
        """Abre la conexión serie con la FPGA (8 bits de datos, sin paridad, 1 bit de stop)."""
        if serial is None:
            raise ProtocolError(
                "El paquete 'pyserial' no está instalado. Instálalo ejecutando: pip install pyserial"
            )
        self.disconnect()
        try:
            self._ser = serial.Serial(
                port=port,
                baudrate=baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=timeout,
                write_timeout=timeout,
            )
            self.port_name = port
            self.baudrate = baudrate
            self.timeout = timeout
            self._ser.reset_input_buffer()
            self._ser.reset_output_buffer()
            self._log("INFO", f"Conectado a {port} @ {baudrate} bps (8N1)")
        except Exception as exc:
            self._ser = None
            raise ProtocolError(f"No se pudo abrir el puerto serie '{port}': {exc}") from exc

    def disconnect(self) -> None:
        """Cierra la conexión serie si estaba abierta."""
        if self._ser is not None:
            port_closed = self.port_name
            try:
                if self._ser.is_open:
                    self._ser.close()
            finally:
                self._ser = None
                self._log("INFO", f"Puerto {port_closed} desconectado.")

    def _require_connection(self) -> "serial.Serial":
        if not self.is_connected or self._ser is None:
            raise ProtocolError("No hay conexión activa con la FPGA. Conéctate a un puerto COM primero.")
        return self._ser

    def _write_bytes(self, payload: bytes, desc: str = "") -> None:
        ser = self._require_connection()
        hex_preview = " ".join(f"{b:02X}" for b in payload[:24])
        if len(payload) > 24:
            hex_preview += f" ... ({len(payload)} B total)"
        self._log("TX", f"{desc} [{hex_preview}]" if desc else hex_preview)
        ser.write(payload)
        ser.flush()

    def _read_exact(self, num_bytes: int, custom_timeout: Optional[float] = None) -> bytes:
        ser = self._require_connection()
        old_timeout = ser.timeout
        if custom_timeout is not None:
            ser.timeout = custom_timeout
        try:
            chunks = bytearray()
            deadline = time.monotonic() + (custom_timeout if custom_timeout is not None else (old_timeout or 2.0))
            while len(chunks) < num_bytes:
                remaining = num_bytes - len(chunks)
                block = ser.read(remaining)
                if block:
                    chunks.extend(block)
                elif time.monotonic() >= deadline:
                    break
            if len(chunks) != num_bytes:
                raise ProtocolError(
                    f"Timeout esperando respuesta UART de la FPGA: "
                    f"se esperaban {num_bytes} bytes, se recibieron {len(chunks)} bytes."
                )
            return bytes(chunks)
        finally:
            if custom_timeout is not None:
                ser.timeout = old_timeout

    # ------------------------------------------------------------------
    # Comandos de Control y Programación (0x01, 0x02, 0x10, 0x11)
    # ------------------------------------------------------------------
    def reset(self) -> int:
        """
        Envía `0x01 RESET` a la Debug Unit.
        Limpia PC, banco de registros, latches intermedios y máscara de memoria usada.
        """
        ser = self._require_connection()
        ser.reset_input_buffer()
        self._write_bytes(bytes([CMD_RESET]), "CMD_RESET (0x01)")
        rsp = self._read_exact(1)[0]
        self._log("RX", f"0x{rsp:02X} ({'ACK' if rsp == RSP_ACK else 'DESCONOCIDO'})")
        if rsp != RSP_ACK:
            raise ProtocolError(f"Respuesta inesperada a CMD_RESET: 0x{rsp:02X} (se esperaba ACK 0xA5)")
        return rsp

    def load_program(self, words: Sequence[int]) -> int:
        """
        Envía `0x02 LOAD_PROG` + `uint16 N` + `N * uint32` palabras en Little-Endian.
        Permite programar y reprogramar dinámicamente la memoria de instrucciones.
        """
        n_words = len(words)
        if n_words <= 0 or n_words > IMEM_MAX_WORDS:
            raise ValueError(
                f"Cantidad de instrucciones inválida ({n_words}). "
                f"Debe estar entre 1 y {IMEM_MAX_WORDS} palabras."
            )

        ser = self._require_connection()
        ser.reset_input_buffer()

        payload = bytearray()
        payload.append(CMD_LOAD_PROG)
        payload.extend(struct.pack("<H", n_words))
        for w in words:
            payload.extend(struct.pack("<I", w & 0xFFFFFFFF))

        self._write_bytes(
            bytes(payload),
            f"CMD_LOAD_PROG (0x02) -> N={n_words} instrucciones ({len(payload)} bytes)",
        )
        # Damos margen suficiente para la transmisión serie completa + escritura en BRAM
        calc_timeout = max(self.timeout, 1.5 + (len(payload) * 10.0 / self.baudrate))
        rsp = self._read_exact(1, custom_timeout=calc_timeout)[0]

        if rsp == RSP_ACK:
            self._log("RX", f"0x{rsp:02X} (ACK - Programa cargado en IMEM)")
            return rsp
        if rsp == RSP_NAK:
            self._log("RX", f"0x{rsp:02X} (NAK - Longitud N fuera de rango)")
            raise ProtocolError("La FPGA rechazó la carga del programa con NAK (0x5A).")
        raise ProtocolError(f"Respuesta inesperada a CMD_LOAD_PROG: 0x{rsp:02X}")

    def step(self) -> int:
        """
        Envía `0x11 STEP` para ejecutar exactamente 1 ciclo de reloj del procesador.
        Retorna `RSP_ACK (0xA5)` si ejecutó el ciclo o `RSP_HALTED (0xF1)` si el
        procesador alcanzó el final del programa con el pipeline vacío.
        """
        ser = self._require_connection()
        ser.reset_input_buffer()
        self._write_bytes(bytes([CMD_STEP]), "CMD_STEP (0x11)")
        rsp = self._read_exact(1)[0]
        if rsp == RSP_ACK:
            self._log("RX", "0xA5 (ACK - 1 ciclo ejecutado)")
        elif rsp == RSP_HALTED:
            self._log("RX", "0xF1 (HALTED - Fin de programa y pipeline vacío)")
        else:
            self._log("RX", f"0x{rsp:02X} (Respuesta desconocida)")
            raise ProtocolError(f"Respuesta inesperada a CMD_STEP: 0x{rsp:02X}")
        return rsp

    def start_run(self) -> int:
        """
        Envía `0x10 RUN` y espera el `ACK (0xA5)` inicial que confirma el arranque
        del modo continuo. Luego el llamador puede esperar `wait_for_halted()`.
        """
        ser = self._require_connection()
        ser.reset_input_buffer()
        self._write_bytes(bytes([CMD_RUN]), "CMD_RUN (0x10)")
        ack = self._read_exact(1)[0]
        if ack != RSP_ACK:
            raise ProtocolError(f"Se esperaba ACK (0xA5) al iniciar CMD_RUN, recibido 0x{ack:02X}")
        self._log("RX", "0xA5 (ACK - Ejecución continua iniciada)")
        return ack

    def wait_for_halted(self, run_timeout: float = 10.0) -> int:
        """
        Espera el byte asíncrono `HALTED (0xF1)` que envía la FPGA cuando detecta
        `ebreak` y los 4 latches intermedios quedan completamente vacíos.
        """
        halted = self._read_exact(1, custom_timeout=run_timeout)[0]
        if halted != RSP_HALTED:
            raise ProtocolError(
                f"Se esperaba HALTED (0xF1) al finalizar modo continuo, recibido 0x{halted:02X}"
            )
        self._log("RX", "0xF1 (HALTED - Ejecución continua finalizada, pipeline vacío)")
        return halted

    def run(self, run_timeout: float = 10.0) -> Tuple[int, int]:
        """
        Ejecuta el modo continuo completo: envía `0x10 RUN`, recibe `ACK (0xA5)` y
        aguarda hasta recibir `HALTED (0xF1)`.
        """
        ack = self.start_run()
        halted = self.wait_for_halted(run_timeout=run_timeout)
        return ack, halted

    # ------------------------------------------------------------------
    # Comandos de Lectura e Inspección (0x20 .. 0x25)
    # ------------------------------------------------------------------
    def dump_regs(self) -> List[int]:
        """
        Envía `0x20 DUMP_REGS` y recibe 128 bytes con los 32 registros (`x0..x31`).
        """
        ser = self._require_connection()
        ser.reset_input_buffer()
        self._write_bytes(bytes([CMD_DUMP_REGS]), "CMD_DUMP_REGS (0x20)")
        raw = self._read_exact(128)
        regs = list(struct.unpack("<32I", raw))
        self._log("RX", "128 bytes recibidos (32 registros x0..x31)")
        return regs

    def dump_latches(self) -> LatchesSnapshot:
        """
        Envía `0x21 DUMP_LATCHES` y recibe 72 bytes (18 palabras de 32 bits) con
        el estado completo de IF/ID, ID/EX, EX/MEM y MEM/WB.
        """
        ser = self._require_connection()
        ser.reset_input_buffer()
        self._write_bytes(bytes([CMD_DUMP_LATCHES]), "CMD_DUMP_LATCHES (0x21)")
        raw = self._read_exact(72)
        words = struct.unpack("<18I", raw)
        self._log("RX", "72 bytes recibidos (18 palabras de latches IF/ID, ID/EX, EX/MEM, MEM/WB)")
        return LatchesSnapshot.from_words(words)

    def dump_dmem(self, offset_word: int = 0, count_words: int = 16) -> List[DmemEntry]:
        """
        Envía `0x22 DUMP_DMEM` + `uint16 offset` + `uint16 count` y recibe
        `count * 4` bytes con las palabras solicitadas de la Memoria de Datos.
        """
        if count_words < 0 or count_words > DMEM_MAX_WORDS:
            raise ValueError(f"Cantidad de palabras inválida ({count_words}).")
        if count_words == 0:
            return []

        ser = self._require_connection()
        ser.reset_input_buffer()
        payload = struct.pack("<BHH", CMD_DUMP_DMEM, offset_word & 0xFFFF, count_words & 0xFFFF)
        self._write_bytes(
            payload,
            f"CMD_DUMP_DMEM (0x22) offset={offset_word}, count={count_words}",
        )
        raw = self._read_exact(count_words * 4)
        words = struct.unpack(f"<{count_words}I", raw)
        self._log("RX", f"{len(raw)} bytes recibidos ({count_words} palabras de DMEM)")
        return [
            DmemEntry(word_addr=(offset_word + idx) & 0x3FF, data=w)
            for idx, w in enumerate(words)
        ]

    def dump_pc(self) -> int:
        """Envía `0x23 DUMP_PC` y recibe 4 bytes Little-Endian con el Program Counter actual."""
        ser = self._require_connection()
        ser.reset_input_buffer()
        self._write_bytes(bytes([CMD_DUMP_PC]), "CMD_DUMP_PC (0x23)")
        raw = self._read_exact(4)
        (pc,) = struct.unpack("<I", raw)
        self._log("RX", f"PC = 0x{pc:08X}")
        return pc

    def get_status(self) -> StatusFlags:
        """Envía `0x24 STATUS` y recibe 1 byte con los flags de estado de la Debug Unit."""
        ser = self._require_connection()
        ser.reset_input_buffer()
        self._write_bytes(bytes([CMD_STATUS]), "CMD_STATUS (0x24)")
        raw = self._read_exact(1)[0]
        status = StatusFlags(raw=raw)
        self._log("RX", f"STATUS = {status.summary_str()}")
        return status

    def dump_dmem_used(self) -> List[DmemEntry]:
        """
        Envía `0x25 DUMP_DMEM_USED` y recibe únicamente las palabras de la Memoria
        de Datos que fueron escritas por el programa (`2 + K * 6` bytes).
        """
        ser = self._require_connection()
        ser.reset_input_buffer()
        self._write_bytes(bytes([CMD_DUMP_DMEM_USED]), "CMD_DUMP_DMEM_USED (0x25)")
        header = self._read_exact(2)
        (k_used,) = struct.unpack("<H", header)
        entries: List[DmemEntry] = []
        if k_used > 0:
            body = self._read_exact(k_used * 6)
            for i in range(k_used):
                word_addr, data = struct.unpack_from("<HI", body, i * 6)
                entries.append(DmemEntry(word_addr=word_addr, data=data))
        self._log("RX", f"DMEM_USED: K={k_used} posiciones modificadas recibidas")
        return entries

    def read_full_snapshot(self) -> ProcessorSnapshot:
        """
        Consulta secuencialmente a la FPGA todo el estado requerido por la consigna:
        - `0x24 STATUS`
        - `0x23 DUMP_PC`
        - `0x20 DUMP_REGS` (los 32 registros)
        - `0x21 DUMP_LATCHES` (los 4 latches intermedios)
        - `0x25 DUMP_DMEM_USED` (el contenido de la memoria de datos usada)
        """
        status = self.get_status()
        pc = self.dump_pc()
        regs = self.dump_regs()
        latches = self.dump_latches()
        dmem_used = self.dump_dmem_used()
        return ProcessorSnapshot(
            pc=pc,
            status=status,
            regs=regs,
            latches=latches,
            dmem_used=dmem_used,
        )
