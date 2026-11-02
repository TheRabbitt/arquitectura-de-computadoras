`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: debug_unit
// Descripción:
//   Unidad de Depuración y Programación por UART para el procesador RISC-V.
//   Adapta e instancia internamente el subsistema UART (uart_top ->
//   baud_rate_generator + uart_rx + uart_tx) e implementa la máquina de
//   estados del protocolo binario Little-Endian (115200 8N1).
//
// Comandos soportados (PC -> FPGA):
//   0x01 RESET          : Detiene ejecución, resetea registros/latches/PC y limpia DMEM -> ACK (0xA5)
//   0x02 LOAD_PROG      : 2B N + N*4B instrucciones -> programa IMEM, limpia estado -> ACK (0xA5)
//   0x10 RUN            : Modo continuo -> envía ACK (0xA5) y al vaciar pipeline tras EBREAK envía HALTED (0xF1)
//   0x11 STEP           : Modo paso a paso -> avanza 1 ciclo de clock mediante enable -> ACK (0xA5) o HALTED (0xF1)
//   0x20 DUMP_REGS      : Envía los 32 registros (x0..x31) -> 128 B
//   0x21 DUMP_LATCHES   : Envía IF/ID (16B) + ID/EX (24B) + EX/MEM (16B) + MEM/WB (16B) -> 72 B
//   0x22 DUMP_DMEM      : 2B offset + 2B cantidad -> envía cantidad*4 B de memoria de datos
//   0x23 DUMP_PC        : Envía el PC actual -> 4 B
//   0x24 STATUS         : Envía 1 B de estado {4'b0, prog_loaded, draining, halted, running}
//   0x25 DUMP_DMEM_USED : Envía solo la memoria de datos usada: 2B K + K*(2B word_addr + 4B data)
//==============================================================================

module debug_unit #(
    parameter integer CLK_FREQ_HZ     = 100_000_000,
    parameter integer BAUD_RATE       = 115_200,
    parameter integer SB_TICK         = 16,
    parameter integer DVSR            = (CLK_FREQ_HZ + ((BAUD_RATE * SB_TICK) / 2)) / (BAUD_RATE * SB_TICK),
    parameter integer IMEM_ADDR_WIDTH = 10, // 1024 palabras
    parameter integer DMEM_ADDR_WIDTH = 8   // 256 palabras
)(
    input  wire                             i_clk,
    input  wire                             i_rst,

    // Interfaz física UART
    input  wire                             i_uart_rx,
    output wire                             o_uart_tx,

    // Control de ejecución hacia riscv_core (sin intervenir i_clk)
    output reg                              o_core_rst,
    output wire                             o_core_en,
    input  wire                             i_halted,
    input  wire                             i_pipeline_empty,
    input  wire                             i_exec_done,
    input  wire                             i_draining,

    // Puerto de programación de InstructionMemory
    output reg                              o_imem_we,
    output reg  [IMEM_ADDR_WIDTH-1:0]       o_imem_waddr,
    output reg  [31:0]                      o_imem_wdata,

    // Puerto de lectura del Register File (32 registros)
    output reg                              o_rf_debug_re,
    output reg  [4:0]                       o_rf_debug_addr,
    input  wire [31:0]                      i_rf_debug_rdata,

    // Puerto de limpieza y lectura de Data Memory
    output reg                              o_dmem_clear_we,
    output reg  [DMEM_ADDR_WIDTH-1:0]       o_dmem_clear_addr,
    output reg                              o_dmem_debug_re,
    output reg  [DMEM_ADDR_WIDTH-1:0]       o_dmem_debug_addr,
    input  wire [31:0]                      i_dmem_debug_rdata,
    input  wire [(1<<DMEM_ADDR_WIDTH)-1:0]  i_dmem_used_mask,

    // Entradas de depuración de PC y Latches intermedios
    input  wire [31:0]                      i_debug_pc,
    input  wire [127:0]                     i_debug_if_id,
    input  wire [191:0]                     i_debug_id_ex,
    input  wire [127:0]                     i_debug_ex_mem,
    input  wire [127:0]                     i_debug_mem_wb,

    // Señales indicadoras de estado (útiles para LEDs / monitoreo)
    output wire                             o_running,
    output wire                             o_prog_loaded
);

    localparam integer IMEM_DEPTH = (1 << IMEM_ADDR_WIDTH);
    localparam integer DMEM_DEPTH = (1 << DMEM_ADDR_WIDTH);

    // Códigos de comando (PC -> FPGA)
    localparam [7:0]
        CMD_RESET          = 8'h01,
        CMD_LOAD_PROG      = 8'h02,
        CMD_RUN            = 8'h10,
        CMD_STEP           = 8'h11,
        CMD_DUMP_REGS      = 8'h20,
        CMD_DUMP_LATCHES   = 8'h21,
        CMD_DUMP_DMEM      = 8'h22,
        CMD_DUMP_PC        = 8'h23,
        CMD_STATUS         = 8'h24,
        CMD_DUMP_DMEM_USED = 8'h25;

    // Códigos de respuesta / eventos (FPGA -> PC)
    localparam [7:0]
        RESP_ACK    = 8'hA5,
        RESP_NAK    = 8'h5A,
        RESP_HALTED = 8'hF1;

    // Modos del serializador de palabras de 32 bits
    localparam [2:0]
        MODE_PC        = 3'd0,
        MODE_LATCHES   = 3'd1,
        MODE_REGS      = 3'd2,
        MODE_DMEM      = 3'd3,
        MODE_DMEM_USED = 3'd4;

    // Estados de la FSM principal
    localparam [4:0]
        S_IDLE              = 5'd0,
        S_TX_SINGLE_WAIT    = 5'd1,
        S_CLEAR_DMEM        = 5'd2,
        S_POST_RESET_WAIT   = 5'd3,
        S_LOAD_CNT_L        = 5'd4,
        S_LOAD_CNT_H        = 5'd5,
        S_LOAD_RX_WORD      = 5'd6,
        S_LOAD_FINISH_WRITE = 5'd7,
        S_STEP_EXEC         = 5'd8,
        S_STEP_SETTLE       = 5'd9,
        S_RUN_SETTLE        = 5'd10,
        S_LATCH_LOAD        = 5'd11,
        S_READ_WAIT         = 5'd12,
        S_READ_CAP          = 5'd13,
        S_TX_WORD_WAIT      = 5'd14,
        S_DMEM_OFF_L        = 5'd15,
        S_DMEM_OFF_H        = 5'd16,
        S_DMEM_CNT_L        = 5'd17,
        S_DMEM_CNT_H        = 5'd18,
        S_USED_COUNT        = 5'd19,
        S_USED_CNT_L_WAIT   = 5'd20,
        S_USED_CNT_H_WAIT   = 5'd21,
        S_USED_SCAN         = 5'd22,
        S_USED_ADDR_L_WAIT  = 5'd23,
        S_USED_ADDR_H_WAIT  = 5'd24;

    // =========================================================================
    // Subsistema UART
    // =========================================================================
    wire       w_rx_done_tick;
    wire [7:0] w_rx_data;
    reg        r_tx_start;
    reg  [7:0] r_tx_data;
    wire       w_tx_done_tick;

    uart_top #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .DBIT       (8),
        .SB_TICK    (SB_TICK),
        .DVSR       (DVSR)
    ) u_uart (
        .i_clk          (i_clk),
        .i_rst          (i_rst),
        .i_rx           (i_uart_rx),
        .o_tx           (o_uart_tx),
        .o_rx_done_tick (w_rx_done_tick),
        .o_rx_data      (w_rx_data),
        .i_tx_start     (r_tx_start),
        .i_tx_data      (r_tx_data),
        .o_tx_done_tick (w_tx_done_tick)
    );

    // =========================================================================
    // Registros Internos de Control y Serialización
    // =========================================================================
    reg [4:0]  r_state;
    reg        r_running;
    reg        r_step_pulse;
    reg        r_prog_loaded;
    reg        r_discard_mode;

    reg [2:0]  r_dump_mode;
    reg [1:0]  r_byte_cnt;
    reg [15:0] r_word_idx;
    reg [15:0] r_words_rem;
    reg [7:0]  r_cnt_low;
    reg [15:0] r_dmem_offset;
    reg [23:0] r_rx_word_low;
    reg [31:0] r_tx_word;
    reg [31:0] r_saved_dmem_word;

    reg [15:0] r_scan_idx;
    reg [15:0] r_used_cnt;

    // Habilitación del procesador (sin tocar el clock):
    // En modo continuo corre hasta que i_exec_done (HALT + pipeline vacío) se activa.
    // En modo paso a paso ejecuta exactamente 1 ciclo de clock con r_step_pulse.
    assign o_core_en     = (r_running & ~i_exec_done) | r_step_pulse;
    assign o_running     = r_running;
    assign o_prog_loaded = r_prog_loaded;

    // =========================================================================
    // Selector de Palabras de 32 bits para DUMP_LATCHES (18 palabras = 72 bytes)
    // Orden: IF/ID (4) -> ID/EX (6) -> EX/MEM (4) -> MEM/WB (4)
    // =========================================================================
    reg [31:0] w_latch_word;
    always @(*) begin
        case (r_word_idx[4:0])
            // IF/ID (16 bytes)
            5'd0:  w_latch_word = i_debug_if_id[31:0];
            5'd1:  w_latch_word = i_debug_if_id[63:32];
            5'd2:  w_latch_word = i_debug_if_id[95:64];
            5'd3:  w_latch_word = i_debug_if_id[127:96];
            // ID/EX (24 bytes)
            5'd4:  w_latch_word = i_debug_id_ex[31:0];
            5'd5:  w_latch_word = i_debug_id_ex[63:32];
            5'd6:  w_latch_word = i_debug_id_ex[95:64];
            5'd7:  w_latch_word = i_debug_id_ex[127:96];
            5'd8:  w_latch_word = i_debug_id_ex[159:128];
            5'd9:  w_latch_word = i_debug_id_ex[191:160];
            // EX/MEM (16 bytes)
            5'd10: w_latch_word = i_debug_ex_mem[31:0];
            5'd11: w_latch_word = i_debug_ex_mem[63:32];
            5'd12: w_latch_word = i_debug_ex_mem[95:64];
            5'd13: w_latch_word = i_debug_ex_mem[127:96];
            // MEM/WB (16 bytes)
            5'd14: w_latch_word = i_debug_mem_wb[31:0];
            5'd15: w_latch_word = i_debug_mem_wb[63:32];
            5'd16: w_latch_word = i_debug_mem_wb[95:64];
            5'd17: w_latch_word = i_debug_mem_wb[127:96];
            default: w_latch_word = 32'd0;
        endcase
    end

    wire [15:0] w_req_len     = {w_rx_data, r_cnt_low};
    wire [15:0] w_used_inc    = r_used_cnt + (i_dmem_used_mask[r_scan_idx[DMEM_ADDR_WIDTH-1:0]] ? 16'd1 : 16'd0);

    // =========================================================================
    // Máquina de Estados Principal de la Debug Unit
    // =========================================================================
    always @(posedge i_clk) begin
        if (i_rst) begin
            r_state           <= S_IDLE;
            r_running         <= 1'b0;
            r_step_pulse      <= 1'b0;
            r_prog_loaded     <= 1'b0;
            r_discard_mode    <= 1'b0;
            r_dump_mode       <= MODE_PC;
            r_byte_cnt        <= 2'd0;
            r_word_idx        <= 16'd0;
            r_words_rem       <= 16'd0;
            r_cnt_low         <= 8'd0;
            r_dmem_offset     <= 16'd0;
            r_rx_word_low     <= 24'd0;
            r_tx_word         <= 32'd0;
            r_saved_dmem_word <= 32'd0;
            r_scan_idx        <= 16'd0;
            r_used_cnt        <= 16'd0;

            r_tx_start        <= 1'b0;
            r_tx_data         <= 8'd0;

            o_core_rst        <= 1'b0;
            o_imem_we         <= 1'b0;
            o_imem_waddr      <= {IMEM_ADDR_WIDTH{1'b0}};
            o_imem_wdata      <= 32'd0;
            o_rf_debug_re     <= 1'b0;
            o_rf_debug_addr   <= 5'd0;
            o_dmem_clear_we   <= 1'b0;
            o_dmem_clear_addr <= {DMEM_ADDR_WIDTH{1'b0}};
            o_dmem_debug_re   <= 1'b0;
            o_dmem_debug_addr <= {DMEM_ADDR_WIDTH{1'b0}};
        end else begin
            // Pulsos por defecto en 0
            r_tx_start <= 1'b0;
            o_imem_we  <= 1'b0;

            case (r_state)
                // -------------------------------------------------------------
                // IDLE: Espera comandos de la PC o fin de ejecución continua
                // -------------------------------------------------------------
                S_IDLE: begin
                    r_step_pulse    <= 1'b0;
                    o_rf_debug_re   <= 1'b0;
                    o_dmem_debug_re <= 1'b0;
                    o_dmem_clear_we <= 1'b0;
                    o_core_rst      <= 1'b0;

                    if (w_rx_done_tick) begin
                        case (w_rx_data)
                            CMD_RESET: begin
                                r_running         <= 1'b0;
                                o_core_rst        <= 1'b1;
                                o_dmem_clear_we   <= 1'b1;
                                o_dmem_clear_addr <= {DMEM_ADDR_WIDTH{1'b0}};
                                r_state           <= S_CLEAR_DMEM;
                            end

                            CMD_LOAD_PROG: begin
                                r_state <= S_LOAD_CNT_L;
                            end

                            CMD_RUN: begin
                                if (r_running || i_exec_done) begin
                                    r_tx_data  <= RESP_NAK;
                                    r_tx_start <= 1'b1;
                                    r_state    <= S_TX_SINGLE_WAIT;
                                end else begin
                                    r_running  <= 1'b1;
                                    r_tx_data  <= RESP_ACK;
                                    r_tx_start <= 1'b1;
                                    r_state    <= S_TX_SINGLE_WAIT;
                                end
                            end

                            CMD_STEP: begin
                                if (r_running) begin
                                    r_tx_data  <= RESP_NAK;
                                    r_tx_start <= 1'b1;
                                    r_state    <= S_TX_SINGLE_WAIT;
                                end else if (i_exec_done) begin
                                    r_tx_data  <= RESP_HALTED;
                                    r_tx_start <= 1'b1;
                                    r_state    <= S_TX_SINGLE_WAIT;
                                end else begin
                                    r_step_pulse <= 1'b1;
                                    r_state      <= S_STEP_EXEC;
                                end
                            end

                            CMD_DUMP_REGS: begin
                                if (r_running) begin
                                    r_tx_data  <= RESP_NAK;
                                    r_tx_start <= 1'b1;
                                    r_state    <= S_TX_SINGLE_WAIT;
                                end else begin
                                    r_dump_mode     <= MODE_REGS;
                                    r_word_idx      <= 16'd0;
                                    r_words_rem     <= 16'd32;
                                    o_rf_debug_re   <= 1'b1;
                                    o_rf_debug_addr <= 5'd0;
                                    r_state         <= S_READ_WAIT;
                                end
                            end

                            CMD_DUMP_LATCHES: begin
                                if (r_running) begin
                                    r_tx_data  <= RESP_NAK;
                                    r_tx_start <= 1'b1;
                                    r_state    <= S_TX_SINGLE_WAIT;
                                end else begin
                                    r_dump_mode <= MODE_LATCHES;
                                    r_word_idx  <= 16'd0;
                                    r_words_rem <= 16'd18;
                                    r_state     <= S_LATCH_LOAD;
                                end
                            end

                            CMD_DUMP_DMEM: begin
                                r_state <= S_DMEM_OFF_L;
                            end

                            CMD_DUMP_PC: begin
                                if (r_running) begin
                                    r_tx_data  <= RESP_NAK;
                                    r_tx_start <= 1'b1;
                                    r_state    <= S_TX_SINGLE_WAIT;
                                end else begin
                                    r_dump_mode <= MODE_PC;
                                    r_words_rem <= 16'd1;
                                    r_tx_data   <= i_debug_pc[7:0];
                                    r_tx_word   <= {8'd0, i_debug_pc[31:8]};
                                    r_byte_cnt  <= 2'd0;
                                    r_tx_start  <= 1'b1;
                                    r_state     <= S_TX_WORD_WAIT;
                                end
                            end

                            CMD_STATUS: begin
                                r_tx_data  <= {4'b0000, r_prog_loaded, i_draining, i_exec_done, r_running};
                                r_tx_start <= 1'b1;
                                r_state    <= S_TX_SINGLE_WAIT;
                            end

                            CMD_DUMP_DMEM_USED: begin
                                if (r_running) begin
                                    r_tx_data  <= RESP_NAK;
                                    r_tx_start <= 1'b1;
                                    r_state    <= S_TX_SINGLE_WAIT;
                                end else begin
                                    r_scan_idx <= 16'd0;
                                    r_used_cnt <= 16'd0;
                                    r_state    <= S_USED_COUNT;
                                end
                            end

                            default: begin
                                r_tx_data  <= RESP_NAK;
                                r_tx_start <= 1'b1;
                                r_state    <= S_TX_SINGLE_WAIT;
                            end
                        endcase
                    end else if (r_running && i_exec_done) begin
                        // El modo continuo alcanzó EBREAK y vació por completo el pipeline
                        r_state <= S_RUN_SETTLE;
                    end
                end

                // -------------------------------------------------------------
                // Espera fin de transmisión de 1 byte simple (ACK/NAK/HALTED/STATUS)
                // -------------------------------------------------------------
                S_TX_SINGLE_WAIT: begin
                    if (w_tx_done_tick) begin
                        r_state <= S_IDLE;
                    end
                end

                // -------------------------------------------------------------
                // Borrado sincrónico de Data Memory (256 palabras) + Reset de Core
                // -------------------------------------------------------------
                S_CLEAR_DMEM: begin
                    if (o_dmem_clear_addr == {DMEM_ADDR_WIDTH{1'b1}}) begin
                        o_dmem_clear_we <= 1'b0;
                        o_core_rst      <= 1'b0;
                        r_state         <= S_POST_RESET_WAIT;
                    end else begin
                        o_dmem_clear_addr <= o_dmem_clear_addr + {{(DMEM_ADDR_WIDTH-1){1'b0}}, 1'b1};
                    end
                end

                // Permite que InstructionMemory resuelva en negedge la instrucción mem[0] con PC=0
                S_POST_RESET_WAIT: begin
                    r_tx_data  <= RESP_ACK;
                    r_tx_start <= 1'b1;
                    r_state    <= S_TX_SINGLE_WAIT;
                end

                // -------------------------------------------------------------
                // Carga dinámica de programa por UART (CMD_LOAD_PROG = 0x02)
                // -------------------------------------------------------------
                S_LOAD_CNT_L: begin
                    if (w_rx_done_tick) begin
                        r_cnt_low <= w_rx_data;
                        r_state   <= S_LOAD_CNT_H;
                    end
                end

                S_LOAD_CNT_H: begin
                    if (w_rx_done_tick) begin
                        if (w_req_len == 16'd0) begin
                            r_tx_data  <= RESP_NAK;
                            r_tx_start <= 1'b1;
                            r_state    <= S_TX_SINGLE_WAIT;
                        end else if (r_running || (w_req_len > IMEM_DEPTH)) begin
                            r_discard_mode <= 1'b1;
                            r_words_rem    <= w_req_len;
                            r_byte_cnt     <= 2'd0;
                            r_state        <= S_LOAD_RX_WORD;
                        end else begin
                            r_discard_mode <= 1'b0;
                            o_core_rst     <= 1'b1;
                            r_words_rem    <= w_req_len;
                            r_word_idx     <= 16'd0;
                            r_byte_cnt     <= 2'd0;
                            r_state        <= S_LOAD_RX_WORD;
                        end
                    end
                end

                S_LOAD_RX_WORD: begin
                    if (w_rx_done_tick) begin
                        case (r_byte_cnt)
                            2'd0: begin
                                r_rx_word_low[7:0] <= w_rx_data;
                                r_byte_cnt         <= 2'd1;
                            end
                            2'd1: begin
                                r_rx_word_low[15:8] <= w_rx_data;
                                r_byte_cnt          <= 2'd2;
                            end
                            2'd2: begin
                                r_rx_word_low[23:16] <= w_rx_data;
                                r_byte_cnt           <= 2'd3;
                            end
                            2'd3: begin
                                r_byte_cnt <= 2'd0;
                                if (!r_discard_mode) begin
                                    o_imem_we    <= 1'b1;
                                    o_imem_waddr <= r_word_idx[IMEM_ADDR_WIDTH-1:0];
                                    o_imem_wdata <= {w_rx_data, r_rx_word_low};
                                end
                                r_word_idx <= r_word_idx + 16'd1;

                                if (r_words_rem == 16'd1) begin
                                    if (r_discard_mode) begin
                                        r_discard_mode <= 1'b0;
                                        r_tx_data      <= RESP_NAK;
                                        r_tx_start     <= 1'b1;
                                        r_state        <= S_TX_SINGLE_WAIT;
                                    end else begin
                                        r_state <= S_LOAD_FINISH_WRITE;
                                    end
                                end else begin
                                    r_words_rem <= r_words_rem - 16'd1;
                                end
                            end
                        endcase
                    end
                end

                S_LOAD_FINISH_WRITE: begin
                    // Finalizada la escritura en IMEM: limpiamos DMEM, registros y pipeline
                    r_prog_loaded     <= 1'b1;
                    o_core_rst        <= 1'b1;
                    o_dmem_clear_we   <= 1'b1;
                    o_dmem_clear_addr <= {DMEM_ADDR_WIDTH{1'b0}};
                    r_state           <= S_CLEAR_DMEM;
                end

                // -------------------------------------------------------------
                // Ejecución Paso a Paso (1 ciclo exacto de clock) y fin de RUN
                // -------------------------------------------------------------
                S_STEP_EXEC: begin
                    // El posedge actual acaba de avanzar exactamente 1 ciclo de clock del core
                    r_step_pulse <= 1'b0;
                    r_state      <= S_STEP_SETTLE;
                end

                S_STEP_SETTLE: begin
                    // En el negedge intermedio ya se actualizaron IMEM, DMEM y used_mask
                    r_tx_data  <= RESP_ACK;
                    r_tx_start <= 1'b1;
                    r_state    <= S_TX_SINGLE_WAIT;
                end

                S_RUN_SETTLE: begin
                    r_running  <= 1'b0;
                    r_tx_data  <= RESP_HALTED;
                    r_tx_start <= 1'b1;
                    r_state    <= S_TX_SINGLE_WAIT;
                end

                // -------------------------------------------------------------
                // Carga y Serialización de Palabras de 32 bits (Latches / Regs / DMEM)
                // -------------------------------------------------------------
                S_LATCH_LOAD: begin
                    r_tx_data  <= w_latch_word[7:0];
                    r_tx_word  <= {8'd0, w_latch_word[31:8]};
                    r_byte_cnt <= 2'd0;
                    r_tx_start <= 1'b1;
                    r_state    <= S_TX_WORD_WAIT;
                end

                S_READ_WAIT: begin
                    // Espera 1 ciclo completo para lectura sincrónica de RegisterFile (posedge)
                    // y DataMemory (negedge manteniendo re=1 hasta capturar).
                    r_state <= S_READ_CAP;
                end

                S_READ_CAP: begin
                    o_rf_debug_re   <= 1'b0;
                    o_dmem_debug_re <= 1'b0;

                    if (r_dump_mode == MODE_REGS) begin
                        r_tx_data  <= i_rf_debug_rdata[7:0];
                        r_tx_word  <= {8'd0, i_rf_debug_rdata[31:8]};
                        r_byte_cnt <= 2'd0;
                        r_tx_start <= 1'b1;
                        r_state    <= S_TX_WORD_WAIT;
                    end else if (r_dump_mode == MODE_DMEM) begin
                        r_tx_data  <= i_dmem_debug_rdata[7:0];
                        r_tx_word  <= {8'd0, i_dmem_debug_rdata[31:8]};
                        r_byte_cnt <= 2'd0;
                        r_tx_start <= 1'b1;
                        r_state    <= S_TX_WORD_WAIT;
                    end else begin
                        // MODE_DMEM_USED: primero envía 2B dirección (LE) y luego 4B dato (LE)
                        r_saved_dmem_word <= i_dmem_debug_rdata;
                        r_tx_data         <= r_scan_idx[7:0];
                        r_tx_start        <= 1'b1;
                        r_state           <= S_USED_ADDR_L_WAIT;
                    end
                end

                S_TX_WORD_WAIT: begin
                    if (w_tx_done_tick) begin
                        if (r_byte_cnt < 2'd3) begin
                            r_tx_data  <= r_tx_word[7:0];
                            r_tx_word  <= {8'd0, r_tx_word[31:8]};
                            r_byte_cnt <= r_byte_cnt + 2'd1;
                            r_tx_start <= 1'b1;
                        end else begin
                            case (r_dump_mode)
                                MODE_PC: begin
                                    r_state <= S_IDLE;
                                end

                                MODE_LATCHES: begin
                                    if (r_words_rem == 16'd1) begin
                                        r_state <= S_IDLE;
                                    end else begin
                                        r_words_rem <= r_words_rem - 16'd1;
                                        r_word_idx  <= r_word_idx + 16'd1;
                                        r_state     <= S_LATCH_LOAD;
                                    end
                                end

                                MODE_REGS: begin
                                    if (r_words_rem == 16'd1) begin
                                        r_state <= S_IDLE;
                                    end else begin
                                        r_words_rem     <= r_words_rem - 16'd1;
                                        r_word_idx      <= r_word_idx + 16'd1;
                                        o_rf_debug_re   <= 1'b1;
                                        o_rf_debug_addr <= r_word_idx[4:0] + 5'd1;
                                        r_state         <= S_READ_WAIT;
                                    end
                                end

                                MODE_DMEM: begin
                                    if (r_words_rem == 16'd1) begin
                                        r_state <= S_IDLE;
                                    end else begin
                                        r_words_rem       <= r_words_rem - 16'd1;
                                        r_word_idx        <= r_word_idx + 16'd1;
                                        o_dmem_debug_re   <= 1'b1;
                                        o_dmem_debug_addr <= r_word_idx[DMEM_ADDR_WIDTH-1:0] + {{(DMEM_ADDR_WIDTH-1){1'b0}}, 1'b1};
                                        r_state           <= S_READ_WAIT;
                                    end
                                end

                                MODE_DMEM_USED: begin
                                    r_scan_idx <= r_scan_idx + 16'd1;
                                    r_state    <= S_USED_SCAN;
                                end

                                default: r_state <= S_IDLE;
                            endcase
                        end
                    end
                end

                // -------------------------------------------------------------
                // DUMP_DMEM (0x22): 2B offset + 2B cantidad
                // -------------------------------------------------------------
                S_DMEM_OFF_L: begin
                    if (w_rx_done_tick) begin
                        r_cnt_low <= w_rx_data;
                        r_state   <= S_DMEM_OFF_H;
                    end
                end

                S_DMEM_OFF_H: begin
                    if (w_rx_done_tick) begin
                        r_dmem_offset <= {w_rx_data, r_cnt_low};
                        r_state       <= S_DMEM_CNT_L;
                    end
                end

                S_DMEM_CNT_L: begin
                    if (w_rx_done_tick) begin
                        r_cnt_low <= w_rx_data;
                        r_state   <= S_DMEM_CNT_H;
                    end
                end

                S_DMEM_CNT_H: begin
                    if (w_rx_done_tick) begin
                        if (r_running || (w_req_len == 16'd0) ||
                            (({1'b0, r_dmem_offset} + {1'b0, w_req_len}) > DMEM_DEPTH)) begin
                            r_tx_data  <= RESP_NAK;
                            r_tx_start <= 1'b1;
                            r_state    <= S_TX_SINGLE_WAIT;
                        end else begin
                            r_dump_mode       <= MODE_DMEM;
                            r_word_idx        <= r_dmem_offset;
                            r_words_rem       <= w_req_len;
                            o_dmem_debug_re   <= 1'b1;
                            o_dmem_debug_addr <= r_dmem_offset[DMEM_ADDR_WIDTH-1:0];
                            r_state           <= S_READ_WAIT;
                        end
                    end
                end

                // -------------------------------------------------------------
                // DUMP_DMEM_USED (0x25): 2B count + K*(2B word_addr + 4B data)
                // -------------------------------------------------------------
                S_USED_COUNT: begin
                    r_used_cnt <= w_used_inc;
                    if (r_scan_idx == (DMEM_DEPTH - 1)) begin
                        r_tx_data  <= w_used_inc[7:0];
                        r_tx_start <= 1'b1;
                        r_state    <= S_USED_CNT_L_WAIT;
                    end else begin
                        r_scan_idx <= r_scan_idx + 16'd1;
                    end
                end

                S_USED_CNT_L_WAIT: begin
                    if (w_tx_done_tick) begin
                        r_tx_data  <= r_used_cnt[15:8];
                        r_tx_start <= 1'b1;
                        r_state    <= S_USED_CNT_H_WAIT;
                    end
                end

                S_USED_CNT_H_WAIT: begin
                    if (w_tx_done_tick) begin
                        r_scan_idx <= 16'd0;
                        r_state    <= S_USED_SCAN;
                    end
                end

                S_USED_SCAN: begin
                    if (r_scan_idx == DMEM_DEPTH) begin
                        r_state <= S_IDLE;
                    end else if (i_dmem_used_mask[r_scan_idx[DMEM_ADDR_WIDTH-1:0]]) begin
                        r_dump_mode       <= MODE_DMEM_USED;
                        o_dmem_debug_re   <= 1'b1;
                        o_dmem_debug_addr <= r_scan_idx[DMEM_ADDR_WIDTH-1:0];
                        r_state           <= S_READ_WAIT;
                    end else begin
                        r_scan_idx <= r_scan_idx + 16'd1;
                    end
                end

                S_USED_ADDR_L_WAIT: begin
                    if (w_tx_done_tick) begin
                        r_tx_data  <= r_scan_idx[15:8];
                        r_tx_start <= 1'b1;
                        r_state    <= S_USED_ADDR_H_WAIT;
                    end
                end

                S_USED_ADDR_H_WAIT: begin
                    if (w_tx_done_tick) begin
                        r_tx_data  <= r_saved_dmem_word[7:0];
                        r_tx_word  <= {8'd0, r_saved_dmem_word[31:8]};
                        r_byte_cnt <= 2'd0;
                        r_tx_start <= 1'b1;
                        r_state    <= S_TX_WORD_WAIT;
                    end
                end

                default: r_state <= S_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire
