`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: data_memory
// Descripción: Memoria de datos para la etapa MEM del pipeline RISC-V.
// Lectura y escritura sincrónicas para inferencia de Block RAM (BRAM) en Vivado.
// Incorpora un puerto de lectura dedicado para la UART.
//==============================================================================

module data_memory #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8  // 2^8 = 256 palabras de 32 bits (1 KB de memoria)
)(
    input  wire                  i_clk,
    
    // -------------------------------------------------------------------------
    // Interfaz Principal: Etapa MEM del Pipeline
    // -------------------------------------------------------------------------
    input  wire                  i_mem_write,
    input  wire                  i_mem_read,
    input  wire [DATA_WIDTH-1:0] i_addr,         // Dirección calculada por la ALU
    input  wire [DATA_WIDTH-1:0] i_write_data,   // Dato a escribir (proveniente de RS2)
    output reg  [DATA_WIDTH-1:0] o_read_data,    // Dato leído hacia el latch MEM/WB
    
    // -------------------------------------------------------------------------
    // Interfaz Secundaria: Depuración (UART)
    // -------------------------------------------------------------------------
    input  wire                  i_debug_re,     // Habilitación de lectura desde UART
    input  wire [ADDR_WIDTH-1:0] i_debug_addr,   // Dirección solicitada por la UART
    output reg  [DATA_WIDTH-1:0] o_debug_rdata   // Dato devuelto a la UART
);

    // Declaración del arreglo de memoria (RAM)
    reg [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];
    
    // Inicialización de la memoria en 0
    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
            ram[i] = 32'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Mapeo de Direcciones
    // -------------------------------------------------------------------------
    // Para alinear la dirección a palabras de 32 bits, se descartan los 2 LSB.
    wire [ADDR_WIDTH-1:0] word_addr = i_addr[ADDR_WIDTH+1:2];

    // -------------------------------------------------------------------------
    // Lógica Sincrónica de Memoria (Infiere BRAM)
    // -------------------------------------------------------------------------
    always @(negedge i_clk) begin
        // --- Puerto 1: Datapath del Pipeline ---
        if (i_mem_write) begin
            ram[word_addr] <= i_write_data;
        end
        
        if (i_mem_read) begin
            o_read_data <= ram[word_addr];
        end else begin
            o_read_data <= {DATA_WIDTH{1'b0}};
        end
        
        // --- Puerto 2: Unidad de Depuración (UART) ---
        if (i_debug_re) begin
            o_debug_rdata <= ram[i_debug_addr];
        end else begin
            o_debug_rdata <= {DATA_WIDTH{1'b0}};
        end
    end

endmodule
`default_nettype wire