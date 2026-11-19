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
    input  wire          i_en,    // Habilitación desde Hazard Detection Unit y Debug Unit (0 = Stall/Pausa)
    input  wire          i_flush, // Limpieza desde Control/Hazard/Halt (1 = Flush de Branch/Jump/Halt)
    
    // Entradas desde la etapa IF
    input  wire [NB-1:0] i_pc,
    input  wire [NB-1:0] i_instruction,
    input  wire [NB-1:0] i_pc_plus_4,

    // Salidas hacia la etapa ID
    output reg  [NB-1:0] o_pc,
    output reg  [NB-1:0] o_pc_plus_4,
    output reg  [NB-1:0] o_instruction,
    output reg           o_valid,

    // Puerto de Depuración (Debug Unit / UART): 4 palabras de 32 bits = 16 bytes
    output wire [127:0]  o_debug_if_id
);

    always @(posedge i_clk) begin
        if (i_rst | i_flush) begin
            // Al hacer flush o reset, inyectamos una burbuja (NOP),
            // limpiamos el PC y marcamos el latch como inválido (vacío).
            o_pc          <= {NB{1'b0}};
            o_pc_plus_4   <= {NB{1'b0}};
            o_instruction <= NOP_INSTR;
            o_valid       <= 1'b0;
        end
        else if (i_en) begin
            // Operación normal de pipeline
            o_pc          <= i_pc;
            o_pc_plus_4   <= i_pc_plus_4;
            o_instruction <= i_instruction;
            o_valid       <= 1'b1;
        end
    end

    // Empaquetado alineado a palabras de 32 bits (Little-Endian por palabra):
    // Word 0 [31:0]   : o_pc
    // Word 1 [63:32]  : o_pc_plus_4
    // Word 2 [95:64]  : o_instruction
    // Word 3 [127:96] : {31'd0, o_valid}
    assign o_debug_if_id = {
        {31'd0, o_valid},
        o_instruction,
        o_pc_plus_4,
        o_pc
    };

endmodule
`default_nettype wire
