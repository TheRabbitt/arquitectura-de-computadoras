# ==============================================================================
# Programa 2: Reprogramación Dinámica por UART y Accesos de Subpalabra (Convención ABI)
# ==============================================================================
# Respeta estrictamente la convención de registros ABI de RISC-V:
#   - x0 (zero) : Constante 0 para direccionamiento base.
#   - x8 (s0)   : Variable local preservada donde se construye la constante de 32 bits
#                 (0x12345678) con LUI + ORI y se almacena en memoria con SW.
#   - x5 (t0)   : Registro temporal para cargar la media palabra baja [15:0] con LH.
#   - x6 (t1)   : Registro temporal para cargar la media palabra alta [31:16] con LHU.
#   - x7 (t2)   : Registro temporal para cargar el byte inferior [7:0] con LBU.
# ==============================================================================

    lui  x8, 0x12345        # x8 (s0) = 0x12345000 (variable local)
    ori  x8, x8, 0x678      # x8 (s0) = 0x12345000 | 0x00000678 = 0x12345678
    sw   x8, 8(x0)          # DMEM[2] (dir 0x08) = 0x12345678
    lh   x5, 8(x0)          # x5 (t0) = media palabra baja [15:0]  = 0x00005678 (22136)
    lhu  x6, 10(x0)         # x6 (t1) = media palabra alta [31:16] = 0x00001234 (4660)
    lbu  x7, 8(x0)          # x7 (t2) = byte 0 sin signo [7:0]     = 0x00000078 (120)
    ebreak                  # Fin del programa -> Drena pipeline y envía HALTED (0xF1)
