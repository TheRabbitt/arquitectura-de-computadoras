`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// mux2
//   Mux 2 a 1 parametrizable. Se reusa en varios puntos del pipeline
//   (seleccion de next_pc, ALU src, write back, etc).
//------------------------------------------------------------------------------
module mux2
#(
    parameter NB = 32
)(
    input  wire          i_sel ,
    input  wire [NB-1:0] i_d0  ,   // se elige con i_sel = 0
    input  wire [NB-1:0] i_d1  ,   // se elige con i_sel = 1

    output wire [NB-1:0] o_out
);

    assign o_out = i_sel ? i_d1 : i_d0;

endmodule

`default_nettype wire