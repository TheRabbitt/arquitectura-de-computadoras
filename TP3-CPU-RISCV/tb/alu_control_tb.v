`timescale 1ns / 1ps
`default_nettype none

module tb_alu_control;

    // Entradas al DUT (Device Under Test)
    reg  [1:0] tb_alu_op;
    reg  [2:0] tb_funct3;
    reg        tb_funct7_5;

    // Salidas del DUT
    wire [3:0] tb_alu_ctrl;

    // Contador de errores
    integer error_count = 0;

    // Códigos esperados de salida de la ALU (Mismos que en alu_control.v)
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

    // Instanciación del módulo a probar
    alu_control uut (
        .i_alu_op   (tb_alu_op),
        .i_funct3   (tb_funct3),
        .i_funct7_5 (tb_funct7_5),
        .o_alu_ctrl (tb_alu_ctrl)
    );

    // Tarea auxiliar de verificación combinacional
    task check_alu_ctrl(
        input [1:0] alu_op,
        input [2:0] funct3,
        input       funct7_5,
        input [3:0] expected_ctrl,
        input [8*25:1] test_name
    );
        begin
            tb_alu_op   = alu_op;
            tb_funct3   = funct3;
            tb_funct7_5 = funct7_5;
            #5; // Tiempo para propagación de la lógica combinacional

            if (tb_alu_ctrl !== expected_ctrl) begin
                $display("[ERROR] %-25s | ALUOp:%b f3:%b f7_5:%b | Esperado: %b | Obtenido: %b",
                         test_name, tb_alu_op, tb_funct3, tb_funct7_5, expected_ctrl, tb_alu_ctrl);
                error_count = error_count + 1;
            end else begin
                $display("[OK]    %-25s | ALUOp:%b f3:%b f7_5:%b -> ALU_Ctrl:%b",
                         test_name, tb_alu_op, tb_funct3, tb_funct7_5, tb_alu_ctrl);
            end
        end
    endtask

    initial begin
        $display("=========================================================================");
        $display("          INICIO DE PRUEBAS AUTOMATIZADAS: ALU CONTROL                   ");
        $display("=========================================================================");

        // --- Caso ALUOp = 00 (Loads, Stores -> Suma) ---
        check_alu_ctrl(2'b00, 3'b000, 1'b0, ALU_ADD, "Loads/Stores (ADD)");
        check_alu_ctrl(2'b00, 3'b010, 1'b1, ALU_ADD, "LW (ADD)");

        // --- Caso ALUOp = 01 (Branches: BEQ, BNE -> Resta) ---
        // check_alu_ctrl(2'b01, 3'b000, 1'b0, ALU_SUB, "BEQ/BNE (SUB)");

        // --- Caso ALUOp = 10 (Instrucciones Tipo-R) ---
        check_alu_ctrl(2'b10, 3'b000, 1'b0, ALU_ADD,  "R-Type: ADD");
        check_alu_ctrl(2'b10, 3'b000, 1'b1, ALU_SUB,  "R-Type: SUB");
        check_alu_ctrl(2'b10, 3'b001, 1'b0, ALU_SLL,  "R-Type: SLL");
        check_alu_ctrl(2'b10, 3'b010, 1'b0, ALU_SLT,  "R-Type: SLT");
        check_alu_ctrl(2'b10, 3'b011, 1'b0, ALU_SLTU, "R-Type: SLTU");
        check_alu_ctrl(2'b10, 3'b100, 1'b0, ALU_XOR,  "R-Type: XOR");
        check_alu_ctrl(2'b10, 3'b101, 1'b0, ALU_SRL,  "R-Type: SRL");
        check_alu_ctrl(2'b10, 3'b101, 1'b1, ALU_SRA,  "R-Type: SRA");
        check_alu_ctrl(2'b10, 3'b110, 1'b0, ALU_OR,   "R-Type: OR");
        check_alu_ctrl(2'b10, 3'b111, 1'b0, ALU_AND,  "R-Type: AND");

        // --- Caso ALUOp = 11 (Instrucciones Tipo-I Aritméticas) ---
        check_alu_ctrl(2'b11, 3'b000, 1'b0, ALU_ADD,  "I-Type: ADDI (f7_5=0)");
        check_alu_ctrl(2'b11, 3'b000, 1'b1, ALU_ADD,  "I-Type: ADDI (f7_5=1)"); // Debe forzar ADD ignorando el bit 30
        check_alu_ctrl(2'b11, 3'b001, 1'b0, ALU_SLL,  "I-Type: SLLI");
        check_alu_ctrl(2'b11, 3'b010, 1'b0, ALU_SLT,  "I-Type: SLTI");
        check_alu_ctrl(2'b11, 3'b011, 1'b0, ALU_SLTU, "I-Type: SLTIU");
        check_alu_ctrl(2'b11, 3'b100, 1'b0, ALU_XOR,  "I-Type: XORI");
        check_alu_ctrl(2'b11, 3'b101, 1'b0, ALU_SRL,  "I-Type: SRLI");
        check_alu_ctrl(2'b11, 3'b101, 1'b1, ALU_SRA,  "I-Type: SRAI");
        check_alu_ctrl(2'b11, 3'b110, 1'b0, ALU_OR,   "I-Type: ORI");
        check_alu_ctrl(2'b11, 3'b111, 1'b0, ALU_AND,  "I-Type: ANDI");

        // --- Reporte Final ---
        $display("=========================================================================");
        if (error_count == 0) begin
            $display("   [ÉXITO] TODAS LAS PRUEBAS PASARON CORRECTAMENTE SIN ERRORES           ");
        end else begin
            $display("   [FALLO] SE ENCONTRARON %0d ERRORES EN LA VERIFICACIÓN                 ", error_count);
        end
        $display("=========================================================================");
        $finish;
    end

endmodule