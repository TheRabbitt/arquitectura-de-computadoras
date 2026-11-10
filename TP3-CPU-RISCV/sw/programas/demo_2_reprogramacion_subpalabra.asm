# ==============================================================================
# Programa 2: Reprogramación Dinámica por UART y Accesos de Subpalabra (LUI/LH/LHU)
# ==============================================================================
# Verifica:
#   1. Reprogramación en caliente de la Memoria de Instrucciones sin resintetizar
#   2. Construcción de constante de 32 bits con LUI + ORI (x10 = 0x12345678)
#   3. Almacenamiento en Memoria de Datos (DMEM[2], dirección de byte 0x08)
#   4. Lectura de media palabra inferior [15:0] con LH  (x11 = 0x00005678)
#   5. Lectura de media palabra superior [31:16] con LHU (x12 = 0x00001234)
#   6. Lectura de byte individual [7:0] con LBU          (x13 = 0x00000078)
#   7. Parada limpia con EBREAK y drenado completo del pipeline
# ==============================================================================

    lui  x10, 0x12345       # x10 = 0x12345000
    ori  x10, x10, 0x678    # x10 = 0x12345000 | 0x00000678 = 0x12345678
    sw   x10, 8(x0)         # DMEM[2] (dir 0x08) = 0x12345678
    lh   x11, 8(x0)         # x11 = media palabra baja [15:0]  = 0x00005678 (22136)
    lhu  x12, 10(x0)        # x12 = media palabra alta [31:16] = 0x00001234 (4660)
    lbu  x13, 8(x0)         # x13 = byte 0 sin signo [7:0]     = 0x00000078 (120)
    ebreak                  # Fin del programa -> Drena pipeline y envía HALTED (0xF1)
