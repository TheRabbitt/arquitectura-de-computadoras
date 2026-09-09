`timescale 1ns / 1ps
`default_nettype none

module tb_register_file();

    // Declaración de señales
    reg         clk;
    reg         rst;
    reg         reg_write;
    reg  [4:0]  read_reg1;
    reg  [4:0]  read_reg2;
    reg  [4:0]  write_reg;
    reg  [31:0] write_data;

    wire [31:0] read_data1;
    wire [31:0] read_data2;

    // Instanciación del Módulo
    register_file uut (
        .i_clk(clk),
        .i_rst(rst),
        .i_reg_write(reg_write),
        .i_read_reg1(read_reg1),
        .i_read_reg2(read_reg2),
        .i_write_reg(write_reg),
        .i_write_data(write_data),
        .o_read_data1(read_data1),
        .o_read_data2(read_data2)
    );

    // Generación del Reloj (Periodo de 10ns -> 100MHz)
    always #5 clk = ~clk;

    // Estímulos de Prueba
    initial begin
        // Inicialización de señales
        clk = 0;
        rst = 1;
        reg_write = 0;
        read_reg1 = 0;
        read_reg2 = 0;
        write_reg = 0;
        write_data = 0;

        $display("--- INICIO DE PRUEBAS DEL BANCO DE REGISTROS ---");

        // Dejar pasar un par de ciclos y soltar el reset
        #20;
        rst = 0;

        // ---------------------------------------------------------
        // PRUEBA 1: Escritura y Lectura Normal
        // ---------------------------------------------------------
        $display("[Test 1] Escribiendo 32'hAAAA_AAAA en x5 y 32'h5555_5555 en x10");
        
        // Escribir en x5
        reg_write = 1; 
        write_reg = 5; 
        write_data = 32'hAAAA_AAAA;
        #10; // Esperar un ciclo de reloj para que se guarde

        // Escribir en x10
        write_reg = 10; 
        write_data = 32'h5555_5555;
        #10;
        
        // Detener escritura y proceder a leer ambos registros a la vez
        reg_write = 0;
        read_reg1 = 5;
        read_reg2 = 10;
        #5; // Pequeña demora para que la lógica combinacional se asiente
        
        if (read_data1 == 32'hAAAA_AAAA && read_data2 == 32'h5555_5555)
            $display("-> EXITO: Lectura correcta de x5 y x10.");
        else
            $display("-> ERROR: Datos incorrectos. read1=%h, read2=%h", read_data1, read_data2);
            
        // ---------------------------------------------------------
        // PRUEBA 2: Internal Forwarding (Write-Through)
        // ---------------------------------------------------------
        // Vamos a escribir en el registro x15 y pedir leerlo en el MISMO ciclo
        $display("\n[Test 2] Probando Internal Forwarding en x15");
        #5;
        
        reg_write = 1;
        write_reg = 15;
        write_data = 32'hDEAD_BEEF;
        
        read_reg1 = 15; // Pedimos leer x15 mientras i_reg_write está en 1
        
        #1; // Esperamos solo 1ns (mucho menos que un ciclo de reloj)
        if (read_data1 == 32'hDEAD_BEEF)
            $display("-> EXITO: El dato fresco (DEAD_BEEF) fluye instantaneamente a la salida.");
        else
            $display("-> ERROR: Internal Forwarding fallido. read1=%h", read_data1);
            
        #9; // Completar el ciclo de reloj

        // ---------------------------------------------------------
        // PRUEBA 3: Protección del registro x0
        // ---------------------------------------------------------
        $display("\n[Test 3] Intentando escribir en el registro x0");
        
        reg_write = 1;
        write_reg = 0;
        write_data = 32'hFFFF_FFFF;
        
        read_reg1 = 0; // Intentamos leer x0 al mismo tiempo (a ver si el forwarding lo pisa)
        
        #1; // Esperar lógica combinacional
        if (read_data1 == 32'h0000_0000)
            $display("-> EXITO: x0 mantiene el valor cero durante la escritura.");
        else
            $display("-> ERROR: x0 se dejo sobreescribir por forwarding. read1=%h", read_data1);
            
        #9; // Completar ciclo
        reg_write = 0; // Detener escritura
        #5; 
        
        if (read_data1 == 32'h0000_0000)
            $display("-> EXITO: x0 mantiene el valor cero de forma permanente en memoria.");
        else
            $display("-> ERROR: x0 cambio en memoria. read1=%h", read_data1);

        // -------------------------------------------------------------
        // PRUEBA 4: Escribir un registro y leer otro en el mismo ciclo
        // -------------------------------------------------------------
        $display("\n[Test 4] Escribir x20 y leer x5 y x10 en el mismo ciclo");    
        reg_write = 1;
        write_reg = 20;
        write_data = 32'h1234_5678;

        read_reg1 = 5;  // x5 debería seguir siendo AAAA_AAAA
        read_reg2 = 10; // x10 debería seguir siendo 5555_555

        #1; // Esperar lógica combinacional
        if (read_data1 == 32'hAAAA_AAAA && read_data2 == 32'h5555_5555)
            $display("-> EXITO: Lectura correcta de x5 y x10 mientras se escribe x20.");
        else
            $display("-> ERROR: Datos incorrectos durante escritura de x20. read1=%h, read2=%h", read_data1, read_data2);

        // Leer x20 en el siguiente ciclo para confirmar que se escribió correctamente
        #9; // Completar ciclo
        read_reg1 = 20; // Ahora leemos x20
        #1; // Esperar lógica combinacional
        if (read_data1 == 32'h1234_5678)
            $display("-> EXITO: x20 fue escrito correctamente y se puede leer ahora.");
        else
            $display("-> ERROR: x20 no contiene el valor esperado. read1=%h", read_data1);

        $display("\n--- FIN DE LAS PRUEBAS ---");
        #20;
        $finish;
    end

endmodule
`default_nettype wire