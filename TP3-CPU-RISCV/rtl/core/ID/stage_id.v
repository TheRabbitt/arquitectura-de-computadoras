`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo Top: id_stage
// Descripción: Encapsula la Etapa de Decodificación (ID) para el procesador RISC-V.
// Contiene: Control Unit, Hazard Detection Unit, Register File,
//           Immediate Generator, Branch Comparator y Sumador de Target.
//==============================================================================

module id_stage (
    input  wire        i_clk,
    input  wire        i_rst,

    // -------------------------------------------------------------------------
    // Entradas desde el Latch IF/ID
    // -------------------------------------------------------------------------
    input  wire [31:0] i_pc,
    input  wire [31:0] i_instruction,

    // -------------------------------------------------------------------------
    // Entradas de Retroalimentación desde la Etapa WB (Write-Back)
    // -------------------------------------------------------------------------
    input  wire        i_wb_reg_write,
    input  wire [4:0]  i_wb_write_reg,
    input  wire [31:0] i_wb_write_data,

    // -------------------------------------------------------------------------
    // Entradas desde la Etapa EX (ID/EX) para la Detección de Riesgos (HDU)
    // -------------------------------------------------------------------------
    input  wire        i_id_ex_mem_read,
    input  wire [4:0]  i_id_ex_rd,

    // -------------------------------------------------------------------------
    // Salidas de Control del Pipeline (Hacia IF y Registro IF/ID)
    // -------------------------------------------------------------------------
    output wire        o_pc_write,
    output wire        o_if_id_write,
    output wire        o_pc_src,
    output wire [31:0] o_branch_target,

    // -------------------------------------------------------------------------
    // Salidas de Control para el Latch ID/EX (Filtradas por MUX de Stall)
    // -------------------------------------------------------------------------
    output wire        o_wb_reg_write,
    output wire        o_wb_mem_to_reg,
    output wire        o_m_mem_read,
    output wire        o_m_mem_write,
    output wire        o_ex_alu_src,
    output wire [1:0]  o_ex_alu_op,

    // -------------------------------------------------------------------------
    // Salidas de Datapath para el Latch ID/EX
    // -------------------------------------------------------------------------
    output wire [31:0] o_pc,
    output wire [31:0] o_rs1_data,
    output wire [31:0] o_rs2_data,
    output wire [31:0] o_imm,
    output wire [4:0]  o_rs1,
    output wire [4:0]  o_rs2,
    output wire [4:0]  o_rd,
    output wire [2:0]  o_funct3,
    output wire        o_funct7_5,

    // -------------------------------------------------------------------------
    // Puerto de Depuración (Debug Unit / UART)
    // -------------------------------------------------------------------------
    input  wire        i_rf_debug_re,
    input  wire [4:0]  i_rf_debug_addr,
    output wire [31:0] o_rf_debug_rdata
);

    // -------------------------------------------------------------------------
    // Señales Internas
    // -------------------------------------------------------------------------
    // Control salidas puras de Control Unit
    wire       ctrl_branch, ctrl_jump, ctrl_mem_read, ctrl_mem_to_reg;
    wire       ctrl_mem_write, ctrl_alu_src, ctrl_reg_write;
    wire [1:0] ctrl_alu_op;

    // Control de MUX de Stall desde HDU
    wire       ctrl_mux_sel;

    // Branching interno
    wire       take_branch;

    // Extraer campos de la instrucción
    wire [4:0] rs1_addr = i_instruction[19:15];
    wire [4:0] rs2_addr = i_instruction[24:20];
    wire [4:0] rd_addr  = i_instruction[11:7];

    // -------------------------------------------------------------------------
    // Unidad de Control Principal
    // -------------------------------------------------------------------------
    control_unit ctrl (
        .i_opcode(i_instruction[6:0]),
        .o_branch(ctrl_branch),
        .o_jump(ctrl_jump),
        .o_mem_read(ctrl_mem_read),
        .o_mem_to_reg(ctrl_mem_to_reg),
        .o_alu_op(ctrl_alu_op),
        .o_mem_write(ctrl_mem_write),
        .o_alu_src(ctrl_alu_src),
        .o_reg_write(ctrl_reg_write)
    );

    // -------------------------------------------------------------------------
    // Unidad de Detección de Riesgos (Hazard Detection Unit)
    // -------------------------------------------------------------------------
    hazard_detection_unit hdu (
        .id_ex_mem_read(i_id_ex_mem_read),
        .id_ex_rd(i_id_ex_rd),
        .if_id_rs1(rs1_addr),
        .if_id_rs2(rs2_addr),
        .pc_write(o_pc_write),
        .if_id_write(o_if_id_write),
        .ctrl_mux_sel(ctrl_mux_sel)
    );

    // -------------------------------------------------------------------------
    // Multiplexor de Control de Burbujas (Stall Mux)
    // Si ctrl_mux_sel == 0 (se detectó Load-Use), se inyectan ceros hacia ID/EX.
    // -------------------------------------------------------------------------
    assign o_wb_reg_write  = ctrl_mux_sel ? ctrl_reg_write  : 1'b0;
    assign o_wb_mem_to_reg = ctrl_mux_sel ? ctrl_mem_to_reg : 1'b0;
    assign o_m_mem_read    = ctrl_mux_sel ? ctrl_mem_read   : 1'b0;
    assign o_m_mem_write   = ctrl_mux_sel ? ctrl_mem_write  : 1'b0;
    assign o_ex_alu_src    = ctrl_mux_sel ? ctrl_alu_src    : 1'b0;
    assign o_ex_alu_op     = ctrl_mux_sel ? ctrl_alu_op     : 2'b00;

    // -------------------------------------------------------------------------
    // Banco de Registros (Register File)
    // -------------------------------------------------------------------------
    register_file rf (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_reg_write(i_wb_reg_write),
        .i_read_reg1(rs1_addr),
        .i_read_reg2(rs2_addr),
        .i_write_reg(i_wb_write_reg),
        .i_write_data(i_wb_write_data),
        .o_read_data1(o_rs1_data),
        .o_read_data2(o_rs2_data),
        
        // Debug
        .i_debug_re(i_rf_debug_re),
        .i_debug_reg_addr(i_rf_debug_addr),
        .o_debug_reg_data(o_rf_debug_rdata)
    );

    // -------------------------------------------------------------------------
    // Generador de Inmediatos
    // -------------------------------------------------------------------------
    imm_gen ig (
        .i_instruction(i_instruction),
        .o_imm(o_imm)
    );

    // -------------------------------------------------------------------------
    // Comparador de Saltos Condicionales
    // -------------------------------------------------------------------------
    branch_comparator bc (
        .i_data1(o_rs1_data),
        .i_data2(o_rs2_data),
        .i_funct3(i_instruction[14:12]),
        .o_take_branch(take_branch)
    );

    // -------------------------------------------------------------------------
    // Sumador para la Dirección Objetivo de Salto (Branch Target)
    // -------------------------------------------------------------------------
    sumador #(.NB_SUM(32)) add_branch_target (
        .i_a(i_pc),
        .i_b(o_imm),
        .o_result(o_branch_target)
    );

    // Lógica para decidir si tomar un salto (BEQ/BNE o JAL)
    assign o_pc_src = (ctrl_branch & take_branch) | ctrl_jump;

    // -------------------------------------------------------------------------
    // Asignación de campos del Datapath hacia el Latch ID/EX
    // -------------------------------------------------------------------------
    assign o_pc       = i_pc;
    assign o_rs1      = rs1_addr;
    assign o_rs2      = rs2_addr;
    assign o_rd       = rd_addr;
    assign o_funct3   = i_instruction[14:12];
    assign o_funct7_5 = i_instruction[30];

endmodule
`default_nettype wire