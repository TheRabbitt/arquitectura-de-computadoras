# ==============================================================================
# Programa 1: Prueba Integral de Forwarding, Riesgo Load-Use, Saltos y Memoria
# ==============================================================================
# Verifica:
#   1. Aritmética inmediata y entre registros con Forwarding EX->EX (x3 = 30)
#   2. Escritura y lectura de palabra completa en Memoria de Datos (DMEM[0] = 30)
#   3. Detección automática de riesgo Load-Use (1 ciclo de stall) + Forwarding MEM->EX (x5 = 35)
#   4. Escritura de byte individual con sb (DMEM[1] = 0x00000023)
#   5. Salto incondicional JAL con etiqueta simbólica y flush de la instrucción especulativa
#   6. Instrucción de parada EBREAK (0x00100073) y vaciado total de los 4 latches
# ==============================================================================

    addi x1, x0, 10         # x1 = 10 (0x0000000A)
    addi x2, x0, 20         # x2 = 20 (0x00000014)
    add  x3, x1, x2         # x3 = x1 + x2 = 30 (0x0000001E) [Forwarding EX/MEM -> EX]
    sw   x3, 0(x0)          # DMEM[0] (dir 0x00) = 30 (0x0000001E)
    lw   x4, 0(x0)          # x4 = DMEM[0] = 30
    addi x5, x4, 5          # x5 = x4 + 5 = 35 (0x00000023) [Riesgo Load-Use: 1 stall + Forwarding MEM/WB -> EX]
    sb   x5, 4(x0)          # DMEM[1] (dir 0x04, byte 0) = 0x23
    jal  x6, salto_ok       # x6 = PC+4 (0x20), salta a salto_ok (PC=0x24)
    addi x7, x0, 99         # Debe ser anulada (FLUSH) por el salto JAL (x7 queda en 0)

salto_ok:
    addi x8, x0, 77         # x8 = 77 (0x0000004D)
    ebreak                  # Fin del programa -> Drena pipeline y envía HALTED (0xF1)
