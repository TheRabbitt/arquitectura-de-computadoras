`timescale 1ns / 1ps

module tb_alu();

    // Parámetros
    parameter NB_IN  = 8;
    parameter NB_OUT = 8;
    parameter NB_OP  = 6;

    localparam op_suma  =       6'b100000  ;
    localparam op_resta =       6'b100010  ;
    localparam op_and   =       6'b100100  ;
    localparam op_or    =       6'b100101  ;
    localparam op_xor   =       6'b100110  ;
    localparam op_sra   =       6'b000011  ;
    localparam op_srl   =       6'b000010  ;
    localparam op_nor   =       6'b100111  ;
    localparam max_val  =       8'b11111111;
    
    // Señales de prueba
    reg               clk          ;
    reg               rst_n        ;
    reg  [2       :0] i_btn        ;
    reg  [NB_IN-1 :0] i_sw_data    ;
    wire [NB_OUT-1:0] o_leds_result;
    wire              o_carry      ;
    wire              o_zero       ;
    
    // Instancia del módulo bajo prueba
    top #(
        .NB_IN(NB_IN)  ,
        .NB_OUT(NB_OUT),
        .NB_OP(NB_OP)
    ) dut (
        .clk(clk)                    ,
        .rst_n(rst_n)                ,
        .i_btn(i_btn)                ,
        .i_sw_data(i_sw_data)        ,
        .o_leds_result(o_leds_result),
        .o_carry(o_carry)            ,
        .o_zero(o_zero)
    );
    
    // Generación de reloj
    always #5 clk = ~clk;

    // Tarea para cargar datos y operación
    task load_data_and_op;
        input [NB_IN-1:0] data_a;
        input [NB_IN-1:0] data_b;
        input [NB_OP-1:0] op    ;
        begin
            // Cargar data_a
            i_sw_data = data_a;
            i_btn     = 3'b001;
            #10               ;
            i_btn     = 3'b000;    // PRIMERO desactivar botón
            #10               ;
            i_sw_data = 8'b0  ;    // DESPUÉS limpiar datos
            #10               ;
            
            // Cargar data_b
            i_sw_data = data_b;
            i_btn     = 3'b010;
            #10               ;
            i_btn     = 3'b000;    // PRIMERO desactivar botón
            #10               ;
            i_sw_data = 8'b0  ;    // DESPUÉS limpiar datos
            #10               ;
            
            // Cargar operación
            i_sw_data = {{(NB_IN-NB_OP){1'b0}}, op};
            i_btn     = 3'b100                     ;
            #10                                    ;
            i_btn     = 3'b000                     ;  // PRIMERO desactivar botón
            #10                                    ;
            i_sw_data = 8'b0                       ;  // DESPUÉS limpiar datos
            #10                                    ;
        end
    endtask
    
    //Procedimiento de prueba
    initial begin
        // Inicialización
        clk       = 0     ;
        rst_n     = 1     ;  // Reset activo
        i_btn     = 3'b000;
        i_sw_data = 8'h00 ;
        
        #10;              // Esperar algunos ciclos
        rst_n = 0;        // Liberar reset (permitir operación normal)
        #10;              // Esperar estabilización
        
        $display("Starting tests...");
        
        // Prueba de suma
        load_data_and_op(8'h01, 8'h02, op_suma);
        #10                                    ;

        if(o_leds_result == 8'h03) begin
            $display("Test passed: 1 + 2 = 3")                        ;
        end else begin
            $display("Test failed: Expected 3, got %h", o_leds_result);
        end

        // Prueba de suma con overflow
        load_data_and_op(8'h64, 8'h32, op_suma); // 100 + 50 = 150 (overflow)
        #10                                    ;
        
        if(o_leds_result == 8'h96 && o_carry) begin
            $display("Test passed: 100 + 50 = 150 with carry")         ;
        end else begin
            $display("Test failed: Expected 150 with carry, got %h (carry=%b)", o_leds_result, o_carry);
        end

        // Prueba 2 de suma con overflow
        load_data_and_op(8'h7F, 8'h01, op_suma); // 127 + 1 = 128 (overflow)
        #20                                    ;

        if(o_leds_result == 8'h80 && o_carry) begin
            $display("Test passed: 127 + 1 = 128 with carry")          ;
        end else begin
            $display("Test failed: Expected 128 with carry, got %h (carry=%b)", o_leds_result, o_carry);
        end

        // Prueba de suma con overflow de 2 números negativos
        load_data_and_op(8'h80, 8'hFF, op_suma); // -128 + -1 = 127 (overflow)
        #20                                    ;

        if(o_leds_result == 8'h7F && o_carry) begin
            $display("Test passed: -128 + -1 = 127 with carry")         ;
        end else begin
            $display("Test failed: Expected 127 with carry, got %h (carry=%b)", o_leds_result, o_carry);
        end

        // Prueba de resta
        load_data_and_op(8'h05, 8'h03, op_resta);
        #10                                     ;

        if(o_leds_result == 8'h02) begin
            $display("Test passed: 5 - 3 = 2")                        ;
        end else begin
            $display("Test failed: Expected 2, got %h", o_leds_result);
        end

        // Prueba de resta con overflow
        load_data_and_op(8'h80, 8'h01, op_resta); // –128 – 1 → overflow
        #10                                     ;

        if(o_leds_result == 8'h7F && o_carry) begin
            $display("Test passed: -128 - 1 = 127 with carry")         ;
        end else begin
            $display("Test failed: Expected 127 with carry, got %h (carry=%b)", o_leds_result, o_carry);
        end

        // Prueba de resta de 1 número positivo y otro negativo
        load_data_and_op(8'h05, 8'hFB, op_resta); // 5 - (-5) = 10
        #20                                     ;
        if(o_leds_result == 8'h0A) begin
            $display("Test passed: 5 - (-5) = 10")                     ;
        end else begin
            $display("Test failed: Expected 10, got %h", o_leds_result);
        end

        // Prueba de resta de 1 número positivo con un número negativo con overflow
        load_data_and_op(8'h7F, 8'h81, op_resta); // 127 - (-127) = overflow
        #20                                     ;

        if(o_leds_result == 8'hFE && o_carry) begin
            $display("Test passed: 127 - (-127) = -2 with carry")       ;
        end else begin
            $display("Test failed: Expected -2 with carry, got %h (carry=%b)", o_leds_result, o_carry);
        end

        // Prueba de resta con resultado negativo sin overflow
        load_data_and_op(8'h03, 8'h05, op_resta); // 3 - 5 = -2
        #20                                     ;

        if(o_leds_result == 8'hFE && !o_carry) begin
            $display("Test passed: 3 - 5 = -2 without carry")           ;
        end else begin
            $display("Test failed: Expected -2 without carry, got %h (carry=%b)", o_leds_result, o_carry);
        end
        
        // Prueba de AND
        load_data_and_op(8'h0F, 8'h03, op_and);
        #10                                   ;

        if(o_leds_result == 8'h03) begin
            $display("Test passed: 0F AND 03 = 03")                    ;
        end else begin
            $display("Test failed: Expected 03, got %h", o_leds_result);
        end

        // Prueba de OR
        load_data_and_op(8'h0F, 8'h03, op_or);
        #10                                ;

        if(o_leds_result == 8'h0F) begin
            $display("Test passed: 0F OR 03 = 0F")                     ;
        end else begin
            $display("Test failed: Expected 0F, got %h", o_leds_result);
        end

        // Prueba de XOR
        load_data_and_op(8'h0F, 8'h03, op_xor);
        #10                                   ;

        if(o_leds_result == 8'h0C) begin
            $display("Test passed: 0F XOR 03 = 0C")                    ;
        end else begin
            $display("Test failed: Expected 0C, got %h", o_leds_result);
        end

        // Prueba de SRA
        load_data_and_op(8'hF0, 8'h02, op_sra);
        #10                                   ;

        if(o_leds_result == 8'hFC) begin
            $display("Test passed: F0 SRA 02 = FC")                    ;
        end else begin
            $display("Test failed: Expected FC, got %h", o_leds_result);
        end

        // Prueba de SRL
        load_data_and_op(8'hF0, 8'h02, op_srl);
        #10                                   ;

        if(o_leds_result == 8'h3C) begin
            $display("Test passed: F0 SRL 02 = 3C")                    ;
        end else begin
            $display("Test failed: Expected 3C, got %h", o_leds_result);
        end

        // Prueba de NOR
        load_data_and_op(8'h0F, 8'h03, op_nor);
        #10                                   ;

        if(o_leds_result == 8'hF0) begin
            $display("Test passed: 0F NOR 03 = F0")                    ;
        end else begin
            $display("Test failed: Expected F0, got %h", o_leds_result);
        end
        
        // Finalizar simulación
        #10    ;
        $finish;
    end
endmodule