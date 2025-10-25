module top (
    input wire clk,           // Clock de la placa (50 MHz en Basys 3)
    input wire reset,         // Reset de la placa
    input wire rx,            // RX serial (entrada)
    output wire tx,           // TX serial (salida)
    
    // Debug LEDs (opcional)
    output wire [7:0] debug_leds,  // Para ver actividad
    output wire rx_activity_led,   // LED cuando recibe dato
    output wire tx_activity_led    // LED cuando transmite dato
);

    // ============================================================
    // Señales internas
    // ============================================================
    wire s_tick;              // Tick del baud rate generator
    wire rx_done_tick;        // Pulso de fin de recepción
    wire [7:0] rx_data;       // Dato recibido
    wire [7:0] alu_a, alu_b;  // Operandos de ALU
    wire [5:0] alu_op;        // Operación de ALU
    wire [7:0] alu_result;    // Resultado de ALU
    wire alu_carry, alu_zero; // Flags de ALU
    wire tx_start;            // Señal para iniciar TX
    wire [7:0] tx_data;       // Dato a transmitir
    wire tx_done_tick;        // Pulso de fin de transmisión
    
    // Registros para detectar actividad (para LEDs de debug)
    reg rx_activity_reg;
    reg tx_activity_reg;
    
    // ============================================================
    // INSTANCIA: Baud Rate Generator (50MHz → 19200 bps)
    // ============================================================
    baud_rate_gen #(
        .CLK_FREQ(100000000),      // Frecuencia del clock en Hz
        .BAUD_RATE(19200),        // Baud rate deseado
        .OVERSAMPLING(16),        // Factor de oversampling
        .DVSR(326),               // Divisor calculado
        .DVSR_BIT(9)              // Bits para el contador
    ) brg_inst (
        .clk(clk),
        .reset(reset),
        .tick(s_tick)
    );
    
    // ============================================================
    // INSTANCIA: UART RX (Recibe datos desde PC)
    // ============================================================
    uart_rx #(
        .DBIT(8),                 // 8 bits de datos
        .SB_TICK(16)              // 16 ticks por bit
    ) rx_inst (
        .clk(clk),
        .reset(reset),
        .rx(rx),                  // Línea RX de la placa
        .s_tick(s_tick),          // Tick de sincronización
        .rx_done_tick(rx_done_tick),
        .dout(rx_data)
    );
    
    // ============================================================
    // INSTANCIA: UART TX (Envía datos hacia PC)
    // ============================================================
    uart_tx #(
        .DBIT(8),                 // 8 bits de datos
        .SB_TICK(16)              // 16 ticks por bit
    ) tx_inst (
        .clk(clk),
        .reset(reset),
        .tx_start(tx_start),      // Señal para iniciar transmisión
        .s_tick(s_tick),          // Tick de sincronización
        .din(tx_data),            // Dato a transmitir
        .tx_done_tick(tx_done_tick),
        .tx(tx)                   // Línea TX de la placa
    );
    
    // ============================================================
    // INSTANCIA: ALU (Unidad Aritmética Lógica)
    // ============================================================
    alu #(
        .NB_IN(8),                // Ancho entrada 8 bits
        .NB_OUT(8),               // Ancho salida 8 bits
        .NB_OP(6)                 // 6 bits para opcode
    ) alu_inst (
        .i_a(alu_a),              // Operando A
        .i_b(alu_b),              // Operando B
        .i_op(alu_op),            // Código de operación
        .o_outresult(alu_result), // Resultado
        .o_carry(alu_carry),      // Flag carry/overflow
        .o_zero(alu_zero)         // Flag zero
    );
    
    // ============================================================
    // INSTANCIA: Interfaz UART-ALU (Controlador FSM)
    // ============================================================
    intf_alu #(
        .DBIT(8),                 // 8 bits de datos UART
        .ALU_WIDTH(8)             // 8 bits de ancho ALU
    ) intf_inst (
        .clk(clk),
        .reset(reset),
        
        // Interfaz con RX
        .rx_done_tick(rx_done_tick),
        .rx_data(rx_data),
        
        // Interfaz con ALU
        .alu_a(alu_a),
        .alu_b(alu_b),
        .alu_op(alu_op),
        .alu_result(alu_result),
        .alu_carry(alu_carry),
        .alu_zero(alu_zero),
        
        // Interfaz con TX
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_done_tick(tx_done_tick)
    );
    
    // ============================================================
    // LEDs de Debug (opcional)
    // ============================================================
    // Mostrar último byte recibido en los LEDs
    assign debug_leds = alu_result;
    
    // // LED de actividad RX (se enciende cuando recibe datos)
    always @(posedge clk) begin
        if (reset)
            rx_activity_reg <= 1'b0;
        else if (rx_done_tick)
            rx_activity_reg <= 1'b1;
        else if (rx_activity_reg == 1'b1)  // Mantener encendido por un momento
            rx_activity_reg <= 1'b0;
    end
    
    // // LED de actividad TX (se enciende cuando transmite datos)
    always @(posedge clk) begin
        if (reset)
            tx_activity_reg <= 1'b0;
        else if (tx_start)
            tx_activity_reg <= 1'b1;
        else if (tx_activity_reg == 1'b1)  // Mantener encendido por un momento
            tx_activity_reg <= 1'b0;
    end
    
    assign rx_activity_led = rx_activity_reg;
    assign tx_activity_led = tx_activity_reg;

endmodule