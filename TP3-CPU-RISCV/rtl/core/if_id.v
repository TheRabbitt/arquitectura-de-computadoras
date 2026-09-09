`timescale 1ns / 1ps
`default_nettype none

module if_id_register #(
    parameter NB = 32,
    // Instrucción NOP en RISC-V (addi x0, x0, 0)
    parameter NOP_INSTR = 32'h00000013 
)(
    input  wire          i_clk,
    input  wire          i_rst,
    
    // Señales de Control / Riesgos
    input  wire          i_en,    // Habilitación desde Hazard Detection Unit (0 = Stall)
    input  wire          i_flush, // Limpieza desde Control/Hazard (1 = Flush de Branch/Jump)
    
    // Entradas desde la etapa IF
    input  wire [NB-1:0] i_pc,
    input  wire [NB-1:0] i_instruction,

    // Salidas hacia la etapa ID
    output reg  [NB-1:0] o_pc,
    output reg  [NB-1:0] o_instruction
);

    always @(posedge i_clk) begin
        if (i_rst | i_flush) begin
            // Al hacer flush o reset, inyectamos una burbuja (NOP) 
            // y limpiamos el PC para no ejecutar basura.
            o_pc          <= {NB{1'b0}};
            o_instruction <= NOP_INSTR; 
        end
        else if (i_en) begin
            // Operación normal de pipeline
            o_pc          <= i_pc;
            o_instruction <= i_instruction;
        end
    end

endmodule
`default_nettype wire