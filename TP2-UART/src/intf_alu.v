module intf_alu #(
    parameter DBIT = 8,           // Bits de datos del UART
    parameter ALU_WIDTH = 8       // Ancho de la ALU
)(
    input wire clk,
    input wire reset,
    
    // Interfaz con UART RX
    input wire rx_done_tick,           // Señal de byte recibido
    input wire [DBIT-1:0] rx_data,     // Dato recibido del RX
    
    // Interfaz con ALU (salidas hacia la ALU)
    output reg [ALU_WIDTH-1:0] alu_a,      // Operando A
    output reg [ALU_WIDTH-1:0] alu_b,      // Operando B
    output reg [5:0] alu_op,               // Código de operación
    output reg alu_start,                  // Señal para iniciar operación
    
    // Interfaz con ALU (entradas desde la ALU)
    input wire [ALU_WIDTH-1:0] alu_result, // Resultado de la ALU
    input wire alu_carry,                  // Flag de carry/overflow
    input wire alu_zero,                   // Flag de zero
    
    // Interfaz con UART TX
    output reg tx_start,                   // Señal para iniciar transmisión
    output reg [DBIT-1:0] tx_data,         // Dato a transmitir
    input wire tx_done_tick                // Señal de transmisión completa
);

    // Estados de la FSM
    localparam [2:0]
        IDLE           = 3'b000,  // Esperando primer byte (operación)
        WAIT_A         = 3'b001,  // Esperando operando A
        WAIT_B         = 3'b010,  // Esperando operando B
        EXEC_ALU       = 3'b011,  // Ejecutando operación en ALU
        SEND_RESULT    = 3'b100,  // Enviando resultado
        WAIT_TX_1      = 3'b110,  // Esperando a que TX termine (entre resultado y flags)
        SEND_FLAGS     = 3'b101,  // Envía byte 2 (flags)
        WAIT_TX_2      = 3'b111;  // Esperando a que TX termine (después de flags)
    
    // Registros de estado
    reg [2:0] state_reg, state_next;
    
    // Registros para almacenar datos
    reg [5:0] op_reg, op_next;              // Operación recibida
    reg [ALU_WIDTH-1:0] a_reg, a_next;      // Operando A
    reg [ALU_WIDTH-1:0] b_reg, b_next;      // Operando B
    reg [ALU_WIDTH-1:0] result_reg, result_next; // Resultado
    reg carry_reg, carry_next;              // Flag de carry capturado
    reg zero_reg, zero_next;                // Flag de zero capturado
    
    // ============================================================
    // REGISTROS PARA SINCRONIZACIÓN DE PULSOS
    // ============================================================
    reg tx_done_tick_r1, tx_done_tick_r2;  // Pipeline para detectar flanco
    reg rx_done_tick_r1, rx_done_tick_r2;  // Pipeline para detectar flanco
    wire tx_done_pulse;                     // Pulso sincronizado de tx_done_tick
    wire rx_done_pulse;                     // Pulso sincronizado de rx_done_tick
    
    // Detectar flancos (transición 0→1)
    assign tx_done_pulse = tx_done_tick_r1 && ~tx_done_tick_r2;
    assign rx_done_pulse = rx_done_tick_r1 && ~rx_done_tick_r2;
    
    // Pipeline de sincronización
    always @(posedge clk) begin
        if (reset) begin
            tx_done_tick_r1 <= 1'b0;
            tx_done_tick_r2 <= 1'b0;
            rx_done_tick_r1 <= 1'b0;
            rx_done_tick_r2 <= 1'b0;
        end
        else begin
            tx_done_tick_r1 <= tx_done_tick;
            tx_done_tick_r2 <= tx_done_tick_r1;
            rx_done_tick_r1 <= rx_done_tick;
            rx_done_tick_r2 <= rx_done_tick_r1;
        end
    end
    
    // ============================================================
    // Registro de estado (con reset asíncrono)
    // ============================================================
    always @(posedge clk) begin
        if (reset) begin
            state_reg <= IDLE;
            op_reg <= 0;
            a_reg <= 0;
            b_reg <= 0;
            result_reg <= 0;
            carry_reg <= 0;
            zero_reg <= 0;
        end
        else begin
            state_reg <= state_next;
            op_reg <= op_next;
            a_reg <= a_next;
            b_reg <= b_next;
            result_reg <= result_next;
            carry_reg <= carry_next;
            zero_reg <= zero_next;
        end
    end
    
    // ============================================================
    // Lógica de próximo estado
    // ============================================================
    always @(*) begin
        // Valores por defecto
        state_next = state_reg;
        op_next = op_reg;
        a_next = a_reg;
        b_next = b_reg;
        result_next = result_reg;
        carry_next = carry_reg;
        zero_next = zero_reg;
        
        // Salidas por defecto
        alu_a = a_reg;
        alu_b = b_reg;
        alu_op = op_reg;
        alu_start = 1'b0;
        tx_start = 1'b0;
        tx_data = 8'h00;
        
        case (state_reg)
            // ====== ESTADO IDLE ======
            IDLE: begin
                // Estado inicial: esperando código de operación
                if (rx_done_pulse) begin
                    // Recibimos el código de operación (primer byte)
                    op_next = rx_data[5:0];  // Usar solo 6 bits para la operación
                    state_next = WAIT_A;
                end
            end
            
            // ====== ESTADO WAIT_A ======
            WAIT_A: begin
                // Esperando operando A (segundo byte)
                if (rx_done_pulse) begin
                    a_next = rx_data;
                    state_next = WAIT_B;
                end
            end
            
            // ====== ESTADO WAIT_B ======
            WAIT_B: begin
                // Esperando operando B (tercer byte)
                if (rx_done_pulse) begin
                    b_next = rx_data;
                    state_next = EXEC_ALU;
                end
            end
            
            // ====== ESTADO EXEC_ALU ======
            EXEC_ALU: begin
                // Ejecutar operación en la ALU
                alu_start = 1'b1;  // Señal de inicio a la ALU
                
                // Capturar el resultado y los flags
                result_next = alu_result;
                carry_next = alu_carry;
                zero_next = alu_zero;

                // Pasar al siguiente estado después de 1 ciclo
                state_next = SEND_RESULT;
            end
            
            // ====== ESTADO SEND_RESULT ======
            // Enviar el resultado de la operación
            SEND_RESULT: begin
                tx_start = 1'b1;
                tx_data = result_reg;
                
                // Usar el flanco detectado para transicionar
                if (tx_done_pulse) begin
                    state_next = WAIT_TX_1;
                end
            end
            
            // ====== ESTADO WAIT_TX_1 (NUEVO) ======
            // Esperar a que tx_done_tick caiga y desactivar tx_start
            // Esto evita que UART_TX se reinicie inmediatamente
            WAIT_TX_1: begin
                tx_start = 1'b0;  // Desactivar tx_start
                
                // Esperar a que el pulso caiga completamente
                if (!tx_done_tick_r1) begin
                    state_next = SEND_FLAGS;
                end
            end
            
            // ====== ESTADO SEND_FLAGS ======
            SEND_FLAGS: begin
                // Enviar segundo byte: flags empaquetados
                // Formato: {6'b0, zero, carry}
                tx_start = 1'b1;
                tx_data = {6'b0, zero_reg, carry_reg};
                
                // Usar el flanco detectado para transicionar
                if (tx_done_pulse) begin
                    state_next = WAIT_TX_2;
                end
            end
            
            // ====== ESTADO WAIT_TX_2 (NUEVO) ======
            // Esperar a que tx_done_tick caiga y desactivar tx_start
            WAIT_TX_2: begin
                tx_start = 1'b0;  // Desactivar tx_start
                
                // Esperar a que el pulso caiga completamente
                if (!tx_done_tick_r1) begin
                    state_next = IDLE;
                end
            end
            
            default: state_next = IDLE;
        endcase
    end

endmodule