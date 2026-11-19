# ==============================================================================
# Programa 4: ALU Completa — Resta, Shifts (SRA/SRL/SLL), Comparaciones y Lógica
# ==============================================================================
# Cubre todas las operaciones de la ALU no ejercitadas en demo_1..demo_3:
#   - Resta con resultado negativo (sub)
#   - Shifts aritméticos con MSB=1 (rellenan con 1s: srai, sra) vs lógicos (0s: srli, srl) y sll
#   - Comparaciones con signo (slt, slti) vs sin signo (sltu, sltiu) sobre número negativo
#   - Lógica bit a bit (and, andi, or, xor, xori)
# ==============================================================================

    addi  x5,  x0, 4         # x5  = 4 (operando y cantidad de desplazamiento)
    addi  x6,  x0, 12        # x6  = 12 (0x0000000C)
    sub   x7,  x5, x6        # x7  = 4 - 12 = -8 (0xFFFFFFF8, MSB=1)
    srai  x28, x7, 1         # x28 = -8 >> 1 = -4 (0xFFFFFFFC) [aritmético: rellena con 1s]
    srli  x29, x7, 4         # x29 = 0x0FFFFFFF [lógico: rellena con 0s]
    sra   x30, x7, x5        # x30 = -8 >> 4 = -1 (0xFFFFFFFF) [sra por registro]
    srl   x31, x30, x5       # x31 = 0x0FFFFFFF [srl por registro]
    sll   x8,  x5, x5        # x8  = 4 << 4 = 64 (0x00000040) [sll por registro]
    slt   x9,  x7, x5        # x9  = 1 (-8 < 4 con signo -> verdadero)
    sltu  x18, x7, x5        # x18 = 0 (0xFFFFFFF8 < 4 sin signo -> falso)
    slti  x19, x7, 0         # x19 = 1 (-8 < 0 con signo -> verdadero)
    sltiu x20, x5, 2         # x20 = 0 (4 < 2 sin signo -> falso)
    andi  x21, x6, 10        # x21 = 12 & 10 = 8 (0x00000008)
    and   x22, x6, x5        # x22 = 12 & 4  = 4 (0x00000004)
    or    x23, x5, x21       # x23 = 4 | 8   = 12 (0x0000000C)
    xor   x24, x6, x5        # x24 = 12 ^ 4  = 8 (0x00000008)
    xori  x25, x0, -1        # x25 = 0 ^ -1  = -1 (0xFFFFFFFF)
    ebreak                   # Fin del programa -> Drena pipeline y envía HALTED (0xF1)
