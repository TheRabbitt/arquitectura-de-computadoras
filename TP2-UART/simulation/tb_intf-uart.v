// Testbench completo: Sistema UART-ALU integrado
module intf_alu_tb;
    reg clk, reset;
    reg rx_line;  // Línea serial física
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
    reg tx_done_tick;
    
    // Parámetros de timing
    localparam CLK_PERIOD = 20;  // 50 MHz
    localparam BIT_PERIOD = 163 * 16 * CLK_PERIOD;  // Tiempo de 1 bit UART
    
    // Instanciar Baud Rate Generator
    baud_rate_gen #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(19200),
        .OVERSAMPLING(16),
        .DVSR_BIT(8)
    ) brg_inst (
        .clk(clk),
        .reset(reset),
        .tick(s_tick),
        .counter_debug()
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
    
    // Instanciar TU ALU REAL
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
    ) uut (
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
    
    // Tarea para enviar un byte por UART (simulando transmisor)
    task send_uart_byte;
        input [7:0] data;
        integer i;
        begin
            $display("  Enviando byte por UART: 0x%h", data);
            
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
    
    // Secuencia de prueba
    initial begin
        $dumpfile("intf_alu.vcd");
        $dumpvars(0, intf_alu_tb);
        
        // Inicialización
        reset = 1;
        rx_line = 1;  // Línea UART idle (alto)
        tx_done_tick = 0;
        #100;
        
        reset = 0;
        #100;
        
        $display("========================================");
        $display("Sistema UART-ALU Integrado");
        $display("Baud Rate: 19200 bps");
        $display("Clock: 50 MHz");
        $display("========================================");
        
        // Prueba 1: ADD (5 + 3 = 8)
        $display("\n=== Prueba 1: ADD ===");
        $display("Enviando: OP=0x20 (ADD), A=5, B=3");
        send_uart_byte(8'h20);  // op_suma
        send_uart_byte(8'h05);  // A = 5
        send_uart_byte(8'h03);  // B = 3
        #(BIT_PERIOD * 2);      // Esperar procesamiento
        $display("Resultado esperado: 8");
        $display("Resultado obtenido: %d", result_reg_wire);
        $display("Flags: Carry=%b, Zero=%b", carry_reg_wire, zero_reg_wire);
        if (result_reg_wire == 8)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");
        
        // Prueba 2: SUB (10 - 4 = 6)
        $display("=== Prueba 2: SUB ===");
        $display("Enviando: OP=0x22 (SUB), A=10, B=4");
        send_uart_byte(8'h22);  // op_resta
        send_uart_byte(8'h0A);  // A = 10
        send_uart_byte(8'h04);  // B = 4
        #(BIT_PERIOD * 2);
        $display("Resultado esperado: 6");
        $display("Resultado obtenido: %d", result_reg_wire);
        $display("Flags: Carry=%b, Zero=%b", carry_reg_wire, zero_reg_wire);
        if (result_reg_wire == 6)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");
        
        // Prueba 3: AND (0xFF & 0x0F = 0x0F)
        $display("=== Prueba 3: AND ===");
        $display("Enviando: OP=0x24 (AND), A=0xFF, B=0x0F");
        send_uart_byte(8'h24);  // op_and
        send_uart_byte(8'hFF);  // A = 0xFF
        send_uart_byte(8'h0F);  // B = 0x0F
        #(BIT_PERIOD * 2);
        $display("Resultado esperado: 0x0F (15)");
        $display("Resultado obtenido: 0x%h (%d)", result_reg_wire, result_reg_wire);
        $display("Flags: Carry=%b, Zero=%b", carry_reg_wire, zero_reg_wire);
        if (result_reg_wire == 8'h0F)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");
        
        // Prueba 4: OR (0xF0 | 0x0F = 0xFF)
        $display("=== Prueba 4: OR ===");
        $display("Enviando: OP=0x25 (OR), A=0xF0, B=0x0F");
        send_uart_byte(8'h25);  // op_or
        send_uart_byte(8'hF0);  // A = 0xF0
        send_uart_byte(8'h0F);  // B = 0x0F
        #(BIT_PERIOD * 2);
        $display("Resultado esperado: 0xFF (255)");
        $display("Resultado obtenido: 0x%h (%d)", result_reg_wire, result_reg_wire);
        $display("Flags: Carry=%b, Zero=%b", carry_reg_wire, zero_reg_wire);
        if (result_reg_wire == 8'hFF)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");
        
        // Prueba 5: XOR (0xAA ^ 0x55 = 0xFF)
        $display("=== Prueba 5: XOR ===");
        $display("Enviando: OP=0x26 (XOR), A=0xAA, B=0x55");
        send_uart_byte(8'h26);  // op_xor
        send_uart_byte(8'hAA);  // A = 0xAA
        send_uart_byte(8'h55);  // B = 0x55
        #(BIT_PERIOD * 2);
        $display("Resultado esperado: 0xFF (255)");
        $display("Resultado obtenido: 0x%h (%d)", result_reg_wire, result_reg_wire);
        $display("Flags: Carry=%b, Zero=%b", carry_reg_wire, zero_reg_wire);
        if (result_reg_wire == 8'hFF)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");
        
        // Prueba 6: NOR (~(0xF0 | 0x0F) = 0x00)
        $display("=== Prueba 6: NOR (verifica flag Zero) ===");
        $display("Enviando: OP=0x27 (NOR), A=0xF0, B=0x0F");
        send_uart_byte(8'h27);  // op_nor
        send_uart_byte(8'hF0);  // A = 0xF0
        send_uart_byte(8'h0F);  // B = 0x0F
        #(BIT_PERIOD * 2);
        $display("Resultado esperado: 0x00 (0)");
        $display("Resultado obtenido: 0x%h (%d)", result_reg_wire, result_reg_wire);
        $display("Flags: Carry=%b, Zero=%b", carry_reg_wire, zero_reg_wire);
        if (result_reg_wire == 8'h00 && zero_reg_wire == 1'b1)
            $display("✓ PASS (Zero flag activado correctamente)\n");
        else
            $display("✗ FAIL\n");
        
        // Prueba 7: SRL (0x80 >> 2 = 0x20)
        $display("=== Prueba 7: SRL ===");
        $display("Enviando: OP=0x02 (SRL), A=0x80, B=2");
        send_uart_byte(8'h02);  // op_srl
        send_uart_byte(8'h80);  // A = 0x80
        send_uart_byte(8'h02);  // B = 2
        #(BIT_PERIOD * 2);
        $display("Resultado esperado: 0x20 (32)");
        $display("Resultado obtenido: 0x%h (%d)", result_reg_wire, result_reg_wire);
        $display("Flags: Carry=%b, Zero=%b", carry_reg_wire, zero_reg_wire);
        if (result_reg_wire == 8'h20)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");
        
        // Prueba 8: SRA (0x80 >>> 2 = 0xE0)
        $display("=== Prueba 8: SRA (arithmetic shift con signo) ===");
        $display("Enviando: OP=0x03 (SRA), A=0x80, B=2");
        send_uart_byte(8'h03);  // op_sra
        send_uart_byte(8'h80);  // A = 0x80 (-128)
        send_uart_byte(8'h02);  // B = 2
        #(BIT_PERIOD * 2);
        $display("Resultado esperado: 0xE0 (224 = -32 en complemento a 2)");
        $display("Resultado obtenido: 0x%h (%d)", result_reg_wire, $signed(result_reg_wire));
        $display("Flags: Carry=%b, Zero=%b", carry_reg_wire, zero_reg_wire);
        if (result_reg_wire == 8'hE0)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");
        
        $display("========================================");
        $display("Todas las pruebas completadas");
        $display("========================================");
        
        #(BIT_PERIOD * 10);
        $finish;
    end
    
    // Monitor de recepción UART
    always @(posedge clk) begin
        if (rx_done_tick)
            $display("  [RX] Byte recibido: 0x%h (%d)", rx_data, rx_data);
    end
    
    // Monitor de cambios de estado de la interfaz
    always @(posedge clk) begin
        if (state_reg != state_next) begin
            case (state_next)
                3'b000: $display("  [INTF] Estado: IDLE");
                3'b001: $display("  [INTF] Estado: WAIT_A (OP=0x%h)", op_next);
                3'b010: $display("  [INTF] Estado: WAIT_B (A=%d)", a_next);
                3'b011: $display("  [INTF] Estado: EXEC_ALU (A=%d, B=%d, OP=0x%h)", 
                                  a_next, b_next, op_next);
            endcase
        end
        
        if (alu_start)
            $display("  [ALU] Ejecutando: A=%d, B=%d, OP=0x%h => Result=%d, Carry=%b, Zero=%b", 
                    alu_a, alu_b, alu_op, alu_result, alu_carry, alu_zero);
    end
    
    // Variables para acceder a señales internas desde el monitor
    wire [2:0] state_reg = uut.state_reg;
    wire [2:0] state_next = uut.state_next;
    wire [5:0] op_next = uut.op_next;
    wire [7:0] a_next = uut.a_next;
    wire [7:0] b_next = uut.b_next;
    wire [7:0] result_reg_wire = uut.result_reg;
    wire carry_reg_wire = uut.carry_reg;
    wire zero_reg_wire = uut.zero_reg;

endmodule