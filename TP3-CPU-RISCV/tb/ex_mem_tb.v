`timescale 1ns / 1ps
`default_nettype none

module tb_ex_mem_latch;

    // Señales de reloj y control global
    reg clk;
    reg rst;
    reg i_enable;

    // Entradas de control y datos
    reg        i_wb_regwrite;
    reg        i_wb_memtoreg;
    reg        i_m_memread;
    reg        i_m_memwrite;
    reg [31:0] i_alu_result;
    reg [31:0] i_rs2_data;
    reg [4:0]  i_rd;

    // Salidas del Latch
    wire        o_wb_regwrite;
    wire        o_wb_memtoreg;
    wire        o_m_memread;
    wire        o_m_memwrite;
    wire [31:0] o_alu_result;
    wire [31:0] o_rs2_data;
    wire [4:0]  o_rd;

    integer error_count = 0;

    // Instanciación del DUT (Device Under Test)
    ex_mem_latch uut (
        .clk           (clk),
        .rst           (rst),
        .i_enable      (i_enable),
        .i_wb_regwrite (i_wb_regwrite),
        .i_wb_memtoreg (i_wb_memtoreg),
        .i_m_memread   (i_m_memread),
        .i_m_memwrite  (i_m_memwrite),
        .i_alu_result  (i_alu_result),
        .i_rs2_data    (i_rs2_data),
        .i_rd          (i_rd),
        .o_wb_regwrite (o_wb_regwrite),
        .o_wb_memtoreg (o_wb_memtoreg),
        .o_m_memread   (o_m_memread),
        .o_m_memwrite  (o_m_memwrite),
        .o_alu_result  (o_alu_result),
        .o_rs2_data    (o_rs2_data),
        .o_rd          (o_rd)
    );

    // Generación del reloj (Periodo de 10ns -> 100MHz)
    always #5 clk = ~clk;

    // Tarea para verificar todas las salidas a la vez
    task check_outputs(
        input        exp_wb_rw,
        input        exp_wb_mtr,
        input        exp_m_mr,
        input        exp_m_mw,
        input [31:0] exp_alu_res,
        input [31:0] exp_rs2,
        input [4:0]  exp_rd,
        input [8*40:1] test_name
    );
        begin
            if ((o_wb_regwrite !== exp_wb_rw) || (o_wb_memtoreg !== exp_wb_mtr) ||
                (o_m_memread !== exp_m_mr)    || (o_m_memwrite !== exp_m_mw)    ||
                (o_alu_result !== exp_alu_res)|| (o_rs2_data !== exp_rs2)       ||
                (o_rd !== exp_rd)) begin
                $display("[ERROR] %-40s", test_name);
                error_count = error_count + 1;
            end else begin
                $display("[OK]    %-40s", test_name);
            end
        end
    endtask

    initial begin
        $display("=========================================================================");
        $display("             INICIO DE PRUEBAS: EX/MEM LATCH                             ");
        $display("=========================================================================");

        // Inicialización
        clk = 0;
        rst = 1; // Activamos el reset
        i_enable = 0;
        i_wb_regwrite = 0; i_wb_memtoreg = 0;
        i_m_memread = 0; i_m_memwrite = 0;
        i_alu_result = 32'h0; i_rs2_data = 32'h0; i_rd = 5'h0;

        // Esperamos un ciclo para que el reset sincrónico surta efecto
        #10; 
        check_outputs(0, 0, 0, 0, 32'h0, 32'h0, 5'h0, "Reset: Todas las salidas en 0");

        // -------------------------------------------------------------------
        // Prueba 1: Operación Normal (Pipeline Habilitado)
        // -------------------------------------------------------------------
        rst = 0;       // Quitamos reset
        i_enable = 1;  // Habilitamos flujo
        
        // Inyectamos valores tipo instrucción "Load Word" (LW)
        i_wb_regwrite = 1;
        i_wb_memtoreg = 1;
        i_m_memread   = 1;
        i_m_memwrite  = 0;
        i_alu_result  = 32'h10002000;
        i_rs2_data    = 32'h00000000;
        i_rd          = 5'd10;
        
        // Esperamos flanco de reloj
        #10; 
        check_outputs(1, 1, 1, 0, 32'h10002000, 32'h0, 5'd10, "Flujo Normal: Propagación de datos (LW)");

        // -------------------------------------------------------------------
        // Prueba 2: Latch Deshabilitado (Stall / Congelamiento para UART)
        // -------------------------------------------------------------------
        i_enable = 0; // Simulamos que la UART pausa el procesador
        
        // Cambiamos las entradas (como si la etapa EX intentara procesar otra cosa)
        i_wb_regwrite = 0;
        i_wb_memtoreg = 0;
        i_m_memread   = 0;
        i_m_memwrite  = 1;
        i_alu_result  = 32'hFFFFFFFF;
        i_rs2_data    = 32'hABCDEF12;
        i_rd          = 5'd31;

        // Esperamos un par de ciclos de reloj
        #20;
        // Las salidas NO deben haber cambiado y deben mantener los valores del ciclo anterior (LW)
        check_outputs(1, 1, 1, 0, 32'h10002000, 32'h0, 5'd10, "Stall: Salidas congeladas con i_enable=0");

        // -------------------------------------------------------------------
        // Prueba 3: Retomar Ejecución
        // -------------------------------------------------------------------
        i_enable = 1; // Liberamos la pausa
        
        // En el siguiente flanco, las entradas "nuevas" que se quedaron esperando deberían pasar
        #10;
        check_outputs(0, 0, 0, 1, 32'hFFFFFFFF, 32'hABCDEF12, 5'd31, "Retomar: Pasan los datos tras habilitar");

        // -------------------------------------------------------------------
        // Prueba 4: Reset Sincrónico durante operación
        // -------------------------------------------------------------------
        rst = 1; // Aplicamos reset en pleno vuelo
        #10;
        check_outputs(0, 0, 0, 0, 32'h0, 32'h0, 5'h0, "Reset Sincrónico borra el estado");

        $display("=========================================================================");
        if (error_count == 0) begin
            $display("   [ÉXITO] TODAS LAS PRUEBAS DEL LATCH EX/MEM PASARON                    ");
        end else begin
            $display("   [FALLO] SE ENCONTRARON %0d ERRORES EN LA VERIFICACION                 ", error_count);
        end
        $display("=========================================================================");
        
        $finish;
    end

endmodule
`default_nettype wire