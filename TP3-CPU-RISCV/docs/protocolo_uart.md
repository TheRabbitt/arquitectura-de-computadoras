# Protocolo UART — contrato PC ↔ FPGA

**Estado: BORRADOR v0.1.** Este archivo es el contrato entre el equipo de
Verilog y el equipo de Python. Antes de escribir la Debug Unit tiene que estar
acordado y firmado por los dos. Cualquier cambio posterior se versiona acá
arriba y se avisa: un cambio silencioso en este archivo cuesta un día de
debugging a la otra mitad del equipo.

---

## 1. Capa física

| Parámetro | Valor | Por qué |
|---|---|---|
| Baud rate | 115200 | 9600 hace que un dump de 128 B tarde ~130 ms. En modo paso a paso eso es inusable. |
| Formato | 8N1 (8 datos, sin paridad, 1 stop) | Estándar, y es lo que espera cualquier terminal. |
| Control de flujo | Ninguno | CTS/RTS existen en la placa pero complican la FSM. Si aparecen bytes perdidos en dumps largos, reconsiderar. |
| Puerto en la PC | `COMx` (Windows) / `/dev/ttyUSB0` (Linux) | Es el mismo cable USB de programación. |

**Endianness:** todos los valores multi-byte viajan en **little-endian**
(byte menos significativo primero), igual que la memoria del procesador.
Un `0xDEADBEEF` se transmite como `EF BE AD DE`.

**Datos crudos, no ASCII.** Mandamos los bytes binarios, no texto hexadecimal.
Es la mitad de bytes y le ahorra el parseo a la FSM. La conversión a algo
legible es responsabilidad del software de la PC.

---

## 2. Reglas generales

1. **La FPGA nunca habla si no le preguntan**, con una sola excepción: el
   evento `HALTED` (§5).
2. **Todo comando recibe respuesta.** Si un comando no genera datos, responde
   `ACK`. Así el software siempre sabe si el comando llegó.
3. **Ningún dump es válido antes de que el pipeline esté drenado.** El
   comando `RUN` responde `ACK` al instante (arranqué) y `HALTED` mucho
   después (terminé de verdad). Pedir un dump entre medio devuelve datos
   inconsistentes. Ver `docs/decisiones.md`, decisión D-04.
4. **Byte desconocido → `NAK` y la FSM vuelve a IDLE.** Nunca se cuelga
   esperando un payload que no va a llegar.
5. **El software de la PC usa timeouts** en cada lectura (sugerido: 1 s).

---

## 3. Comandos PC → FPGA

| Byte | Nombre | Payload que sigue | Respuesta |
|------|--------|-------------------|-----------|
| `0x01` | `RESET` | — | `ACK` |
| `0x02` | `LOAD_PROG` | 2 B: cantidad N de instrucciones, luego N×4 B | `ACK` al final |
| `0x10` | `RUN` | — | `ACK`, y más tarde `HALTED` |
| `0x11` | `STEP` | — | `ACK` cuando avanzó 1 ciclo |
| `0x20` | `DUMP_REGS` | — | 128 B (32 registros × 4 B, de x0 a x31) |
| `0x21` | `DUMP_LATCHES` | — | ver §4 |
| `0x22` | `DUMP_DMEM` | 2 B offset (palabra) + 2 B cantidad | cantidad×4 B |
| `0x23` | `DUMP_PC` | — | 4 B |
| `0x24` | `STATUS` | — | 1 B de flags (§5) |

### Notas por comando

- **`RESET`** deja el sistema en el mismo estado que después de un power-on.
  Qué implica exactamente eso es la decisión D-02 y está sin cerrar.
- **`LOAD_PROG`** solo se acepta con el core detenido. Si el core está
  corriendo, responde `NAK`. La escritura entra por el segundo puerto de la
  BRAM de programa.
- **`STEP`** ejecuta **un ciclo de reloj del core**, no una instrucción. Con
  el pipeline lleno, un ciclo hace avanzar cinco instrucciones a la vez;
  eso es exactamente lo que la cátedra quiere que se vea.
- **`DUMP_DMEM`** pide un rango en vez de la memoria entera. Volcar 1024
  palabras a 115200 baudios son ~350 ms y casi siempre sobran.

---

## 4. Formato del dump de latches (`0x21`)

**PENDIENTE.** No se puede completar hasta tener los latches diseñados.
Estructura acordada: los cuatro bloques en orden IF/ID, ID/EX, EX/MEM, MEM/WB,
cada uno redondeado hacia arriba a un múltiplo de 4 bytes, con los bits sin
usar en cero.

| Latch | Campos | Bits | Bytes en el stream |
|---|---|---|---|
| IF/ID  | pc, instr, valid | TBD | TBD |
| ID/EX  | TBD | TBD | TBD |
| EX/MEM | TBD | TBD | TBD |
| MEM/WB | TBD | TBD | TBD |

Cuando se llene esta tabla, generarla desde un único lugar (por ejemplo un
`.json` que lea tanto el generador de Verilog como el parser de Python) para
que no puedan desincronizarse.

---

## 5. Respuestas y eventos FPGA → PC

| Byte | Nombre | Significado |
|------|--------|-------------|
| `0xA5` | `ACK` | Comando aceptado y completado |
| `0x5A` | `NAK` | Comando desconocido, o inválido en el estado actual |
| `0xF1` | `HALTED` | El programa terminó **y el pipeline quedó vacío** |

Los valores `0xA5` y `0x5A` se eligieron por ser complementarios bit a bit:
un cable ruidoso o un baud rate mal configurado difícilmente convierta uno en
el otro sin que se note.

### Byte de STATUS (`0x24`)

| Bit | Nombre | Significado |
|-----|--------|-------------|
| 0 | `running` | El core está ejecutando en modo continuo |
| 1 | `halted` | Se detectó HALT y el pipeline está drenado |
| 2 | `draining` | Se detectó HALT pero todavía quedan instrucciones adentro |
| 3 | `prog_loaded` | Hay un programa cargado en la memoria de instrucciones |
| 4–7 | reservados | En 0 |

El bit `draining` es el que evita el bug más común de este proyecto: pedir el
dump apenas se detecta el HALT y leer registros viejos.

---

## 6. Secuencias típicas

**Cargar y correr un programa**

```
PC  -> 0x01                          RESET
FPGA-> 0xA5                          ACK
PC  -> 0x02  05 00  <20 bytes>       LOAD_PROG, 5 instrucciones
FPGA-> 0xA5                          ACK
PC  -> 0x10                          RUN
FPGA-> 0xA5                          ACK  (arranqué)
        ... el core ejecuta ...
FPGA-> 0xF1                          HALTED (pipeline vacío)
PC  -> 0x20                          DUMP_REGS
FPGA-> <128 bytes>
```

**Modo paso a paso**

```
PC  -> 0x11        STEP
FPGA-> 0xA5        ACK
PC  -> 0x23        DUMP_PC       -> 4 B
PC  -> 0x21        DUMP_LATCHES  -> N B
PC  -> 0x20        DUMP_REGS     -> 128 B
        ... repetir ...
```

Si esto resulta lento en la práctica, la optimización obvia es un comando
`STEP_AND_DUMP` que devuelva todo junto. **No lo implementen todavía**: primero
que funcione, después que sea rápido.

---

## 7. Preguntas abiertas

- [ ] ¿`RUN` debería mandar el dump completo solo, sin que se lo pidan?
- [ ] ¿Hace falta un comando para leer/escribir un registro puntual (útil para
      breakpoints, no exigido por la consigna)?
- [ ] ¿Checksum al final de cada dump? Encarece la FSM; decidir después de ver
      si aparece corrupción real a 115200.
