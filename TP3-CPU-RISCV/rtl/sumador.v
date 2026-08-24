`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// sumador
//   Sumador combinacional de NB_SUM bits, salida truncada a NB_SUM bits.
//   Uso previsto: PC+4 (etapa IF) y PC+offset (target de branch/jal).
//------------------------------------------------------------------------------
module sumador
#(
    parameter NB_SUM = 32
)(
    input  wire [NB_SUM-1:0] i_a      ,
    input  wire [NB_SUM-1:0] i_b      ,

    output wire [NB_SUM-1:0] o_result
);

    assign o_result = i_a + i_b;

endmodule

`default_nettype wire