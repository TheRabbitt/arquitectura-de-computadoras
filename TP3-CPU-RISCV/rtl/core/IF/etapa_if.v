`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// etapa_if
//
//   Etapa Instruction Fetch. Es el contenedor que pediste: instancia
//   registro_pc, sumador y mux2 y los cablea. Coincide 1 a 1 con la parte
//   izquierda del diagrama de Patterson.
//
//       +-------------------------------------------------+
//       |  mux2 --> registro_pc --> +-> sumador (+4) --+   |
//       |    ^                      |                  |   |
//       |    +----------------------|------------------+   |
//       |    ^                      v                      |
//       |  i_pc_target            o_pc -> memoria programa |
//       +-------------------------------------------------+
//
//   LA MEMORIA DE PROGRAMA NO ESTA ACA. Sale o_pc y entra la instruccion por
//   fuera. Dos razones:
//     1. La memoria va a ser un IP core de Vivado: si estuviera adentro, no
//        podrias simular esta etapa sin generar el IP.
//     2. Un Block RAM tiene 1 ciclo de latencia (ver nota abajo), asi que su
//        registro de salida hace de latch IF/ID para el campo instruccion.
//        Meterla aca esconderia esa decision.
//
//   DIRECCIONAMIENTO: o_pc es la direccion en BYTES. La memoria de programa es
//   por PALABRAS, asi que el indice es o_pc[N:2] (se descartan los 2 bits
//   bajos). Ese slicing se hace donde se instancia la memoria.
//------------------------------------------------------------------------------
module etapa_if
#(
    parameter              NB_PC    = 32             ,
    parameter [NB_PC-1:0]  PC_RESET = {NB_PC{1'b0}}
)(
    input  wire             i_clk       ,
    input  wire             i_rst       ,
    input  wire             i_en        ,  // debug unit: continuo / paso a paso
    input  wire             i_stall     ,  // hazard detection unit
    input  wire             i_halt      ,  // HALT decodificado en ID
    input  wire             i_pc_src    ,  // 0 = pc+4 , 1 = i_pc_target
    input  wire [NB_PC-1:0] i_pc_target ,  // destino calculado en ID

    output wire [NB_PC-1:0] o_pc        ,  // -> memoria de programa
    output wire [NB_PC-1:0] o_pc_plus4  ,  // -> latch IF/ID (lo usa jal)
    output wire             o_halted       // -> debug unit
);

    wire [NB_PC-1:0] pc      ;
    wire [NB_PC-1:0] pc_plus4;
    wire [NB_PC-1:0] next_pc ;

    //--------------------------------------------------------------------------
    // Sumador PC+4 (mismo modulo verificado en el testbench del sumador)
    //--------------------------------------------------------------------------
    sumador #(
        .NB_IN    (NB_PC)
    ) u_sumador_pc4 (
        .i_a      (pc),
        .i_b      ({{(NB_PC-3){1'b0}}, 3'd4}),
        .o_result (pc_plus4)
    );

    //--------------------------------------------------------------------------
    // Seleccion del proximo PC
    //--------------------------------------------------------------------------
    // mux2 #(
    //     .NB    (NB_PC)
    // ) u_mux_next_pc (
    //     .i_sel (i_pc_src),
    //     .i_d0  (pc_plus4),
    //     .i_d1  (i_pc_target),
    //     .o_out (next_pc)
    // );

    //--------------------------------------------------------------------------
    // Registro del PC
    //--------------------------------------------------------------------------
    registro_pc #(
        .NB_PC     (NB_PC),
        .PC_RESET  (PC_RESET)
    ) u_registro_pc (
        .i_clk     (i_clk),
        .i_rst     (i_rst),
        .i_en      (i_en),
        .i_stall   (i_stall),
        .i_halt    (i_halt),
        .i_next_pc (next_pc),
        .o_pc      (pc),
        .o_halted  (o_halted)
    );

    assign o_pc       = pc      ;
    assign o_pc_plus4 = pc_plus4;

endmodule

`default_nettype wire
