`timescale 1ns / 1ps
`default_nettype none

module alu #(
    parameter NB_IN  = 32,
    parameter NB_OUT = 32,
    parameter NB_OP  = 4
)(
    input  wire [NB_IN-1:0]  i_a,
    input  wire [NB_IN-1:0]  i_b,
    input  wire [NB_OP-1:0]  i_op,          // Conectado a o_alu_ctrl de alu_control
    output wire [NB_OUT-1:0] o_outresult
);

    reg [NB_OUT-1:0] result;

    // Códigos de operación idénticos a los de alu_control.v
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
        case (i_op)
            // Aritmética y Lógica Básica
            ALU_ADD:    result = i_a + i_b;
            ALU_SUB:    result = i_a - i_b;
            ALU_AND:    result = i_a & i_b;
            ALU_OR:     result = i_a | i_b;
            ALU_XOR:    result = i_a ^ i_b;

            // Desplazamientos (Solo se toman los 5 bits LSB de B para indicar 0-31 posiciones)
            ALU_SLL:    result = i_a << i_b[4:0];
            ALU_SRL:    result = i_a >> i_b[4:0];
            ALU_SRA:    result = $signed(i_a) >>> i_b[4:0]; // Extensión de signo al desplazar

            // Comparaciones Set Less Than
            ALU_SLT:    result = ($signed(i_a) < $signed(i_b)) ? 32'd1 : 32'd0; // Con signo
            ALU_SLTU:   result = (i_a < i_b) ? 32'd1 : 32'd0;                   // Sin signo

            // Pasaje directo (LUI)
            ALU_PASS_B: result = i_b;

            default:    result = {NB_OUT{1'b0}};
        endcase
    end

    assign o_outresult = result;

endmodule
`default_nettype wire