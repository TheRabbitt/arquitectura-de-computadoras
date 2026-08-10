# Procesador RISC-V segmentado (RV32I) con Debug Unit por UART

Trabajo final. Placa: Nexys 4 (Artix-7 XC7A100T). Vivado 2026.1. Verilog.

## Puesta en marcha

```bash
make            # corre todos los testbenches (Icarus)
make project    # regenera el proyecto de Vivado
make bit        # sintetiza, implementa y genera el bitstream + reportes
make wave TB=top_tb
```

Dependencias del ciclo rápido: `sudo apt install iverilog gtkwave verilator`.
En Windows conviene hacerlo dentro de WSL.

## Estructura

```
rtl/            Verilog sintetizable
  core/           etapas, ALU, banco de registros, forwarding, hazards, latches
  mem/            memoria de programa e instrucciones (BRAM)
  uart/           uart_rx, uart_tx, generador de baudios
  debug/          debug_unit (FSM de comandos)
  top.v           top level
tb/             testbenches (uno por modulo, autoverificantes)
sim/            salidas de simulacion (ignorado por git)
scripts/        create_project.tcl, build_bitstream.tcl
constraints/    nexys4.xdc
docs/           protocolo_uart.md, decisiones.md, diagramas
sw/             ensamblador y CLI en Python
  programas/      programas .asm de prueba
build/          proyecto de Vivado (generado, ignorado por git)
reports/        timing y utilizacion (generado)
```

## Estado

- [x] **Fase 0 — Toolchain.** Repo, scripts, XDC, heartbeat en la placa.
- [ ] **Fase 1 — UART loopback.** Un byte va y vuelve.
- [ ] **Fase 2 — Debug Unit esqueleto.** Dump de un banco de registros falso.
- [ ] **Fase 3 — Core incremental.** addi → tipo R → forwarding → stalls →
      loads/stores → branches → jal/jalr/lui.
- [ ] **Fase 4 — Ensamblador.**
- [ ] **Fase 5 — Integracion.** Carga de programa, modo continuo, paso a paso, HALT.
- [ ] **Fase 6 — Timing.** Camino critico, Clock Wizard, metricas.

## Documentos

- [`docs/protocolo_uart.md`](docs/protocolo_uart.md) — contrato PC ↔ FPGA.
  Ninguna linea de la Debug Unit se escribe antes de que esto este acordado.
- [`docs/decisiones.md`](docs/decisiones.md) — decisiones de diseno y preguntas
  del TP.
