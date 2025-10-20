module uart_rx #(
    parameter DBIT = 8,           // Bits de datos (N)
    parameter SB_TICK = 16        // Ticks por bit (oversampling)
)(
    input wire clk,               // Clock del sistema
    input wire reset,             // Reset asíncrono
    input wire rx,                // Línea serial de entrada
    input wire s_tick,            // Tick del baud rate generator
    output reg rx_done_tick,      // Pulso cuando se completa recepción
    output wire [DBIT-1:0] dout   // Dato recibido
);

    // Estados de la FSM
    localparam [1:0] 
        IDLE  = 2'b00,    // Esperando bit de Start
        START = 2'b01,    // Verificando bit de Start
        DATA  = 2'b10,    // Recibiendo bits de datos
        STOP  = 2'b11;    // Verificando bit de Stop

    // Registros de estado
    reg [1:0] state_reg, state_next;
    reg [3:0] s_reg, s_next;              // Contador de ticks (0-15)
    reg [2:0] n_reg, n_next;              // Contador de bits (0-7)
    reg [DBIT-1:0] b_reg, b_next;         // Shift register para datos

    // Registro de estado (con reset asíncrono)
    always @(posedge clk) begin
        if (reset) begin
            state_reg <= IDLE;
            s_reg <= 0;
            n_reg <= 0;
            b_reg <= 0;
        end
        else begin
            state_reg <= state_next;
            s_reg <= s_next;
            n_reg <= n_next;
            b_reg <= b_next;
        end
    end

    // Lógica de próximo estado y salidas
    always @(*) begin
        // Valores por defecto (evitar latches)
        state_next = state_reg;
        s_next = s_reg;
        n_next = n_reg;
        b_next = b_reg;
        rx_done_tick = 1'b0;

        case (state_reg)
            IDLE: begin
                // Reiniciar contadores
                n_next = 0;
                // Paso 1: Esperar a que rx = 0 (inicio de bit de Start)
                if (~rx) begin
                    state_next = START;
                    s_next = 0;
                end
            end

            START: begin
                if (s_tick) begin
                    if (s_reg == 7) begin
                        // Paso 2: En el medio del bit de Start (tick 7)
                        // Verificar que siga en 0 (Start bit válido)
                        if (~rx) begin
                            // Start bit válido, continuar
                            state_next = DATA;
                            s_next = 0;
                            n_next = 0;
                        end
                        else begin
                            // Falsa alarma (glitch o ruido), volver a IDLE
                            state_next = IDLE;
                        end
                    end
                    else begin
                        s_next = s_reg + 1;
                    end
                end
            end

            DATA: begin
                if (s_tick) begin
                    if (s_reg == (SB_TICK - 1)) begin
                        // Paso 3: En el medio del bit de datos (tick 15)
                        // Muestrear el bit y guardarlo en el shift register
                        s_next = 0;
                        b_next = {rx, b_reg[DBIT-1:1]};  // Shift right, LSB first
                        
                        if (n_reg == (DBIT - 1)) begin
                            // Paso 4: Ya recibimos todos los N bits
                            state_next = STOP;
                        end
                        else begin
                            n_next = n_reg + 1;
                        end
                    end
                    else begin
                        s_next = s_reg + 1;
                    end
                end
            end

            STOP: begin
                if (s_tick) begin
                    if (s_reg == (SB_TICK - 1)) begin
                        // Paso 6: En el medio del bit de Stop
                        // Verificar que el bit de Stop sea válido (rx=1)
                        if (rx) begin
                            // Stop bit válido, recepción exitosa
                            state_next = IDLE;
                            rx_done_tick = 1'b1;  // Señal de dato recibido
                        end
                        else begin
                            // Error de framing (stop bit incorrecto)
                            // Descartamos el dato y volvemos a IDLE
                            state_next = IDLE;
                            // No generamos rx_done_tick (dato inválido)
                        end
                    end
                    else begin
                        s_next = s_reg + 1;
                    end
                end
            end

            default: state_next = IDLE;
        endcase
    end

    // Salida de datos
    assign dout = b_reg;

endmodule
