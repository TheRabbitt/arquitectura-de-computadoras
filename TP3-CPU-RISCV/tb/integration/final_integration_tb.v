`timescale 1ns / 1ps
`default_nettype none

module tb_pipeline;

    // =========================================================================
    // Generación de Reloj y Reset
    // =========================================================================
    reg clk;
    reg rst;
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // Periodo de 10ns
    end

    // =========================================================================
    // Cables de Interconexión del Pipeline
    // =========================================================================
    
    // Señales Globales
    wire enable = 1'b1;

    // IF -> IF/ID
    wire [31:0] if_pc;
    wire [31:0] if_instr;
    wire [31:0] if_pc_plus_4;
    wire        if_halted;
    
    // ID -> IF (Retroalimentación de Control)
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

    // WB -> ID (Retroalimentación al Banco de Registros)
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
    // Instanciación de Etapas y Registros
    // =========================================================================

    stage_if u_stage_if (
        .i_clk(clk), .i_rst(rst), .i_en(enable),
        .i_stall(~id_pc_write), .i_halt(id_halt),
        .i_branch_sel(id_pc_src), .i_branch_target(id_branch_target),
        .i_mem_we(1'b0), .i_debug_re(1'b0), .i_debug_addr(10'b0), 
        .i_write_addr(10'b0), .i_write_data(32'b0),
        .o_pc(if_pc), .o_pc_plus_4(if_pc_plus_4), .o_instruction(if_instr), .o_halted(if_halted), .o_debug_rdata()
    );

    if_id_register u_if_id (
        .i_clk(clk), .i_rst(rst), .i_en(id_if_id_write),
        .i_flush(id_pc_src | if_halted), .i_pc(if_pc), .i_pc_plus_4(if_pc_plus_4), .i_instruction(if_instr),
        .o_pc(if_id_pc), .o_pc_plus_4(if_id_pc_plus_4), .o_instruction(if_id_instr),
        .o_valid(if_id_valid), .o_debug_if_id()
    );

    id_stage u_stage_id (
        .i_clk(clk), .i_rst(rst), .i_pc(if_id_pc), .i_pc_plus_4(if_id_pc_plus_4), .i_instruction(if_id_instr),
        .i_wb_reg_write(wb_reg_write_final), .i_wb_write_reg(wb_rd_final), .i_wb_write_data(wb_write_data),
        .i_id_ex_mem_read(id_ex_m_mem_read), .i_id_ex_reg_write(id_ex_wb_reg_write),
        .i_id_ex_wb_jump(id_ex_wb_jump), .i_id_ex_rd(id_ex_rd),
        .i_ex_mem_reg_write(ex_mem_wb_reg_write), .i_ex_mem_mem_read(ex_mem_m_mem_read),
        .i_ex_mem_wb_jump(ex_mem_wb_jump), .i_ex_mem_rd(ex_mem_rd),
        .i_ex_mem_alu_result(ex_mem_alu_result), .i_ex_mem_pc_plus_4(ex_mem_pc_plus_4),
        .o_pc_write(id_pc_write), .o_if_id_write(id_if_id_write), .o_pc_src(id_pc_src), .o_branch_target(id_branch_target),
        .o_halt(id_halt), .o_ctrl_mux_sel(id_ctrl_mux_sel),
        .o_wb_reg_write(id_wb_reg_write), .o_wb_mem_to_reg(id_wb_mem_to_reg),
        .o_m_mem_read(id_m_mem_read), .o_m_mem_write(id_m_mem_write),
        .o_ex_alu_src(id_ex_alu_src), .o_ex_alu_op(id_ex_alu_op),
        .o_pc(id_pc_out), .o_pc_plus_4(id_pc_plus_4), .o_rs1_data(id_rs1_data), .o_rs2_data(id_rs2_data), .o_imm(id_imm),
        .o_rs1(id_rs1), .o_rs2(id_rs2), .o_rd(id_rd),
        .o_funct3(id_funct3), .o_funct7_5(id_funct7_5), .o_wb_jump(id_wb_jump),
        .i_rf_debug_re(1'b0), .i_rf_debug_addr(5'b0), .o_rf_debug_rdata()
    );

    id_ex_register u_id_ex (
        .i_clk(clk), .i_rst(rst), .i_en(enable), .i_valid(if_id_valid & id_ctrl_mux_sel & ~id_halt),
        .i_wb_reg_write(id_wb_reg_write), .i_wb_mem_to_reg(id_wb_mem_to_reg),
        .i_m_mem_read(id_m_mem_read), .i_m_mem_write(id_m_mem_write),
        .i_ex_alu_src(id_ex_alu_src), .i_ex_alu_op(id_ex_alu_op),
        .i_pc(id_pc_out), .i_pc_plus_4(id_pc_plus_4), .i_rs1_data(id_rs1_data), .i_rs2_data(id_rs2_data), .i_imm(id_imm),
        .i_rs1(id_rs1), .i_rs2(id_rs2), .i_rd(id_rd),
        .i_funct3(id_funct3), .i_funct7_5(id_funct7_5), .i_wb_jump(id_wb_jump),
        .o_wb_reg_write(id_ex_wb_reg_write), .o_wb_mem_to_reg(id_ex_wb_mem_to_reg),
        .o_m_mem_read(id_ex_m_mem_read), .o_m_mem_write(id_ex_m_mem_write),
        .o_ex_alu_src(id_ex_ex_alu_src), .o_ex_alu_op(id_ex_ex_alu_op), .o_valid(id_ex_valid),
        .o_pc(id_ex_pc), .o_pc_plus_4(id_ex_pc_plus_4), .o_rs1_data(id_ex_rs1_data), .o_rs2_data(id_ex_rs2_data), .o_imm(id_ex_imm),
        .o_rs1(id_ex_rs1), .o_rs2(id_ex_rs2), .o_rd(id_ex_rd),
        .o_funct3(id_ex_funct3), .o_funct7_5(id_ex_funct7_5), .o_wb_jump(id_ex_wb_jump),
        .o_debug_id_ex()
    );

    stage_ex u_stage_ex (
        .i_alu_op(id_ex_ex_alu_op), .i_alusrc(id_ex_ex_alu_src),
        .i_funct3(id_ex_funct3), .i_funct7_5(id_ex_funct7_5),
        .i_rs1(id_ex_rs1), .i_rs2(id_ex_rs2),
        .i_read_data1(id_ex_rs1_data), .i_read_data2(id_ex_rs2_data), .i_imm(id_ex_imm), .i_pc_plus_4(id_ex_pc_plus_4), .i_wb_jump(id_ex_wb_jump),
        .i_ex_mem_rd(ex_mem_rd), .i_ex_mem_regwrite(ex_mem_wb_reg_write), .i_ex_mem_wb_jump(ex_mem_wb_jump),
        .i_ex_mem_alu_result(ex_mem_alu_result), .i_ex_mem_pc_plus_4(ex_mem_pc_plus_4),
        .i_mem_wb_rd(wb_rd_final), .i_mem_wb_regwrite(wb_reg_write_final), .i_mem_wb_data(wb_write_data), .i_mem_wb_pc_plus_4(wb_pc_plus_4_final),
        .o_alu_result(ex_alu_result), .o_rs2_data(ex_rs2_data), .o_pc_plus_4(ex_pc_plus_4), .o_funct3(ex_funct3), .o_wb_jump(ex_wb_jump)
    );

    ex_mem_latch u_ex_mem (
        .clk(clk), .rst(rst), .i_enable(enable), .i_valid(id_ex_valid),
        .i_wb_regwrite(id_ex_wb_reg_write), .i_wb_memtoreg(id_ex_wb_mem_to_reg), .i_wb_jump(ex_wb_jump),
        .i_m_memread(id_ex_m_mem_read), .i_m_memwrite(id_ex_m_mem_write),
        .i_alu_result(ex_alu_result), .i_rs2_data(ex_rs2_data), .i_rd(id_ex_rd), .i_funct3(ex_funct3), .i_pc_plus_4(ex_pc_plus_4),
        .o_wb_regwrite(ex_mem_wb_reg_write), .o_wb_memtoreg(ex_mem_wb_mem_to_reg),
        .o_m_memread(ex_mem_m_mem_read), .o_m_memwrite(ex_mem_m_mem_write), .o_valid(ex_mem_valid),
        .o_alu_result(ex_mem_alu_result), .o_rs2_data(ex_mem_rs2_data), .o_rd(ex_mem_rd), .o_funct3(ex_mem_funct3),
        .o_wb_jump(ex_mem_wb_jump), .o_pc_plus_4(ex_mem_pc_plus_4), .o_debug_ex_mem()
    );

    stage_mem u_stage_mem (
        .i_clk(clk),
        .i_wb_reg_write(ex_mem_wb_reg_write), .i_wb_mem_to_reg(ex_mem_wb_mem_to_reg), .i_wb_jump(ex_mem_wb_jump),
        .i_m_mem_read(ex_mem_m_mem_read), .i_m_mem_write(ex_mem_m_mem_write),
        .i_alu_result(ex_mem_alu_result), .i_rs2_data(ex_mem_rs2_data), .i_rd(ex_mem_rd), .i_funct3(ex_mem_funct3), .i_pc_plus_4(ex_mem_pc_plus_4),
        .i_debug_re(1'b0), .i_debug_addr(8'b0), .o_debug_rdata(),
        .o_wb_reg_write(mem_wb_reg_write_out), .o_wb_mem_to_reg(mem_wb_mem_to_reg_out), .o_wb_jump(mem_wb_jump),
        .o_read_data(mem_read_data), .o_alu_result(mem_alu_result), .o_rd(mem_rd), .o_pc_plus_4(mem_pc_plus_4)
    );

    mem_wb_latch u_mem_wb (
        .i_clk(clk), .i_rst(rst), .i_enable(enable), .i_valid(ex_mem_valid),
        .i_wb_reg_write(mem_wb_reg_write_out), .i_wb_mem_to_reg(mem_wb_mem_to_reg_out), .i_wb_jump(mem_wb_jump),
        .i_read_data(mem_read_data), .i_alu_result(mem_alu_result), .i_rd(mem_rd), .i_pc_plus_4(mem_pc_plus_4),
        .o_wb_reg_write(wb_reg_write_final), .o_wb_mem_to_reg(wb_mem_to_reg_final), .o_wb_jump(wb_jump_final), .o_valid(mem_wb_valid),
        .o_read_data(wb_read_data_final), .o_alu_result(wb_alu_result_final), .o_rd(wb_rd_final), .o_pc_plus_4(wb_pc_plus_4_final),
        .o_debug_mem_wb()
    );

    stage_wb u_stage_wb (
        .i_mem_to_reg(wb_mem_to_reg_final), .i_jump(wb_jump_final),
        .i_alu_result(wb_alu_result_final), .i_read_data(wb_read_data_final), .i_pc_plus_4(wb_pc_plus_4_final),
        .o_write_data(wb_write_data)
    );

    // =========================================================================
    // Inicialización de Memoria y Programa de Prueba
    // =========================================================================
    initial begin
        rst = 1;
        #17;
        rst = 0;

        // Programa completo que prueba todas las instrucciones solicitadas en el enunciado
        // -- Bloque 1: U-Type & I-Type Básicas --
        u_stage_if.u_imem.mem[0]  = 32'h123450b7; // 0x00: lui x1, 0x12345       (U-Type)
        u_stage_if.u_imem.mem[1]  = 32'h00a00113; // 0x04: addi x2, x0, 10       (I-Type)
        u_stage_if.u_imem.mem[2]  = 32'h00f17193; // 0x08: andi x3, x2, 15       (I-Type)
        u_stage_if.u_imem.mem[3]  = 32'h0051e213; // 0x0C: ori x4, x3, 5         (I-Type)
        u_stage_if.u_imem.mem[4]  = 32'h00f24293; // 0x10: xori x5, x4, 15       (I-Type)
        
        // -- Bloque 2: Shifts & Set Less Than (I-Type y R-Type) --
        u_stage_if.u_imem.mem[5]  = 32'h01412313; // 0x14: slti x6, x2, 20       (I-Type)
        u_stage_if.u_imem.mem[6]  = 32'h01413393; // 0x18: sltiu x7, x2, 20      (I-Type)
        u_stage_if.u_imem.mem[7]  = 32'h00111413; // 0x1C: slli x8, x2, 1        (I-Type)
        u_stage_if.u_imem.mem[8]  = 32'h00145493; // 0x20: srli x9, x8, 1        (I-Type)
        u_stage_if.u_imem.mem[9]  = 32'h4024d513; // 0x24: srai x10, x9, 2       (I-Type)
        
        // -- Bloque 3: Operaciones R-Type --
        u_stage_if.u_imem.mem[10] = 32'h002085b3; // 0x28: add x11, x1, x2       (R-Type)
        u_stage_if.u_imem.mem[11] = 32'h40258633; // 0x2C: sub x12, x11, x2      (R-Type)
        u_stage_if.u_imem.mem[12] = 32'h00a616b3; // 0x30: sll x13, x12, x10     (R-Type)
        u_stage_if.u_imem.mem[13] = 32'h00a6d733; // 0x34: srl x14, x13, x10     (R-Type)
        u_stage_if.u_imem.mem[14] = 32'h402757b3; // 0x38: sra x15, x14, x2      (R-Type)
        u_stage_if.u_imem.mem[15] = 32'h0025a833; // 0x3C: slt x16, x11, x2      (R-Type)
        u_stage_if.u_imem.mem[16] = 32'h0025b8b3; // 0x40: sltu x17, x11, x2     (R-Type)
        u_stage_if.u_imem.mem[17] = 32'h0008e933; // 0x44: or x18, x17, x0       (R-Type)
        u_stage_if.u_imem.mem[18] = 32'h011979b3; // 0x48: and x19, x18, x17     (R-Type)
        u_stage_if.u_imem.mem[19] = 32'h0128ca33; // 0x4C: xor x20, x17, x18     (R-Type)

        // -- Bloque 4: Memoria S-Type y Loads I-Type --
        u_stage_if.u_imem.mem[20] = 32'h00202023; // 0x50: sw x2, 0(x0)          (S-Type)
        u_stage_if.u_imem.mem[21] = 32'h00201223; // 0x54: sh x2, 4(x0)          (S-Type)
        u_stage_if.u_imem.mem[22] = 32'h00200423; // 0x58: sb x2, 8(x0)          (S-Type)
        u_stage_if.u_imem.mem[23] = 32'h00002a83; // 0x5C: lw x21, 0(x0)         (I-Type Load)
        u_stage_if.u_imem.mem[24] = 32'h00401b03; // 0x60: lh x22, 4(x0)         (I-Type Load)
        u_stage_if.u_imem.mem[25] = 32'h00800b83; // 0x64: lb x23, 8(x0)         (I-Type Load)
        u_stage_if.u_imem.mem[26] = 32'h00405c03; // 0x68: lhu x24, 4(x0)        (I-Type Load)
        u_stage_if.u_imem.mem[27] = 32'h00804c83; // 0x6C: lbu x25, 8(x0)        (I-Type Load)

        // -- Bloque 5: Saltos B-Type, J-Type y JALR (sin stall tras JAL) --
        u_stage_if.u_imem.mem[28] = 32'h016a8463; // 0x70: beq x21, x22, 8       (B-Type) (Salta a 0x78)
        u_stage_if.u_imem.mem[29] = 32'h00000013; // 0x74: nop                   (Ignorado por salto)
        u_stage_if.u_imem.mem[30] = 32'h000a9463; // 0x78: bne x21, x0, 8        (B-Type) (Salta a 0x80)
        u_stage_if.u_imem.mem[31] = 32'h00000013; // 0x7C: nop
        u_stage_if.u_imem.mem[32] = 32'h00800d6f; // 0x80: jal x26, 8            (J-Type) (Salta a 0x88, x26=0x84)
        u_stage_if.u_imem.mem[33] = 32'h00000013; // 0x84: nop
        u_stage_if.u_imem.mem[34] = 32'h00cd0067; // 0x88: jalr x0, x26, 12      (Salta a 0x84+12 = 0x90 sin stall)
        u_stage_if.u_imem.mem[35] = 32'h00000013; // 0x8C: nop                   (Ignorado por flush de jalr)

        // -- Bloque 6: SLTI, SLTIU, SLLI y SLL con Números Negativos --
        u_stage_if.u_imem.mem[36] = 32'hff600d93; // 0x90: addi x27, x0, -10     (x27 = 0xFFFFFFF6 = -10)
        u_stage_if.u_imem.mem[37] = 32'hffbda313; // 0x94: slti x6, x27, -5      (-10 < -5 con signo  -> x6 = 1)
        u_stage_if.u_imem.mem[38] = 32'hfecda393; // 0x98: slti x7, x27, -20     (-10 < -20 con signo -> x7 = 0)
        u_stage_if.u_imem.mem[39] = 32'hffb12413; // 0x9C: slti x8, x2, -5       (10 < -5 con signo   -> x8 = 0)
        u_stage_if.u_imem.mem[40] = 32'hffb13493; // 0xA0: sltiu x9, x2, -5      (10 < 0xFFFFFFFB u   -> x9 = 1)
        u_stage_if.u_imem.mem[41] = 32'h014db513; // 0xA4: sltiu x10, x27, 20    (0xFFFFFFF6 < 20 u   -> x10 = 0)
        u_stage_if.u_imem.mem[42] = 32'hffbdb593; // 0xA8: sltiu x11, x27, -5    (0xFFFFFFF6 < 0xFFFFFFFB u -> x11 = 1)
        u_stage_if.u_imem.mem[43] = 32'h002d9613; // 0xAC: slli x12, x27, 2      (0xFFFFFFF6 << 2     -> x12 = 0xFFFFFFD8)
        u_stage_if.u_imem.mem[44] = 32'h002d96b3; // 0xB0: sll x13, x27, x2      (0xFFFFFFF6 << 10    -> x13 = 0xFFFFD800)
        u_stage_if.u_imem.mem[45] = 32'h01bd9733; // 0xB4: sll x14, x27, x27     (0xFFFFFFF6 << 22    -> x14 = 0xFD800000)

        // -- Bloque 7: Sub-palabra (SB, SH, LB, LBU, LH, LHU) con Negativos y Offsets 0..3 --
        u_stage_if.u_imem.mem[46] = 32'hf8000793; // 0xB8: addi x15, x0, -128    (x15 = 0xFFFFFF80)
        u_stage_if.u_imem.mem[47] = 32'hed400813; // 0xBC: addi x16, x0, -300    (x16 = 0xFFFFFED4)
        u_stage_if.u_imem.mem[48] = 32'h00200623; // 0xC0: sb x2, 12(x0)         (ram[3][7:0]   = 0x0A)
        u_stage_if.u_imem.mem[49] = 32'h00f006a3; // 0xC4: sb x15, 13(x0)        (ram[3][15:8]  = 0x80)
        u_stage_if.u_imem.mem[50] = 32'h01001723; // 0xC8: sh x16, 14(x0)        (ram[3][31:16] = 0xFED4 -> ram[3]=0xFED4800A)
        u_stage_if.u_imem.mem[51] = 32'h00c02883; // 0xCC: lw x17, 12(x0)        (x17 = 0xFED4800A)
        u_stage_if.u_imem.mem[52] = 32'h00d00903; // 0xD0: lb x18, 13(x0)        (x18 = 0xFFFFFF80, extensión de signo)
        u_stage_if.u_imem.mem[53] = 32'h00d04983; // 0xD4: lbu x19, 13(x0)       (x19 = 0x00000080, extensión con ceros)
        u_stage_if.u_imem.mem[54] = 32'h00e01a03; // 0xD8: lh x20, 14(x0)        (x20 = 0xFFFFFED4, extensión de signo)
        u_stage_if.u_imem.mem[55] = 32'h00e05a83; // 0xDC: lhu x21, 14(x0)       (x21 = 0x0000FED4, extensión con ceros)
        u_stage_if.u_imem.mem[56] = 32'h00f00b03; // 0xE0: lb x22, 15(x0)        (x22 = 0xFFFFFFFE, byte 3 con signo)
        u_stage_if.u_imem.mem[57] = 32'h00f04b83; // 0xE4: lbu x23, 15(x0)       (x23 = 0x000000FE, byte 3 sin signo)

        // -- Bloque 8: Riesgos con Stall (Load-Use, ALU->BEQ, Load->BEQ, ALU->JALR, Load->JALR) --
        u_stage_if.u_imem.mem[58] = 32'h00002c03; // 0xE8:  lw x24, 0(x0)        (x24 = 0x0000000A)
        u_stage_if.u_imem.mem[59] = 32'h005c0c93; // 0xEC:  addi x25, x24, 5     (1 stall Load-Use -> x25 = 0x0000000F)
        u_stage_if.u_imem.mem[60] = 32'h00f00e13; // 0xF0:  addi x28, x0, 15     (x28 = 0x0000000F)
        u_stage_if.u_imem.mem[61] = 32'h019e0463; // 0xF4:  beq x28, x25, 8      (1 stall ALU->BEQ -> salta a 0xFC)
        u_stage_if.u_imem.mem[62] = 32'h06300e13; // 0xF8:  addi x28, x0, 99     (Descartada por flush)
        u_stage_if.u_imem.mem[63] = 32'h00002e83; // 0xFC:  lw x29, 0(x0)        (x29 = 0x0000000A)
        u_stage_if.u_imem.mem[64] = 32'h002e8463; // 0x100: beq x29, x2, 8       (2 stalls Load->BEQ -> salta a 0x108)
        u_stage_if.u_imem.mem[65] = 32'h06300e93; // 0x104: addi x29, x0, 99     (Descartada por flush)
        u_stage_if.u_imem.mem[66] = 32'h11400f13; // 0x108: addi x30, x0, 276    (x30 = 0x00000114)
        u_stage_if.u_imem.mem[67] = 32'h000f0067; // 0x10C: jalr x0, x30, 0      (1 stall ALU->JALR -> salta a 0x114)
        u_stage_if.u_imem.mem[68] = 32'h06300f13; // 0x110: addi x30, x0, 99     (Descartada por flush)
        u_stage_if.u_imem.mem[69] = 32'h12800f13; // 0x114: addi x30, x0, 296    (x30 = 0x00000128)
        u_stage_if.u_imem.mem[70] = 32'h01e02823; // 0x118: sw x30, 16(x0)       (Guarda 0x128 en ram[4])
        u_stage_if.u_imem.mem[71] = 32'h01002f83; // 0x11C: lw x31, 16(x0)       (x31 = 0x00000128)
        u_stage_if.u_imem.mem[72] = 32'h000f8d67; // 0x120: jalr x26, x31, 0     (2 stalls Load->JALR -> salta a 0x128, x26=0x124)
        u_stage_if.u_imem.mem[73] = 32'h06300f93; // 0x124: addi x31, x0, 99     (Descartada por flush)
        u_stage_if.u_imem.mem[74] = 32'h06400f93; // 0x128: addi x31, x0, 100    (x31 = 0x00000064 -> Fin exitoso)
        u_stage_if.u_imem.mem[75] = 32'h00000063; // 0x12C: beq x0, x0, 0        (Bucle final de parada en 0x12C)
        u_stage_if.u_imem.mem[76] = 32'h00000013; // 0x130: nop

        // Finalización extendida para permitir que todo el pipeline procese el programa
        #1100;
        $finish;
    end

    // =========================================================================
    // Monitorización por Consola
    // =========================================================================
    initial begin
        $display("===========================================================================================================================");
        $display("   Time |       IF Stage        |       ID Stage        |     EX Stage     |    MEM Stage     |          WB Stage          ");
        $display("===========================================================================================================================");
    end

    always @(negedge clk) begin
        if (!rst) begin
            #1;
            $display("%7t | PC:%4h Inst:%8h | PC:%4h Inst:%8h | ALU_Res:%8h RS1:%8h RS2:%8h | MemData:%8h MemWr:%b | RegWr:%b RD:%2d Data:%8h",
                $time, 
                if_pc[15:0], if_instr,                                   // IF
                if_id_pc[15:0], if_id_instr,                             // ID
                ex_alu_result, id_ex_rs1_data, id_ex_rs2_data,           // EX
                mem_read_data, ex_mem_m_mem_write,                       // MEM
                wb_reg_write_final, wb_rd_final, wb_write_data           // WB
            );
        end
    end

endmodule
`default_nettype wire
