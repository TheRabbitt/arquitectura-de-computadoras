module baud_rate_gen #(
    parameter CLK_FREQ = 50000000,    // Frecuencia del clock en Hz (50 MHz para Basys 3)
    parameter BAUD_RATE = 19200,      // Baud rate deseado (19200 bps)
    parameter OVERSAMPLING = 16,      // Factor de oversampling (16x)
    parameter DVSR = 163,             // Divisor: CLK_FREQ/(BAUD_RATE*OVERSAMPLING) ≈ 163
    parameter DVSR_BIT = 8            // Bits necesarios para contar hasta 163
)(
    input wire clk,                   // Clock del sistema 50MHz (Basys 3)
    input wire reset,                 // Reset asíncrono
    output reg tick,                  // Tick generado cada DVSR ciclos
    output wire [DVSR_BIT-1:0] counter_debug  // Salida de debug (opcional)
);

    // Contador módulo DVSR
    reg [DVSR_BIT-1:0] counter;
    
    // Asignar counter a la salida de debug
    assign counter_debug = counter;
    
    // Bloque inicial para mostrar los parámetros calculados
    initial begin
        $display("===========================================");
        $display("Baud Rate Generator - Parámetros");
        $display("===========================================");
        $display("Clock Frequency: %0d Hz", CLK_FREQ);
        $display("Baud Rate: %0d bps", BAUD_RATE);
        $display("Oversampling: %0dx", OVERSAMPLING);
        $display("Divisor (DVSR): %0d", DVSR);
        $display("Formula: DVSR = CLK_FREQ / (BAUD_RATE * OVERSAMPLING)");
        $display("         DVSR = %0d / (%0d * %0d) = %0d", 
                 CLK_FREQ, BAUD_RATE, OVERSAMPLING, DVSR);
        $display("Tick Frequency: %0d Hz", CLK_FREQ / DVSR);
        $display("===========================================");
    end
    
    always @(posedge clk) begin
        if (reset) begin
            counter <= 0;
            tick <= 1'b0;
        end
        else begin
            if (counter == DVSR - 1) begin
                counter <= 0;
                tick <= 1'b1;  // Generar tick cuando counter llega a DVSR-1 (162)
            end
            else begin
                counter <= counter + 1;
                tick <= 1'b0;
            end
        end
    end

endmodule