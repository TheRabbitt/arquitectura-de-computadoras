# Registro de decisiones

La consigna dice tres veces "documenten estas decisiones y su porqué". Este
archivo es esa documentación, y se escribe **mientras** se decide, no la noche
antes de entregar. Cada entrada lleva: qué se decidió, qué alternativas había,
por qué se eligió esa, y qué habría que cambiar si resulta mala.

Estados: `DECIDIDO` · `PROVISORIO` (elegido para avanzar, revisable con datos)
· `PENDIENTE` (no se puede decidir todavía).

---

## Decisiones de arquitectura

### D-01 · Instrucción de HALT — `PENDIENTE`

RV32I no tiene una instrucción de parada. Alternativas:

- **`ebreak`** (`0x00100073`). Es una instrucción real del ISA, pensada
  justamente para devolverle el control a un depurador. El ensamblador no
  necesita inventar mnemónicos y cualquiera que lea el código la reconoce.
- **Opcode propio** (por ejemplo el opcode reservado `0x0B`). Más libre, pero
  el programa deja de ser RV32I válido y no se puede contrastar contra otras
  herramientas.

*Recomendación: `ebreak`.* Justificar en el informe.

**Decisión:** ___
**Fecha:** ___

---

### D-02 · Qué borra exactamente el comando `RESET` — `PENDIENTE`

Esta es la pregunta del TP *"¿es necesario vaciar la memoria? ¿y los
registros? ¿se necesita vaciar el pipeline? ¿y la memoria de programa?"*.
Analizar **cada uno por separado** — la respuesta no es la misma para los
cuatro. El criterio: *¿puede un valor viejo hacer que el programa nuevo dé un
resultado distinto al que daría en una FPGA recién encendida?*

| Elemento | ¿Se vacía? | Justificación | Costo en hardware |
|---|---|---|---|
| Registros x1–x31 | ___ | ___ | ___ |
| Registro x0 | siempre lee 0 **por construcción**, no por inicialización | | |
| Latches del pipeline | ___ | ___ | ___ |
| Memoria de datos | ___ | ___ | ___ |
| Memoria de programa | ___ | ___ | ___ |

Pista para la última fila: pensar qué pasa si el programa nuevo es más corto
que el anterior y qué instrucciones quedan después del HALT.

**Decisión:** ___

---

### D-03 · Dónde se resuelven los saltos — `PENDIENTE`

| Opción | Penalidad | Efecto en el camino crítico |
|---|---|---|
| En ID | 1 ciclo | Comparador + sumador en ID; empeora el camino crítico |
| En EX | 2 ciclos | Reusa la ALU; camino más corto |
| En MEM | 3 ciclos | El más simple, el más lento |

*Recomendación: empezar en EX.* Es el punto medio y no hipoteca el timing
antes de haber medido nada. Anotar el CPI que da cada opción en el programa de
prueba: eso es una métrica concreta para el informe.

**Decisión:** ___

---

### D-04 · Criterio de "pipeline vacío" — `PENDIENTE`

Al detectar HALT hay dos poblaciones de instrucciones adentro del pipeline:
las **anteriores** al HALT, que tienen que completar (drenar), y las
**posteriores** que ya se buscaron, que hay que anular (flush).

- Etapa donde se detecta el HALT: ___
- Cuántas instrucciones posteriores hay que anular: ___
- Criterio para declarar el pipeline vacío: ___

**No usar un contador fijo de 4 ciclos.** Si durante el drenaje ocurre un
stall por load-use, el contador miente. El criterio robusto es drenar mientras
alguno de los bits de *válido* de los cuatro latches siga en 1.

**Decisión:** ___

---

### D-05 · Tamaño y direccionamiento de las memorias — `PENDIENTE`

| | Tamaño | Bits de dirección | Tipo |
|---|---|---|---|
| Memoria de programa | ___ palabras | ___ | BRAM dual port (escribe la Debug Unit, lee IF) |
| Memoria de datos | ___ palabras | ___ | BRAM |

Definirlo temprano: determina el ancho del PC y el formato de `DUMP_DMEM`.

**Decisión:** ___

---

### D-06 · Lectura y escritura del banco de registros en el mismo ciclo — `PENDIENTE`

Cuando WB escribe x5 y al mismo tiempo ID lee x5, ¿ID ve el valor nuevo o el
viejo? Alternativas: escribir en el flanco de bajada, o forwardear
explícitamente de WB a ID. Elegir una y probarla con un testbench dedicado —
este bug es silencioso y aparece recién con programas largos.

**Decisión:** ___

---

## Preguntas del TP

Las siguientes **no se pueden contestar honestamente todavía**. Se responden
con evidencia propia (simulaciones, reportes de Vivado), no con teoría copiada.
Se dejan acá anotadas para no olvidarlas.

### P-01 · ¿Qué pasa si en la memoria no hay una instrucción de parada?

Pistas para investigarlo cuando el core exista: ¿qué instrucción RV32I es
`0x00000000`? ¿Qué hay en las posiciones de memoria que nunca se escribieron?
¿Qué pasa cuando el PC llega al final del espacio direccionable? ¿Cómo se
entera el software de la PC de que el programa "terminó"?

**Responder en la fase:** integración.

### P-02 · ¿Cuál es el camino crítico del sistema?

Sale de `reports/timing_summary.rpt` (`make bit` lo genera solo). Adjuntar el
path concreto, no una descripción genérica.

**Responder en la fase:** timing.

### P-03 · ¿El camino crítico genera skew? ¿Qué consecuencias tiene?

Ojo con el vocabulario: un camino crítico largo **no** genera *skew*
(diferencia en el tiempo de llegada del reloj a distintos flip-flops); genera
*slack negativo*. Vale la pena aclarar la distinción en el informe.

**Responder en la fase:** timing.

### P-04 · ¿Cuál es la frecuencia óptima de funcionamiento?

Sale de iterar: `WNS` del reporte → ajustar el Clock Wizard → resintetizar.
Registrar la tabla de frecuencia vs. WNS, no solo el valor final.

**Responder en la fase:** timing.

---

## Decisiones de proceso

### D-P1 · Vivado no es el editor — `DECIDIDO`

Se escribe en VS Code. Se simula localmente con Icarus Verilog (`make`),
que da un ciclo de iteración de segundos en vez de minutos. Vivado se usa solo
para síntesis, implementación, timing y bitstream.

### D-P2 · El proyecto de Vivado no se commitea — `DECIDIDO`

Se regenera con `scripts/create_project.tcl`. El `.xpr` y las carpetas
`.runs/`, `.cache/`, `.Xil/` son binarios y generados: en git producen
conflictos irresolubles y repos de cientos de megas.

### D-P3 · Todo testbench es autoverificante — `DECIDIDO`

Termina en `TEST PASSED` o `TEST FAILED`, nunca en "mirá las ondas y fijate".
Las ondas son para diagnosticar un fallo, no para detectarlo.
