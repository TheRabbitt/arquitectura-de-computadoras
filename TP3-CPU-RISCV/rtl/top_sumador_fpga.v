`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// top_sumador_fpga
//   SW[7:0]   -> operando A (8 bits)
//   SW[15:8]  -> operando B (8 bits)
//   BTNC      -> 0 = extension con ceros (sin signo)
//                1 = extension de signo  (con signo)
//   LED[8:0]  -> resultado de 9 bits (bit 8 = acarreo / signo)
//   LED[14:9] -> apagados
//   LED[15]   -> eco de BTNC
//
//   Combinacional puro: sin clock, sin reset, sin debounce.
//------------------------------------------------------------------------------
module top_sumador_fpga (
    input  wire [15:0] i_sw   ,
    input  wire        i_btnc ,

    output wire [15:0] o_led
);

    localparam integer NB_OP  = 8;   // ancho de cada operando desde los switches
    localparam integer NB_SUM = 9;   // +1 bit para no perder el acarreo

    wire [NB_OP-1:0]  a_raw     ;
    wire [NB_OP-1:0]  b_raw     ;
    wire [NB_SUM-1:0] a_ext     ;
    wire [NB_SUM-1:0] b_ext     ;
    wire [NB_SUM-1:0] resultado ;

    assign a_raw = i_sw[7:0] ;
    assign b_raw = i_sw[15:8];

    // La extension de signo se hace ACA, no dentro del sumador.
    assign a_ext = i_btnc ? {a_raw[NB_OP-1], a_raw} : {1'b0, a_raw};
    assign b_ext = i_btnc ? {b_raw[NB_OP-1], b_raw} : {1'b0, b_raw};

    sumador #(
        .NB_SUM    (NB_SUM)
    ) u_sumador (
        .i_a      (a_ext),
        .i_b      (b_ext),
        .o_result (resultado)
    );

    assign o_led[NB_SUM-1:0] = resultado;
    assign o_led[14:NB_SUM]  = {(15-NB_SUM){1'b0}};
    assign o_led[15]         = i_btnc;

endmodule

`default_nettype wire