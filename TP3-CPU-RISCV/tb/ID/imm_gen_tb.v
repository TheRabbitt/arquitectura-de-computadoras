`timescale 1ns / 1ps
`default_nettype none

module tb_imm_gen();

    // Señales del Testbench
    reg  [31:0] instruction;
    wire [31:0] imm;

    // Instanciación del Módulo Bajo Prueba (UUT)
    imm_gen uut (
        .i_instruction(instruction),
        .o_imm(imm)
    );

    initial begin
        $display("--- INICIO DE PRUEBAS DEL GENERADOR DE INMEDIATOS (IMM_GEN) ---");

        // -------------------------------------------------------------
        // PRUEBA 1: Tipo I - Positivo y Negativo (addi x1, x2, imm)
        // -------------------------------------------------------------
        $display("\n[Test 1] Probando Tipo-I (addi)");
        
        // addi x1, x2, 100 -> Imm = +100 (12'h064)
        // Inst: [imm[11:0] = 0x064][rs1 = 2][funct3 = 0][rd = 1][opcode = 0010011]
        instruction = {12'h064, 5'd2, 3'b000, 5'd1, 7'b0010011};
        #10;
        if (imm == 32'h0000_0064)
            $display("-> EXITO: Inmediato positivo Tipo-I correcto (+100).");
        else
            $display("-> ERROR: Inmediato Tipo-I incorrecto. Obtenido: %h", imm);

        // addi x1, x2, -50 -> Imm = -50 (12'hFCE)
        instruction = {12'hFCE, 5'd2, 3'b000, 5'd1, 7'b0010011};
        #10;
        if (imm == 32'hFFFF_FFCE)
            $display("-> EXITO: Extension de signo negativa Tipo-I correcta (-50).");
        else
            $display("-> ERROR: Extension de signo Tipo-I incorrecta. Obtenido: %h", imm);

        // -------------------------------------------------------------
        // PRUEBA 2: Tipo S - Positivo y Negativo (sw x1, offset(x2))
        // -------------------------------------------------------------
        $display("\n[Test 2] Probando Tipo-S (sw)");
        
        // sw x1, 20(x2) -> Imm = +20 (12'b0000000_10100)
        // Inst: [imm[11:5]=0000000][rs2=1][rs1=2][funct3=010][imm[4:0]=10100][opcode=0100011]
        instruction = {7'b0000000, 5'd1, 5'd2, 3'b010, 5'b10100, 7'b0100011};
        #10;
        if (imm == 32'h0000_0014)
            $display("-> EXITO: Inmediato Tipo-S correcto (+20).");
        else
            $display("-> ERROR: Inmediato Tipo-S incorrecto. Obtenido: %h", imm);

        // sw x1, -20(x2) -> Imm = -20 (12'b1111111_01100)
        instruction = {7'b1111111, 5'd1, 5'd2, 3'b010, 5'b01100, 7'b0100011};
        #10;
        if (imm == 32'hFFFF_FFEC)
            $display("-> EXITO: Extension de signo negativa Tipo-S correcta (-20).");
        else
            $display("-> ERROR: Extension de signo Tipo-S incorrecta. Obtenido: %h", imm);

        // -------------------------------------------------------------
        // PRUEBA 3: Tipo B - Salto Condicional (beq x1, x2, offset)
        // -------------------------------------------------------------
        $display("\n[Test 3] Probando Tipo-B (beq)");
        
        // beq x1, x2, +16 -> Imm = +16 (13'b0_0000_0001_0000)
        // inst[31]=0, inst[30:25]=000000, inst[11:8]=1000, inst[7]=0
        instruction = {1'b0, 6'b000000, 5'd2, 5'd1, 3'b000, 4'b1000, 1'b0, 7'b1100011};
        #10;
        if (imm == 32'h0000_0010)
            $display("-> EXITO: Inmediato Tipo-B correcto (+16).");
        else
            $display("-> ERROR: Inmediato Tipo-B incorrecto. Obtenido: %h", imm);

        // bne x1, x2, -16 -> Imm = -16 (13'b1_1111_1111_0000)
        // inst[31]=1, inst[30:25]=111111, inst[11:8]=1000, inst[7]=1
        instruction = {1'b1, 6'b111111, 5'd2, 5'd1, 3'b001, 4'b1000, 1'b1, 7'b1100011};
        #10;
        if (imm == 32'hFFFF_FFF0)
            $display("-> EXITO: Extension de signo negativa Tipo-B correcta (-16).");
        else
            $display("-> ERROR: Extension de signo Tipo-B incorrecta. Obtenido: %h", imm);

        // -------------------------------------------------------------
        // PRUEBA 4: Tipo U - Inmediato Superior (lui x1, 0x12345)
        // -------------------------------------------------------------
        $display("\n[Test 4] Probando Tipo-U (lui)");
        
        // lui x1, 0x12345 -> Imm = 0x12345000
        instruction = {20'h12345, 5'd1, 7'b0110111};
        #10;
        if (imm == 32'h1234_5000)
            $display("-> EXITO: Inmediato Tipo-U alineado a la izquierda correctamente.");
        else
            $display("-> ERROR: Inmediato Tipo-U incorrecto. Obtenido: %h", imm);

        // -------------------------------------------------------------
        // PRUEBA 5: Tipo J - Salto Incondicional (jal x1, offset)
        // -------------------------------------------------------------
        $display("\n[Test 5] Probando Tipo-J (jal)");
        
        // jal x1, +2048 -> Imm = +2048 (21'b0_0000_0000_1000_0000_0000)
        // inst[31]=0, inst[30:21]=0000000000, inst[20]=1, inst[19:12]=00000001
        instruction = {1'b0, 10'b0000000000, 1'b1, 8'b00000000, 5'd1, 7'b1101111};
        #10;
        if (imm == 32'h0000_0800)
            $display("-> EXITO: Inmediato Tipo-J correcto (+2048).");
        else
            $display("-> ERROR: Inmediato Tipo-J incorrecto. Obtenido: %h", imm);

        // -------------------------------------------------------------
        // PRUEBA 6: Tipo R (Sin Inmediato)
        // -------------------------------------------------------------
        $display("\n[Test 6] Probando Tipo-R (add)");
        
        // add x1, x2, x3 -> Debe retornar 0
        instruction = {7'b0000000, 5'd3, 5'd2, 3'b000, 5'd1, 7'b0110011};
        #10;
        if (imm == 32'h0000_0000)
            $display("-> EXITO: Tipo-R retorna 0 correctamente.");
        else
            $display("-> ERROR: Tipo-R debe entregar 0. Obtenido: %h", imm);

        $display("\n--- FIN DE LAS PRUEBAS ---");
        $finish;
    end

endmodule
`default_nettype wire