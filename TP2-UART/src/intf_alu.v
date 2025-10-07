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
    
    // Interfaz con UART TX (para cuando lo implementes)
    output reg tx_start,                   // Señal para iniciar transmisión
    output reg [DBIT-1:0] tx_data,         // Dato a transmitir
    input wire tx_done_tick                // Señal de transmisión completa
);

    // Estados de la FSM
    localparam [2:0]
        IDLE       = 3'b000,  // Esperando primer byte (operación)
        WAIT_A     = 3'b001,  // Esperando operando A
        WAIT_B     = 3'b010,  // Esperando operando B
        EXEC_ALU   = 3'b011,  // Ejecutando operación en ALU
        WAIT_TX    = 3'b100,  // Esperando transmisión (para futuro)
        SEND_RESULT = 3'b101; // Enviando resultado (para futuro)
    
    // Registros de estado
    reg [2:0] state_reg, state_next;
    
    // Registros para almacenar datos
    reg [5:0] op_reg, op_next;              // Operación recibida
    reg [ALU_WIDTH-1:0] a_reg, a_next;      // Operando A
    reg [ALU_WIDTH-1:0] b_reg, b_next;      // Operando B
    reg [ALU_WIDTH-1:0] result_reg, result_next; // Resultado
    reg carry_reg, carry_next;              // Flag de carry capturado
    reg zero_reg, zero_next;                // Flag de zero capturado
    
    // Registro de estado
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
    
    // Lógica de próximo estado
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
        tx_data = result_reg;
        
        case (state_reg)
            IDLE: begin
                // Estado inicial: esperando código de operación
                if (rx_done_tick) begin
                    // Recibimos el código de operación (primer byte)
                    op_next = rx_data[5:0];  // Usar solo 6 bits para la operación
                    state_next = WAIT_A;
                end
            end
            
            WAIT_A: begin
                // Esperando operando A (segundo byte)
                if (rx_done_tick) begin
                    a_next = rx_data;
                    state_next = WAIT_B;
                end
            end
            
            WAIT_B: begin
                // Esperando operando B (tercer byte)
                if (rx_done_tick) begin
                    b_next = rx_data;
                    state_next = EXEC_ALU;
                end
            end
            
            EXEC_ALU: begin
                // Ejecutar operación en la ALU
                alu_start = 1'b1;  // Señal de inicio a la ALU
                
                // Capturar el resultado y los flags (asumiendo ALU combinacional)
                result_next = alu_result;
                carry_next = alu_carry;
                zero_next = alu_zero;
                
                // Por ahora volvemos a IDLE (cuando tengas TX, irás a SEND_RESULT)
                state_next = IDLE;
                
                // Cuando implementes TX, cambiar a:
                // state_next = SEND_RESULT;
            end
            
            SEND_RESULT: begin
                // Estado futuro: enviar resultado por TX
                // Podrías enviar 2 bytes: resultado + flags empaquetados
                // Byte 1: result_reg
                // Byte 2: {6'b0, carry_reg, zero_reg}
                tx_start = 1'b1;
                tx_data = result_reg;  // Por ahora solo el resultado
                
                if (tx_done_tick) begin
                    state_next = IDLE;
                end
            end
            
            default: state_next = IDLE;
        endcase
    end

endmodule


