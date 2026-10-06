`timescale 1ns / 1ps
`default_nettype none

module tb_forwarding_unit;

    // Entradas del DUT
    reg [4:0] tb_id_ex_rs1;
    reg [4:0] tb_id_ex_rs2;
    reg [4:0] tb_ex_mem_rd;
    reg       tb_ex_mem_regwrite;
    reg [4:0] tb_mem_wb_rd;
    reg       tb_mem_wb_regwrite;

    // Salidas del DUT
    wire [1:0] tb_forward_a;
    wire [1:0] tb_forward_b;

    // Contador de errores
    integer error_count = 0;

    // Instanciación del módulo
    forwarding_unit uut (
        .i_id_ex_rs1       (tb_id_ex_rs1),
        .i_id_ex_rs2       (tb_id_ex_rs2),
        .i_ex_mem_rd       (tb_ex_mem_rd),
        .i_ex_mem_regwrite (tb_ex_mem_regwrite),
        .i_mem_wb_rd       (tb_mem_wb_rd),
        .i_mem_wb_regwrite (tb_mem_wb_regwrite),
        .o_forward_a       (tb_forward_a),
        .o_forward_b       (tb_forward_b)
    );

    // Tarea autochequeable
    task check_fw(
        input [4:0] rs1,
        input [4:0] rs2,
        input [4:0] ex_rd,
        input       ex_rw,
        input [4:0] mem_rd,
        input       mem_rw,
        input [1:0] exp_fa,
        input [1:0] exp_fb,
        input [8*40:1] test_name
    );
        begin
            tb_id_ex_rs1       = rs1;
            tb_id_ex_rs2       = rs2;
            tb_ex_mem_rd       = ex_rd;
            tb_ex_mem_regwrite = ex_rw;
            tb_mem_wb_rd       = mem_rd;
            tb_mem_wb_regwrite = mem_rw;
            #5; // Espera para propagación de lógica combinacional

            if ((tb_forward_a !== exp_fa) || (tb_forward_b !== exp_fb)) begin
                $display("[ERROR] %-40s | FA Exp: %b Obt: %b | FB Exp: %b Obt: %b", 
                         test_name, exp_fa, tb_forward_a, exp_fb, tb_forward_b);
                error_count = error_count + 1;
            end else begin
                $display("[OK]    %-40s | FA: %b | FB: %b", test_name, tb_forward_a, tb_forward_b);
            end
        end
    endtask

    initial begin
        $display("=========================================================================");
        $display("          INICIO DE PRUEBAS AUTOMATIZADAS: FORWARDING UNIT               ");
        $display("=========================================================================");

        // Valores iniciales (sin adelantamiento)
        // check_fw(rs1, rs2, ex_rd, ex_rw, mem_rd, mem_rw, exp_fa, exp_fb, "Nombre del test");

        // Sin riesgo (No hay coincidencias)
        check_fw(5'd5, 5'd6, 5'd7, 1'b1, 5'd8, 1'b1, 2'b00, 2'b00, "Sin riesgo: Registros distintos");

        // Sin riesgo (Hay coincidencias pero RegWrite está apagado)
        check_fw(5'd5, 5'd6, 5'd5, 1'b0, 5'd6, 1'b0, 2'b00, 2'b00, "Sin riesgo: RegWrite en 0");

        // Riesgo de Datos en EX (Precedencia EX/MEM) - Adelanto hacia A
        check_fw(5'd10, 5'd6, 5'd10, 1'b1, 5'd0, 1'b0, 2'b10, 2'b00, "Riesgo EX en RS1 -> ForwardA = 10");

        // Riesgo de Datos en EX (Precedencia EX/MEM) - Adelanto hacia B
        check_fw(5'd5, 5'd11, 5'd11, 1'b1, 5'd0, 1'b0, 2'b00, 2'b10, "Riesgo EX en RS2 -> ForwardB = 10");

        // Riesgo de Datos en MEM (Precedencia MEM/WB) - Adelanto hacia A
        check_fw(5'd15, 5'd6, 5'd0, 1'b0, 5'd15, 1'b1, 2'b01, 2'b00, "Riesgo MEM en RS1 -> ForwardA = 01");

        // Riesgo de Datos en MEM (Precedencia MEM/WB) - Adelanto hacia B
        check_fw(5'd5, 5'd20, 5'd0, 1'b0, 5'd20, 1'b1, 2'b00, 2'b01, "Riesgo MEM en RS2 -> ForwardB = 01");

        // Riesgo Doble (Tanto EX como MEM escriben en el mismo registro)
        // La etapa EX/MEM es más reciente, por lo que debe tomar prioridad.
        check_fw(5'd25, 5'd6, 5'd25, 1'b1, 5'd25, 1'b1, 2'b10, 2'b00, "Riesgo Doble RS1 (Prioridad EX sobre MEM)");

        // Protección del registro x0 (Cero)
        // Aunque coincidan los registros fuente y destino, x0 nunca debe adelantarse.
        check_fw(5'd0, 5'd0, 5'd0, 1'b1, 5'd0, 1'b1, 2'b00, 2'b00, "Ignorar adelantamiento para x0");

        // Adelantamientos mixtos (Un operando desde EX, otro desde MEM)
        check_fw(5'd12, 5'd14, 5'd12, 1'b1, 5'd14, 1'b1, 2'b10, 2'b01, "RS1 de EX (10) y RS2 de MEM (01)");

        $display("=========================================================================");
        if (error_count == 0) begin
            $display("   [ÉXITO] TODAS LAS PRUEBAS DE LA FORWARDING UNIT PASARON               ");
        end else begin
            $display("   [FALLO] SE ENCONTRARON %0d ERRORES EN LA VERIFICACION                 ", error_count);
        end
        $display("=========================================================================");
        $finish;
    end

endmodule
`default_nettype wire