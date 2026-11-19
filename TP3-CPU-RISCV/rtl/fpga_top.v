`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo Top-Level Sintetizable para FPGA: fpga_top
// Descripción:
//   Integra el procesador RISC-V segmentado de 5 etapas (`riscv_core`) con la
//   Unidad de Depuración y Programación por UART (`debug_unit`).
//
//   Análisis de Camino Crítico y Frecuencia Óptima (Vivado Timing Signoff):
//   - A 100 MHz (T = 10.000 ns), el reporte de Timing arroja WNS = -0.356 ns
//     (Total Delay = 10.393 ns, 21 niveles lógicos) en el camino crítico que
//     nace en el latch IF/ID (`u_if_id/o_instruction_reg[5]`), atraviesa la
//     decodificación, forwarding y resolución anticipada de saltos en la etapa ID
//     y termina en la entrada del Program Counter (`u_pc/pc_reg[30]/D`).
//   - Período mínimo real: T_min = 10.000 ns - (-0.356 ns) = 10.356 ns
//     -> Frecuencia máxima teórica: F_max = 1000 / 10.356 ns = 96.56 MHz.
//   - Mediante el primitivo dedicado `MMCME2_BASE` + `BUFG` se sintetiza una
//     frecuencia óptima de operación de 90.0 MHz (T = 11.111 ns, VCO = 900 MHz
//     con M = 9, D = 10), logrando un Slack positivo (WNS ≈ +0.75 ns) sin
//     Clock Skew gracias al árbol global dedicado `BUFG`.
//   - Para 90 MHz y 115200 baudios: DVSR = 90_000_000 / (16 * 115200) = 48.83 -> 49
//     (error de baudios de apenas 0.35%).
//==============================================================================

module fpga_top #(
    parameter integer CLK_FREQ_HZ     = 90_000_000,
    parameter integer BAUD_RATE       = 115_200,
    parameter integer SB_TICK         = 16,
    parameter integer DVSR            = 49,   // 90 MHz / (16 * 115200) = 48.83 -> 49 (error 0.35%)
    parameter integer IMEM_ADDR_WIDTH = 10,   // 1024 palabras (4 KB IMEM)
    parameter integer DMEM_ADDR_WIDTH = 8     // 256 palabras (1 KB DMEM)
)(
    input  wire        clk_100MHz,
    input  wire        btnC,
    input  wire        i_uart_rx,
    output wire        o_uart_tx,
    output wire [15:0] o_led
);

    // =========================================================================
    // 1. Síntesis de Frecuencia Óptima (90 MHz) con MMCM + Red Global BUFG
    // =========================================================================
    wire mmcm_clkfb;
    wire mmcm_clkfb_buf;
    wire mmcm_clkout0;
    wire sys_clk;
    wire mmcm_locked;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (9.000),    // VCO = 100 MHz * 9 = 900 MHz (rango Artix-7: 600..1200 MHz)
        .CLKFBOUT_PHASE     (0.000),
        .CLKIN1_PERIOD      (10.000),   // Entrada: 100 MHz (10.0 ns)
        .CLKOUT0_DIVIDE_F   (10.000),   // Salida : 900 MHz / 10 = 90.0 MHz (11.111 ns)
        .CLKOUT0_DUTY_CYCLE (0.500),
        .CLKOUT0_PHASE      (0.000),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm_sys_clk (
        .CLKOUT0            (mmcm_clkout0),
        .CLKOUT0B           (),
        .CLKOUT1            (),
        .CLKOUT1B           (),
        .CLKOUT2            (),
        .CLKOUT2B           (),
        .CLKOUT3            (),
        .CLKOUT3B           (),
        .CLKOUT4            (),
        .CLKOUT5            (),
        .CLKOUT6            (),
        .CLKFBOUT           (mmcm_clkfb),
        .CLKFBOUTB          (),
        .LOCKED             (mmcm_locked),
        .CLKIN1             (clk_100MHz),
        .PWRDWN             (1'b0),
        .RST                (1'b0),
        .CLKFBIN            (mmcm_clkfb_buf)
    );

    // Buffers globales dedicados (BUFG) para minimizar el Clock Skew en toda la FPGA
    BUFG u_bufg_clkfb (
        .I (mmcm_clkfb),
        .O (mmcm_clkfb_buf)
    );

    BUFG u_bufg_sysclk (
        .I (mmcm_clkout0),
        .O (sys_clk)
    );

    // =========================================================================
    // 2. Sincronizador de Reset (activo mientras se presiona btnC o el MMCM no enganchó)
    // =========================================================================
    reg [1:0] rst_sync_r = 2'b11;
    always @(posedge sys_clk) begin
        rst_sync_r <= {rst_sync_r[0], (btnC | ~mmcm_locked)};
    end
    wire sys_rst = rst_sync_r[1];

    // =========================================================================
    // 3. Señales de Interconexión entre Debug Unit y Procesador RISC-V
    // =========================================================================
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

    // =========================================================================
    // 4. Instancia del Procesador RISC-V de 5 Etapas (RV32I)
    // =========================================================================
    riscv_core #(
        .NB_PC          (32),
        .DATA_WIDTH     (32),
        .IMEM_ADDR_WIDTH(IMEM_ADDR_WIDTH),
        .DMEM_ADDR_WIDTH(DMEM_ADDR_WIDTH)
    ) u_riscv_core (
        .i_clk              (sys_clk),
        .i_rst              (sys_rst | dbg_core_rst),
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

    // =========================================================================
    // 5. Instancia de la Debug Unit (Esclavo UART 115200 8N1)
    // =========================================================================
    debug_unit #(
        .CLK_FREQ_HZ    (CLK_FREQ_HZ),
        .BAUD_RATE      (BAUD_RATE),
        .SB_TICK        (SB_TICK),
        .DVSR           (DVSR),
        .IMEM_ADDR_WIDTH(IMEM_ADDR_WIDTH),
        .DMEM_ADDR_WIDTH(DMEM_ADDR_WIDTH)
    ) u_debug_unit (
        .i_clk              (sys_clk),
        .i_rst              (sys_rst),
        .i_uart_rx          (i_uart_rx),
        .o_uart_tx          (o_uart_tx),
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
    // 6. Asignación de LEDs de Diagnóstico en Placa
    // =========================================================================
    wire if_id_valid  = debug_if_id[96];
    wire id_ex_valid  = debug_id_ex[188];
    wire ex_mem_valid = debug_ex_mem[109];
    wire mem_wb_valid = debug_mem_wb[104];

    assign o_led[7:0]  = debug_pc[9:2];   // Índice de palabra del PC actual (0..255)
    assign o_led[8]    = if_id_valid;     // Etapa IF/ID ocupada
    assign o_led[9]    = id_ex_valid;     // Etapa ID/EX ocupada
    assign o_led[10]   = ex_mem_valid;    // Etapa EX/MEM ocupada
    assign o_led[11]   = mem_wb_valid;    // Etapa MEM/WB ocupada
    assign o_led[12]   = dbg_prog_loaded; // Programa cargado por UART
    assign o_led[13]   = dbg_running;     // Ejecución continua activa
    assign o_led[14]   = core_draining;   // Vaciando pipeline tras EBREAK
    assign o_led[15]   = core_exec_done;  // Fin de programa (HALTED + pipeline vacío)

endmodule
`default_nettype wire
