# ==============================================================================
# Programa 3: Sumatoria en Bucle y Llamada a Subrutina (Convención ABI RISC-V)
# ==============================================================================
# Respeta estrictamente la convención de llamada ABI de RISC-V:
#   - x5  (t0) : Registro temporal para el contador del bucle (i = 1..4).
#   - x6  (t1) : Registro temporal para el límite del bucle (N = 5).
#   - x8  (s0) : Registro preservado (Saved) para el puntero de memoria (0, 4, 8, 12, 16),
#                ya que su valor debe conservarse intacto tras llamar a la subrutina.
#   - x10 (a0) : Registro de argumento y retorno de función (acumula 1+2+3+4 = 10,
#                entra como parámetro a `sub_duplicar` y vuelve con el retorno = 20).
#   - x1  (ra) : Return Address (guarda PC+4 en JAL y se usa en JALR para retornar).
# ==============================================================================

    addi x5, x0, 1          # x5  (t0) = contador temporal i = 1
    addi x6, x0, 5          # x6  (t1) = límite temporal N = 5 (itera para i = 1, 2, 3, 4)
    addi x10, x0, 0         # x10 (a0) = argumento/acumulador suma = 0
    addi x8, x0, 0          # x8  (s0) = puntero preservado a Memoria de Datos (dir 0x00)

bucle_suma:
    add  x10, x10, x5       # x10 += i (1, 3, 6, 10)
    sw   x10, 0(x8)         # DMEM[x8/4] = suma parcial
    addi x8, x8, 4          # avanza puntero preservado (+4 bytes)
    addi x5, x5, 1          # i++
    bne  x5, x6, bucle_suma # si i != 5, repite el bucle

    # Llamada a función bajo convención ABI:
    # - Argumento de entrada en x10 (a0) = 10
    # - Dirección de retorno en x1  (ra) = PC + 4 (0x0028)
    # - Resultado de retorno en x10 (a0) = 20
    jal  x1, sub_duplicar   # llama a sub_duplicar(x10), guarda retorno en x1 (ra)
    sw   x10, 0(x8)         # guarda valor retornado x10 (20) usando x8 preservado (DMEM[4])
    ebreak                  # Fin del programa -> Drena pipeline y envía HALTED (0xF1)

sub_duplicar:
    slli x10, x10, 1        # x10 = x10 << 1 = 20 (duplica el argumento y lo deja en x10)
    jalr x0, 0(x1)          # retorna al llamador usando x1 (ra)
