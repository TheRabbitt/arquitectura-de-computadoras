## =============================================================================
## Archivo de Restricciones Físicas (.xdc) para fpga_top.v
## Placa objetivo: Digilent Nexys 4 (Rev B) — Artix-7 (xc7a100tcsg324-1)
## =============================================================================

## 1. Reloj Principal del Sistema (100 MHz)
set_property PACKAGE_PIN E3 [get_ports clk_100MHz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100MHz]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk_100MHz]

## 2. Botón Físico de Reset General (BTNC - Central)
set_property PACKAGE_PIN E16 [get_ports btnC]
set_property IOSTANDARD LVCMOS33 [get_ports btnC]

## 3. Interfaz USB-RS232 (UART 115200 8N1 integrada en FT2232HQ)
## Nota: En el esquemático de la Nexys 4:
##   - C4 (UART_TXD_IN)  es la línea que transmite el FTDI hacia la FPGA -> i_uart_rx
##   - D4 (UART_RXD_OUT) es la línea que transmite la FPGA hacia el FTDI -> o_uart_tx
set_property PACKAGE_PIN C4 [get_ports i_uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports i_uart_rx]

set_property PACKAGE_PIN D4 [get_ports o_uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports o_uart_tx]

## 4. LEDs de Diagnóstico en Tiempo Real (o_led[15:0])
set_property PACKAGE_PIN T8 [get_ports {o_led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[0]}]
set_property PACKAGE_PIN V9 [get_ports {o_led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[1]}]
set_property PACKAGE_PIN R8 [get_ports {o_led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[2]}]
set_property PACKAGE_PIN T6 [get_ports {o_led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[3]}]
set_property PACKAGE_PIN T5 [get_ports {o_led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[4]}]
set_property PACKAGE_PIN T4 [get_ports {o_led[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[5]}]
set_property PACKAGE_PIN U7 [get_ports {o_led[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[6]}]
set_property PACKAGE_PIN U6 [get_ports {o_led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[7]}]
set_property PACKAGE_PIN V4 [get_ports {o_led[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[8]}]
set_property PACKAGE_PIN U3 [get_ports {o_led[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[9]}]
set_property PACKAGE_PIN V1 [get_ports {o_led[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[10]}]
set_property PACKAGE_PIN R1 [get_ports {o_led[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[11]}]
set_property PACKAGE_PIN P5 [get_ports {o_led[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[12]}]
set_property PACKAGE_PIN U1 [get_ports {o_led[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[13]}]
set_property PACKAGE_PIN R2 [get_ports {o_led[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[14]}]
set_property PACKAGE_PIN P2 [get_ports {o_led[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_led[15]}]

## Configuración eléctrica general de la placa
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
