`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: imm_gen
// Descripción: Generador de inmediatos para la etapa ID del procesador RISC-V.
//   Extrae y reordena los bits del valor inmediato de 32 bits con extensión
//   de signo según el formato de la instrucción (RV32I).
//==============================================================================

module imm_gen (
    input  wire [31:0] i_instruction, // Instrucción completa de 32 bits (desde IF/ID)
    output reg  [31:0] o_imm          // Inmediato de 32 bits extendido
);

    // Opcodes base de RV32I
    localparam OPCODE_I_TYPE_1 = 7'b0010011; // OP-IMM (ADDI, SLTI, etc.)
    localparam OPCODE_I_TYPE_2 = 7'b0000011; // LOAD (LB, LH, LW, etc.)
    localparam OPCODE_JALR     = 7'b1100111; // JALR
    localparam OPCODE_S_TYPE   = 7'b0100011; // STORE (SB, SH, SW)
    localparam OPCODE_B_TYPE   = 7'b1100011; // BRANCH (BEQ, BNE, etc.)
    localparam OPCODE_U_LUI    = 7'b0110111; // LUI
    localparam OPCODE_JAL      = 7'b1101111; // JAL

    always @(*) begin
        case (i_instruction[6:0])
            //------------------------------------------------------------------
            // Tipo I: Imm[11:0] = inst[31:20]
            //------------------------------------------------------------------
            OPCODE_I_TYPE_1, 
            OPCODE_I_TYPE_2, 
            OPCODE_JALR: begin
                o_imm = {{20{i_instruction[31]}}, i_instruction[31:20]};
            end

            //------------------------------------------------------------------
            // Tipo S: Imm[11:0] = {inst[31:25], inst[11:7]}
            //------------------------------------------------------------------
            OPCODE_S_TYPE: begin
                o_imm = {{20{i_instruction[31]}}, i_instruction[31:25], i_instruction[11:7]};
            end

            //------------------------------------------------------------------
            // Tipo B: Imm[12:0] = {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
            // Nota: El bit LSB (bit 0) siempre es 0 por alineación a media palabra.
            //------------------------------------------------------------------
            OPCODE_B_TYPE: begin
                o_imm = {{19{i_instruction[31]}}, i_instruction[31], i_instruction[7], i_instruction[30:25], i_instruction[11:8], 1'b0};
            end

            //------------------------------------------------------------------
            // Tipo U: Imm[31:0] = {inst[31:12], 12'b0}
            //------------------------------------------------------------------
            OPCODE_U_LUI: begin
                o_imm = {i_instruction[31:12], 12'b0};
            end

            //------------------------------------------------------------------
            // Tipo J: Imm[20:0] = {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
            //------------------------------------------------------------------
            OPCODE_JAL: begin
                o_imm = {{11{i_instruction[31]}}, i_instruction[31], i_instruction[19:12], i_instruction[20], i_instruction[30:21], 1'b0};
            end

            // Por defecto (Instrucciones Tipo-R u Opcodes no soportados)
            default: begin
                o_imm = 32'd0;
            end
        endcase
    end

endmodule
`default_nettype wire