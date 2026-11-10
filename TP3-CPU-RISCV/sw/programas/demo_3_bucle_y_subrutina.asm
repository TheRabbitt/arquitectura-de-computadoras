# ==============================================================================
# Programa 3: Sumatoria en Bucle con Saltos Condicionales y Llamada a Subrutina
# ==============================================================================
# Calcula la suma 1 + 2 + 3 + 4 = 10 usando un bucle con BNE, guarda cada
# resultado parcial en la Memoria de Datos, invoca una subrutina con JAL/JALR
# que duplica el resultado final (20) y detiene el procesador con EBREAK.
# ==============================================================================

    addi x1, x0, 1          # x1 = contador i = 1
    addi x2, x0, 5          # x2 = límite N = 5 (itera para i = 1, 2, 3, 4)
    addi x3, x0, 0          # x3 = acumulador suma = 0
    addi x4, x0, 0          # x4 = puntero de byte a Memoria de Datos (0, 4, 8, 12)

bucle_suma:
    add  x3, x3, x1         # suma += i
    sw   x3, 0(x4)          # DMEM[x4/4] = suma parcial (1, 3, 6, 10)
    addi x4, x4, 4          # avanza puntero de memoria (+4 bytes)
    addi x1, x1, 1          # i++
    bne  x1, x2, bucle_suma # si i != 5, repite el bucle

    # Llamada a subrutina para duplicar el acumulador (x3 = 10 -> x10 = 20)
    jal  ra, sub_duplicar   # guarda dirección de retorno en ra (x1) y salta
    sw   x10, 16(x0)        # DMEM[4] (dir 0x10) = 20 (0x00000014)
    ebreak                  # Fin del programa -> Drena pipeline y envía HALTED (0xF1)

sub_duplicar:
    slli x10, x3, 1         # x10 = x3 << 1 = 20
    jalr x0, 0(ra)          # retorna al llamador
