module uart_tx #(
    parameter DBIT = 8,           // Bits de datos (N)
    parameter SB_TICK = 16        // Ticks por bit (oversampling)
)(
    input wire clk,               // Clock del sistema
    input wire reset,             // Reset asíncrono
    input wire tx_start,          // Señal para iniciar transmisión
    input wire s_tick,            // Tick del baud rate generator
    input wire [DBIT-1:0] din,    // Dato a transmitir
    output reg tx_done_tick,      // Pulso cuando completa transmisión
    output wire tx                // Línea serial de salida
);

    // Estados de la FSM
    localparam [1:0]
        IDLE  = 2'b00,    // Esperando señal de inicio
        START = 2'b01,    // Transmitiendo bit de Start
        DATA  = 2'b10,    // Transmitiendo bits de datos
        STOP  = 2'b11;    // Transmitiendo bit de Stop

    // Registros de estado
    reg [1:0] state_reg, state_next;
    reg [3:0] s_reg, s_next;              // Contador de ticks (0-15)
    reg [2:0] n_reg, n_next;              // Contador de bits (0-7)
    reg [DBIT-1:0] b_reg, b_next;         // Registro de datos a transmitir
    reg tx_reg, tx_next;                  // Bit actual en la línea TX

    // Registro de estado (con reset asíncrono)
    always @(posedge clk) begin
        if (reset) begin
            state_reg <= IDLE;
            s_reg <= 0;
            n_reg <= 0;
            b_reg <= 0;
            tx_reg <= 1'b1;  // Línea idle en alto
        end
        else begin
            state_reg <= state_next;
            s_reg <= s_next;
            n_reg <= n_next;
            b_reg <= b_next;
            tx_reg <= tx_next;
        end
    end

    // Lógica de próximo estado y salidas
    always @(*) begin
        // Valores por defecto (evitar latches)
        state_next = state_reg;
        s_next = s_reg;
        n_next = n_reg;
        b_next = b_reg;
        tx_next = tx_reg;
        tx_done_tick = 1'b0;

        case (state_reg)
            IDLE: begin
                tx_next = 1'b1;  // Línea idle en alto
                
                if (tx_start) begin
                    // Capturar dato a transmitir
                    b_next = din;
                    state_next = START;
                    s_next = 0;
                end
            end

            START: begin
                tx_next = 1'b0;  // Start bit = 0
                
                if (s_tick) begin
                    if (s_reg == (SB_TICK - 1)) begin
                        // Fin del bit de Start
                        state_next = DATA;
                        s_next = 0;
                        n_next = 0;
                    end
                    else begin
                        s_next = s_reg + 1;
                    end
                end
            end

            DATA: begin
                // Transmitir bit actual (LSB first)
                tx_next = b_reg[0];
                
                if (s_tick) begin
                    if (s_reg == (SB_TICK - 1)) begin
                        // Fin del bit actual
                        s_next = 0;
                        b_next = {1'b0, b_reg[DBIT-1:1]};  // Shift right
                        
                        if (n_reg == (DBIT - 1)) begin
                            // Ya transmitimos todos los bits de datos
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
                tx_next = 1'b1;  // Stop bit = 1
                
                if (s_tick) begin
                    if (s_reg == (SB_TICK - 1)) begin
                        // Fin del bit de Stop
                        state_next = IDLE;
                        tx_done_tick = 1'b1;  // Señal de transmisión completa
                    end
                    else begin
                        s_next = s_reg + 1;
                    end
                end
            end

            default: state_next = IDLE;
        endcase
    end

    // Salida TX
    assign tx = tx_reg;

endmodule