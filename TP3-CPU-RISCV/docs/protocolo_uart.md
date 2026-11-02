# Protocolo UART — contrato PC ↔ FPGA

**Estado: v1.0 (Implementado en `rtl/debug_unit/debug_unit.v`).** Este archivo
define el contrato binario entre la FPGA y el software de la PC (CLI/GUI/TUI).

---

## 1. Capa física

| Parámetro | Valor | Por qué |
|---|---|---|
| Baud rate | 115200 | 9600 hace que un dump de 128 B tarde ~130 ms. En modo paso a paso eso es inusable. |
| Formato | 8N1 (8 datos, sin paridad, 1 stop) | Estándar, con sobremuestreo 16x (`DVSR = 54` a 100 MHz, error +0.47%). |
| Control de flujo | Ninguno | Sin CTS/RTS. |
| Puerto en la PC | `COMx` (Windows) / `/dev/ttyUSB0` (Linux) | Cable USB-UART integrado en Nexys 4. |

**Endianness:** todos los valores multi-byte viajan en **little-endian**
(byte menos significativo primero), igual que la memoria del procesador.
Un `0xDEADBEEF` se transmite como `EF BE AD DE`.

**Instrucción de parada (`HALT`):** se utiliza la instrucción estándar de RV32I
`ebreak` (`0x00100073`). Al decodificarse en la etapa ID, congela el PC, anula
la instrucción posterior en IF/ID y permite que las instrucciones previas en
EX/MEM/WB completen su ejecución hasta dejar los 4 latches vacíos (`valid = 0`).

---

## 2. Reglas generales

1. **La FPGA nunca habla si no le preguntan**, con una sola excepción: el
   evento asíncrono `HALTED` (`0xF1`) al finalizar `RUN`.
2. **Todo comando recibe respuesta.** Si un comando no genera datos, responde
   `ACK` (`0xA5`).
3. **Ningún dump es válido mientras el core corre en modo continuo.** `RUN`
   responde `ACK` al instante y envía `HALTED` recién cuando el pipeline quedó
   completamente vacío.
4. **Byte desconocido o comando inválido en el estado actual → `NAK` (`0x5A`)**
   y la FSM vuelve a `IDLE` sin perder sincronismo de trama.

---

## 3. Comandos PC → FPGA

| Byte | Nombre | Payload que sigue | Respuesta |
|------|--------|-------------------|-----------|
| `0x01` | `RESET` | — | `ACK` (`0xA5`) tras resetear PC, registros, latches y limpiar DMEM |
| `0x02` | `LOAD_PROG` | 2 B: cantidad `N` de palabras (LE), luego `N×4` B (LE) | `ACK` (`0xA5`) tras escribir IMEM y limpiar estado (`NAK` si inválido) |
| `0x10` | `RUN` | — | `ACK` (`0xA5`), y al vaciar el pipeline tras `ebreak`: `HALTED` (`0xF1`) |
| `0x11` | `STEP` | — | `ACK` (`0xA5`) tras avanzar 1 ciclo de clock (`HALTED` `0xF1` si ya terminó) |
| `0x20` | `DUMP_REGS` | — | 128 B (`32` registros × 4 B, de `x0` a `x31`, LE) |
| `0x21` | `DUMP_LATCHES` | — | 72 B (`18` palabras de 32 bits, LE — ver §4) |
| `0x22` | `DUMP_DMEM` | 2 B `offset` (palabra, LE) + 2 B `cantidad` (LE) | `cantidad×4` B (LE) (`NAK` si excede 256 palabras o `cantidad=0`) |
| `0x23` | `DUMP_PC` | — | 4 B (`PC` actual, LE) |
| `0x24` | `STATUS` | — | 1 B de flags (§5) |
| `0x25` | `DUMP_DMEM_USED` | — | 2 B `K` (palabras usadas, LE) + `K × (2 B word_addr + 4 B data)` (LE) |

---

## 4. Formato del dump de latches (`0x21` — 72 bytes / 18 palabras de 32 bits)

Los cuatro bloques se transmiten en orden **IF/ID, ID/EX, EX/MEM, MEM/WB**,
alineados a palabras de 32 bits en little-endian (`struct.unpack('<18I', buf)`):

| Índice Palabra | Bytes | Latch | Contenido |
|---|---|---|---|
| `0` | `0..3` | **IF/ID** | `o_pc` (`[31:0]`) |
| `1` | `4..7` | **IF/ID** | `o_pc_plus_4` (`[31:0]`) |
| `2` | `8..11` | **IF/ID** | `o_instruction` (`[31:0]`) |
| `3` | `12..15` | **IF/ID** | `[0]=valid`, `[31:1]=0` |
| `4` | `16..19` | **ID/EX** | `o_pc` (`[31:0]`) |
| `5` | `20..23` | **ID/EX** | `o_pc_plus_4` (`[31:0]`) |
| `6` | `24..27` | **ID/EX** | `o_rs1_data` (`[31:0]`) |
| `7` | `28..31` | **ID/EX** | `o_rs2_data` (`[31:0]`) |
| `8` | `32..35` | **ID/EX** | `o_imm` (`[31:0]`) |
| `9` | `36..39` | **ID/EX** | `[4:0]=rs1`, `[9:5]=rs2`, `[14:10]=rd`, `[17:15]=funct3`, `[18]=funct7_5`, `[21:19]=alu_op`, `[22]=alu_src`, `[23]=mem_read`, `[24]=mem_write`, `[25]=reg_write`, `[26]=mem_to_reg`, `[27]=wb_jump`, `[28]=valid`, `[31:29]=0` |
| `10` | `40..43` | **EX/MEM** | `o_alu_result` (`[31:0]`) |
| `11` | `44..47` | **EX/MEM** | `o_rs2_data` (`[31:0]`) |
| `12` | `48..51` | **EX/MEM** | `o_pc_plus_4` (`[31:0]`) |
| `13` | `52..55` | **EX/MEM** | `[4:0]=rd`, `[7:5]=funct3`, `[8]=mem_read`, `[9]=mem_write`, `[10]=reg_write`, `[11]=mem_to_reg`, `[12]=wb_jump`, `[13]=valid`, `[31:14]=0` |
| `14` | `56..59` | **MEM/WB** | `o_read_data` (`[31:0]`) |
| `15` | `60..63` | **MEM/WB** | `o_alu_result` (`[31:0]`) |
| `16` | `64..67` | **MEM/WB** | `o_pc_plus_4` (`[31:0]`) |
| `17` | `68..71` | **MEM/WB** | `[4:0]=rd`, `[5]=reg_write`, `[6]=mem_to_reg`, `[7]=wb_jump`, `[8]=valid`, `[31:9]=0` |

---

## 5. Respuestas y eventos FPGA → PC

| Byte | Nombre | Significado |
|------|--------|-------------|
| `0xA5` | `ACK` | Comando aceptado y completado |
| `0x5A` | `NAK` | Comando desconocido, o inválido en el estado actual |
| `0xF1` | `HALTED` | El programa terminó (`ebreak`) **y el pipeline quedó vacío** |

### Byte de STATUS (`0x24`)

| Bit | Nombre | Significado |
|-----|--------|-------------|
| 0 | `running` | El core está ejecutando en modo continuo |
| 1 | `halted` | Se detectó `ebreak` y los 4 latches del pipeline están vacíos |
| 2 | `draining` | Se detectó `ebreak` pero aún quedan instrucciones previas drenando |
| 3 | `prog_loaded` | Hay un programa cargado dinámicamente en `InstructionMemory` |
| 4–7 | reservados | En `0` |
