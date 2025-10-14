// Testbench completo: Sistema UART-ALU con TX integrado
module uart_tx_tb;
    reg clk, reset;
    reg rx_line;                // Línea serial de entrada (para RX)
    wire tx_line;               // Línea serial de salida (del TX)
    wire s_tick;
    wire rx_done_tick;
    wire [7:0] rx_data;
    wire [7:0] alu_a, alu_b;
    wire [5:0] alu_op;
    wire alu_start;
    wire [7:0] alu_result;
    wire alu_carry, alu_zero;
    wire tx_start;
    wire [7:0] tx_data;
    wire tx_done_tick;
    
    // Parámetros de timing
    localparam CLK_PERIOD = 20;  // 50 MHz
    localparam BIT_PERIOD = 163 * 16 * CLK_PERIOD;  // Tiempo de 1 bit UART
    
    // ====== VARIABLES PARA MEJORAR EL DEBUG ======
    reg [7:0] tx_data_last;     // Guardar último tx_data transmitido
    reg tx_start_last;          // Guardar último estado de tx_start
    integer tx_byte_count;      // Contar bytes transmitidos
    
    // Instanciar Baud Rate Generator
    baud_rate_gen #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(19200),
        .OVERSAMPLING(16),
        .DVSR_BIT(8)
    ) brg_inst (
        .clk(clk),
        .reset(reset),
        .tick(s_tick)
    );
    
    // Instanciar UART RX
    uart_rx #(
        .DBIT(8),
        .SB_TICK(16)
    ) rx_inst (
        .clk(clk),
        .reset(reset),
        .rx(rx_line),
        .s_tick(s_tick),
        .rx_done_tick(rx_done_tick),
        .dout(rx_data)
    );
    
    // Instanciar UART TX
    uart_tx #(
        .DBIT(8),
        .SB_TICK(16)
    ) tx_inst (
        .clk(clk),
        .reset(reset),
        .tx_start(tx_start),
        .s_tick(s_tick),
        .din(tx_data),
        .tx_done_tick(tx_done_tick),
        .tx(tx_line)
    );
    
    // Instanciar ALU
    alu #(
        .NB_IN(8),
        .NB_OUT(8),
        .NB_OP(6)
    ) alu_inst (
        .i_a(alu_a),
        .i_b(alu_b),
        .i_op(alu_op),
        .o_outresult(alu_result),
        .o_carry(alu_carry),
        .o_zero(alu_zero)
    );
    
    // Instanciar interfaz ALU
    intf_alu #(
        .DBIT(8),
        .ALU_WIDTH(8)
    ) intf_inst (
        .clk(clk),
        .reset(reset),
        .rx_done_tick(rx_done_tick),
        .rx_data(rx_data),
        .alu_a(alu_a),
        .alu_b(alu_b),
        .alu_op(alu_op),
        .alu_start(alu_start),
        .alu_result(alu_result),
        .alu_carry(alu_carry),
        .alu_zero(alu_zero),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_done_tick(tx_done_tick)
    );
    
    // Clock de 50MHz
    initial clk = 0;
    always #10 clk = ~clk;
    
    // Tarea para enviar un byte por UART RX (simula PC enviando datos)
    task send_uart_byte;
        input [7:0] data;
        integer i;
        begin
            $display("  [TX_PC] Enviando byte: 0x%h (%d)", data, data);
            
            // Start bit
            rx_line = 0;
            #BIT_PERIOD;
            
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                rx_line = data[i];
                #BIT_PERIOD;
            end
            
            // Stop bit
            rx_line = 1;
            #BIT_PERIOD;
        end
    endtask
    
    // Tarea para recibir un byte del TX (simula PC recibiendo datos)
    task receive_uart_byte;
        output [7:0] data;
        integer i;
        begin
            data = 8'h00;
            
            // Esperar Start bit
            @(negedge tx_line);
            $display("  [RX_PC] Start bit detectado");
            
            // Ir al medio del Start bit
            #(BIT_PERIOD / 2);
            
            // Muestrear bits de datos en el medio de cada bit
            for (i = 0; i < 8; i = i + 1) begin
                #BIT_PERIOD;
                data[i] = tx_line;
            end
            
            // Verificar Stop bit
            #BIT_PERIOD;
            if (tx_line == 1'b1)
                $display("  [RX_PC] Stop bit OK - Byte recibido: 0x%h (%d)", data, data);
            else
                $display("  [RX_PC] ERROR: Stop bit incorrecto");
        end
    endtask
    
    // Variables para recepción
    reg [7:0] received_result;
    reg [7:0] received_flags;
    
    // ====== MONITOR DE TX CON FILTRO ======
    // Solo mostrar cuando tx_start cambia de 0 a 1
    always @(posedge clk) begin
        tx_data_last <= tx_data;
        tx_start_last <= tx_start;
        
        // Detectar transición 0→1 en tx_start (flanco positivo)
        if (tx_start && !tx_start_last) begin
            tx_byte_count = tx_byte_count + 1;
            $display("  [TX] INICIAR transmisión #%0d: tx_data = 0x%h", tx_byte_count, tx_data);
        end
        
        // Mostrar cuando se completa la transmisión
        if (tx_done_tick) begin
            $display("  [TX] ✓ Transmisión completada (byte #%0d)", tx_byte_count);
        end
    end
    
    // Secuencia de prueba
    initial begin
        $dumpfile("uart_system.vcd");
        $dumpvars(0, uart_tx_tb);
        
        // Inicialización
        reset = 1;
        rx_line = 1;  // Línea idle
        tx_byte_count = 0;
        tx_start_last = 0;
        tx_data_last = 0;
        #100;
        
        reset = 0;
        #100;
        
        $display("\n========================================");
        $display("Sistema UART-ALU Bidireccional");
        $display("========================================\n");
        
        // ========== PRUEBA 1: ADD (5 + 3 = 8) ==========
        $display("=== Prueba 1: ADD (5 + 3) ===");
        fork
            // Enviar operación
            begin
                send_uart_byte(8'h20);  // ADD (0x20)
                send_uart_byte(8'h05);  // A = 5
                send_uart_byte(8'h03);  // B = 3
            end
            
            // Recibir resultado
            begin
                #(BIT_PERIOD * 35);  // Esperar a que se procese
                receive_uart_byte(received_result);
                receive_uart_byte(received_flags);
                $display("  [RESULTADO] Valor: %d, Carry: %b, Zero: %b", 
                         received_result, received_flags[0], received_flags[1]);
                if (received_result == 8 && received_flags[0] == 0)
                    $display("  ✓ PASS\n");
                else
                    $display("  ✗ FAIL (Esperado: 8, Carry=0)\n");
            end
        join
        
        // Esperar entre pruebas
        #(BIT_PERIOD * 20);
        
        // ========== PRUEBA 2: SUB (10 - 4 = 6) ==========
        $display("=== Prueba 2: SUB (10 - 4) ===");
        fork
            begin
                send_uart_byte(8'h22);  // SUB (0x22)
                send_uart_byte(8'h0A);  // A = 10
                send_uart_byte(8'h04);  // B = 4
            end
            
            begin
                #(BIT_PERIOD * 35);
                receive_uart_byte(received_result);
                receive_uart_byte(received_flags);
                $display("  [RESULTADO] Valor: %d, Carry: %b, Zero: %b", 
                         received_result, received_flags[0], received_flags[1]);
                if (received_result == 6 && received_flags[0] == 0)
                    $display("  ✓ PASS\n");
                else
                    $display("  ✗ FAIL (Esperado: 6, Carry=0)\n");
            end
        join
        
        // Esperar entre pruebas
        #(BIT_PERIOD * 20);
        
        // ========== PRUEBA 3: NOR (0xF0 | 0x0F = 0x00) ==========
        $display("=== Prueba 3: NOR (0xF0 | 0x0F) - Verifica Zero flag ===");
        fork
            begin
                send_uart_byte(8'h27);  // NOR (0x27)
                send_uart_byte(8'hF0);  // A = 0xF0
                send_uart_byte(8'h0F);  // B = 0x0F
            end
            
            begin
                #(BIT_PERIOD * 35);
                receive_uart_byte(received_result);
                receive_uart_byte(received_flags);
                $display("  [RESULTADO] Valor: 0x%h, Carry: %b, Zero: %b", 
                         received_result, received_flags[0], received_flags[1]);
                if (received_result == 0 && received_flags[1] == 1)
                    $display("  ✓ PASS (Zero flag activado)\n");
                else
                    $display("  ✗ FAIL (Esperado: 0x00, Zero=1)\n");
            end
        join
        
        // Esperar entre pruebas
        #(BIT_PERIOD * 20);
        
        // ========== PRUEBA 4: AND (0xAA & 0x55 = 0x00) ==========
        $display("=== Prueba 4: AND (0xAA & 0x55) ===");
        fork
            begin
                send_uart_byte(8'h24);  // AND (0x24)
                send_uart_byte(8'hAA);  // A = 0xAA
                send_uart_byte(8'h55);  // B = 0x55
            end
            
            begin
                #(BIT_PERIOD * 35);
                receive_uart_byte(received_result);
                receive_uart_byte(received_flags);
                $display("  [RESULTADO] Valor: 0x%h, Carry: %b, Zero: %b", 
                         received_result, received_flags[0], received_flags[1]);
                if (received_result == 0 && received_flags[1] == 1)
                    $display("  ✓ PASS (Resultado=0x00, Zero flag activado)\n");
                else
                    $display("  ✗ FAIL (Esperado: 0x00, Zero=1)\n");
            end
        join
        
        // Esperar entre pruebas
        #(BIT_PERIOD * 20);
        
        // ========== PRUEBA 5: ADD con CARRY (127 + 1 = 128) ==========
        $display("=== Prueba 5: ADD con CARRY (127 + 1) ===");
        $display("  Nota: Suma de dos números positivos con resultado negativo");
        fork
            begin
                send_uart_byte(8'h20);  // ADD (0x20)
                send_uart_byte(8'h7F);  // A = 127 (0x7F, máximo positivo)
                send_uart_byte(8'h01);  // B = 1
            end
            
            begin
                #(BIT_PERIOD * 35);
                receive_uart_byte(received_result);
                receive_uart_byte(received_flags);
                $display("  [RESULTADO] Valor: 0x%h (%d), Carry: %b, Zero: %b", 
                         received_result, $signed(received_result), received_flags[0], received_flags[1]);
                if (received_result == 128 && received_flags[0] == 1)
                    $display("  ✓ PASS (Overflow detectado, Carry=1)\n");
                else
                    $display("  ✗ FAIL (Esperado: 0x80, Carry=1)\n");
            end
        join
        
        // Esperar entre pruebas
        #(BIT_PERIOD * 20);
        
        // ========== PRUEBA 6: ADD con CARRY (128 + 128 = 256→0) ==========
        $display("=== Prueba 6: ADD con CARRY y ZERO (128 + 128) ===");
        $display("  Nota: Suma de dos números negativos (signed)");
        fork
            begin
                send_uart_byte(8'h20);  // ADD (0x20)
                send_uart_byte(8'h80);  // A = 128 (0x80, mínimo en signed)
                send_uart_byte(8'h80);  // B = 128 (0x80)
            end
            
            begin
                #(BIT_PERIOD * 35);
                receive_uart_byte(received_result);
                receive_uart_byte(received_flags);
                $display("  [RESULTADO] Valor: 0x%h, Carry: %b, Zero: %b", 
                         received_result, received_flags[0], received_flags[1]);
                if (received_result == 0 && received_flags[0] == 1 && received_flags[1] == 1)
                    $display("  ✓ PASS (Overflow, Carry=1 y Zero=1)\n");
                else
                    $display("  ✗ FAIL (Esperado: 0x00, Carry=1, Zero=1)\n");
            end
        join
        
        // Esperar entre pruebas
        #(BIT_PERIOD * 20);
        
        // ========== PRUEBA 7: SUB sin CARRY (5 - 10 = -5) ==========
        $display("=== Prueba 7: SUB sin CARRY (5 - 10) ===");
        $display("  Nota: Resta donde A < B (resultado negativo, pero sin overflow)");
        fork
            begin
                send_uart_byte(8'h22);  // SUB (0x22)
                send_uart_byte(8'h05);  // A = 5
                send_uart_byte(8'h0A);  // B = 10
            end
            
            begin
                #(BIT_PERIOD * 35);
                receive_uart_byte(received_result);
                receive_uart_byte(received_flags);
                $display("  [RESULTADO] Valor: 0x%h (%d), Carry: %b, Zero: %b", 
                         received_result, $signed(received_result), received_flags[0], received_flags[1]);
                if (received_result == 251 && received_flags[0] == 0)  // 251 es -5 en complemento a 2, sin overflow
                    $display("  ✓ PASS (Resultado negativo válido, Carry=0)\n");
                else
                    $display("  ✗ FAIL (Esperado: 0xFB (-5), Carry=0)\n");
            end
        join
        
        // Esperar entre pruebas
        #(BIT_PERIOD * 20);
        
        // ========== PRUEBA 8: SUB sin CARRY (10 - 5 = 5) ==========
        $display("=== Prueba 8: SUB sin CARRY (10 - 5) ===");
        $display("  Nota: Resta normal sin overflow");
        fork
            begin
                send_uart_byte(8'h22);  // SUB (0x22)
                send_uart_byte(8'h0A);  // A = 10
                send_uart_byte(8'h05);  // B = 5
            end
            
            begin
                #(BIT_PERIOD * 35);
                receive_uart_byte(received_result);
                receive_uart_byte(received_flags);
                $display("  [RESULTADO] Valor: 0x%h (%d), Carry: %b, Zero: %b", 
                         received_result, $signed(received_result), received_flags[0], received_flags[1]);
                if (received_result == 5 && received_flags[0] == 0)
                    $display("  ✓ PASS (Resta normal, Carry=0)\n");
                else
                    $display("  ✗ FAIL (Esperado: 0x05, Carry=0)\n");
            end
        join
        
        $display("\n========================================");
        $display("Todas las pruebas completadas");
        $display("========================================\n");
    end

endmodule