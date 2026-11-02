`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: mem_wb
// Descripción: Latch/Registro de Pipeline entre las etapas MEM (Memory)
//              y WB (Write-Back) para un procesador RISC-V de 5 etapas.
//              Incluye bus de depuración (o_debug_mem_wb), bit de validez
//              y señal de enable.
//==============================================================================

module mem_wb_latch (
    input  wire        i_clk,
    input  wire        i_rst,
    
    // Control de flujo para Debug / Stall
    // i_enable = 1: El pipeline avanza normalmente.
    // i_enable = 0: El latch congela su estado (Pausa para la UART).
    input  wire        i_enable,
    input  wire        i_valid,

    // -------------------------------------------------------------------------
    // Entradas desde la etapa MEM (y latch EX/MEM)
    // -------------------------------------------------------------------------
    // Grupo WB (Write-Back) - Señales de control
    input  wire        i_wb_reg_write,
    input  wire        i_wb_mem_to_reg,
    input  wire        i_wb_jump,      // Señal de salto para la etapa WB

    // Datapath
    input  wire [31:0] i_read_data,    // Dato leído desde la Memoria de Datos
    input  wire [31:0] i_alu_result,   // Resultado proveniente de la ALU
    input  wire [4:0]  i_rd,           // Registro de destino
    input  wire [31:0] i_pc_plus_4,    // Dirección de retorno para JAL/JALR

    // -------------------------------------------------------------------------
    // Salidas hacia la etapa WB
    // -------------------------------------------------------------------------
    // Grupo WB (Write-Back)
    output reg         o_wb_reg_write,
    output reg         o_wb_mem_to_reg,
    output reg         o_wb_jump,
    output reg         o_valid,

    // Datapath
    output reg  [31:0] o_read_data,
    output reg  [31:0] o_alu_result,
    output reg  [4:0]  o_rd,
    output reg  [31:0] o_pc_plus_4,

    // -------------------------------------------------------------------------
    // Puerto de Depuración (Debug Unit / UART): 4 palabras de 32 bits = 16 bytes
    // -------------------------------------------------------------------------
    output wire [127:0] o_debug_mem_wb
);

    // -------------------------------------------------------------------------
    // Lógica Secuencial del Registro MEM/WB
    // -------------------------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            // Reset sincrónico: Limpia todas las señales
            o_wb_reg_write  <= 1'b0;
            o_wb_mem_to_reg <= 1'b0;
            o_wb_jump       <= 1'b0;
            o_valid         <= 1'b0;
    
            o_read_data     <= 32'b0;
            o_alu_result    <= 32'b0;
            o_rd            <= 5'b0;
            o_pc_plus_4     <= 32'b0;
        end 
        else if (i_enable) begin
            // Operación Normal: Se propagan las señales hacia WB
            o_wb_reg_write  <= i_wb_reg_write;
            o_wb_mem_to_reg <= i_wb_mem_to_reg;
            o_wb_jump       <= i_wb_jump;
            o_valid         <= i_valid;
            o_read_data     <= i_read_data;
            o_alu_result    <= i_alu_result;
            o_rd            <= i_rd;
            o_pc_plus_4     <= i_pc_plus_4;
        end
        // Si i_enable es 0, los registros mantienen su valor actual (Hold/Pausa)
    end

    // -------------------------------------------------------------------------
    // Empaquetado alineado a palabras de 32 bits (4 palabras = 16 bytes):
    // Word 0 [31:0]   : o_read_data
    // Word 1 [63:32]  : o_alu_result
    // Word 2 [95:64]  : o_pc_plus_4
    // Word 3 [127:96] : {23'd0, o_valid, o_wb_jump, o_wb_mem_to_reg, o_wb_reg_write, o_rd}
    // -------------------------------------------------------------------------
    wire [31:0] w_ctrl_word = {
        23'd0,
        o_valid,         // [8]
        o_wb_jump,       // [7]
        o_wb_mem_to_reg, // [6]
        o_wb_reg_write,  // [5]
        o_rd             // [4:0]
    };

    assign o_debug_mem_wb = {
        w_ctrl_word,
        o_pc_plus_4,
        o_alu_result,
        o_read_data
    };

endmodule
`default_nettype wire
