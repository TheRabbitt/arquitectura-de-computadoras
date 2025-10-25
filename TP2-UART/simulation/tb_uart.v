`timescale 1ns / 1ps

module tb_alu_uart_system;

    // Parámetros
    parameter CLK_PERIOD = 10;           // 100MHz clock (10ns period)
    parameter CLK_FREQ = 100000000;
    parameter BAUD_RATE = 19200;
    parameter OVERSAMPLING = 16;
    parameter DVSR = 326;
    parameter DVSR_BIT = 9;
    parameter DBIT = 8;
    parameter ALU_WIDTH = 8;
    
    // Bit period para UART (en ns)
    // CRÍTICO: Debe coincidir exactamente con el timing del baud rate generator
    // BIT_PERIOD = DVSR * OVERSAMPLING * CLK_PERIOD
    parameter BIT_PERIOD = DVSR * OVERSAMPLING * CLK_PERIOD; // 326 * 16 * 10ns = 52160ns
    
    // Señales del sistema
    reg clk;
    reg reset;
    wire tick;
    
    // Señales UART
    wire rx_line;
    wire tx_line;
    reg tx_sim;  // Para simular transmisión desde PC
    
    // Señales internas RX
    wire rx_done_tick;
    wire [DBIT-1:0] rx_data;
    
    // Señales internas TX
    wire tx_start;
    wire [DBIT-1:0] tx_data;
    wire tx_done_tick;
    
    // Señales ALU
    wire [ALU_WIDTH-1:0] alu_a;
    wire [ALU_WIDTH-1:0] alu_b;
    wire [5:0] alu_op;
    wire alu_start;
    wire [ALU_WIDTH-1:0] alu_result;
    wire alu_carry;
    wire alu_zero;
    
    // Variables para testbench
    reg [7:0] expected_result;
    reg expected_carry;
    reg expected_zero;
    integer test_count;
    integer pass_count;
    integer fail_count;
    
    // Instancia del Baud Rate Generator
    baud_rate_gen #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .OVERSAMPLING(OVERSAMPLING),
        .DVSR(DVSR),
        .DVSR_BIT(DVSR_BIT)
    ) baud_gen (
        .clk(clk),
        .reset(reset),
        .tick(tick)
    );
    
    // Instancia UART RX
    uart_rx #(
        .DBIT(DBIT),
        .SB_TICK(OVERSAMPLING)
    ) uart_rx_inst (
        .clk(clk),
        .reset(reset),
        .rx(rx_line),
        .s_tick(tick),
        .rx_done_tick(rx_done_tick),
        .dout(rx_data)
    );
    
    // Instancia UART TX
    uart_tx #(
        .DBIT(DBIT),
        .SB_TICK(OVERSAMPLING)
    ) uart_tx_inst (
        .clk(clk),
        .reset(reset),
        .tx_start(tx_start),
        .s_tick(tick),
        .din(tx_data),
        .tx_done_tick(tx_done_tick),
        .tx(tx_line)
    );
    
    // Instancia de la Interfaz ALU
    intf_alu #(
        .DBIT(DBIT),
        .ALU_WIDTH(ALU_WIDTH)
    ) intf_alu_inst (
        .clk(clk),
        .reset(reset),
        .rx_done_tick(rx_done_tick),
        .rx_data(rx_data),
        .alu_a(alu_a),
        .alu_b(alu_b),
        .alu_op(alu_op),
        .alu_result(alu_result),
        .alu_carry(alu_carry),
        .alu_zero(alu_zero),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_done_tick(tx_done_tick)
    );
    
    // Instancia de la ALU
    alu #(
        .NB_IN(ALU_WIDTH),
        .NB_OUT(ALU_WIDTH),
        .NB_OP(6)
    ) alu_inst (
        .i_a(alu_a),
        .i_b(alu_b),
        .i_op(alu_op),
        .o_outresult(alu_result),
        .o_carry(alu_carry),
        .o_zero(alu_zero)
    );
    
    // Conexión de línea RX (simulada desde testbench)
    assign rx_line = tx_sim;
    
    // Generación del clock
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Task para transmitir un byte por UART (simula PC enviando)
    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            // $display("[%0t] Enviando byte: 0x%02h (%d)", $time, data, data);
            
            // Start bit
            tx_sim = 0;
            #BIT_PERIOD;
            
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                tx_sim = data[i];
                #BIT_PERIOD;
            end
            
            // Stop bit
            tx_sim = 1;
            #(BIT_PERIOD/2);
            
            // Pequeña pausa entre bytes
            // #(BIT_PERIOD * 2);
        end
    endtask
    
    // Task para recibir un byte por UART (simula PC recibiendo)
    task uart_receive_byte;
        output [7:0] data;
        integer i;
        begin
            // $display("Recibiendo nuevo byte");
            // Esperar start bit
            wait(tx_line == 0);
            #(BIT_PERIOD/2); // Ir al medio del start bit
            
            // Verificar start bit
            if (tx_line != 0) begin
                $display("[%0t] ERROR: Start bit invalido", $time);
            end
            
            #BIT_PERIOD; // Ir al primer bit de datos
            
            // Leer data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                data[i] = tx_line;
                #BIT_PERIOD;
            end
            
            // Verificar stop bit
            if (tx_line != 1) begin
                $display("[%0t] ERROR: Stop bit invalido", $time);
            end
            
            // $display("[%0t] Byte recibido: 0x%02h (%d)", $time, data, data);
        end
    endtask
    
    // Task para ejecutar un test completo
    task test_alu_operation;
        input [5:0] op_code;
        input [7:0] operand_a;
        input [7:0] operand_b;
        input [7:0] exp_result;
        input exp_carry;
        input exp_zero;
        input [256*8:1] op_name;
        
        reg [7:0] received_result;
        reg [7:0] received_flags;
        reg recv_carry, recv_zero;
        
        begin
            test_count = test_count + 1;
            $display("\n------------------------------------------------------");
            $display("TEST %0d: %0s", test_count, op_name);
            $display("--------------------------------------------------------");
            $display("Operando A: %0d (0x%02h, 0b%08b)", $signed(operand_a), operand_a, operand_a);
            $display("Operando B: %0d (0x%02h, 0b%08b)", $signed(operand_b), operand_b, operand_b);
            $display("Operacion: 0b%06b", op_code);
            $display("");
            
            // Enviar operación, operando A y operando B
            // $display(">>> Enviando operacion y operandos:");
            uart_send_byte({2'b00, op_code});
            uart_send_byte(operand_a);
            uart_send_byte(operand_b);
            
            // $display("\n<<< Recibiendo resultado y flags:");
            // Esperar y recibir resultado
            uart_receive_byte(received_result);
            uart_receive_byte(received_flags);
            
            recv_carry = received_flags[1];
            recv_zero = received_flags[0];
            
            // Verificar resultados
            $display("\n------------------------------------------------");
            $display("VERIFICACION DE RESULTADOS");
            $display("---------------------------------------------------");
            $display("Resultado:");
            $display("Esperado: %4d (0x%02h, 0b%08b)", $signed(exp_result), exp_result, exp_result);
            $display("Recibido: %4d (0x%02h, 0b%08b)", $signed(received_result), received_result, received_result);
            $display("Match: %s", (received_result == exp_result) ? "OK" : "FAIL");
            $display("----------------------------------------------------");
            $display("Flags:");
            $display("Carry - Esperado: %b | Recibido: %b | %s", exp_carry, recv_carry, 
                     (exp_carry == recv_carry) ? "OK" : "FAIL");
            $display("Zero  - Esperado: %b | Recibido: %b | %s", exp_zero, recv_zero,
                     (exp_zero == recv_zero) ? "OK" : "FAIL");
            $display("-----------------------------------------------------");
            
            if (received_result == exp_result && recv_carry == exp_carry && recv_zero == exp_zero) begin
                $display("\nTEST %0d PASSED\n", test_count);
                pass_count = pass_count + 1;
            end else begin
                $display("\nTEST %0d FAILED\n", test_count);
                fail_count = fail_count + 1;
            end
            
            #(BIT_PERIOD * 10); // Pausa entre tests
        end
    endtask
    
    // Proceso principal de testing
    initial begin
        $display("\n");
        $display("----------------------------------------------------------");
        $display("TESTBENCH SISTEMA ALU-UART");
        $display("----------------------------------------------------------");
        $display("\n");
        
        // Inicialización
        tx_sim = 1;  // Línea idle
        reset = 1;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Reset
        #(CLK_PERIOD * 20);
        reset = 0;
        #(CLK_PERIOD * 20);
        
        $display("\nIniciando pruebas...\n");
        
        // ========== PRUEBAS DE OPERACIONES ==========
        
        // Test 1: SUMA (sin overflow)
        test_alu_operation(
            6'b100000,  // op_suma
            8'd15,      // A = 15
            8'd10,      // B = 10
            8'd25,      // Resultado = 25
            1'b0,       // Carry = 0
            1'b0,       // Zero = 0
            "SUMA: 15 + 10 = 25"
        );
        
        // Test 2: SUMA (con overflow positivo)
        test_alu_operation(
            6'b100000,  // op_suma
            8'd127,     // A = 127 (máximo positivo)
            8'd1,       // B = 1
            -8'd128,    // Resultado = -128 (overflow)
            1'b1,       // Carry = 1 (overflow)
            1'b0,       // Zero = 0
            "SUMA: 127 + 1 = -128 (overflow)"
        );
        
        // Test 3: RESTA
        test_alu_operation(
            6'b100010,  // op_resta
            8'd30,      // A = 30
            8'd12,      // B = 12
            8'd18,      // Resultado = 18
            1'b0,       // Carry = 0
            1'b0,       // Zero = 0
            "RESTA: 30 - 12 = 18"
        );
        
        // Test 4: RESTA (resultado cero)
        test_alu_operation(
            6'b100010,  // op_resta
            8'd50,      // A = 50
            8'd50,      // B = 50
            8'd0,       // Resultado = 0
            1'b0,       // Carry = 0
            1'b1,       // Zero = 1
            "RESTA: 50 - 50 = 0 (flag zero)"
        );
        
        // Test 5: AND
        test_alu_operation(
            6'b100100,  // op_and
            8'b11110000, // A = 0xF0
            8'b10101010, // B = 0xAA
            8'b10100000, // Resultado = 0xA0
            1'b0,        // Carry = 0
            1'b0,        // Zero = 0
            "AND: 0xF0 & 0xAA = 0xA0"
        );
        
        // Test 6: OR
        test_alu_operation(
            6'b100101,  // op_or
            8'b11110000, // A = 0xF0
            8'b00001111, // B = 0x0F
            8'b11111111, // Resultado = 0xFF
            1'b0,        // Carry = 0
            1'b0,        // Zero = 0
            "OR: 0xF0 | 0x0F = 0xFF"
        );
        
        // Test 7: XOR
        test_alu_operation(
            6'b100110,  // op_xor
            8'b11110000, // A = 0xF0
            8'b11110000, // B = 0xF0
            8'b00000000, // Resultado = 0x00
            1'b0,        // Carry = 0
            1'b1,        // Zero = 1
            "XOR: 0xF0 ^ 0xF0 = 0x00 (flag zero)"
        );
        
        // Test 8: SRA (shift right arithmetic)
        test_alu_operation(
            6'b000011,  // op_sra
            -8'd8,      // A = -8 (0xF8)
            8'd2,       // B = 2
            -8'd2,      // Resultado = -2 (0xFE, mantiene signo)
            1'b0,       // Carry = 0
            1'b0,       // Zero = 0
            "SRA: -8 >>> 2 = -2 (aritmetico)"
        );
        
        // Test 9: SRL (shift right logical)
        test_alu_operation(
            6'b000010,  // op_srl
            8'b11110000, // A = 0xF0
            8'd4,       // B = 4
            8'b00001111, // Resultado = 0x0F
            1'b0,        // Carry = 0
            1'b0,        // Zero = 0
            "SRL: 0xF0 >> 4 = 0x0F (logico)"
        );
        
        // Test 10: NOR
        test_alu_operation(
            6'b100111,  // op_nor
            8'b11110000, // A = 0xF0
            8'b00001111, // B = 0x0F
            8'b00000000, // Resultado = 0x00
            1'b0,        // Carry = 0
            1'b1,        // Zero = 1
            "NOR: ~(0xF0 | 0x0F) = 0x00"
        );
        
        // ========== RESUMEN ==========
        #(BIT_PERIOD * 20);
        
        $display("\n");
        $display("----------------------------------------------------------");
        $display("RESUMEN DE PRUEBAS");
        $display("----------------------------------------------------------");
        $display("Tests ejecutados: %3d", test_count);
        $display("Tests exitosos:   %3d", pass_count);
        $display("Tests fallidos:   %3d", fail_count);
        $display("-----------------------------------------------------------");
        
        if (fail_count == 0) begin
            $display("TODOS LOS TESTS PASARON");
        end else begin
            $display("ALGUNOS TESTS FALLARON");
        end
        
        $display("----------------------------------------------------------");
        $display("\n");
        
        #(BIT_PERIOD * 50);
        $finish;
    end
    
    // Timeout de seguridad
    initial begin
        #50000000; // 50ms timeout
        $display("\n[ERROR] Timeout - La simulacion se detuvo automaticamente");
        $finish;
    end
    
    // Monitoreo opcional - Descomenta para debugging detallado
    // Opción 1: Monitor de estados principales
    // initial begin
    //     $monitor("[%0t] FSM=%0d | RX_done=%b RX_data=0x%02h | TX_start=%b TX_done=%b | ALU_OP=0b%06b A=%0d B=%0d Result=%0d Result_reg:0x%0d tx_line=%b", 
    //              $time, intf_alu_inst.state_reg, rx_done_tick, rx_data, 
    //              tx_start, tx_done_tick, alu_op, alu_a, alu_b, alu_result, intf_alu_inst.result_reg, tx_line);
    // end
    
    // Opción 2: Monitor solo de cambios importantes (comenta el anterior y descomenta este)
    /*
    always @(intf_alu_inst.state_reg) begin
        $display("[%0t] ═══ Estado FSM cambió a: %0d", $time, intf_alu_inst.state_reg);
    end
    
    always @(posedge rx_done_tick) begin
        $display("[%0t] *** RX recibió byte: 0x%02h", $time, rx_data);
    end
    
    always @(posedge tx_start) begin
        $display("[%0t] >>> TX iniciando envío de: 0x%02h", $time, tx_data);
    end
    */

endmodule