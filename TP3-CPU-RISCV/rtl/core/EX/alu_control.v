`timescale 1ns / 1ps
`default_nettype none

module alu_control (
    input  wire [1:0] i_alu_op,     // Proviene de Control Unit
    input  wire [2:0] i_funct3,     // Instruction [14:12]
    input  wire       i_funct7_5,   // Instruction [30]
    output reg  [3:0] o_alu_ctrl    // Control de 4 bits directo a la ALU
);

    // Códigos de salida para la ALU
    localparam ALU_ADD    = 4'b0000;
    localparam ALU_SUB    = 4'b0001;
    localparam ALU_AND    = 4'b0010;
    localparam ALU_OR     = 4'b0011;
    localparam ALU_XOR    = 4'b0100;
    localparam ALU_SLL    = 4'b0101;
    localparam ALU_SRL    = 4'b0110;
    localparam ALU_SRA    = 4'b0111;
    localparam ALU_SLT    = 4'b1000;
    localparam ALU_SLTU   = 4'b1001;
    localparam ALU_PASS_B = 4'b1010;

    always @(*) begin
        case (i_alu_op)
            // Loads, Stores, JAL, JALR: Calculan dirección con suma
            2'b00: o_alu_ctrl = ALU_ADD;

            // Branches (BEQ, BNE): Comparación con resta (no lo usamos en esta implementación
            // porque se resuelve el sato en ID). Se deja para respetar la teoría.
            2'b01: o_alu_ctrl = ALU_SUB;

            // Tipo-R
            2'b10: begin
                case (i_funct3)
                    3'b000: o_alu_ctrl = (i_funct7_5) ? ALU_SUB : ALU_ADD; // ADD o SUB
                    3'b001: o_alu_ctrl = ALU_SLL;                          // SLL
                    3'b010: o_alu_ctrl = ALU_SLT;                          // SLT
                    3'b011: o_alu_ctrl = ALU_SLTU;                         // SLTU
                    3'b100: o_alu_ctrl = ALU_XOR;                          // XOR
                    3'b101: o_alu_ctrl = (i_funct7_5) ? ALU_SRA : ALU_SRL; // SRL o SRA
                    3'b110: o_alu_ctrl = ALU_OR;                           // OR
                    3'b111: o_alu_ctrl = ALU_AND;                          // AND
                endcase
            end

            // Tipo-I Aritméticas (ADDI, ANDI, SRLI, SRAI, etc.)
            2'b11: begin
                case (i_funct3)
                    3'b000: o_alu_ctrl = ALU_ADD;                          // ADDI siempre suma
                    3'b001: o_alu_ctrl = ALU_SLL;                          // SLLI
                    3'b010: o_alu_ctrl = ALU_SLT;                          // SLTI
                    3'b011: o_alu_ctrl = ALU_SLTU;                         // SLTIU
                    3'b100: o_alu_ctrl = ALU_XOR;                          // XORI
                    3'b101: o_alu_ctrl = (i_funct7_5) ? ALU_SRA : ALU_SRL; // SRLI o SRAI
                    3'b110: o_alu_ctrl = ALU_OR;                           // ORI
                    3'b111: o_alu_ctrl = ALU_AND;                          // ANDI
                endcase
            end

            default: o_alu_ctrl = ALU_ADD;
        endcase
    end

endmodule
`default_nettype wire