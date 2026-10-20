`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: stage_mem
// Descripción: Etapa de Memoria (MEM) del pipeline RISC-V de 5 etapas.
// Encapsula la Memoria de Datos y enruta las señales de control y datapath 
// hacia la etapa Write-Back (WB) y hacia la Forwarding Unit.
//==============================================================================

module stage_mem #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8
)(
    input  wire                  i_clk,

    // -------------------------------------------------------------------------
    // Entradas desde el Latch EX/MEM
    // -------------------------------------------------------------------------
    // Control WB (Write-Back)
    input  wire                  i_wb_reg_write,
    input  wire                  i_wb_mem_to_reg,
    
    // Control MEM (Memoria)
    input  wire                  i_m_mem_read,
    input  wire                  i_m_mem_write,
    
    // Datapath
    input  wire [DATA_WIDTH-1:0] i_alu_result, // Dirección de memoria / Dato calculado por la ALU
    input  wire [DATA_WIDTH-1:0] i_rs2_data,   // Dato a escribir en memoria (Store)
    input  wire [4:0]            i_rd,         // Registro destino
    
    // -------------------------------------------------------------------------
    // Interfaz de Debug / UART (hacia Memoria de Datos)
    // -------------------------------------------------------------------------
    input  wire                  i_debug_re,
    input  wire [ADDR_WIDTH-1:0] i_debug_addr,
    output wire [DATA_WIDTH-1:0] o_debug_rdata,

    // -------------------------------------------------------------------------
    // Salidas hacia el Latch MEM/WB (y Forwarding Unit)
    // -------------------------------------------------------------------------
    // Nota: o_wb_reg_write, o_rd y o_alu_result se utilizan simultáneamente 
    // para la etapa de WB y para alimentar la Forwarding Unit (Riesgo EX/MEM).
    
    // Control WB (Passthrough)
    output wire                  o_wb_reg_write,
    output wire                  o_wb_mem_to_reg,
    
    // Datapath
    output wire [DATA_WIDTH-1:0] o_read_data,  // Dato leído de la memoria
    output wire [DATA_WIDTH-1:0] o_alu_result, // Pasaje directo del resultado ALU
    output wire [4:0]            o_rd          // Pasaje directo del registro destino
);

    // -------------------------------------------------------------------------
    // Pasaje de señales de control y datapath (Bypass)
    // -------------------------------------------------------------------------
    // Estas señales atraviesan la etapa MEM sin modificaciones. 
    // Van directo al Latch MEM/WB 
    assign o_wb_reg_write  = i_wb_reg_write;
    assign o_wb_mem_to_reg = i_wb_mem_to_reg;
    assign o_alu_result    = i_alu_result;
    assign o_rd            = i_rd;

    // -------------------------------------------------------------------------
    // Instanciación de la Memoria de Datos (Data Memory)
    // -------------------------------------------------------------------------
    data_memory #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_data_memory (
        .i_clk         (i_clk),
        .i_mem_write   (i_m_mem_write),
        .i_mem_read    (i_m_mem_read),
        .i_addr        (i_alu_result), // El resultado de la ALU actúa como dirección
        .i_write_data  (i_rs2_data),   // RS2 contiene el dato a guardar en SW
        .o_read_data   (o_read_data),  // Dato leído en LW hacia Write-Back
        
        // Interfaz de depuración dedicada (UART)
        .i_debug_re    (i_debug_re),
        .i_debug_addr  (i_debug_addr),
        .o_debug_rdata (o_debug_rdata)
    );

endmodule
`default_nettype wire