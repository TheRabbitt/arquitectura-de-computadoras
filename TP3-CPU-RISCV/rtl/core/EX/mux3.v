`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// mux3
//   Mux 3 a 1 parametrizable.
//   Selección de operandos para la ALU (dato proveniente del banco de registros, 
//   adelantado de la etapa EX o adelantado de la etapa MEM).
//------------------------------------------------------------------------------
module mux3
#(
    parameter NB = 32
)(
    input  wire [1:0]    i_sel ,
    input  wire [NB-1:0] i_d0  ,   // se elige con i_sel = 0
    input  wire [NB-1:0] i_d1  ,   // se elige con i_sel = 1
    input  wire [NB-1:0] i_d2  ,   // se elige con i_sel = 2

    output wire [NB-1:0] o_out
);

    assign o_out = (i_sel == 2'b00) ? i_d0 : (i_sel == 2'b01) ? i_d1 : i_d2;

endmodule

`default_nettype wire