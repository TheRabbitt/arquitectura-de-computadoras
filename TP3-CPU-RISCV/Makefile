# ---------------------------------------------------------------------------
# Makefile  -  Procesador RISC-V segmentado
#
# Simulacion rapida con Icarus Verilog (WSL / Linux).
# Sintesis e implementacion con Vivado.
#
#   make find-vivado -> busca vivado.bat en los discos montados
#   make check-tools -> verifica que este todo en su lugar
#   make             -> corre todos los testbenches
#   make top_tb      -> corre un testbench puntual
#   make wave TB=top_tb -> abre las ondas en GTKWave
#   make lint        -> chequeo estatico con Verilator
#   make project     -> regenera el proyecto de Vivado
#   make bit         -> sintetiza, implementa y genera el bitstream
#   make clean
#
# Dependencias:  sudo apt install iverilog gtkwave verilator
# ---------------------------------------------------------------------------

# ===========================================================================
# >>> CONFIGURAR ACA <<<
#
# Ruta al ejecutable de Vivado. Si `make find-vivado` lo encuentra, copiar
# la ruta que imprime, descomentar la linea de abajo y pegarla.
#
# WSL con Vivado de Windows (lo mas comun):
#   VIVADO := /mnt/e/Xilinx/Vivado/2026.1/bin/vivado.bat
#
# Linux nativo: dejar comentado y hacer antes
#   source /tools/Xilinx/Vivado/2026.1/settings64.sh
# ===========================================================================

VIVADO := /mnt/c/AMDDesignTools/2026.1/Vivado/bin/vivado.bat


# --- Autodeteccion (solo se usa si VIVADO quedo vacio arriba) --------------
ifeq ($(strip $(VIVADO)),)
VIVADO := $(shell command -v vivado 2>/dev/null)
endif
ifeq ($(strip $(VIVADO)),)
VIVADO := $(firstword \
  $(wildcard /mnt/*/Xilinx/Vivado/*/bin/vivado.bat) \
  $(wildcard /mnt/*/AMD/Vivado/*/bin/vivado.bat) \
  $(wildcard /mnt/*/Vivado/*/bin/vivado.bat) \
  $(wildcard /mnt/*/Xilinx/*/Vivado/*/bin/vivado.bat))
endif

# --- Herramientas de simulacion --------------------------------------------
IVERILOG := iverilog
VVP      := vvp
IVFLAGS  := -g2012 -Wall -Irtl

RTL := $(wildcard rtl/*.v rtl/*/*.v)
TBS := $(basename $(notdir $(wildcard tb/*_tb.v)))
SIM := sim

.PHONY: all $(TBS) find-vivado check-tools lint wave project bit gui clean help

# ===========================================================================
# Simulacion
# ===========================================================================

all: $(TBS)
	@echo ""
	@echo "== todos los testbenches corrieron =="

$(TBS): %: $(SIM)/%.vvp
	@echo ""
	@echo "---- $@ ----"
	@$(VVP) $(SIM)/$@.vvp

$(SIM)/%.vvp: tb/%.v $(RTL) | $(SIM)
	@$(IVERILOG) $(IVFLAGS) -o $@ $< $(RTL)

$(SIM):
	@mkdir -p $(SIM)

lint:
	@command -v verilator >/dev/null 2>&1 || { echo "verilator no instalado, salteando"; exit 0; }
	verilator --lint-only -Wall --top-module top $(RTL)

wave:
	@test -n "$(TB)" || { echo "uso: make wave TB=top_tb"; exit 1; }
	@$(MAKE) --no-print-directory $(TB)
	gtkwave $(SIM)/$(TB).vcd &

# ===========================================================================
# Diagnostico
# ===========================================================================

find-vivado:
	@echo "Buscando vivado.bat en los discos montados (puede tardar un minuto)..."
	@echo ""
	@found=0; \
	for d in /mnt/*/; do \
	  case "$$d" in /mnt/wsl*) continue;; esac; \
	  res=$$(find "$$d" -maxdepth 7 -name 'vivado.bat' -not -path '*/Windows/*' 2>/dev/null); \
	  if [ -n "$$res" ]; then echo "$$res"; found=1; fi; \
	done; \
	echo ""; \
	if [ $$found -eq 1 ]; then \
	  echo ">> Copiar la ruta que termina en /bin/vivado.bat"; \
	  echo ">> y pegarla arriba en la linea  VIVADO :=  (descomentandola)"; \
	else \
	  echo ">> No se encontro nada. Posibilidades:"; \
	  echo ">>   1. Vivado no esta instalado en esta maquina."; \
	  echo ">>   2. Esta en un disco no montado en WSL. Ver: ls -d /mnt/*/"; \
	  echo ">>   3. Esta a mas de 7 niveles de profundidad."; \
	  echo ">> Desde PowerShell en Windows:"; \
	  echo ">>   Get-ChildItem C:\\,E:\\ -Filter vivado.bat -Recurse -ErrorAction SilentlyContinue | Select FullName"; \
	fi

check-tools:
	@ok=1; \
	if command -v $(IVERILOG) >/dev/null 2>&1; then \
	  echo "iverilog : $$(command -v $(IVERILOG))"; \
	else \
	  echo "iverilog : FALTA  ->  sudo apt install iverilog"; ok=0; \
	fi; \
	if command -v gtkwave >/dev/null 2>&1; then \
	  echo "gtkwave  : $$(command -v gtkwave)"; \
	else \
	  echo "gtkwave  : falta (opcional)  ->  sudo apt install gtkwave"; \
	fi; \
	if [ -n "$(strip $(VIVADO))" ]; then \
	  echo "vivado   : $(VIVADO)"; \
	  [ -e "$(VIVADO)" ] || { echo "           AVISO: esa ruta no existe"; ok=0; }; \
	else \
	  echo "vivado   : FALTA  ->  correr 'make find-vivado' y fijar la ruta"; \
	  echo "                      en la linea VIVADO := del Makefile"; ok=0; \
	fi; \
	case "$(CURDIR)" in \
	  /mnt/*) echo "repo     : $(CURDIR)  [ok, visible desde Windows]";; \
	  *)      echo "repo     : $(CURDIR)  [AVISO: fuera de /mnt/, Vivado de Windows no lo va a ver]";; \
	esac; \
	echo ""; \
	if [ $$ok -eq 1 ]; then echo "== todo listo =="; \
	else echo "== faltan herramientas =="; exit 1; fi

# ===========================================================================
# Vivado
# ===========================================================================

# Ojo: NO invocar "$(VIVADO)" directo. Si es un .bat, WSL se lo pasa a /bin/sh
# y explota con "rem: not found". scripts/vivado.sh lo rutea por cmd.exe.

project:
	@test -n "$(strip $(VIVADO))" || { \
	  echo "ERROR: Vivado no configurado. Correr 'make find-vivado'."; exit 1; }
	@VIVADO="$(VIVADO)" scripts/vivado.sh -mode batch -source scripts/create_project.tcl

bit:
	@test -n "$(strip $(VIVADO))" || { \
	  echo "ERROR: Vivado no configurado. Correr 'make find-vivado'."; exit 1; }
	@VIVADO="$(VIVADO)" scripts/vivado.sh -mode batch -source scripts/build_bitstream.tcl

gui:
	@test -n "$(strip $(VIVADO))" || { \
	  echo "ERROR: Vivado no configurado. Correr 'make find-vivado'."; exit 1; }
	@VIVADO="$(VIVADO)" scripts/vivado.sh -mode gui build/riscv_pipeline.xpr &

# ===========================================================================

clean:
	rm -rf $(SIM)/*.vvp $(SIM)/*.vcd build reports
	rm -f vivado*.jou vivado*.log

help:
	@echo "make               corre todos los testbenches"
	@echo "make <nombre_tb>   corre uno solo"
	@echo "make wave TB=x_tb  abre las ondas"
	@echo "make lint          chequeo estatico"
	@echo "make find-vivado   busca la instalacion de Vivado"
	@echo "make check-tools   verifica el entorno"
	@echo "make project       regenera el proyecto de Vivado"
	@echo "make bit           sintesis + implementacion + bitstream"
	@echo "make clean"