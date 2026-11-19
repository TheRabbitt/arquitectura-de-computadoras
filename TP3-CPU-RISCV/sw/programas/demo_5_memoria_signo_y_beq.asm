# ==============================================================================
# Programa 5: Subpalabras con Signo Negativo (LH/LB/SH/SB), BEQ y Load -> Branch
# ==============================================================================
# Cubre todas las operaciones de memoria y riesgo de salto faltantes en demo_1..demo_3:
#   - sh en offset +0 (baja) y +2 (alta) sin pisar la otra media palabra
#   - sb en offsets no nulos (+1 y +3)
#   - lh y lb con MSB=1 (extienden con 1s) vs lhu y lbu (extienden con 0s)
#   - Riesgo Load -> Branch (2 ciclos de stall automático) + beq no tomado y tomado
# ==============================================================================

    addi x5,  x0, -1         # x5  = 0xFFFFFFFF
    addi x6,  x0, -126       # x6  = 0xFFFFFF82 (byte=0x82 y half=0xFF82, ambos con MSB=1)
    sh   x6,  0(x0)          # DMEM[0][15:0]  = 0xFF82 (sh en offset +0)
    sh   x5,  2(x0)          # DMEM[0][31:16] = 0xFFFF (sh en offset +2 -> DMEM[0]=0xFFFFFF82)
    sb   x6,  5(x0)          # DMEM[1][15:8]  = 0x82   (sb en offset +1)
    sb   x5,  7(x0)          # DMEM[1][31:24] = 0xFF   (sb en offset +3 -> DMEM[1]=0xFF008200)
    lh   x7,  0(x0)          # x7  = 0xFFFFFF82 (-126)  [lh con MSB=1: rellena con 1s]
    lhu  x8,  0(x0)          # x8  = 0x0000FF82 (65410) [lhu misma dir: rellena con 0s]
    lb   x9,  5(x0)          # x9  = 0xFFFFFF82 (-126)  [lb con MSB=1: rellena con 1s]
    lbu  x28, 5(x0)          # x28 = 0x00000082 (130)   [lbu misma dir: rellena con 0s]
    beq  x28, x7, error      # Riesgo Load->Branch (2 stalls) + beq NO tomado (130 != -126)
    beq  x9,  x7, salto_ok   # beq TOMADO (-126 == -126) -> salta y hace FLUSH de error

error:
    addi x29, x0, 99         # Anulada por FLUSH (x29 queda en 0)

salto_ok:
    addi x30, x0, 1          # x30 = 1 (confirma ejecución correcta de ambos beq)
    ebreak                   # Fin del programa -> Drena pipeline y envía HALTED (0xF1)
