`timescale 1ns / 1ps
`default_nettype none

module tb_branch_comparator;

    // Señales de entrada (reg)
    reg [31:0] i_data1;
    reg [31:0] i_data2;
    reg [2:0]  i_funct3;

    // Señales de salida (wire)
    wire o_take_branch;

    // Instanciación del módulo bajo prueba (UUT)
    branch_comparator uut (
        .i_data1(i_data1),
        .i_data2(i_data2),
        .i_funct3(i_funct3),
        .o_take_branch(o_take_branch)
    );

    initial begin
        $display("--- INICIO DE PRUEBAS DEL COMPARADOR DE SALTOS ---");
        
        // Monitor para observar los cambios en tiempo real
        $monitor("Tiempo=%0t | funct3=%b | data1=%h | data2=%h || take_branch=%b", 
                 $time, i_funct3, i_data1, i_data2, o_take_branch);

        // -----------------------------------------------------------
        // PRUEBA 1: BEQ (000) con datos IGUALES
        // Resultado esperado: take_branch = 1
        // -----------------------------------------------------------
        i_funct3 = 3'b000;
        i_data1  = 32'hAAAA_5555;
        i_data2  = 32'hAAAA_5555;
        $display("\n[Test 1] BEQ (000) con datos IGUALES");
        #10;

        // -----------------------------------------------------------
        // PRUEBA 2: BEQ (000) con datos DISTINTOS
        // Resultado esperado: take_branch = 0
        // -----------------------------------------------------------
        i_funct3 = 3'b000;
        i_data1  = 32'hAAAA_5555;
        i_data2  = 32'hBBBB_6666;
        $display("\n[Test 2] BEQ (000) con datos DISTINTOS");
        #10;

        // -----------------------------------------------------------
        // PRUEBA 3: BNE (001) con datos IGUALES
        // Resultado esperado: take_branch = 0
        // -----------------------------------------------------------
        i_funct3 = 3'b001;
        i_data1  = 32'h1234_5678;
        i_data2  = 32'h1234_5678;
        $display("\n[Test 3] BNE (001) con datos IGUALES");
        #10;

        // -----------------------------------------------------------
        // PRUEBA 4: BNE (001) con datos DISTINTOS
        // Resultado esperado: take_branch = 1
        // -----------------------------------------------------------
        i_funct3 = 3'b001;
        i_data1  = 32'h1234_5678;
        i_data2  = 32'hFFFF_FFFF;
        $display("\n[Test 4] BNE (001) con datos DISTINTOS");
        #10;

        $display("--- FIN DE LAS PRUEBAS ---");
        $finish;
    end

endmodule
`default_nettype wire