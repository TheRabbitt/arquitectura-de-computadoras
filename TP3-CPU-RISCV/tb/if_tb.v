`timescale 1ns / 1ps
`default_nettype none

module if_stage_tb;

    // Parámetros
    localparam NB_PC      = 32;
    localparam ADDR_WIDTH = 10;
    localparam DATA_WIDTH = 32;
    localparam T          = 10;

    // Señales de Control Generales
    reg tb_clk;
    reg tb_rst;
    reg tb_en;
    reg tb_stall;
    reg tb_halt;
    reg tb_read_enable; // Control de lectura Fetch

    // Señales de Control de Salto (MUX)
    reg                 tb_branch_sel;
    reg  [NB_PC-1:0]    tb_branch_target;

    // Señales de Programación y Lectura de Memoria (Simula UART)
    reg                   tb_mem_we;
    reg                   tb_debug_re; // Control de lectura UART
    reg  [ADDR_WIDTH-1:0] tb_mem_addr;
    reg  [DATA_WIDTH-1:0] tb_mem_data;

    // Cables de Interconexión de la etapa IF
    wire [NB_PC-1:0]      w_next_pc;
    wire [NB_PC-1:0]      w_pc_plus_4;
    wire [NB_PC-1:0]      w_pc_actual;
    wire                  w_halted;
    wire [DATA_WIDTH-1:0] w_instruction;
    wire [DATA_WIDTH-1:0] w_debug_rdata; // Salida de lectura UART

    integer errores = 0;

    // Instancia del Registro PC
    registro_pc #(
        .NB_PC(NB_PC),
        .PC_RESET(32'h0000_0000)
    ) u_pc (
        .i_clk     (tb_clk),
        .i_rst     (tb_rst),
        .i_en      (tb_en),
        .i_stall   (tb_stall),
        .i_halt    (tb_halt),
        .i_next_pc (w_next_pc),
        .o_pc      (w_pc_actual),
        .o_halted  (w_halted)
    );

    // Instancia del Sumador (PC + 4)
    sumador #(
        .NB_SUM(NB_PC)
    ) u_adder_pc4 (
        .i_a      (w_pc_actual),
        .i_b      (32'd4),
        .o_result (w_pc_plus_4)
    );

    // Instancia del MUX2 (Selección de próximo PC)
    mux2 #(
        .NB(NB_PC)
    ) u_mux_next_pc (
        .i_sel (tb_branch_sel),
        .i_d0  (w_pc_plus_4),
        .i_d1  (tb_branch_target),
        .o_out (w_next_pc)
    );

    // Instancia de la Memoria de Instrucciones
    InstructionMemory #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_imem (
        .i_clk         (tb_clk),
        // Puerto A (Lectura del procesador)
        .i_pc          (w_pc_actual),
        .i_read_enable (tb_read_enable),
        .o_instruction (w_instruction),
        // Puerto B (Lectura/Escritura desde UART)
        .i_write_en    (tb_mem_we),
        .i_debug_re    (tb_debug_re),   
        .i_write_addr  (tb_mem_addr),
        .i_write_data  (tb_mem_data),
        .i_debug_addr  (tb_mem_addr),
        .o_debug_rdata (w_debug_rdata)  
    );

    // Generación de Reloj
    initial tb_clk = 1'b0;
    always #(T/2) tb_clk = ~tb_clk;

    task ciclo;
        begin
            @(posedge tb_clk);
            @(negedge tb_clk);
            #1;                
        end
    endtask

    // Secuencia de Pruebas
    initial begin
        $dumpfile("if_stage_tb.vcd");
        $dumpvars(0, if_stage_tb);

        // Estado inicial: Procesador en reset y apagado
        tb_rst           = 1'b1;
        tb_en            = 1'b0;
        tb_stall         = 1'b0;
        tb_halt          = 1'b0;
        tb_branch_sel    = 1'b0;
        tb_branch_target = 32'h0;
        tb_read_enable   = 1'b1; // Fetch habilitado por defecto
        tb_mem_we        = 1'b0;
        tb_debug_re      = 1'b0; // UART no lee por defecto
        tb_mem_addr      = 0;
        tb_mem_data      = 0;
        
        ciclo();

        // ---------------------------------------------------------
        // FASE 1: Programación de la memoria (Simulando UART)
        // ---------------------------------------------------------
        $display("=== FASE 1: Cargando programa via Puerto B ===");
        tb_mem_we = 1'b1;
        
        // Escribimos instrucciones secuenciales
        tb_mem_addr = 10'd0; tb_mem_data = 32'hAAAA_0000; ciclo();
        tb_mem_addr = 10'd1; tb_mem_data = 32'hBBBB_1111; ciclo();
        tb_mem_addr = 10'd2; tb_mem_data = 32'hCCCC_2222; ciclo();
        tb_mem_addr = 10'd3; tb_mem_data = 32'hDDDD_3333; ciclo();
        
        // Escribimos instrucciones para probar saltos y reanudación
        tb_mem_addr = 10'd10; tb_mem_data = 32'hFFFF_9999; ciclo(); // PC = 40 (0x28)
        tb_mem_addr = 10'd11; tb_mem_data = 32'hEEEE_4444; ciclo(); // PC = 44 (0x2C) - Siguiente tras salto

        tb_mem_we = 1'b0; // Terminamos de escribir

        // ---------------------------------------------------------
        // FASE 2: Verificación de lectura por UART
        // ---------------------------------------------------------
        $display("\n=== FASE 2: Verificando Lectura UART ===");
        tb_debug_re = 1'b1; // Habilitamos lectura del Puerto B
        
        tb_mem_addr = 10'd0; ciclo(); // Leemos dirección 0
        if (w_debug_rdata !== 32'hAAAA_0000) begin
            $display("[FAIL] Lectura UART dir 0 incorrecta: %h", w_debug_rdata);
            errores = errores + 1;
        end else $display("[ OK ] Lectura UART dir 0 correcta.");

        tb_mem_addr = 10'd10; ciclo(); // Leemos dirección 10
        if (w_debug_rdata !== 32'hFFFF_9999) begin
            $display("[FAIL] Lectura UART dir 10 incorrecta: %h", w_debug_rdata);
            errores = errores + 1;
        end else $display("[ OK ] Lectura UART dir 10 correcta.");

        tb_debug_re = 1'b0; // Deshabilitamos lectura UART

        // ---------------------------------------------------------
        // FASE 3: Ejecución (Fetch)
        // ---------------------------------------------------------
        $display("\n=== FASE 3: Ejecucion Secuencial ===");
        if(w_instruction !==32'hAAAA_0000) begin
            $display("[FAIL] Instruccion inicial incorrecta: %h", w_instruction);
            errores = errores + 1;
        end else $display("[ OK ] Instruccion inicial correcta.");
            
        tb_rst = 1'b0;
        tb_en  = 1'b1; // Encendemos el procesador
        
        // Ciclo 1: PC pasa a 4 (posedge). La memoria escupe la instr 1 (negedge).
        ciclo();
        if (w_instruction !== 32'hBBBB_1111) begin
            $display("[FAIL] Instruccion en PC=4 incorrecta: %h", w_instruction);
            errores = errores + 1;
        end else $display("[ OK ] Instruccion 1 (PC=4) recuperada.");

        // Ciclo 2: PC pasa a 8 (posedge). La memoria escupe la instr 2 (negedge).
        ciclo();
        if (w_instruction !== 32'hCCCC_2222) begin
            $display("[FAIL] Instruccion en PC=8 incorrecta: %h", w_instruction);
            errores = errores + 1;
        end else $display("[ OK ] Instruccion 2 (PC=8) recuperada.");

        // ---------------------------------------------------------
        // FASE 4: Salto (Branch/Jump)
        // ---------------------------------------------------------
        $display("\n=== FASE 4: Salto a PC=40 (0x28) ===");
        tb_branch_sel    = 1'b1;
        tb_branch_target = 32'd40; // Indice de palabra 10[cite: 2]
        ciclo(); // En este ciclo el MUX mete el 40 al PC[cite: 2]
        
        tb_branch_sel = 1'b0; // Soltamos el salto[cite: 2]
        
        // La memoria debe escupir la instrucción alojada en la palabra 10.
        if (w_instruction !== 32'hFFFF_9999) begin
            $display("[FAIL] Instruccion tras salto incorrecta: %h", w_instruction);
            errores = errores + 1;
        end else $display("[ OK ] Instruccion de destino de salto recuperada.");

        // ---------------------------------------------------------
        // FASE 5: Reanudación de la Ejecución Secuencial
        // ---------------------------------------------------------
        $display("\n=== FASE 5  : Reanudacion Secuencial (PC=44) ===");
        // Como soltamos tb_branch_sel en el ciclo anterior, el PC debe avanzar a 40 + 4
        ciclo(); 
        
        if (w_instruction !== 32'hEEEE_4444) begin
            $display("[FAIL] Instruccion tras reanudacion incorrecta: %h", w_instruction);
            errores = errores + 1;
        end else $display("[ OK ] Ejecucion secuencial reanudada en PC=44.");

        $display("\n--------------------------------------------------");
        if (errores == 0) $display(">>> TEST PASSED : IF Stage Completado");
        else              $display(">>> TEST FAILED : %0d errores", errores);
        $display("--------------------------------------------------\n");
        
        $finish;
    end

endmodule
`default_nettype wire