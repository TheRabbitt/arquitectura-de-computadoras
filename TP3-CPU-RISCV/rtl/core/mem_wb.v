`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: mem_wb
// Descripción: Latch/Registro de Pipeline entre las etapas MEM (Memory)
//              y WB (Write-Back) para un procesador RISC-V de 5 etapas.
//              Incluye bus de depuración (o_debug_mem_wb) y señal de enable.
//==============================================================================

module mem_wb_latch (
    input  wire        i_clk,
    input  wire        i_rst,
    
    // Control de flujo para Debug / Stall
    // i_enable = 1: El pipeline avanza normalmente.
    // i_enable = 0: El latch congela su estado (Pausa para la UART).
    input  wire        i_enable,

    // -------------------------------------------------------------------------
    // Entradas desde la etapa MEM (y latch EX/MEM)
    // -------------------------------------------------------------------------
    // Grupo WB (Write-Back) - Señales de control
    input  wire        i_wb_reg_write,
    input  wire        i_wb_mem_to_reg,

    // Datapath
    input  wire [31:0] i_read_data,    // Dato leído desde la Memoria de Datos
    input  wire [31:0] i_alu_result,   // Resultado proveniente de la ALU
    input  wire [4:0]  i_rd,           // Registro de destino

    // -------------------------------------------------------------------------
    // Salidas hacia la etapa WB
    // -------------------------------------------------------------------------
    // Grupo WB (Write-Back)
    output reg         o_wb_reg_write,
    output reg         o_wb_mem_to_reg,

    // Datapath
    output reg  [31:0] o_read_data,
    output reg  [31:0] o_alu_result,
    output reg  [4:0]  o_rd

    // -------------------------------------------------------------------------
    // Puerto de Depuración (Debug Unit / UART)
    // -------------------------------------------------------------------------
    // Suma de bits: 1 + 1 + 32 + 32 + 5 = 71 bits
    // output wire [70:0] o_debug_mem_wb
);

    // -------------------------------------------------------------------------
    // Lógica Secuencial del Registro MEM/WB
    // -------------------------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            // Reset sincrónico: Limpia todas las señales
            o_wb_reg_write  <= 1'b0;
            o_wb_mem_to_reg <= 1'b0;
            
            o_read_data     <= 32'b0;
            o_alu_result    <= 32'b0;
            o_rd            <= 5'b0;
        end 
        else if (i_enable) begin
            // Operación Normal: Se propagan las señales hacia WB
            o_wb_reg_write  <= i_wb_reg_write;
            o_wb_mem_to_reg <= i_wb_mem_to_reg;
            
            o_read_data     <= i_read_data;
            o_alu_result    <= i_alu_result;
            o_rd            <= i_rd;
        end
        // Si i_enable es 0, los registros mantienen su valor actual (Hold/Pausa)
    end

    // -------------------------------------------------------------------------
    // Empaquetado de Datos para transmisión UART / Debug Unit
    // Unifica los 71 bits del latch para que la Debug Unit los serialice.
    // -------------------------------------------------------------------------
    // assign o_debug_mem_wb = {
    //     o_wb_reg_write,  // [70]    (1 bit)
    //     o_wb_mem_to_reg, // [69]    (1 bit)
    //     o_read_data,     // [68:37] (32 bits)
    //     o_alu_result,    // [36:5]  (32 bits)
    //     o_rd             // [4:0]   (5 bits)
    // };

endmodule
`default_nettype wire