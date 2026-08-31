`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: top_pc_fpga
// Descripción: 
//   Top level para probar el módulo registro_pc en la placa Nexys 4.
//   Adapta el ancho del PC a 12 bits para dejar 4 LEDs libres que 
//   indiquen el estado de las señales de control.
//==============================================================================

module top_pc_fpga (
    input  wire        CLK100MHZ, // Reloj principal de 100 MHz de la Nexys 4
    input  wire [11:0] i_sw,        // i_sw[11:0] para simular i_next_pc
    
    // Botones para las señales de control
    input  wire        i_btnc,      // Reset
    input  wire        i_btnu,      // Enable
    input  wire        i_btnd,      // Stall
    input  wire        btnL,      // Halt
    
    // Salidas a los LEDs
    output wire [15:0] o_led
);

    // Reducimos el PC a 12 bits para poder usar los 4 LEDs restantes para control
    localparam integer NB_PC = 12;

    wire [NB_PC-1:0] w_pc;
    wire             w_halted;

    //==========================================================================
    // Instancia del Registro PC
    //==========================================================================
    registro_pc #(
        .NB_PC    (NB_PC),
        .PC_RESET (12'b0)
    ) u_registro_pc (
        .i_clk     (CLK100MHZ),
        .i_rst     (i_btnc),
        .i_en      (i_btnu),
        .i_stall   (i_btnd),
        .i_halt    (btnL),
        .i_next_pc (i_sw),
        .o_pc      (w_pc),
        .o_halted  (w_halted)
    );

    //==========================================================================
    // Mapeo de salidas a los LEDs de la placa
    //==========================================================================
    // Los 12 LEDs de la derecha muestran el valor almacenado en el PC
    assign o_led[11:0] = w_pc;

    // Los 4 LEDs de la izquierda muestran las señales de control
    assign o_led[12] = i_btnu;     // LED 12: Estado de Enable (refleja el botón)
    assign o_led[13] = i_btnd;     // LED 13: Estado de Stall (refleja el botón)
    assign o_led[14] = w_halted; // LED 14: Estado de Halt (refleja la bandera interna "sticky" del módulo)
    assign o_led[15] = i_btnc;     // LED 15: Estado de Reset (refleja el botón)

endmodule

`default_nettype wire