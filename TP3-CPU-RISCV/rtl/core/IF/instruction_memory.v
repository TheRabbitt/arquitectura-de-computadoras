`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: InstructionMemory
// Descripción: Memoria RAM de doble puerto para instrucciones RISC-V.
//   - Puerto A (Lectura): Dedicado a la etapa IF (Fetch) del procesador.
//   - Puerto B (Escritura): Dedicado a la Debug Unit/UART para carga dinámica.
//==============================================================================

module InstructionMemory #(
    parameter ADDR_WIDTH = 10, // 1024 palabras (4 KB de memoria de programa)
    parameter DATA_WIDTH = 32
)(
    input  wire                  i_clk,

    // Puerto A: Fetch del procesador (Lectura Sincrónica)
    input  wire [DATA_WIDTH-1:0]          i_pc,
    input  wire                  i_read_enable,
    output reg  [DATA_WIDTH-1:0] o_instruction,

    // Puerto B: Debug Unit / UART (Escritura para Reprogramación)
    input  wire                  i_write_en,
    input  wire                  i_debug_re,    // Habilitación de lectura
    input  wire [ADDR_WIDTH-1:0] i_debug_addr,  // Dirección de lectura UART
    input  wire [ADDR_WIDTH-1:0] i_write_addr,
    input  wire [DATA_WIDTH-1:0] i_write_data,
    output reg  [DATA_WIDTH-1:0] o_debug_rdata
);

    // Arreglo de memoria
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

   // INICIALIZACIÓN DIRECTA PARA SÍNTESIS/FPGA FÍSICA
    // integer i;
    // initial begin
    //     // 1. Llenar toda la memoria con ceros por seguridad
    //     for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
    //         mem[i] = 32'd0;
    //     end

    //     // 2. Cargar tus instrucciones manualmente en cada índice
    //     // (El índice corresponde a la palabra, no al byte, por eso va de 1 en 1)
    //     mem[0] = 32'hAAAA0000; // Reemplazá con tu 1ra instrucción
    //     mem[1] = 32'hBBBB1111; // Reemplazá con tu 2da instrucción
    //     mem[2] = 32'hCCCC2222; // Reemplazá con tu 3ra instrucción
    //     mem[3] = 32'hDDDD3333; // Reemplazá con tu 4ta instrucción
    //     mem[8] = 32'hFFFF9999; // Reemplazá con tu 4ta instrucción
    //     mem[9] = 32'hEEEE4444; // Reemplazá con tu 4ta instrucción
    // end

    // Cálculo del índice de palabra: el PC avanza de a 4 bytes, 
    // por lo que ignoramos los 2 bits menos significativos.
    wire [ADDR_WIDTH-1:0] word_addr = i_pc[ADDR_WIDTH+1:2];

    // Puerto A: Lectura para Fetch
    always @(negedge i_clk) begin
        if(i_read_enable) begin
            o_instruction <= mem[word_addr];
        end
    end

    // Puerto B: Escritura desde la UART / Debug Unit
    always @(posedge i_clk) begin
        if (i_write_en) begin
            mem[i_write_addr] <= i_write_data;
        end

        if (i_debug_re) begin
            o_debug_rdata <= mem[i_debug_addr]; 
        end
    end

endmodule
`default_nettype wire
