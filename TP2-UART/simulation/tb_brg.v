// Testbench para verificar el funcionamiento
module baud_rate_gen_tb;
    reg clk, reset;
    wire tick;
    wire [7:0] counter_debug;  //wire para counter_debug
    integer tick_count;
    real simulation_time;
    
    // Instanciar el módulo con parámetros explícitos
    baud_rate_gen #(
        .CLK_FREQ(50000000),      // 50 MHz
        .BAUD_RATE(19200),        // 19200 baud
        .OVERSAMPLING(16),        // 16x oversampling
        .DVSR_BIT(8)
    ) uut (
        .clk(clk),
        .reset(reset),
        .tick(tick)
    );
    
    // Generar clock de 50MHz (periodo 20ns)
    initial clk = 0;
    always #10 clk = ~clk;  // 10ns alto + 10ns bajo = 20ns periodo = 50MHz
    
    // Contador de ticks para verificar frecuencia
    initial tick_count = 0;
    always @(posedge clk) begin
        if (tick)
            tick_count = tick_count + 1;
    end
    
    // Secuencia de test
    initial begin

        // Reset inicial
        reset = 1;
        #100;
        
        reset = 0;
        
        // Esperar varios ticks para verificar
        #100000;  // 100 microsegundos
        
        simulation_time = 100.0; // microsegundos
        
        $display("\n===========================================");
        $display("Resultados de la Simulación");
        $display("===========================================");
        $display("Tiempo de simulación: %.1f us", simulation_time);
        $display("Ticks generados: %0d", tick_count);
        $display("Frecuencia de ticks medida: %.2f kHz", tick_count / simulation_time * 1000);
        $display("Frecuencia de ticks esperada: %.2f kHz", 50000000.0 / uut.DVSR / 1000);
        $display("Baud rate resultante: %0d baud", 50000000 / uut.DVSR / uut.OVERSAMPLING);
        $display("===========================================\n");
        
        $finish;
    end
    
    // Monitor para debugging
    /*initial begin
        $monitor("Time=%0t ns | reset=%b | tick=%b | counter=%0d", 
                 $time, reset, tick, counter_debug);
    end
    */

endmodule