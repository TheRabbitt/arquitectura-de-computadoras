`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: debug_unit_tb
// Descripción:
//   Testbench AUTOVERIFICANTE de integración completa entre riscv_core y
//   debug_unit comunicándose exclusivamente por líneas seriales UART (8N1).
//
//   Escenarios verificados automáticamente:
//   1. Comando inválido (NAK 0x5A), RESET (0x01 -> ACK 0xA5) y STATUS (0x24).
//   2. Carga dinámica del Programa #1 por UART (LOAD_PROG 0x02) con EBREAK.
//   3. Ejecución Paso a Paso (STEP 0x11): inspección ciclo a ciclo de PC y
//      latches intermedios (incluyendo burbuja Load-Use y fase de draining tras
//      EBREAK), verificación de vaciado total del pipeline, los 32 registros y
//      memoria de datos usada (DUMP_DMEM y DUMP_DMEM_USED).
//   4. Reprogramación dinámica sin reset físico cargando el Programa #2 (más
//      corto que el #1), comprobación de limpieza previa de estado, ejecución
//      en Modo Continuo (RUN 0x10 -> ACK 0xA5 -> HALTED 0xF1) y verificación
//      completa de los 32 registros, latches vacíos y memoria de datos usada.
//==============================================================================

module debug_unit_tb;

    // Parámetros acelerados para simulación (DVSR = 2 -> 1 bit UART = 32 ciclos = 320 ns)
    localparam integer CLK_PERIOD_NS   = 10;
    localparam integer SB_TICK         = 16;
    localparam integer DVSR            = 2;
    localparam integer BIT_CYCLES      = SB_TICK * DVSR; // 32 ciclos por bit
    localparam integer BIT_TIME_NS     = BIT_CYCLES * CLK_PERIOD_NS;
    localparam integer IMEM_ADDR_WIDTH = 10;
    localparam integer DMEM_ADDR_WIDTH = 8;

    // Reloj y Reset físico
    reg  clk = 1'b0;
    reg  rst = 1'b1;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // Líneas seriales UART (PC <-> FPGA)
    reg  pc_tx_line = 1'b1; // Conecta a i_uart_rx de la FPGA
    wire fpga_tx_line;      // Conecta a o_uart_tx de la FPGA

    // Interconexión Debug Unit <-> RISC-V Core
    wire                        dbg_core_rst;
    wire                        dbg_core_en;
    wire                        core_halted;
    wire                        core_pipeline_empty;
    wire                        core_exec_done;
    wire                        core_draining;

    wire                        imem_we;
    wire [IMEM_ADDR_WIDTH-1:0]  imem_waddr;
    wire [31:0]                 imem_wdata;

    wire                        rf_debug_re;
    wire [4:0]                  rf_debug_addr;
    wire [31:0]                 rf_debug_rdata;

    wire                        dmem_clear_we;
    wire [DMEM_ADDR_WIDTH-1:0]  dmem_clear_addr;
    wire                        dmem_debug_re;
    wire [DMEM_ADDR_WIDTH-1:0]  dmem_debug_addr;
    wire [31:0]                 dmem_debug_rdata;
    wire [(1<<DMEM_ADDR_WIDTH)-1:0] dmem_used_mask;

    wire [31:0]                 debug_pc;
    wire [127:0]                debug_if_id;
    wire [191:0]                debug_id_ex;
    wire [127:0]                debug_ex_mem;
    wire [127:0]                debug_mem_wb;
    wire                        dbg_running;
    wire                        dbg_prog_loaded;

    // Instancia del Procesador RISC-V
    riscv_core #(
        .NB_PC          (32),
        .DATA_WIDTH     (32),
        .IMEM_ADDR_WIDTH(IMEM_ADDR_WIDTH),
        .DMEM_ADDR_WIDTH(DMEM_ADDR_WIDTH)
    ) u_core (
        .i_clk              (clk),
        .i_rst              (rst | dbg_core_rst),
        .i_en               (dbg_core_en),
        .o_halted           (core_halted),
        .o_pipeline_empty   (core_pipeline_empty),
        .o_exec_done        (core_exec_done),
        .o_draining         (core_draining),
        .i_imem_we          (imem_we),
        .i_imem_waddr       (imem_waddr),
        .i_imem_wdata       (imem_wdata),
        .i_imem_debug_re    (1'b0),
        .i_imem_debug_addr  ({IMEM_ADDR_WIDTH{1'b0}}),
        .o_imem_debug_rdata (),
        .i_rf_debug_re      (rf_debug_re),
        .i_rf_debug_addr    (rf_debug_addr),
        .o_rf_debug_rdata   (rf_debug_rdata),
        .i_dmem_clear_we    (dmem_clear_we),
        .i_dmem_clear_addr  (dmem_clear_addr),
        .i_dmem_debug_re    (dmem_debug_re),
        .i_dmem_debug_addr  (dmem_debug_addr),
        .o_dmem_debug_rdata (dmem_debug_rdata),
        .o_dmem_used_mask   (dmem_used_mask),
        .o_debug_pc         (debug_pc),
        .o_debug_if_id      (debug_if_id),
        .o_debug_id_ex      (debug_id_ex),
        .o_debug_ex_mem     (debug_ex_mem),
        .o_debug_mem_wb     (debug_mem_wb)
    );

    // Instancia de la Debug Unit
    debug_unit #(
        .CLK_FREQ_HZ    (100_000_000),
        .BAUD_RATE      (115_200),
        .SB_TICK        (SB_TICK),
        .DVSR           (DVSR),
        .IMEM_ADDR_WIDTH(IMEM_ADDR_WIDTH),
        .DMEM_ADDR_WIDTH(DMEM_ADDR_WIDTH)
    ) u_debug_unit (
        .i_clk              (clk),
        .i_rst              (rst),
        .i_uart_rx          (pc_tx_line),
        .o_uart_tx          (fpga_tx_line),
        .o_core_rst         (dbg_core_rst),
        .o_core_en          (dbg_core_en),
        .i_halted           (core_halted),
        .i_pipeline_empty   (core_pipeline_empty),
        .i_exec_done        (core_exec_done),
        .i_draining         (core_draining),
        .o_imem_we          (imem_we),
        .o_imem_waddr       (imem_waddr),
        .o_imem_wdata       (imem_wdata),
        .o_rf_debug_re      (rf_debug_re),
        .o_rf_debug_addr    (rf_debug_addr),
        .i_rf_debug_rdata   (rf_debug_rdata),
        .o_dmem_clear_we    (dmem_clear_we),
        .o_dmem_clear_addr  (dmem_clear_addr),
        .o_dmem_debug_re    (dmem_debug_re),
        .o_dmem_debug_addr  (dmem_debug_addr),
        .i_dmem_debug_rdata (dmem_debug_rdata),
        .i_dmem_used_mask   (dmem_used_mask),
        .i_debug_pc         (debug_pc),
        .i_debug_if_id      (debug_if_id),
        .i_debug_id_ex      (debug_id_ex),
        .i_debug_ex_mem     (debug_ex_mem),
        .i_debug_mem_wb     (debug_mem_wb),
        .o_running          (dbg_running),
        .o_prog_loaded      (dbg_prog_loaded)
    );

    // =========================================================================
    // Receptor Asíncrono (Monitor PC) con Buffer Circular para no perder bytes
    // =========================================================================
    reg [7:0] rx_fifo [0:4095];
    integer   rx_wr_ptr = 0;
    integer   rx_rd_ptr = 0;

    always begin : monitor_fpga_tx
        reg [7:0] captured;
        integer   b;
        @(negedge fpga_tx_line);          // Detectar flanco de bajada (Start bit)
        #(BIT_TIME_NS / 2);               // Centro del Start bit
        if (fpga_tx_line === 1'b0) begin
            for (b = 0; b < 8; b = b + 1) begin
                #(BIT_TIME_NS);
                captured[b] = fpga_tx_line;
            end
            #(BIT_TIME_NS);               // Centro del Stop bit
            rx_fifo[rx_wr_ptr & 4095] = captured;
            rx_wr_ptr = rx_wr_ptr + 1;
        end
    end

    // =========================================================================
    // Tareas Auxiliares de Envío/Recepción UART y Verificación
    // =========================================================================
    integer errors = 0;

    task check_cond(input cond, input [8*80-1:0] msg);
        begin
            if (cond) begin
                $display("  [OK]   %0s", msg);
            end else begin
                $display("  [FAIL] %0s (t=%0t)", msg, $time);
                errors = errors + 1;
            end
        end
    endtask

    task check_eq32(input [31:0] got, input [31:0] exp, input [8*80-1:0] msg);
        begin
            if (got === exp) begin
                $display("  [OK]   %0s = 0x%08h", msg, got);
            end else begin
                $display("  [FAIL] %0s: obtenido=0x%08h esperado=0x%08h (t=%0t)", msg, got, exp, $time);
                errors = errors + 1;
            end
        end
    endtask

    task uart_send_byte(input [7:0] data);
        integer b;
        begin
            pc_tx_line = 1'b0; // Start bit
            #(BIT_TIME_NS);
            for (b = 0; b < 8; b = b + 1) begin
                pc_tx_line = data[b];
                #(BIT_TIME_NS);
            end
            pc_tx_line = 1'b1; // Stop bit
            #(BIT_TIME_NS);
        end
    endtask

    task uart_send_u16(input [15:0] val);
        begin
            uart_send_byte(val[7:0]);
            uart_send_byte(val[15:8]);
        end
    endtask

    task uart_send_u32(input [31:0] val);
        begin
            uart_send_byte(val[7:0]);
            uart_send_byte(val[15:8]);
            uart_send_byte(val[23:16]);
            uart_send_byte(val[31:24]);
        end
    endtask

    task uart_recv_byte(output [7:0] data);
        integer timeout_cycles;
        begin
            timeout_cycles = 0;
            while (rx_rd_ptr == rx_wr_ptr) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
                if (timeout_cycles > 200000) begin
                    $display("  [FAIL] Timeout esperando byte UART desde FPGA (t=%0t)", $time);
                    errors = errors + 1;
                    $fatal(1);
                end
            end
            data = rx_fifo[rx_rd_ptr & 4095];
            rx_rd_ptr = rx_rd_ptr + 1;
        end
    endtask

    task uart_recv_u16(output [15:0] val);
        reg [7:0] b0, b1;
        begin
            uart_recv_byte(b0);
            uart_recv_byte(b1);
            val = {b1, b0};
        end
    endtask

    task uart_recv_u32(output [31:0] val);
        reg [7:0] b0, b1, b2, b3;
        begin
            uart_recv_byte(b0);
            uart_recv_byte(b1);
            uart_recv_byte(b2);
            uart_recv_byte(b3);
            val = {b3, b2, b1, b0};
        end
    endtask

    // Buffers de lectura de dumps en el TB
    reg [31:0] dumped_regs    [0:31];
    reg [31:0] dumped_latches [0:17];

    task dump_all_regs;
        integer r;
        begin
            uart_send_byte(8'h20); // CMD_DUMP_REGS
            for (r = 0; r < 32; r = r + 1) begin
                uart_recv_u32(dumped_regs[r]);
            end
        end
    endtask

    task dump_all_latches;
        integer w;
        begin
            uart_send_byte(8'h21); // CMD_DUMP_LATCHES (18 palabras = 72 bytes)
            for (w = 0; w < 18; w = w + 1) begin
                uart_recv_u32(dumped_latches[w]);
            end
        end
    endtask

    // =========================================================================
    // Secuencia Principal de Pruebas
    // =========================================================================
    reg [7:0]  resp;
    reg [7:0]  status_byte;
    reg [31:0] pc_val;
    reg [31:0] mem_word;
    reg [15:0] used_cnt;
    reg [15:0] used_addr0, used_addr1;
    reg [31:0] used_data0, used_data1;
    integer    step_num;
    integer    k;
    reg        saw_load_use_bubble;
    reg        saw_draining_flag;

    initial begin
        $display("============================================================================");
        $display("          INICIO TESTBENCH AUTOVERIFICANTE: DEBUG UNIT + RISC-V CORE        ");
        $display("============================================================================");

        // Reset físico inicial
        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (10) @(posedge clk);

        // ---------------------------------------------------------------------
        // TEST 1: Comando inválido (NAK), RESET (0x01) y STATUS (0x24)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 1] Comando desconocido, RESET y STATUS inicial ---");
        uart_send_byte(8'hFE); // Comando inexistente
        uart_recv_byte(resp);
        check_cond(resp === 8'h5A, "Comando desconocido devuelve NAK (0x5A)");

        uart_send_byte(8'h01); // CMD_RESET
        uart_recv_byte(resp);
        check_cond(resp === 8'hA5, "CMD_RESET devuelve ACK (0xA5)");

        uart_send_byte(8'h24); // CMD_STATUS
        uart_recv_byte(status_byte);
        check_cond(status_byte === 8'h00, "STATUS inicial en 0x00 (detenido, sin prog)");

        // ---------------------------------------------------------------------
        // TEST 2: Carga dinámica del Programa #1 por UART (LOAD_PROG = 0x02)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 2] Carga dinamica de Programa #1 (11 instrucciones) por UART ---");
        uart_send_byte(8'h02);    // CMD_LOAD_PROG
        uart_send_u16(16'd11);    // N = 11 instrucciones
        uart_send_u32(32'h01900093); // 0x00: addi x1, x0, 25        -> x1 = 25
        uart_send_u32(32'hFFB00113); // 0x04: addi x2, x0, -5        -> x2 = 0xFFFFFFFB
        uart_send_u32(32'h002081B3); // 0x08: add  x3, x1, x2        -> x3 = 20
        uart_send_u32(32'h00302423); // 0x0C: sw   x3, 8(x0)         -> dmem[2] = 0x00000014
        uart_send_u32(32'h00802203); // 0x10: lw   x4, 8(x0)         -> x4 = 20
        uart_send_u32(32'h001202B3); // 0x14: add  x5, x4, x1        -> Load-Use Stall -> x5 = 45
        uart_send_u32(32'h00200AA3); // 0x18: sb   x2, 21(x0)        -> dmem[5] = 0x0000FB00
        uart_send_u32(32'h0080036F); // 0x1C: jal  x6, 8             -> salta a 0x24, x6 = 0x20
        uart_send_u32(32'h30900F13); // 0x20: addi x30, x0, 777      -> descartada por flush de JAL
        uart_send_u32(32'h00100073); // 0x24: ebreak                 -> HALT
        uart_send_u32(32'h3E700F93); // 0x28: addi x31, x0, 999      -> descartada tras EBREAK

        uart_recv_byte(resp);
        check_cond(resp === 8'hA5, "LOAD_PROG #1 devuelve ACK (0xA5)");

        uart_send_byte(8'h24); // CMD_STATUS
        uart_recv_byte(status_byte);
        check_cond(status_byte === 8'h08, "STATUS indica prog_loaded=1 (0x08)");

        // ---------------------------------------------------------------------
        // TEST 3: Modo Paso a Paso (STEP = 0x11) hasta vaciar el pipeline
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 3] Modo Paso a Paso (STEP) e inspeccion de latches/drenaje ---");
        saw_load_use_bubble = 1'b0;
        saw_draining_flag   = 1'b0;

        // Paso 1: verificar que exactamente 1 ciclo mete la 1ra instrucción en IF/ID
        uart_send_byte(8'h11); // CMD_STEP
        uart_recv_byte(resp);
        check_cond(resp === 8'hA5, "STEP #1 devuelve ACK (0xA5)");

        uart_send_byte(8'h23); // CMD_DUMP_PC
        uart_recv_u32(pc_val);
        check_eq32(pc_val, 32'h00000004, "Tras STEP #1 PC avanza exactamente a 0x04");

        dump_all_latches();
        check_eq32(dumped_latches[0], 32'h00000000, "STEP #1 IF/ID.pc == 0x00");
        check_eq32(dumped_latches[2], 32'h01900093, "STEP #1 IF/ID.instr == addi x1, x0, 25");
        check_cond(dumped_latches[3][0] === 1'b1,   "STEP #1 IF/ID.valid == 1");
        check_cond(dumped_latches[9][28] === 1'b0,  "STEP #1 ID/EX.valid == 0");

        // Avanzar paso a paso hasta que STATUS marque halted=1 (pipeline drenado)
        for (step_num = 2; step_num <= 25; step_num = step_num + 1) begin
            uart_send_byte(8'h24); // CMD_STATUS
            uart_recv_byte(status_byte);
            if (!status_byte[1]) begin
                uart_send_byte(8'h11); // CMD_STEP
                uart_recv_byte(resp);
                if (resp !== 8'hA5) begin
                    $display("  [FAIL] STEP #%0d devolvio 0x%02h en vez de ACK", step_num, resp);
                    errors = errors + 1;
                end

                dump_all_latches();
                uart_send_byte(8'h24); // CMD_STATUS post-step
                uart_recv_byte(status_byte);

                // Detectar burbuja por Load-Use: IF/ID contiene add x5 (0x001202B3) e ID/EX queda inválido
                if ((dumped_latches[2] === 32'h001202B3) && (dumped_latches[9][28] === 1'b0) &&
                    (dumped_latches[13][13] === 1'b1)) begin
                    saw_load_use_bubble = 1'b1;
                end

                // Detectar bandera draining=1 (EBREAK detectado mientras aún drenan etapas posteriores)
                if (status_byte[2] === 1'b1) begin
                    saw_draining_flag = 1'b1;
                end
            end
        end

        check_cond(saw_load_use_bubble === 1'b1, "Se observo burbuja Load-Use en ID/EX durante STEP");
        check_cond(saw_draining_flag === 1'b1,   "Se observo estado draining=1 antes del vaciado total");
        check_cond(status_byte === 8'h0A,        "STATUS final en STEP = 0x0A (prog_loaded=1, halted=1, draining=0)");

        // Verificar que un STEP adicional sobre CPU ya detenido devuelve HALTED (0xF1)
        uart_send_byte(8'h11);
        uart_recv_byte(resp);
        check_cond(resp === 8'hF1, "STEP adicional tras vaciado devuelve HALTED (0xF1)");

        // Verificar que los 4 latches intermedios quedaron vacíos (valid == 0)
        dump_all_latches();
        check_cond(dumped_latches[3][0]   === 1'b0, "Fin STEP: IF/ID vacio (valid == 0)");
        check_cond(dumped_latches[9][28]  === 1'b0, "Fin STEP: ID/EX vacio (valid == 0)");
        check_cond(dumped_latches[13][13] === 1'b0, "Fin STEP: EX/MEM vacio (valid == 0)");
        check_cond(dumped_latches[17][8]  === 1'b0, "Fin STEP: MEM/WB vacio (valid == 0)");

        // Verificar los 32 registros del Programa #1
        dump_all_regs();
        check_eq32(dumped_regs[0],  32'h00000000, "Prog #1 Reg x0");
        check_eq32(dumped_regs[1],  32'h00000019, "Prog #1 Reg x1 (25)");
        check_eq32(dumped_regs[2],  32'hFFFFFFFB, "Prog #1 Reg x2 (-5)");
        check_eq32(dumped_regs[3],  32'h00000014, "Prog #1 Reg x3 (20)");
        check_eq32(dumped_regs[4],  32'h00000014, "Prog #1 Reg x4 (lw -> 20)");
        check_eq32(dumped_regs[5],  32'h0000002D, "Prog #1 Reg x5 (Load-Use -> 45)");
        check_eq32(dumped_regs[6],  32'h00000020, "Prog #1 Reg x6 (JAL link -> 0x20)");
        check_eq32(dumped_regs[30], 32'h00000000, "Prog #1 Reg x30 (flush JAL -> 0)");
        check_eq32(dumped_regs[31], 32'h00000000, "Prog #1 Reg x31 (flush post-EBREAK -> 0)");

        // Verificar memoria de datos por rango (DUMP_DMEM 0x22) y por palabras usadas (DUMP_DMEM_USED 0x25)
        uart_send_byte(8'h22); // CMD_DUMP_DMEM: offset=2, count=4 (palabras 2,3,4,5)
        uart_send_u16(16'd2);
        uart_send_u16(16'd4);
        uart_recv_u32(mem_word); check_eq32(mem_word, 32'h00000014, "Prog #1 DUMP_DMEM[2]");
        uart_recv_u32(mem_word); check_eq32(mem_word, 32'h00000000, "Prog #1 DUMP_DMEM[3]");
        uart_recv_u32(mem_word); check_eq32(mem_word, 32'h00000000, "Prog #1 DUMP_DMEM[4]");
        uart_recv_u32(mem_word); check_eq32(mem_word, 32'h0000FB00, "Prog #1 DUMP_DMEM[5] (sb offset 1)");

        uart_send_byte(8'h25); // CMD_DUMP_DMEM_USED
        uart_recv_u16(used_cnt);
        check_cond(used_cnt === 16'd2, "Prog #1 DUMP_DMEM_USED reporta exactamente 2 palabras usadas");
        uart_recv_u16(used_addr0); uart_recv_u32(used_data0);
        uart_recv_u16(used_addr1); uart_recv_u32(used_data1);
        check_cond((used_addr0 === 16'd2) && (used_data0 === 32'h00000014), "Prog #1 DUMP_DMEM_USED entrada 0 (addr=2, data=0x14)");
        check_cond((used_addr1 === 16'd5) && (used_data1 === 32'h0000FB00), "Prog #1 DUMP_DMEM_USED entrada 1 (addr=5, data=0xFB00)");

        // ---------------------------------------------------------------------
        // TEST 4: Reprogramación Dinámica + Modo Continuo (RUN = 0x10)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 4] Reprogramacion dinamica con Programa #2 (6 instr) y Modo Continuo (RUN) ---");
        uart_send_byte(8'h02);    // CMD_LOAD_PROG (sin reset físico!)
        uart_send_u16(16'd6);     // N = 6 instrucciones (menor que las 11 del Prog #1)
        uart_send_u32(32'hABCDE537); // 0x00: lui  x10, 0xABCDE      -> x10 = 0xABCDE000
        uart_send_u32(32'h12356513); // 0x04: ori  x10, x10, 0x123   -> x10 = 0xABCDE123
        uart_send_u32(32'h02A02423); // 0x08: sw   x10, 40(x0)       -> dmem[10] = 0xABCDE123
        uart_send_u32(32'h02A01583); // 0x0C: lh   x11, 42(x0)       -> x11 = 0xFFFFABCD
        uart_send_u32(32'h02A05603); // 0x10: lhu  x12, 42(x0)       -> x12 = 0x0000ABCD (drena tras EBREAK!)
        uart_send_u32(32'h00100073); // 0x14: ebreak                 -> HALT

        uart_recv_byte(resp);
        check_cond(resp === 8'hA5, "LOAD_PROG #2 dinamico devuelve ACK (0xA5)");

        // Verificar que la reprogramación limpió registros y memoria de datos del Programa #1
        dump_all_regs();
        check_eq32(dumped_regs[1], 32'h00000000, "Post-reprogramacion: x1 limpio en 0");
        check_eq32(dumped_regs[5], 32'h00000000, "Post-reprogramacion: x5 limpio en 0");

        uart_send_byte(8'h25); // CMD_DUMP_DMEM_USED
        uart_recv_u16(used_cnt);
        check_cond(used_cnt === 16'd0, "Post-reprogramacion: DUMP_DMEM_USED limpio (0 palabras usadas)");

        // Ejecutar en Modo Continuo (CMD_RUN = 0x10)
        uart_send_byte(8'h10);
        uart_recv_byte(resp);
        check_cond(resp === 8'hA5, "CMD_RUN devuelve ACK inmediato (0xA5)");

        uart_recv_byte(resp);
        check_cond(resp === 8'hF1, "CMD_RUN envia evento HALTED (0xF1) al vaciar el pipeline");

        // Verificar que el pipeline quedó completamente vacío tras RUN
        dump_all_latches();
        check_cond(dumped_latches[3][0]   === 1'b0, "Fin RUN: IF/ID vacio (valid == 0)");
        check_cond(dumped_latches[9][28]  === 1'b0, "Fin RUN: ID/EX vacio (valid == 0)");
        check_cond(dumped_latches[13][13] === 1'b0, "Fin RUN: EX/MEM vacio (valid == 0)");
        check_cond(dumped_latches[17][8]  === 1'b0, "Fin RUN: MEM/WB vacio (valid == 0)");

        // Verificar los 32 registros tras RUN (incluyendo x12 escrito durante el drenaje del pipeline!)
        dump_all_regs();
        for (k = 0; k < 32; k = k + 1) begin
            if (k == 10)      check_eq32(dumped_regs[k], 32'hABCDE123, "Prog #2 Reg x10 (lui+ori)");
            else if (k == 11) check_eq32(dumped_regs[k], 32'hFFFFABCD, "Prog #2 Reg x11 (lh con signo)");
            else if (k == 12) check_eq32(dumped_regs[k], 32'h0000ABCD, "Prog #2 Reg x12 (lhu drenado pre-EBREAK)");
            else if (dumped_regs[k] !== 32'h00000000) begin
                $display("  [FAIL] Prog #2 Reg x%0d debia ser 0 y vale 0x%08h", k, dumped_regs[k]);
                errors = errors + 1;
            end
        end
        $display("  [OK]   Verificados los 32 registros completos en Modo Continuo");

        // Verificar memoria de datos usada en Programa #2
        uart_send_byte(8'h25); // CMD_DUMP_DMEM_USED
        uart_recv_u16(used_cnt);
        check_cond(used_cnt === 16'd1, "Prog #2 DUMP_DMEM_USED reporta exactamente 1 palabra usada");
        uart_recv_u16(used_addr0); uart_recv_u32(used_data0);
        check_cond((used_addr0 === 16'd10) && (used_data0 === 32'hABCDE123),
                   "Prog #2 DUMP_DMEM_USED entrada 0 (addr=10, data=0xABCDE123)");

        // Resumen final
        $display("\n============================================================================");
        $display("  RESULTADO FINAL: %0d error(es)", errors);
        if (errors == 0) begin
            $display("  TEST PASSED");
        end else begin
            $display("  TEST FAILED");
        end
        $display("============================================================================");

        if (errors != 0) $fatal(1);
        $finish;
    end

    // Watchdog de seguridad
    initial begin
        #50_000_000;
        $display("TEST FAILED (Watchdog Timeout)");
        $fatal(1);
    end

endmodule
`default_nettype wire
