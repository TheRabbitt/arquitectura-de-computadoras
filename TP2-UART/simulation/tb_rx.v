module uart_rx_tb;
    reg clk, reset;
    reg rx;
    wire s_tick;  // Utilizado para conectar al baud rate generator
    wire rx_done_tick;
    wire [7:0] dout;
    
    // Instanciar baud rate generator REAL
    baud_rate_gen #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(19200),
        .OVERSAMPLING(16),
        .DVSR_BIT(8)
    ) brg (
        .clk(clk),
        .reset(reset),
        .tick(s_tick),
        .counter_debug()  // No lo vamos a usar aca
    );
    
    // Instanciar módulo RX
    uart_rx #(
        .DBIT(8),
        .SB_TICK(16)
    ) uut (
        .clk(clk),
        .reset(reset),
        .rx(rx),
        .s_tick(s_tick),  // Conectado al baud rate generator
        .rx_done_tick(rx_done_tick),
        .dout(dout)
    );
    
    // Clock de 50MHz
    initial clk = 0;
    always #10 clk = ~clk;
    
    // Tarea para enviar un byte por UART
    // Con esto respetamos el timing REAL del baud rate generator
    task send_byte;
        input [7:0] data;
        integer i;
        reg [31:0] bit_time;
        begin
            // Calcular tiempo por bit: 163 ciclos de clock × 20ns
            bit_time = 163 * 16 * 20;  // 163 ticks × 16 ticks/bit × 20ns/ciclo
            
            // Start bit
            rx = 0;
            #bit_time;
            
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i];
                #bit_time;
            end
            
            // Stop bit
            rx = 1;
            #bit_time;
        end
    endtask
    
    // Secuencia de prueba
    initial begin

        // Inicialización
        reset = 1;
        rx = 1;  // Línea idle
        #200;
        
        reset = 0;
        #200;
        
        $display("========================================");
        $display("Prueba UART RX con Baud Rate Generator");
        $display("Baud Rate: 19200");
        $display("Clock: 50 MHz");
        $display("========================================");
        
        // Enviar byte 0xA5
        $display("\nEnviando byte: 0xA5 (10100101)");
        send_byte(8'hA5);
        #10000;
        
        if (dout == 8'hA5)
            $display("✓ Byte recibido correctamente: 0x%h", dout);
        else
            $display("✗ Error: Esperado 0xA5, recibido 0x%h", dout);
        
        // Enviar byte 0x3C
        $display("\nEnviando byte: 0x3C (00111100)");
        send_byte(8'h3C);
        #10000;
        
        if (dout == 8'h3C)
            $display("✓ Byte recibido correctamente: 0x%h", dout);
        else
            $display("✗ Error: Esperado 0x3C, recibido 0x%h", dout);
        
        // Enviar byte 0xFF
        $display("\nEnviando byte: 0xFF (11111111)");
        send_byte(8'hFF);
        #10000;
        
        if (dout == 8'hFF)
            $display("✓ Byte recibido correctamente: 0x%h", dout);
        else
            $display("✗ Error: Esperado 0xFF, recibido 0x%h", dout);
        
        $display("\n========================================");
        $display("Prueba completada");
        $display("========================================");
        
        #50000;
        $finish;
    end
    
    // Monitor de señales
    always @(posedge clk) begin
        if (rx_done_tick)
            $display("Time=%0t | Dato recibido: 0x%h (%b)", $time, dout, dout);
    end

endmodule