`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo Top: id_stage
// Descripción: Encapsula la Etapa de Decodificación (ID) para el procesador RISC-V.
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
    // Entradas para Hazard Detection Unit y Forwarding ID
    // -------------------------------------------------------------------------
    // Desde ID/EX
    input  wire        i_id_ex_mem_read,
    input  wire        i_id_ex_reg_write,
    input  wire [4:0]  i_id_ex_rd,
    
    // Desde EX/MEM
    input  wire        i_ex_mem_reg_write,
    input  wire        i_ex_mem_mem_read,
    input  wire [4:0]  i_ex_mem_rd,
    input  wire [31:0] i_ex_mem_alu_result, // Dato para adelantar

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
    output wire [2:0]  o_ex_alu_op,

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
    wire       ctrl_mem_write, ctrl_alu_src, ctrl_reg_write, ctrl_jalr;
    wire [2:0] ctrl_alu_op;

    wire       ctrl_mux_sel; // Control de Stall
    wire       take_branch;

    // Cables de datos con posible adelantamiento (Forwarding)
    wire [1:0] forward_a_id;
    wire [1:0] forward_b_id;
    wire [31:0] cmp_data1;
    wire [31:0] cmp_data2;

    // Señales para el cálculo de saltos
    wire [31:0] base_address_sum;
    wire [31:0] branch_target_raw;

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
        .o_jalr(ctrl_jalr),
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
        .id_ex_mem_read  (i_id_ex_mem_read),
        .id_ex_reg_write (i_id_ex_reg_write),
        .id_ex_rd        (i_id_ex_rd),
        .ex_mem_mem_read (i_ex_mem_mem_read),
        .ex_mem_rd       (i_ex_mem_rd),
        .if_id_branch    (ctrl_branch),
        .if_id_rs1       (rs1_addr),
        .if_id_rs2       (rs2_addr),
        .pc_write        (o_pc_write),
        .if_id_write     (o_if_id_write),
        .ctrl_mux_sel    (ctrl_mux_sel)
    );

    // -------------------------------------------------------------------------
    // Multiplexor de Control de Burbujas (Stall Mux)
    // -------------------------------------------------------------------------
    assign o_wb_reg_write  = ctrl_mux_sel ? ctrl_reg_write  : 1'b0;
    assign o_wb_mem_to_reg = ctrl_mux_sel ? ctrl_mem_to_reg : 1'b0;
    assign o_m_mem_read    = ctrl_mux_sel ? ctrl_mem_read   : 1'b0;
    assign o_m_mem_write   = ctrl_mux_sel ? ctrl_mem_write  : 1'b0;
    assign o_ex_alu_src    = ctrl_mux_sel ? ctrl_alu_src    : 1'b0;
    assign o_ex_alu_op     = ctrl_mux_sel ? ctrl_alu_op     : 3'b0;

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
        .o_read_data1(o_rs1_data), // Salida cruda hacia el Latch ID/EX
        .o_read_data2(o_rs2_data), // Salida cruda hacia el Latch ID/EX
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
    // ID Forwarding Unit
    // -------------------------------------------------------------------------
    id_forwarding_unit id_fwd (
        .if_id_rs1        (rs1_addr),
        .if_id_rs2        (rs2_addr),
        .ex_mem_reg_write (i_ex_mem_reg_write),
        .ex_mem_rd        (i_ex_mem_rd),
        .mem_wb_reg_write (i_wb_reg_write), // RegWrite final desde MEM/WB
        .mem_wb_rd        (i_wb_write_reg), // Registro de destino final
        .forward_a_id     (forward_a_id),
        .forward_b_id     (forward_b_id)
    );

    // MUX para adelantar el Operando A (rs1) en ID
    mux3 #(.NB(32)) mux_id_fwd_a (
        .i_sel (forward_a_id),
        .i_d0  (o_rs1_data),           // 00: Dato del registro normal
        .i_d1  (i_wb_write_data),      // 01: Dato adelantado desde MEM/WB
        .i_d2  (i_ex_mem_alu_result),  // 10: Dato adelantado desde EX/MEM
        .o_out (cmp_data1)
    );

    // MUX para adelantar el Operando B (rs2) en ID
    mux3 #(.NB(32)) mux_id_fwd_b (
        .i_sel (forward_b_id),
        .i_d0  (o_rs2_data),           // 00: Dato del registro normal
        .i_d1  (i_wb_write_data),      // 01: Dato adelantado desde MEM/WB
        .i_d2  (i_ex_mem_alu_result),  // 10: Dato adelantado desde EX/MEM
        .o_out (cmp_data2)
    );

    // -------------------------------------------------------------------------
    // Comparador de Saltos Condicionales (Usa datos adelantados)
    // -------------------------------------------------------------------------
    branch_comparator bc (
        .i_data1(cmp_data1),
        .i_data2(cmp_data2),
        .i_funct3(i_instruction[14:12]),
        .o_take_branch(take_branch)
    );

    // -------------------------------------------------------------------------
    // Sumador para la Dirección Objetivo de Salto
    // -------------------------------------------------------------------------
    // JALR usa la base rs1 (adelantada). Branch/JAL usan el PC.
    assign base_address_sum = ctrl_jalr ? cmp_data1 : i_pc;

    sumador #(.NB_SUM(32)) add_branch_target (
        .i_a(base_address_sum),
        .i_b(o_imm),
        .o_result(branch_target_raw)
    );

    // Enmascarar el bit LSB a 0 para cumplir con la especificación de RISC-V para JALR
    assign o_branch_target = {branch_target_raw[31:1], 1'b0};

    // Lógica para decidir si tomar un salto (BEQ/BNE o JAL/JALR)
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