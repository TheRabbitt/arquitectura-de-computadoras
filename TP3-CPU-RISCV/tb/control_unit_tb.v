`timescale 1ns / 1ps
`default_nettype none

module tb_control_unit;

    // Señales de entrada (reg)
    reg [6:0] i_opcode;

    // Señales de salida (wire)
    wire       o_branch;
    wire       o_mem_read;
    wire       o_mem_to_reg;
    wire [1:0] o_alu_op;
    wire       o_mem_write;
    wire       o_alu_src;
    wire       o_reg_write;

    // Instanciación del módulo bajo prueba (UUT)
    control_unit uut (
        .i_opcode(i_opcode),
        .o_branch(o_branch),
        .o_mem_read(o_mem_read),
        .o_mem_to_reg(o_mem_to_reg),
        .o_alu_op(o_alu_op),
        .o_mem_write(o_mem_write),
        .o_alu_src(o_alu_src),
        .o_reg_write(o_reg_write)
    );

    initial begin
        $display("--- INICIO DE PRUEBAS DE LA UNIDAD DE CONTROL ---");
        
        // Monitor para observar las salidas en cada cambio de opcode
        $monitor("Tiempo=%0t | Opcode=%b || Branch=%b | MemRead=%b | MemToReg=%b | ALUOp=%b | MemWrite=%b | ALUSrc=%b | RegWrite=%b", 
                 $time, i_opcode, o_branch, o_mem_read, o_mem_to_reg, o_alu_op, o_mem_write, o_alu_src, o_reg_write);

        // -----------------------------------------------------------
        // PRUEBA 1: Tipo R (Aritmético/Lógico)
        // Opcode: 0110011
        // Esperado: RegWrite=1, ALUOp=10, Resto=0
        // -----------------------------------------------------------
        i_opcode = 7'b0110011;
        $display("\n[Test 1] Tipo R (Aritmético/Lógico): Esperado: RegWrite=1, ALUOp=10, Resto=0");
        #10;

        // -----------------------------------------------------------
        // PRUEBA 2: Tipo I (Load - lw)
        // Opcode: 0000011
        // Esperado: ALUSrc=1, MemToReg=1, RegWrite=1, MemRead=1, ALUOp=00
        // -----------------------------------------------------------
        i_opcode = 7'b0000011;
        $display("\n[Test 2] Tipo I (Load - lw): Esperado: ALUSrc=1, MemToReg=1, RegWrite=1, MemRead=1, ALUOp=00");
        #10;

        // -----------------------------------------------------------
        // PRUEBA 3: Tipo S (Store - sw)
        // Opcode: 0100011
        // Esperado: ALUSrc=1, MemWrite=1, ALUOp=00, Resto=0
        // -----------------------------------------------------------
        i_opcode = 7'b0100011;
        $display("\n[Test 3] Tipo S (Store - sw): Esperado: ALUSrc=1, MemWrite=1, ALUOp=00, Resto=0");
        #10;

        // -----------------------------------------------------------
        // PRUEBA 4: Tipo B (Branch - beq/bne)
        // Opcode: 1100011
        // Esperado: Branch=1, ALUOp=01, Resto=0
        // -----------------------------------------------------------
        i_opcode = 7'b1100011;
        $display("\n[Test 4] Tipo B (Branch - beq/bne): Esperado: Branch=1, ALUOp=01 (Don't care), Resto=0");
        #10;

        // -----------------------------------------------------------
        // PRUEBA 5: Opcode inválido o no soportado (Seguridad)
        // Opcode: 0000000
        // Esperado: Todas las señales en 0 para evitar escrituras corruptas
        // -----------------------------------------------------------
        i_opcode = 7'b0000000;
        $display("\n[Test 5] Opcode inválido/no soportado: Esperado: Todas las señales en 0");
        #10;

        $display("--- FIN DE LAS PRUEBAS ---");
        $finish;
    end

endmodule
`default_nettype wire