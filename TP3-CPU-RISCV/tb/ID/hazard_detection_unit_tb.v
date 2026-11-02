`timescale 1ns / 1ps
`default_nettype none

module tb_hazard_detection_unit;

    // Señales de entrada (reg)
    reg       id_ex_mem_read;
    reg [4:0] id_ex_rd;
    reg [4:0] if_id_rs1;
    reg [4:0] if_id_rs2;

    // Señales de salida (wire)
    wire pc_write;
    wire if_id_write;
    wire ctrl_mux_sel;

    // Instanciación del módulo bajo prueba (UUT)
    hazard_detection_unit uut (
        .id_ex_mem_read(id_ex_mem_read),
        .id_ex_rd(id_ex_rd),
        .if_id_rs1(if_id_rs1),
        .if_id_rs2(if_id_rs2),
        .pc_write(pc_write),
        .if_id_write(if_id_write),
        .ctrl_mux_sel(ctrl_mux_sel)
    );

    initial begin
        $display("--- INICIO DE PRUEBAS DE HAZARD DETECTION UNIT (RISC-V) ---");
        
        // Monitor para observar los cambios
        $monitor("Tiempo=%0t | MemRead=%b | EX_rd=%d | ID_rs1=%d | ID_rs2=%d || pc_write=%b | if_id_write=%b | ctrl_mux=%b", 
                 $time, id_ex_mem_read, id_ex_rd, if_id_rs1, if_id_rs2, pc_write, if_id_write, ctrl_mux_sel);

        // -----------------------------------------------------------
        // PRUEBA 1: Sin riesgo (Instrucción normal sin Load previo)
        // -----------------------------------------------------------
        id_ex_mem_read = 1'b0;
        id_ex_rd       = 5'd5;
        if_id_rs1      = 5'd6;
        if_id_rs2      = 5'd7;

        $display("\n[Test 1] Sin riesgo (Instrucción normal sin Load previo)");
        #10;
        
        // -----------------------------------------------------------
        // PRUEBA 2: Riesgo Load-Use en rs1
        // (Ej: lw x5, 0(x2) seguido de add x8, x5, x7)
        // -----------------------------------------------------------
        id_ex_mem_read = 1'b1;
        id_ex_rd       = 5'd5;
        if_id_rs1      = 5'd5; // rs1 coincide con el rd del Load
        if_id_rs2      = 5'd7;

        $display("\n[Test 2] Riesgo Load-Use en rs1 (lw seguido de add con rs1 = rd del Load)");
        #10;

        // -----------------------------------------------------------
        // PRUEBA 3: Riesgo Load-Use en rs2
        // (Ej: lw x9, 0(x2) seguido de add x8, x7, x9)
        // -----------------------------------------------------------
        id_ex_mem_read = 1'b1;
        id_ex_rd       = 5'd9;
        if_id_rs1      = 5'd7;
        if_id_rs2      = 5'd9; // rs2 coincide con el rd del Load

        $display("\n[Test 3] Riesgo Load-Use en rs2 (lw seguido de add con rs2 = rd del Load)");
        #10;

        // -----------------------------------------------------------
        // PRUEBA 4: Dependencia de datos estándar (SIN Load)
        // (Ej: add x5, x1, x2 seguido de sub x8, x5, x7)
        // Esto lo resuelve Forwarding Unit, NO debe haber stall.
        // -----------------------------------------------------------
        id_ex_mem_read = 1'b0;
        id_ex_rd       = 5'd5;
        if_id_rs1      = 5'd5;
        if_id_rs2      = 5'd7;

        $display("\n[Test 4] Dependencia de datos estándar (SIN Load) - Forwarding Unit debe resolverlo");
        #10;

        // -----------------------------------------------------------
        // PRUEBA 5: Riesgo ignorado con el registro x0
        // (Ej: lw x0, 0(x2) seguido de add x8, x0, x7)
        // Como x0 está cableado a cero, no hay riesgo real.
        // -----------------------------------------------------------
        id_ex_mem_read = 1'b1;
        id_ex_rd       = 5'd0;
        if_id_rs1      = 5'd0;
        if_id_rs2      = 5'd7;

        $display("\n[Test 5] Riesgo ignorado con el registro x0 (lw x0 seguido de add con rs1 = x0)");
        #10;

        $display("--- FIN DE LAS PRUEBAS ---");
        $finish;
    end

endmodule
`default_nettype wire