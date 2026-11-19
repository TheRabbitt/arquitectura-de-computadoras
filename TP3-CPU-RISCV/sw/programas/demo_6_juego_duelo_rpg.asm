# ==============================================================================
# Programa 6: Mini-Juego RPG — "Duelo en la Mazmorra" (Héroe vs. Monstruo)
# ==============================================================================
# Demostración integral de las 32 instrucciones RV32I de la consigna (+ EBREAK)
# en una aplicación real fácil de depurar y explicar paso a paso en la GUI.
#
# Mecánica del juego (combate por turnos determinista con dado PRNG):
#   En cada turno:
#     1. El Héroe llama a la subrutina `tirar_dado` (xorshift) -> dado 1..8.
#     2. Calcula su ataque: dado + (Energia >> 2) + (1 << turno).
#        Si dado >= 6, aplica GOLPE CRÍTICO (ataque x 2).
#     3. Resta la Defensa del Monstruo (daño mínimo garantizado = 1).
#     4. Actualiza HP del Monstruo, alterna su estado (Furia/Herido) y, si
#        el daño supera su defensa, le rompe el Escudo (Defensa -> 0).
#     5. Suma Score (+8 por punto de daño) y guarda un "replay" del turno en DMEM.
#     6. Si HP_Monstruo <= 0 -> VICTORIA (0xCAFE0001).
#     7. Si sigue vivo, el Monstruo contraataca (-16 mitigado con srai y sra
#        a -4 de daño) y el Héroe gasta 4 de Energía.
#
# Mapa de Memoria de Datos (DMEM) para inspeccionar en la exposición:
#   - DMEM[0] (0x00) Héroe    : [7:0]   HP_Heroe (signed byte, inicio = 30)
#                               [15:8]  Energia  (unsigned byte, inicio = 16)
#                               [31:16] Score    (unsigned half, inicio = 0)
#   - DMEM[1] (0x04) Monstruo : [15:0]  HP_Monstruo (signed half, inicio = 32)
#                               [23:16] Defensa     (unsigned byte, inicio = 6)
#                               [31:24] Flags (b0=Furia, b1=Escudo, b2=Herido)
#   - DMEM[2] (0x08) PRNG     : Semilla actual del dado (inicio = 0x00000026)
#   - DMEM[3] (0x0C) Resultado: 0xCAFE0001 (VICTORIA) o 0xDEAD0000 (DERROTA)
#   - DMEM[4..6] (0x10..0x18) : Log por turno [31:24]=turno | [23:16]=dado |
#                                             [15:8]=daño   | [7:0]=HP_Monstruo
#
# Resultados esperados al finalizar (3 turnos exactos -> VICTORIA):
#   - DMEM[0] = 0x01080816 (Score=264, Energia=8, HP_Heroe=22)
#   - DMEM[1] = 0x0500FFFF (Flags=0x05 escudo roto, Defensa=0, HP_Monstruo=-1)
#   - DMEM[2] = 0x000050CD (Semilla PRNG final)
#   - DMEM[3] = 0xCAFE0001 (VICTORIA!)
#   - DMEM[4] = 0x0104041C (Turno 1: Dado=4, Daño=4,  HP_Mon=28)
#   - DMEM[5] = 0x02020319 (Turno 2: Dado=2, Daño=3,  HP_Mon=25)
#   - DMEM[6] = 0x03061AFF (Turno 3: Dado=6 [CRÍTICO], Daño=26, HP_Mon=-1)
#   - x10(a0) = 0xFFFFFFFF (-1, lectura con signo `lh` del HP final del Monstruo)
#   - x31(t6) = 0xCAFE0001 (Firma de victoria armada con `lui` + `ori`)
# ==============================================================================

    # --------------------------------------------------------------------------
    # 1. Inicialización del estado del juego en Memoria de Datos (DMEM)
    # --------------------------------------------------------------------------
    addi x5,  x0, 30            # HP_Heroe = 30 (0x1E)
    sb   x5,  0(x0)             # DMEM[0][7:0]   = 0x1E
    addi x5,  x0, 16            # Energia = 16 (0x10)
    sb   x5,  1(x0)             # DMEM[0][15:8]  = 0x10
    sh   x0,  2(x0)             # DMEM[0][31:16] = 0x0000 (Score = 0)

    addi x5,  x0, 32            # HP_Monstruo = 32 (0x0020)
    sh   x5,  4(x0)             # DMEM[1][15:0]  = 0x0020
    addi x5,  x0, 6             # Defensa = 6 (0x06)
    sb   x5,  6(x0)             # DMEM[1][23:16] = 0x06
    addi x5,  x0, 2             # Flags = 0x02 (Escudo activo, Furia apagada)
    sb   x5,  7(x0)             # DMEM[1][31:24] = 0x02

    addi x5,  x0, 0x26          # Semilla inicial PRNG = 38 (genera dados: 4, 2, 6)
    sw   x5,  8(x0)             # DMEM[2] = 0x00000026

    # Registros preservados (convención ABI: s0, s1, s2)
    addi x8,  x0, 16            # x8  (s0) = puntero al Log de turnos (dir 0x10 = DMEM[4])
    addi x9,  x0, 1             # x9  (s1) = contador de turno actual (1..5)
    addi x18, x0, 6             # x18 (s2) = límite de turnos (máximo 5 turnos)

    # --------------------------------------------------------------------------
    # 2. Bucle Principal de Combate por Turnos
    # --------------------------------------------------------------------------
bucle_turno:
    # 2.1 Tirar el dado (subrutina ABI: retorna dado 1..8 en x10 / a0)
    jal  x1, tirar_dado         # guarda PC+4 en x1 (ra) y salta a `tirar_dado`

    # 2.2 Calcular ataque del Héroe: dado + (Energia >> 2) + (1 << turno)
    lbu  x11, 1(x0)             # x11 = Energia del Héroe (sin signo)
    addi x5,  x0, 2             # desplazamiento = 2
    srl  x12, x11, x5           # x12 = Energia >> 2 (bonus por energía, shift lógico reg)
    addi x6,  x0, 1             # base = 1
    sll  x13, x6, x9            # x13 = 1 << turno (bonus de combo: 2, 4, 8)
    add  x14, x10, x12          # x14 = dado + bonus_energia
    add  x14, x14, x13          # x14 = ataque bruto

    # Comprobar Golpe Crítico (dado >= 6 -> !(dado < 6) sin signo)
    sltiu x5, x10, 6            # x5 = 1 si dado < 6, 0 si dado >= 6
    bne  x5,  x0, sin_critico   # si no es crítico, salta el multiplicador
    slli x14, x14, 1            # ¡GOLPE CRÍTICO! duplica el ataque (x2)

sin_critico:
    # 2.3 Restar Defensa del Monstruo y asegurar daño mínimo = 1
    lbu  x15, 6(x0)             # x15 = Defensa del Monstruo
    sub  x14, x14, x15          # x14 = daño neto = ataque - defensa
    slti x5,  x14, 1            # x5 = 1 si daño < 1 (con signo)
    beq  x5,  x0, danio_ok      # si daño >= 1, continúa
    addi x14, x0, 1             # daño mínimo garantizado = 1

danio_ok:
    # 2.4 Aplicar daño al HP del Monstruo (16 bits con signo)
    lh   x28, 4(x0)             # x28 = HP_Monstruo (extensión de signo)
    sub  x28, x28, x14          # HP_Monstruo -= daño
    sh   x28, 4(x0)             # guarda nuevo HP_Monstruo en DMEM[1][15:0]

    # 2.5 Actualizar Flags de estado del Monstruo (bitmask)
    lbu  x29, 7(x0)             # x29 = Flags actuales
    xori x29, x29, 1            # alterna bit 0 (Furia ON/OFF cada turno)
    ori  x29, x29, 4            # activa bit 2 (Herido en combate)
    sltu x5,  x15, x14          # ¿Defensa < Daño? (sin signo) -> rompe Escudo
    beq  x5,  x0, mantener_escudo
    addi x6,  x0, 5             # máscara 0b101 (apaga bit 1 = Escudo roto)
    and  x29, x29, x6           # limpia bit de Escudo
    sb   x0,  6(x0)             # Defensa del Monstruo cae a 0

mantener_escudo:
    sb   x29, 7(x0)             # guarda Flags actualizados en DMEM[1][31:24]

    # 2.6 Actualizar Score (+8 pts por daño) y guardar Log del turno en DMEM
    lhu  x30, 2(x0)             # x30 = Score actual (16 bits sin signo)
    slli x5,  x14, 3            # puntos = daño * 8
    add  x30, x30, x5           # Score += puntos
    sh   x30, 2(x0)             # guarda Score en DMEM[0][31:16]

    # Empaquetar Log: [31:24]=turno | [23:16]=dado | [15:8]=daño | [7:0]=HP_Mon
    slli x5,  x9,  24           # turno << 24
    slli x6,  x10, 16           # dado  << 16
    or   x5,  x5,  x6           # combina turno y dado
    slli x6,  x14, 8            # daño  << 8
    or   x5,  x5,  x6           # combina daño
    andi x6,  x28, 0xFF         # 8 bits bajos de HP_Monstruo
    or   x5,  x5,  x6           # palabra completa de Log
    sw   x5,  0(x8)             # DMEM[log_ptr] = log del turno
    addi x8,  x8,  4            # avanza puntero de Log (+4 bytes)

    # 2.7 Verificar si el Monstruo fue derrotado (HP_Monstruo < 1 con signo)
    addi x5,  x0, 1             # umbral = 1
    slt  x6,  x28, x5           # x6 = 1 si HP_Monstruo <= 0 (detecta negativos!)
    bne  x6,  x0, victoria      # si cayó el Monstruo -> ¡VICTORIA!

    # 2.8 Contraataque del Monstruo (aritmética con signo: srai y sra)
    addi x5,  x0, -16           # golpe base del Monstruo = -16 (0xFFFFFFF0)
    srai x5,  x5, 1             # -16 >> 1 = -8 (0xFFFFFFF8, shift aritmético imm)
    addi x6,  x0, 1             # mitigación por armadura del Héroe = 1
    sra  x5,  x5, x6            # -8  >> 1 = -4 (0xFFFFFFFC, shift aritmético reg)

    lb   x7,  0(x0)             # x7 = HP_Heroe (byte con signo)
    add  x7,  x7, x5            # HP_Heroe += (-4)
    sb   x7,  0(x0)             # guarda nuevo HP_Heroe en DMEM[0][7:0]

    addi x11, x11, -4           # gasta 4 de Energía
    sb   x11, 1(x0)             # guarda nueva Energía en DMEM[0][15:8]

    # Verificar si el Héroe cayó (HP_Heroe < 1)
    slti x6,  x7, 1             # x6 = 1 si HP_Heroe <= 0
    bne  x6,  x0, derrota       # si cayó el Héroe -> DERROTA

    # Siguiente turno
    addi x9,  x9, 1             # turno++
    bne  x9,  x18, bucle_turno  # repite mientras turno < 6

    # --------------------------------------------------------------------------
    # 3. Cierre de Partida: DERROTA o VICTORIA
    # --------------------------------------------------------------------------
derrota:
    lui  x31, 0xDEAD0           # x31 = 0xDEAD0000 (firma de derrota)
    sw   x31, 12(x0)            # DMEM[3] = 0xDEAD0000
    jal  x0, fin_juego          # salto incondicional al final

victoria:
    lh   x10, 4(x0)             # x10 = HP final del Monstruo (-1 = 0xFFFFFFFF)
    lui  x31, 0xCAFE0           # x31 = 0xCAFE0000 (parte alta de firma)
    ori  x31, x31, 1            # x31 = 0xCAFE0001 (firma de VICTORIA!)
    sw   x31, 12(x0)            # DMEM[3] = 0xCAFE0001

fin_juego:
    ebreak                      # Fin del juego -> Drena pipeline y envía HALTED

    # --------------------------------------------------------------------------
    # 4. Subrutina: tirar_dado (PRNG xorshift -> retorna 1..8 en x10 / a0)
    # --------------------------------------------------------------------------
tirar_dado:
    lw   x5,  8(x0)             # carga semilla actual desde DMEM[2]
    slli x6,  x5, 3             # x6 = semilla << 3
    xor  x5,  x5, x6            # x5 = semilla ^ (semilla << 3)
    srli x6,  x5, 2             # x6 = x5 >> 2 (shift lógico sin signo)
    xor  x5,  x5, x6            # x5 = x5 ^ (x5 >> 2)
    sw   x5,  8(x0)             # guarda nueva semilla en DMEM[2]
    andi x10, x5, 7             # x10 = x5 & 0x07 (rango 0..7)
    addi x10, x10, 1            # x10 (a0) = dado en rango 1..8
    jalr x0,  0(x1)             # retorna al llamador usando x1 (ra)
