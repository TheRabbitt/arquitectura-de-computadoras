## ---------------------------------------------------------------------------
## nexys4.xdc  -  constraints minimos
##
## Pines tomados del Master XDC oficial de Digilent (Nexys 4 DDR Rev. C /
## Nexys A7-100T). VERIFIQUEN contra el archivo de SU revision de placa:
##   https://github.com/Digilent/digilent-xdc
##
## Regla del proyecto: aca solo se descomenta lo que el top realmente usa.
## Un pin restringido y no conectado hace fallar la implementacion.
## ---------------------------------------------------------------------------

## ---- Reloj de 100 MHz ----
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { clk }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }]

## ---- Boton CPU_RESETN (rojo, ACTIVO EN BAJO) ----
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports { rst_n }]

## ---- LEDs 0 y 1 ----
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { led[1] }]

## ---------------------------------------------------------------------------
## UART (USB-RS232 via el puente FTDI del cable de programacion)
## Descomentar en la FASE 1, cuando el top tenga estos puertos.
##
## Ojo con los nombres: los del esquematico estan desde el punto de vista
## de la PC, no de la FPGA.
##   uart_txd_in  = la PC transmite  -> es la ENTRADA de la FPGA (rx)
##   uart_rxd_out = la PC recibe     -> es la SALIDA  de la FPGA (tx)
## ---------------------------------------------------------------------------
# set_property -dict { PACKAGE_PIN C4  IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]
# set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]

## ---- Configuracion del bitstream ----
set_property CONFIG_VOLTAGE 3.3        [current_design]
set_property CFGBVS VCCO                [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

## ---------------------------------------------------------------------------
## Entradas asincronicas: el boton no tiene relacion temporal con el reloj,
## lo sincronizamos en RTL. Sin esto Vivado reporta paths imposibles.
## ---------------------------------------------------------------------------
set_false_path -from [get_ports { rst_n }]
