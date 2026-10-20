`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: stage_wb
// Descripción: Etapa Write-Back (WB) del pipeline de 5 etapas.
// Selecciona el dato a escribir en el banco de registros, incluyendo
// el soporte para guardar la dirección de retorno (PC+4) en saltos (JAL/JALR).
//==============================================================================

module stage_wb (
    // Señales de control
    input  wire        i_mem_to_reg,
    input  wire        i_jump,         // Señal para elegir PC+4 en instrucciones de salto

    // Datapath
    input  wire [31:0] i_alu_result, // Resultado calculado en la ALU
    input  wire [31:0] i_read_data,  // Dato leído desde la Memoria de Datos (Load)
    input  wire [31:0] i_pc_plus_4,  // Dirección de retorno para JAL/JALR propagada por el pipeline

    // Salidas
    output wire [31:0] o_write_data, // Dato que se escribirá en el Register File
    output wire [31:0] o_forward_ex  // Dato que se adelanta a la Forwarding Unit en EX
);

    // Cable interno para la salida del primer multiplexor
    wire [31:0] w_mem_to_reg_out;

    // -------------------------------------------------------------------------
    // Primer Multiplexor (MemToReg)
    // 0: Dato proveniente de la ALU (Instrucciones aritméticas)
    // 1: Dato proveniente de la Memoria (Instrucciones Load)
    // -------------------------------------------------------------------------
    mux2 #(.NB(32)) mux_mem_to_reg (
        .i_sel (i_mem_to_reg),
        .i_d0  (i_alu_result), 
        .i_d1  (i_read_data),  
        .o_out (w_mem_to_reg_out)
    );

    // -------------------------------------------------------------------------
    // Segundo Multiplexor (Jump)
    // 0: Dato proveniente del multiplexor anterior (ALU o Memoria)
    // 1: PC+4 (Dirección de retorno para JAL/JALR)
    // -------------------------------------------------------------------------
    mux2 #(.NB(32)) mux_jump (
        .i_sel (i_jump),
        .i_d0  (w_mem_to_reg_out),
        .i_d1  (i_pc_plus_4),
        .o_out (o_write_data)
    );

    // -------------------------------------------------------------------------
    // Ruteo de señal de Forwarding
    // Tal como se definió previamente, el forwarding hacia la ALU en EX
    // sale estrictamente del primer multiplexor, ignorando lógicas de salto.
    // -------------------------------------------------------------------------
    assign o_forward_ex = w_mem_to_reg_out;

endmodule
`default_nettype wire