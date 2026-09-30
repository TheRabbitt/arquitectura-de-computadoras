`timescale 1ns / 1ps
`default_nettype none

module tb_alu;

    // Parámetros de la ALU
    localparam NB_IN  = 32;
    localparam NB_OUT = 32;
    localparam NB_OP  = 4;

    // Entradas del DUT
    reg  [NB_IN-1:0] tb_a;
    reg  [NB_IN-1:0] tb_b;
    reg  [NB_OP-1:0] tb_op;

    // Salida del DUT
    wire [NB_OUT-1:0] tb_outresult;

    // Contador de errores
    integer error_count = 0;

    // Códigos de operación (Idénticos a los definidos en alu.v)
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

    // Instanciación de la ALU
    alu #(
        .NB_IN  (NB_IN),
        .NB_OUT (NB_OUT),
        .NB_OP  (NB_OP)
    ) uut (
        .i_a         (tb_a),
        .i_b         (tb_b),
        .i_op        (tb_op),
        .o_outresult (tb_outresult)
    );

    // Tarea auxiliar de verificación combinacional
    task check_alu(
        input [NB_IN-1:0]  a,
        input [NB_IN-1:0]  b,
        input [NB_OP-1:0]  op,
        input [NB_OUT-1:0] expected_res,
        input [8*30:1]     test_name
    );
        begin
            tb_a  = a;
            tb_b  = b;
            tb_op = op;
            #5; // Tiempo para propagación de la lógica combinacional

            if (tb_outresult !== expected_res) begin
                $display("[ERROR] %-30s | A:0x%h (%0d) B:0x%h (%0d) OP:%b | Esperado: 0x%h | Obtenido: 0x%h",
                         test_name, tb_a, $signed(tb_a), tb_b, $signed(tb_b), tb_op, expected_res, tb_outresult);
                error_count = error_count + 1;
            end else begin
                $display("[OK]    %-30s | A:0x%h B:0x%h OP:%b -> Result: 0x%h",
                         test_name, tb_a, tb_b, tb_op, tb_outresult);
            end
        end
    endtask

    initial begin
        $display("=========================================================================");
        $display("          INICIO DE PRUEBAS AUTOMATIZADAS: ALU (32 BITS)                 ");
        $display("=========================================================================");

        // --- Aritmética Básica (ADD, SUB) ---
        check_alu(32'd15, 32'd27, ALU_ADD, 32'd42, "ADD: Positivos (15 + 27)");
        check_alu(32'd50, 32'd20, ALU_SUB, 32'd30, "SUB: Positivos (50 - 20)");
        check_alu(32'd10, 32'd15, ALU_SUB, -32'd5, "SUB: Resultado negativo (10 - 15)");

        // --- Operaciones Lógicas (AND, OR, XOR) ---
        check_alu(32'hFFFF0000, 32'h00FFFF00, ALU_AND, 32'h00FF0000, "AND: Mascara");
        check_alu(32'hF0F00000, 32'h0F0F0000, ALU_OR,  32'hFFFF0000, "OR: Combinación");
        check_alu(32'hAA55AA55, 32'hFFFF0000, ALU_XOR, 32'h55AAAA55, "XOR: Inversión selectiva");

        // --- Desplazamientos (SLL, SRL, SRA) ---
        check_alu(32'h00000001, 32'd4,  ALU_SLL, 32'h00000010, "SLL: Desplazamiento Izquierda (1 << 4)");
        check_alu(32'h80000000, 32'd4,  ALU_SRL, 32'h08000000, "SRL: Desplazamiento Logico Der (MSB=1)");
        check_alu(32'h80000000, 32'd4,  ALU_SRA, 32'hF8000000, "SRA: Desplazamiento Aritmetico (Ext. Signo)");
        check_alu(32'h00000001, 32'd35, ALU_SLL, 32'h00000008, "SLL: Mascara de B[4:0] (35 mod 32 = 3)");

        // --- Comparaciones (SLT, SLTU) ---
        check_alu(-32'd10, 32'd5, ALU_SLT,  32'd1, "SLT: -10 < 5 (Con signo -> True)");
        check_alu(-32'd10, 32'd5, ALU_SLTU, 32'd0, "SLTU: -10 < 5 (Sin signo -> False)");
        check_alu(32'd5,  32'd10, ALU_SLT,  32'd1, "SLT: 5 < 10 (True)");
        check_alu(32'd10,  32'd5, ALU_SLT,  32'd0, "SLT: 10 < 5 (False)");

        // --- Pasaje directo (LUI / PASS_B) ---
        check_alu(32'h12345678, 32'hDEADBEEF, ALU_PASS_B, 32'hDEADBEEF, "PASS_B: Copia directa de B");

        // --- Caso Default (Opcode Inválido) ---
        check_alu(32'd10, 32'd20, 4'b1111, 32'd0, "DEFAULT: Opcode desconocido");

        // --- Reporte Final ---
        $display("=========================================================================");
        if (error_count == 0) begin
            $display("   [ÉXITO] TODAS LAS PRUEBAS DE LA ALU PASARON CORRECTAMENTE             ");
        end else begin
            $display("   [FALLO] SE ENCONTRARON %0d ERRORES EN LA VERIFICACION DE LA ALU       ", error_count);
        end
        $display("=========================================================================");
        $finish;
    end

endmodule
`default_nettype wire