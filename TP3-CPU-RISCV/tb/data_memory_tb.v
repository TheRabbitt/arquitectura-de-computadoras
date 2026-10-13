`timescale 1ns / 1ps
`default_nettype none

module tb_data_memory;

    // -------------------------------------------------------------------------
    // Parámetros
    // -------------------------------------------------------------------------
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 8;

    // -------------------------------------------------------------------------
    // Señales de prueba
    // -------------------------------------------------------------------------
    reg                   i_clk;
    
    // Interfaz del Pipeline
    reg                   i_mem_write;
    reg                   i_mem_read;
    reg  [DATA_WIDTH-1:0] i_addr;
    reg  [DATA_WIDTH-1:0] i_write_data;
    wire [DATA_WIDTH-1:0] o_read_data;
    
    // Interfaz de la UART / Debug
    reg                   i_debug_re;
    reg  [ADDR_WIDTH-1:0] i_debug_addr;
    wire [DATA_WIDTH-1:0] o_debug_rdata;

    // -------------------------------------------------------------------------
    // Instanciación del módulo a probar (UUT)
    // -------------------------------------------------------------------------
    data_memory #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) uut (
        .i_clk(i_clk),
        .i_mem_write(i_mem_write),
        .i_mem_read(i_mem_read),
        .i_addr(i_addr),
        .i_write_data(i_write_data),
        .o_read_data(o_read_data),
        .i_debug_re(i_debug_re),
        .i_debug_addr(i_debug_addr),
        .o_debug_rdata(o_debug_rdata)
    );

    // -------------------------------------------------------------------------
    // Generación de Reloj (Periodo = 10ns)
    // -------------------------------------------------------------------------
    initial begin
        i_clk = 0;
        forever #5 i_clk = ~i_clk;
    end

    // -------------------------------------------------------------------------
    // Secuencia de Pruebas
    // -------------------------------------------------------------------------
    initial begin
        // Inicialización de señales
        i_mem_write  = 0;
        i_mem_read   = 0;
        i_addr       = 0;
        i_write_data = 0;
        i_debug_re   = 0;
        i_debug_addr = 0;

        $display("=== Iniciando Simulacion de data_memory ===");

        // Esperar un poco para salir de tiempo 0
        #15;

        // ---------------------------------------------------------------------
        // Prueba 1: Escritura desde el procesador (Etapa MEM simula SW)
        // ---------------------------------------------------------------------
        $display("[%0t] Prueba 1: Escritura de datos (SW)", $time);
        
        // Escribir 0xDEADBEEF en la direccion 0x00
        i_mem_write  = 1;
        i_addr       = 32'h0000_0000;
        i_write_data = 32'hDEAD_BEEF;
        #10;
        
        // Escribir 0xCAFEBABE en la direccion 0x04 (Palabra 1)
        i_addr       = 32'h0000_0004;
        i_write_data = 32'hCAFE_BABE;
        #10;
        
        // Escribir 0x12345678 en la direccion 0x08 (Palabra 2)
        i_addr       = 32'h0000_0008;
        i_write_data = 32'h1234_5678;
        #10;

        i_mem_write  = 0;
        #10;

        // ---------------------------------------------------------------------
        // Prueba 2: Lectura desde el procesador (Etapa MEM simula LW)
        // ---------------------------------------------------------------------
        $display("[%0t] Prueba 2: Lectura desde el procesador (LW)", $time);
        i_mem_read = 1;

        // Leer direccion 0x04 (Debería ser 0xCAFEBABE)
        i_addr = 32'h0000_0004;
        #10;
        if (o_read_data === 32'hCAFE_BABE)
            $display("  -> OK: Leido %h en dir 0x04", o_read_data);
        else
            $display("  -> ERROR: Se esperaba CAFEBABE, se leyo %h", o_read_data);

        // Leer direccion 0x00 (Debería ser 0xDEADBEEF)
        i_addr = 32'h0000_0000;
        #10;
        if (o_read_data === 32'hDEAD_BEEF)
            $display("  -> OK: Leido %h en dir 0x00", o_read_data);
        else
            $display("  -> ERROR: Se esperaba DEADBEEF, se leyo %h", o_read_data);

        i_mem_read = 0;
        #10;

        // ---------------------------------------------------------------------
        // Prueba 3: Lectura desde el puerto dedicado UART / Debug
        // ---------------------------------------------------------------------
        $display("[%0t] Prueba 3: Lectura iterativa desde la UART", $time);
        i_debug_re = 1;

        // La UART direcciona por palabras (0, 1, 2...), no por bytes
        i_debug_addr = 8'd0; // Debería leer lo que está en 0x00 (DEADBEEF)
        #10;
        $display("  -> UART Lee dir 0: %h", o_debug_rdata);

        i_debug_addr = 8'd1; // Debería leer lo que está en 0x04 (CAFEBABE)
        #10;
        $display("  -> UART Lee dir 1: %h", o_debug_rdata);

        i_debug_addr = 8'd2; // Debería leer lo que está en 0x08 (12345678)
        #10;
        $display("  -> UART Lee dir 2: %h", o_debug_rdata);

        i_debug_re = 0;

        // ---------------------------------------------------------------------
        // Prueba 4: No se puede leer sin habilitación de lectura
        // ---------------------------------------------------------------------
        $display("[%0t] Prueba 4: Intento de lectura sin habilitación", $time);
        i_debug_addr = 8'd0; // Intento de leer dir 0
        #10;
        if (o_debug_rdata === 32'b0)
            $display("  -> OK: Sin habilitación, UART devuelve 0");
        else
            $display("  -> ERROR: Sin habilitación, UART devolvió %h", o_debug_rdata);

        if(o_read_data === 32'b0)
            $display("  -> OK: Sin habilitación, Datapath devuelve 0");
        else
            $display("  -> ERROR: Sin habilitación, Datapath devolvió %h", o_read_data);

        // ---------------------------------------------------------------------
        // Prueba 5: No se puede escribir sin habilitación de escritura
        // ---------------------------------------------------------------------
        $display("[%0t] Prueba 5: Intento de escritura sin habilitación", $time);
        i_mem_write  = 0; // Asegurarse de que la escritura está deshabilitada
        i_addr       = 32'h0000_000C; // Palabra 3
        i_write_data = 32'hFFFFFFFF; // Intento de escribir
        #10;
        if(o_read_data == 32'hFFFFFFFF)
            $display("  -> ERROR: Sin habilitación, Datapath escribió %h", o_read_data);
        else
            $display("  -> OK: Sin habilitación, Datapath no escribió (valor actual: %h)", o_read_data);
        
        // ---------------------------------------------------------------------
        // Fin de simulación
        // ---------------------------------------------------------------------
        #20;
        $display("=== Fin de la Simulacion ===");
        $finish;
    end

endmodule
`default_nettype wire