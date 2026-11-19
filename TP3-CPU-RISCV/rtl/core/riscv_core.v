`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: riscv_core
// Descripción:
//   Procesador RISC-V (RV32I) segmentado de 5 etapas (IF, ID, EX, MEM, WB)
//   preparado para integración con la Debug Unit por UART.
//   - El reloj del sistema (i_clk) NUNCA es intervenido; el avance en modo
//     continuo y paso a paso se gobierna exclusivamente mediante clock-enable (i_en).
//   - Soporta parada por instrucción EBREAK (0x00100073) con vaciado completo
//     del pipeline verificado por bits de validez en los 4 latches intermedios.
//   - Expone puertos de programación dinámica de InstructionMemory, limpieza y
//     lectura de DataMemory (con máscara de palabras usadas), lectura de los
//     32 registros y buses empaquetados de los 4 latches intermedios.
//==============================================================================

module riscv_core #(
    parameter NB_PC           = 32,
    parameter DATA_WIDTH      = 32,
    parameter IMEM_ADDR_WIDTH = 10, // 1024 palabras (4 KB)
    parameter DMEM_ADDR_WIDTH = 8   // 256 palabras  (1 KB)
)(
    input  wire                             i_clk,
    input  wire                             i_rst,
    input  wire                             i_en, // Habilitación global (1: avanza, 0: congela pipeline)

    // Estado de ejecución hacia Debug Unit
    output wire                             o_halted,         // HALT detectado (combinacional + sticky)
    output wire                             o_pipeline_empty, // Los 4 latches intermedios están vacíos
    output wire                             o_exec_done,      // HALT alcanzado Y pipeline completamente vacío
    output wire                             o_draining,       // HALT alcanzado, vaciando instrucciones previas

    // Programación / Lectura de Memoria de Instrucciones (Puerto B BRAM)
    input  wire                             i_imem_we,
    input  wire [IMEM_ADDR_WIDTH-1:0]       i_imem_waddr,
    input  wire [DATA_WIDTH-1:0]            i_imem_wdata,
    input  wire                             i_imem_debug_re,
    input  wire [IMEM_ADDR_WIDTH-1:0]       i_imem_debug_addr,
    output wire [DATA_WIDTH-1:0]            o_imem_debug_rdata,

    // Depuración del Banco de Registros (x0..x31)
    input  wire                             i_rf_debug_re,
    input  wire [4:0]                       i_rf_debug_addr,
    output wire [DATA_WIDTH-1:0]            o_rf_debug_rdata,

    // Depuración y Limpieza Dinámica de Memoria de Datos
    input  wire                             i_dmem_clear_we,
    input  wire [DMEM_ADDR_WIDTH-1:0]       i_dmem_clear_addr,
    input  wire                             i_dmem_debug_re,
    input  wire [DMEM_ADDR_WIDTH-1:0]       i_dmem_debug_addr,
    output wire [DATA_WIDTH-1:0]            o_dmem_debug_rdata,
    output wire [(1<<DMEM_ADDR_WIDTH)-1:0]  o_dmem_used_mask,

    // Buses de Depuración de PC y Latches Intermedios
    output wire [NB_PC-1:0]                 o_debug_pc,
    output wire [127:0]                     o_debug_if_id,
    output wire [191:0]                     o_debug_id_ex,
    output wire [127:0]                     o_debug_ex_mem,
    output wire [127:0]                     o_debug_mem_wb
);

    localparam DMEM_DEPTH = (1 << DMEM_ADDR_WIDTH);

    // =========================================================================
    // Señales Internas del Pipeline
    // =========================================================================

    // IF -> IF/ID
    wire [31:0] if_pc;
    wire [31:0] if_instr;
    wire [31:0] if_pc_plus_4;
    wire        if_halted;

    // ID -> IF / IF/ID
    wire        id_pc_write;
    wire        id_if_id_write;
    wire        id_pc_src;
    wire [31:0] id_branch_target;
    wire        id_halt;
    wire        id_ctrl_mux_sel;

    // IF/ID -> ID
    wire [31:0] if_id_pc;
    wire [31:0] if_id_pc_plus_4;
    wire [31:0] if_id_instr;
    wire        if_id_valid;

    // WB -> ID
    wire [31:0] wb_write_data;

    // ID -> ID/EX
    wire        id_wb_reg_write, id_wb_mem_to_reg;
    wire        id_m_mem_read, id_m_mem_write;
    wire        id_ex_alu_src;
    wire [2:0]  id_ex_alu_op;
    wire [31:0] id_pc_out, id_rs1_data, id_rs2_data, id_imm, id_pc_plus_4;
    wire [4:0]  id_rs1, id_rs2, id_rd;
    wire [2:0]  id_funct3;
    wire        id_funct7_5;
    wire        id_wb_jump;
    wire        id_valid_to_ex;

    // ID/EX -> EX
    wire        id_ex_wb_reg_write, id_ex_wb_mem_to_reg;
    wire        id_ex_m_mem_read, id_ex_m_mem_write;
    wire        id_ex_ex_alu_src;
    wire [2:0]  id_ex_ex_alu_op;
    wire [31:0] id_ex_pc, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm, id_ex_pc_plus_4;
    wire [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    wire [2:0]  id_ex_funct3;
    wire        id_ex_funct7_5;
    wire        id_ex_wb_jump;
    wire        id_ex_valid;

    // EX -> EX/MEM
    wire [31:0] ex_alu_result, ex_rs2_data, ex_pc_plus_4;
    wire [2:0]  ex_funct3;
    wire        ex_wb_jump;

    // EX/MEM -> MEM
    wire        ex_mem_wb_reg_write, ex_mem_wb_mem_to_reg, ex_mem_wb_jump;
    wire        ex_mem_m_mem_read, ex_mem_m_mem_write;
    wire [31:0] ex_mem_alu_result, ex_mem_rs2_data, ex_mem_pc_plus_4;
    wire [4:0]  ex_mem_rd;
    wire [2:0]  ex_mem_funct3;
    wire        ex_mem_valid;

    // MEM -> MEM/WB
    wire        mem_wb_reg_write_out, mem_wb_mem_to_reg_out, mem_wb_jump;
    wire [31:0] mem_read_data, mem_alu_result, mem_pc_plus_4;
    wire [4:0]  mem_rd;

    // MEM/WB -> WB (y Forwarding)
    wire        wb_reg_write_final;
    wire        wb_mem_to_reg_final;
    wire        wb_jump_final;
    wire [31:0] wb_read_data_final;
    wire [31:0] wb_alu_result_final;
    wire [31:0] wb_pc_plus_4_final;
    wire [4:0]  wb_rd_final;
    wire        mem_wb_valid;

    // =========================================================================
    // Control de Avance Sincrónico, Vaciado de Pipeline y Memoria de Datos
    // =========================================================================

    // Si hay salto tomado o HALT activo en un ciclo habilitado, se limpia IF/ID
    // para descartar la instrucción posterior buscada en IF.
    wire if_id_en    = i_en & id_if_id_write;
    wire if_id_flush = i_en & (id_pc_src | if_halted);

    // Una instrucción pasa como válida a ID/EX solo si era válida en IF/ID,
    // no hubo stall (ctrl_mux_sel == 1) y no es la instrucción EBREAK (id_halt == 0).
    assign id_valid_to_ex = if_id_valid & id_ctrl_mux_sel & ~id_halt;

    // Ventana activa para el flanco negativo de DataMemory tras un posedge con i_en=1.
    // Evita re-escrituras espurias mientras el procesador está pausado en modo STEP.
    reg r_mem_cycle_active;
    always @(posedge i_clk) begin
        if (i_rst) begin
            r_mem_cycle_active <= 1'b0;
        end else begin
            r_mem_cycle_active <= i_en;
        end
    end

    // Registro de máscara de palabras escritas en DataMemory (256 bits)
    reg [DMEM_DEPTH-1:0] r_dmem_used_mask;
    always @(posedge i_clk) begin
        if (i_rst) begin
            r_dmem_used_mask <= {DMEM_DEPTH{1'b0}};
        end else if (r_mem_cycle_active && ex_mem_m_mem_write) begin
            r_dmem_used_mask[ex_mem_alu_result[DMEM_ADDR_WIDTH+1:2]] <= 1'b1;
        end
    end

    // Multiplexación limpia del Puerto 1 de DataMemory para borrado dinámico en RESET
    // sin agregar un segundo puerto de escritura (preserva inferencia BRAM 100% en Vivado).
    wire        mem_write_mux  = i_dmem_clear_we ? 1'b1                                    : (ex_mem_m_mem_write & r_mem_cycle_active);
    wire        mem_read_mux   = i_dmem_clear_we ? 1'b0                                    : ex_mem_m_mem_read;
    wire [2:0]  mem_funct3_mux = i_dmem_clear_we ? 3'b010                                  : ex_mem_funct3; // 3'b010 = SW (32 bits)
    wire [31:0] mem_addr_mux   = i_dmem_clear_we ? {{(30-DMEM_ADDR_WIDTH){1'b0}}, i_dmem_clear_addr, 2'b00} : ex_mem_alu_result;
    wire [31:0] mem_wdata_mux  = i_dmem_clear_we ? 32'd0                                   : ex_mem_rs2_data;

    // Estado global del pipeline
    assign o_halted         = if_halted;
    assign o_pipeline_empty = ~if_id_valid & ~id_ex_valid & ~ex_mem_valid & ~mem_wb_valid;
    assign o_exec_done      = if_halted & o_pipeline_empty;
    assign o_draining       = if_halted & ~o_pipeline_empty;
    assign o_debug_pc       = if_pc;
    assign o_dmem_used_mask = r_dmem_used_mask;

    // =========================================================================
    // Instanciación de Etapas y Latches Intermedios
    // =========================================================================

    stage_if #(
        .NB_PC     (NB_PC),
        .ADDR_WIDTH(IMEM_ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_stage_if (
        .i_clk           (i_clk),
        .i_rst           (i_rst),
        .i_en            (i_en),
        .i_stall         (~id_pc_write),
        .i_halt          (id_halt),
        .i_branch_sel    (id_pc_src),
        .i_branch_target (id_branch_target),
        .i_mem_we        (i_imem_we),
        .i_debug_re      (i_imem_debug_re),
        .i_debug_addr    (i_imem_debug_addr),
        .i_write_addr    (i_imem_waddr),
        .i_write_data    (i_imem_wdata),
        .o_pc            (if_pc),
        .o_instruction   (if_instr),
        .o_pc_plus_4     (if_pc_plus_4),
        .o_halted        (if_halted),
        .o_debug_rdata   (o_imem_debug_rdata)
    );

    if_id_register #(
        .NB(NB_PC)
    ) u_if_id (
        .i_clk          (i_clk),
        .i_rst          (i_rst),
        .i_en           (if_id_en),
        .i_flush        (if_id_flush),
        .i_pc           (if_pc),
        .i_instruction  (if_instr),
        .i_pc_plus_4    (if_pc_plus_4),
        .o_pc           (if_id_pc),
        .o_pc_plus_4    (if_id_pc_plus_4),
        .o_instruction  (if_id_instr),
        .o_valid        (if_id_valid),
        .o_debug_if_id  (o_debug_if_id)
    );

    id_stage u_stage_id (
        .i_clk               (i_clk),
        .i_rst               (i_rst),
        .i_pc                (if_id_pc),
        .i_instruction       (if_id_instr),
        .i_pc_plus_4         (if_id_pc_plus_4),
        .i_wb_reg_write      (wb_reg_write_final & i_en),
        .i_wb_write_reg      (wb_rd_final),
        .i_wb_write_data     (wb_write_data),
        .i_id_ex_mem_read    (id_ex_m_mem_read),
        .i_id_ex_reg_write   (id_ex_wb_reg_write),
        .i_id_ex_wb_jump     (id_ex_wb_jump),
        .i_id_ex_rd          (id_ex_rd),
        .i_ex_mem_reg_write  (ex_mem_wb_reg_write),
        .i_ex_mem_mem_read   (ex_mem_m_mem_read),
        .i_ex_mem_wb_jump    (ex_mem_wb_jump),
        .i_ex_mem_rd         (ex_mem_rd),
        .i_ex_mem_alu_result (ex_mem_alu_result),
        .i_ex_mem_pc_plus_4  (ex_mem_pc_plus_4),
        .o_pc_write          (id_pc_write),
        .o_if_id_write       (id_if_id_write),
        .o_pc_src            (id_pc_src),
        .o_branch_target     (id_branch_target),
        .o_halt              (id_halt),
        .o_ctrl_mux_sel      (id_ctrl_mux_sel),
        .o_wb_reg_write      (id_wb_reg_write),
        .o_wb_mem_to_reg     (id_wb_mem_to_reg),
        .o_m_mem_read        (id_m_mem_read),
        .o_m_mem_write       (id_m_mem_write),
        .o_ex_alu_src        (id_ex_alu_src),
        .o_ex_alu_op         (id_ex_alu_op),
        .o_wb_jump           (id_wb_jump),
        .o_pc                (id_pc_out),
        .o_pc_plus_4         (id_pc_plus_4),
        .o_rs1_data          (id_rs1_data),
        .o_rs2_data          (id_rs2_data),
        .o_imm               (id_imm),
        .o_rs1               (id_rs1),
        .o_rs2               (id_rs2),
        .o_rd                (id_rd),
        .o_funct3            (id_funct3),
        .o_funct7_5          (id_funct7_5),
        .i_rf_debug_re       (i_rf_debug_re),
        .i_rf_debug_addr     (i_rf_debug_addr),
        .o_rf_debug_rdata    (o_rf_debug_rdata)
    );

    id_ex_register #(
        .NB_DATA(DATA_WIDTH),
        .NB_REG (5)
    ) u_id_ex (
        .i_clk           (i_clk),
        .i_rst           (i_rst),
        .i_en            (i_en),
        .i_valid         (id_valid_to_ex),
        .i_wb_reg_write  (id_wb_reg_write),
        .i_wb_mem_to_reg (id_wb_mem_to_reg),
        .i_m_mem_read    (id_m_mem_read),
        .i_m_mem_write   (id_m_mem_write),
        .i_ex_alu_src    (id_ex_alu_src),
        .i_ex_alu_op     (id_ex_alu_op),
        .i_pc            (id_pc_out),
        .i_pc_plus_4     (id_pc_plus_4),
        .i_rs1_data      (id_rs1_data),
        .i_rs2_data      (id_rs2_data),
        .i_imm           (id_imm),
        .i_rs1           (id_rs1),
        .i_rs2           (id_rs2),
        .i_rd            (id_rd),
        .i_funct3        (id_funct3),
        .i_funct7_5      (id_funct7_5),
        .i_wb_jump       (id_wb_jump),
        .o_wb_reg_write  (id_ex_wb_reg_write),
        .o_wb_mem_to_reg (id_ex_wb_mem_to_reg),
        .o_m_mem_read    (id_ex_m_mem_read),
        .o_m_mem_write   (id_ex_m_mem_write),
        .o_ex_alu_src    (id_ex_ex_alu_src),
        .o_ex_alu_op     (id_ex_ex_alu_op),
        .o_valid         (id_ex_valid),
        .o_pc            (id_ex_pc),
        .o_pc_plus_4     (id_ex_pc_plus_4),
        .o_rs1_data      (id_ex_rs1_data),
        .o_rs2_data      (id_ex_rs2_data),
        .o_imm           (id_ex_imm),
        .o_rs1           (id_ex_rs1),
        .o_rs2           (id_ex_rs2),
        .o_rd            (id_ex_rd),
        .o_funct3        (id_ex_funct3),
        .o_funct7_5      (id_ex_funct7_5),
        .o_wb_jump       (id_ex_wb_jump),
        .o_debug_id_ex   (o_debug_id_ex)
    );

    stage_ex u_stage_ex (
        .i_alu_op            (id_ex_ex_alu_op),
        .i_alusrc            (id_ex_ex_alu_src),
        .i_wb_jump           (id_ex_wb_jump),
        .i_funct3            (id_ex_funct3),
        .i_funct7_5          (id_ex_funct7_5),
        .i_rs1               (id_ex_rs1),
        .i_rs2               (id_ex_rs2),
        .i_read_data1        (id_ex_rs1_data),
        .i_read_data2        (id_ex_rs2_data),
        .i_imm               (id_ex_imm),
        .i_pc_plus_4         (id_ex_pc_plus_4),
        .i_ex_mem_rd         (ex_mem_rd),
        .i_ex_mem_regwrite   (ex_mem_wb_reg_write),
        .i_ex_mem_wb_jump    (ex_mem_wb_jump),
        .i_ex_mem_alu_result (ex_mem_alu_result),
        .i_ex_mem_pc_plus_4  (ex_mem_pc_plus_4),
        .i_mem_wb_rd         (wb_rd_final),
        .i_mem_wb_regwrite   (wb_reg_write_final),
        .i_mem_wb_data       (wb_write_data),
        .i_mem_wb_pc_plus_4  (wb_pc_plus_4_final),
        .o_alu_result        (ex_alu_result),
        .o_rs2_data          (ex_rs2_data),
        .o_pc_plus_4         (ex_pc_plus_4),
        .o_funct3            (ex_funct3),
        .o_wb_jump           (ex_wb_jump)
    );

    ex_mem_latch u_ex_mem (
        .clk            (i_clk),
        .rst            (i_rst),
        .i_enable       (i_en),
        .i_valid        (id_ex_valid),
        .i_wb_regwrite  (id_ex_wb_reg_write),
        .i_wb_memtoreg  (id_ex_wb_mem_to_reg),
        .i_wb_jump      (ex_wb_jump),
        .i_m_memread    (id_ex_m_mem_read),
        .i_m_memwrite   (id_ex_m_mem_write),
        .i_alu_result   (ex_alu_result),
        .i_rs2_data     (ex_rs2_data),
        .i_rd           (id_ex_rd),
        .i_funct3       (ex_funct3),
        .i_pc_plus_4    (ex_pc_plus_4),
        .o_wb_regwrite  (ex_mem_wb_reg_write),
        .o_wb_memtoreg  (ex_mem_wb_mem_to_reg),
        .o_wb_jump      (ex_mem_wb_jump),
        .o_m_memread    (ex_mem_m_mem_read),
        .o_m_memwrite   (ex_mem_m_mem_write),
        .o_valid        (ex_mem_valid),
        .o_alu_result   (ex_mem_alu_result),
        .o_rs2_data     (ex_mem_rs2_data),
        .o_rd           (ex_mem_rd),
        .o_funct3       (ex_mem_funct3),
        .o_pc_plus_4    (ex_mem_pc_plus_4),
        .o_debug_ex_mem (o_debug_ex_mem)
    );

    stage_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(DMEM_ADDR_WIDTH)
    ) u_stage_mem (
        .i_clk           (i_clk),
        .i_wb_reg_write  (ex_mem_wb_reg_write),
        .i_wb_mem_to_reg (ex_mem_wb_mem_to_reg),
        .i_wb_jump       (ex_mem_wb_jump),
        .i_m_mem_read    (mem_read_mux),
        .i_m_mem_write   (mem_write_mux),
        .i_alu_result    (mem_addr_mux),
        .i_rs2_data      (mem_wdata_mux),
        .i_rd            (ex_mem_rd),
        .i_funct3        (mem_funct3_mux),
        .i_pc_plus_4     (ex_mem_pc_plus_4),
        .i_debug_re      (i_dmem_debug_re),
        .i_debug_addr    (i_dmem_debug_addr),
        .o_debug_rdata   (o_dmem_debug_rdata),
        .o_wb_reg_write  (mem_wb_reg_write_out),
        .o_wb_mem_to_reg (mem_wb_mem_to_reg_out),
        .o_wb_jump       (mem_wb_jump),
        .o_read_data     (mem_read_data),
        .o_alu_result    (mem_alu_result),
        .o_rd            (mem_rd),
        .o_pc_plus_4     (mem_pc_plus_4)
    );

    mem_wb_latch u_mem_wb (
        .i_clk           (i_clk),
        .i_rst           (i_rst),
        .i_enable        (i_en),
        .i_valid         (ex_mem_valid),
        .i_wb_reg_write  (mem_wb_reg_write_out),
        .i_wb_mem_to_reg (mem_wb_mem_to_reg_out),
        .i_wb_jump       (mem_wb_jump),
        .i_read_data     (mem_read_data),
        .i_alu_result    (mem_alu_result),
        .i_rd            (mem_rd),
        .i_pc_plus_4     (mem_pc_plus_4),
        .o_wb_reg_write  (wb_reg_write_final),
        .o_wb_mem_to_reg (wb_mem_to_reg_final),
        .o_wb_jump       (wb_jump_final),
        .o_valid         (mem_wb_valid),
        .o_read_data     (wb_read_data_final),
        .o_alu_result    (wb_alu_result_final),
        .o_rd            (wb_rd_final),
        .o_pc_plus_4     (wb_pc_plus_4_final),
        .o_debug_mem_wb  (o_debug_mem_wb)
    );

    stage_wb u_stage_wb (
        .i_mem_to_reg (wb_mem_to_reg_final),
        .i_jump       (wb_jump_final),
        .i_alu_result (wb_alu_result_final),
        .i_read_data  (wb_read_data_final),
        .i_pc_plus_4  (wb_pc_plus_4_final),
        .o_write_data (wb_write_data)
    );

endmodule
`default_nettype wire

