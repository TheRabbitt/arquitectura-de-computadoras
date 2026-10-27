`timescale 1ns / 1ps
`default_nettype none

module tb_if_to_id();

    // Parámetros
    localparam NB_PC = 32;
    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 10;
    localparam NOP_INSTR = 32'h00000013;

    // Señales de reloj y reset
    reg clk;
    reg rst;

    // Señales de control IF
    reg en;
    reg stall;
    reg halt;
    reg branch_sel;
    reg [NB_PC-1:0] branch_target;

    // Señales de control IF/ID (Riesgos)
    reg if_id_en;
    reg flush;

    // Señales simulando la Debug Unit / UART para carga de memoria
    reg                  mem_we;
    reg [ADDR_WIDTH-1:0] write_addr;
    reg [DATA_WIDTH-1:0] write_data;

    // Variable para el bucle for
    integer i;
    
    // Control de impresiones por ciclo
    integer cycle = 0;
    reg     print_en = 0;

    // Señales de conexión IF -> IF/ID
    wire [NB_PC-1:0] w_pc_if;
    wire [DATA_WIDTH-1:0] w_instruction_if;
    wire w_halted;

    // Salidas del registro IF/ID
    wire [NB_PC-1:0] o_pc_id;
    wire [DATA_WIDTH-1:0] o_instruction_id;

    // Generación de Reloj (100 MHz, Periodo de 10ns)
    always #5 clk = ~clk;

    // Instancia de la etapa IF (Fetch)
    stage_if u_stage_if (
        .i_clk           (clk),
        .i_rst           (rst),
        .i_en            (en),
        .i_stall         (stall),
        .i_halt          (halt),
        .i_branch_sel    (branch_sel),
        .i_branch_target (branch_target),
        
        // Conexiones al puerto B (Simulación UART)
        .i_mem_we        (mem_we),
        .i_debug_re      (1'b0),
        .i_debug_addr    (10'd0),
        .i_write_addr    (write_addr),
        .i_write_data    (write_data),
        
        .o_pc            (w_pc_if),
        .o_instruction   (w_instruction_if),
        .o_halted        (w_halted),
        .o_debug_rdata   ()
    );

    // Instancia del registro IF/ID (Pipeline)
    if_id_register u_if_id (
        .i_clk         (clk),
        .i_rst         (rst),
        .i_en          (if_id_en),
        .i_flush       (flush),
        .i_pc          (w_pc_if),
        .i_instruction (w_instruction_if),
        .o_pc          (o_pc_id),
        .o_instruction (o_instruction_id)
    );

    // Secuencia de prueba (Estímulos)
    initial begin
        // 0. Inicialización
        clk = 0;
        rst = 1;
        en = 0;
        stall = 0;
        halt = 0;
        branch_sel = 0;
        branch_target = 32'd0;
        if_id_en = 0;
        flush = 0;
        
        // Inicializar puerto de UART
        mem_we = 0;
        write_addr = 0;
        write_data = 0;

        $display("\n=== INICIO DE SIMULACION ===");
        
        // ---------------------------------------------------------------------
        // FASE 0: Carga del Programa vía "UART" (Puerto B de la Memoria)
        // ---------------------------------------------------------------------
        $display("--> Fase 0: Inicializando memoria completa con ceros...");
        @(negedge clk);
        mem_we = 1;
        
        // Bucle for para barrer todas las direcciones de memoria simulando la UART
        for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1) begin
            write_addr = i;
            write_data = 32'd0;
            @(negedge clk);
        end

        $display("--> Cargando instrucciones en memoria (Simulacion UART)...");
        // Alineamos las escrituras a los flancos de bajada para que se capturen en el flanco de subida
        @(negedge clk);
        mem_we = 1;
        
        write_addr = 10'd0;  write_data = 32'hAAAA0000; @(negedge clk);
        write_addr = 10'd1;  write_data = 32'hBBBB1111; @(negedge clk);
        write_addr = 10'd2;  write_data = 32'hCCCC2222; @(negedge clk);
        write_addr = 10'd3;  write_data = 32'hDDDD3333; @(negedge clk);
        
        // Cargamos una instrucción en el índice 10 (correspondiente al PC=40, porque 40/4 = 10)
        write_addr = 10'd10; write_data = 32'hFFFF9999; @(negedge clk);
        
        mem_we = 0; // Finaliza la carga
        $display("    Carga completada.");
        #10;
        
        print_en = 1;

        // ---------------------------------------------------------------------
        // FASE 1: Ejecución Normal
        // ---------------------------------------------------------------------
        $display("--> Fase 1: Liberar reset y Ejecucion Secuencial");
        rst = 0; 
        en = 1; 
        if_id_en = 1;
        
        // Esperamos 4 ciclos de reloj para ver las instrucciones AAAA0000 a DDDD3333
        #40;
        
        // ---------------------------------------------------------------------
        // FASE 2: Riesgo de Datos (Stall)
        // ---------------------------------------------------------------------
        $display("--> Fase 2: Stall (Congelando Pipeline por Riesgo de Datos)");
        stall = 1;      
        if_id_en = 0;   
        #20;
        
        // ---------------------------------------------------------------------
        // FASE 3: Reanudación tras Stall
        // ---------------------------------------------------------------------
        $display("--> Fase 3: Reanudacion de Ejecucion");
        stall = 0;
        if_id_en = 1;
        #20;

        // ---------------------------------------------------------------------
        // FASE 4: Riesgo de Control (Salto Tomado / Branch)
        // ---------------------------------------------------------------------
        $display("--> Fase 4: Flush por Branch Tomado a PC=40");
        branch_sel = 1;
        branch_target = 32'd40; // PC objetivo = 40 (índice 10 cargado previamente)
        flush = 1;              // Se borra el registro IF/ID inyectando NOP (0x00000013)
        #10;
        
        // ---------------------------------------------------------------------
        // FASE 5: Reanudación desde el nuevo PC
        // ---------------------------------------------------------------------
        $display("--> Fase 5: Soltar rama y ejecutar la nueva direccion (Target = FFFF9999)");
        branch_sel = 0;
        flush = 0;
        #30;

        // ---------------------------------------------------------------------
        // FASE 6: Prueba de HALT (Inyectar Stop)
        // ---------------------------------------------------------------------
        $display("--> Fase 6: Activar instruccion HALT (Detiene el PC)");
        halt = 1;
        #20; // Dejamos pasar 2 ciclos para verificar que se congele

        // ---------------------------------------------------------------------
        // FASE 7: Retención del estado HALT
        // ---------------------------------------------------------------------
        $display("--> Fase 7: Desactivar HALT de entrada (El PC debe seguir congelado)");
        halt = 0;
        #20; // Dejamos pasar 2 ciclos más. El sticky bit debe mantener el procesador frenado.

        // ---------------------------------------------------------------------
        // FASE 8: Reset para recuperar el procesador
        // ---------------------------------------------------------------------
        $display("--> Fase 8: Reset para limpiar el estado HALT y reiniciar ejecucion");
        rst = 1;
        #10; // 1 ciclo de reset
        
        rst = 0;
        #30; // 3 ciclos para ver cómo arranca de nuevo desde PC=0

        $display("=== FIN DE SIMULACION ===\n");
        $finish;
    end

    // Contador global de ciclos
    always @(posedge clk) begin
        cycle = cycle + 1;
    end

    // Monitorización de medio ciclo (flancos de subida y bajada)
    always @(posedge clk or negedge clk) begin
        if (print_en) begin
            if (clk == 1'b1) begin
                // Flanco de subida: Vemos el PC actualizarse. La memoria todavía muestra el dato viejo.
                $display("Ciclo %3d (SUBIDA) | rst=%b halt=%b flush=%b stall=%b br_sel=%b br_tgt=%2d | IF_PC=%2d IF_Instr=%8h | ID_PC=%2d ID_Instr=%8h", 
                         cycle, rst, halt, flush, stall, branch_sel, branch_target, w_pc_if, w_instruction_if, o_pc_id, o_instruction_id);
            end else begin
                // Flanco de bajada: La memoria ya resolvió la lectura y entrega la instrucción correspondiente al nuevo PC.
                $display("Ciclo %3d (BAJADA) | rst=%b halt=%b flush=%b stall=%b br_sel=%b br_tgt=%2d | IF_PC=%2d IF_Instr=%8h | ID_PC=%2d ID_Instr=%8h", 
                         cycle, rst, halt, flush, stall, branch_sel, branch_target, w_pc_if, w_instruction_if, o_pc_id, o_instruction_id);
            end
        end
    end

endmodule
`default_nettype wire