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

    // INICIALIZACIÓN PARA SÍNTESIS/FPGA FÍSICA
    initial begin
        $readmemh("firmware.hex", mem);
    end

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
