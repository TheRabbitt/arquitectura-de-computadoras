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
    
    // IF/ID -> ID
    wire [31:0] if_id_pc;
    wire [31:0] if_id_pc_plus_4;
    wire [31:0] if_id_instr;

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

    // EX -> EX/MEM
    wire [31:0] ex_alu_result, ex_rs2_data, ex_pc_plus_4;
    wire        ex_wb_jump;

    // EX/MEM -> MEM
    wire        ex_mem_wb_reg_write, ex_mem_wb_mem_to_reg, ex_mem_wb_jump;
    wire        ex_mem_m_mem_read, ex_mem_m_mem_write;
    wire [31:0] ex_mem_alu_result, ex_mem_rs2_data, ex_mem_pc_plus_4;
    wire [4:0]  ex_mem_rd;

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

    // =========================================================================
    // Instanciación de Etapas y Registros
    // =========================================================================

    stage_if u_stage_if (
        .i_clk(clk), .i_rst(rst), .i_en(enable),
        .i_stall(~id_pc_write), .i_halt(1'b0),
        .i_branch_sel(id_pc_src), .i_branch_target(id_branch_target),
        .i_mem_we(1'b0), .i_debug_re(1'b0), .i_debug_addr(10'b0), 
        .i_write_addr(10'b0), .i_write_data(32'b0),
        .o_pc(if_pc), .o_pc_plus_4(if_pc_plus_4), .o_instruction(if_instr), .o_halted(if_halted), .o_debug_rdata()
    );

    if_id_register u_if_id (
        .i_clk(clk), .i_rst(rst), .i_en(id_if_id_write),
        .i_flush(id_pc_src), .i_pc(if_pc), .i_pc_plus_4(if_pc_plus_4), .i_instruction(if_instr),
        .o_pc(if_id_pc), .o_pc_plus_4(if_id_pc_plus_4), .o_instruction(if_id_instr)
    );

    id_stage u_stage_id (
        .i_clk(clk), .i_rst(rst), .i_pc(if_id_pc), .i_pc_plus_4(if_id_pc_plus_4), .i_instruction(if_id_instr),
        .i_wb_reg_write(wb_reg_write_final), .i_wb_write_reg(wb_rd_final), .i_wb_write_data(wb_write_data),
        .i_id_ex_mem_read(id_ex_m_mem_read), .i_id_ex_reg_write(id_ex_wb_reg_write), .i_id_ex_rd(id_ex_rd),
        .i_ex_mem_reg_write(ex_mem_wb_reg_write), .i_ex_mem_mem_read(ex_mem_m_mem_read),
        .i_ex_mem_rd(ex_mem_rd), .i_ex_mem_alu_result(ex_mem_alu_result),
        .o_pc_write(id_pc_write), .o_if_id_write(id_if_id_write), .o_pc_src(id_pc_src), .o_branch_target(id_branch_target),
        .o_wb_reg_write(id_wb_reg_write), .o_wb_mem_to_reg(id_wb_mem_to_reg),
        .o_m_mem_read(id_m_mem_read), .o_m_mem_write(id_m_mem_write),
        .o_ex_alu_src(id_ex_alu_src), .o_ex_alu_op(id_ex_alu_op),
        .o_pc(id_pc_out), .o_pc_plus_4(id_pc_plus_4), .o_rs1_data(id_rs1_data), .o_rs2_data(id_rs2_data), .o_imm(id_imm),
        .o_rs1(id_rs1), .o_rs2(id_rs2), .o_rd(id_rd),
        .o_funct3(id_funct3), .o_funct7_5(id_funct7_5), .o_wb_jump(id_wb_jump),
        .i_rf_debug_re(1'b0), .i_rf_debug_addr(5'b0), .o_rf_debug_rdata()
    );

    id_ex_register u_id_ex (
        .i_clk(clk), .i_rst(rst), .i_en(enable),
        .i_wb_reg_write(id_wb_reg_write), .i_wb_mem_to_reg(id_wb_mem_to_reg),
        .i_m_mem_read(id_m_mem_read), .i_m_mem_write(id_m_mem_write),
        .i_ex_alu_src(id_ex_alu_src), .i_ex_alu_op(id_ex_alu_op),
        .i_pc(id_pc_out), .i_pc_plus_4(id_pc_plus_4), .i_rs1_data(id_rs1_data), .i_rs2_data(id_rs2_data), .i_imm(id_imm),
        .i_rs1(id_rs1), .i_rs2(id_rs2), .i_rd(id_rd),
        .i_funct3(id_funct3), .i_funct7_5(id_funct7_5), .i_wb_jump(id_wb_jump),
        .o_wb_reg_write(id_ex_wb_reg_write), .o_wb_mem_to_reg(id_ex_wb_mem_to_reg),
        .o_m_mem_read(id_ex_m_mem_read), .o_m_mem_write(id_ex_m_mem_write),
        .o_ex_alu_src(id_ex_ex_alu_src), .o_ex_alu_op(id_ex_ex_alu_op),
        .o_pc(id_ex_pc), .o_pc_plus_4(id_ex_pc_plus_4), .o_rs1_data(id_ex_rs1_data), .o_rs2_data(id_ex_rs2_data), .o_imm(id_ex_imm),
        .o_rs1(id_ex_rs1), .o_rs2(id_ex_rs2), .o_rd(id_ex_rd),
        .o_funct3(id_ex_funct3), .o_funct7_5(id_ex_funct7_5), .o_wb_jump(id_ex_wb_jump)
        // .o_debug_id_ex()
    );

    stage_ex u_stage_ex (
        .i_alu_op(id_ex_ex_alu_op), .i_alusrc(id_ex_ex_alu_src),
        .i_funct3(id_ex_funct3), .i_funct7_5(id_ex_funct7_5),
        .i_rs1(id_ex_rs1), .i_rs2(id_ex_rs2),
        .i_read_data1(id_ex_rs1_data), .i_read_data2(id_ex_rs2_data), .i_imm(id_ex_imm), .i_pc_plus_4(id_ex_pc_plus_4), .i_wb_jump(id_ex_wb_jump),
        .i_ex_mem_rd(ex_mem_rd), .i_ex_mem_regwrite(ex_mem_wb_reg_write), .i_ex_mem_alu_result(ex_mem_alu_result),
        .i_mem_wb_rd(wb_rd_final), .i_mem_wb_regwrite(wb_reg_write_final), .i_mem_wb_data(wb_write_data),
        .o_alu_result(ex_alu_result), .o_rs2_data(ex_rs2_data), .o_pc_plus_4(ex_pc_plus_4), .o_wb_jump(ex_wb_jump)
    );

    ex_mem_latch u_ex_mem (
        .clk(clk), .rst(rst), .i_enable(enable),
        .i_wb_regwrite(id_ex_wb_reg_write), .i_wb_memtoreg(id_ex_wb_mem_to_reg), .i_wb_jump(id_ex_wb_jump),
        .i_m_memread(id_ex_m_mem_read), .i_m_memwrite(id_ex_m_mem_write),
        .i_alu_result(ex_alu_result), .i_rs2_data(ex_rs2_data), .i_rd(id_ex_rd), .i_pc_plus_4(id_ex_pc_plus_4),
        .o_wb_regwrite(ex_mem_wb_reg_write), .o_wb_memtoreg(ex_mem_wb_mem_to_reg),
        .o_m_memread(ex_mem_m_mem_read), .o_m_memwrite(ex_mem_m_mem_write),
        .o_alu_result(ex_mem_alu_result), .o_rs2_data(ex_mem_rs2_data), .o_rd(ex_mem_rd),
        .o_wb_jump(ex_mem_wb_jump), .o_pc_plus_4(ex_mem_pc_plus_4)
    );

    stage_mem u_stage_mem (
        .i_clk(clk),
        .i_wb_reg_write(ex_mem_wb_reg_write), .i_wb_mem_to_reg(ex_mem_wb_mem_to_reg), .i_wb_jump(ex_mem_wb_jump),
        .i_m_mem_read(ex_mem_m_mem_read), .i_m_mem_write(ex_mem_m_mem_write),
        .i_alu_result(ex_mem_alu_result), .i_rs2_data(ex_mem_rs2_data), .i_rd(ex_mem_rd), .i_pc_plus_4(ex_mem_pc_plus_4),
        .i_debug_re(1'b0), .i_debug_addr(8'b0), .o_debug_rdata(),
        .o_wb_reg_write(mem_wb_reg_write_out), .o_wb_mem_to_reg(mem_wb_mem_to_reg_out), .o_wb_jump(mem_wb_jump),
        .o_read_data(mem_read_data), .o_alu_result(mem_alu_result), .o_rd(mem_rd), .o_pc_plus_4(mem_pc_plus_4)
    );

    mem_wb_latch u_mem_wb (
        .i_clk(clk), .i_rst(rst), .i_enable(enable),
        .i_wb_reg_write(mem_wb_reg_write_out), .i_wb_mem_to_reg(mem_wb_mem_to_reg_out), .i_wb_jump(mem_wb_jump),
        .i_read_data(mem_read_data), .i_alu_result(mem_alu_result), .i_rd(mem_rd), .i_pc_plus_4(mem_pc_plus_4),
        .o_wb_reg_write(wb_reg_write_final), .o_wb_mem_to_reg(wb_mem_to_reg_final), .o_wb_jump(wb_jump_final),
        .o_read_data(wb_read_data_final), .o_alu_result(wb_alu_result_final), .o_rd(wb_rd_final), .o_pc_plus_4(wb_pc_plus_4_final)
    );

    // assign wb_write_data = (wb_mem_to_reg_final) ? wb_read_data_final : wb_alu_result_final;

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

        // -- Bloque 5: Saltos B-Type, J-Type y JALR --
        u_stage_if.u_imem.mem[28] = 32'h016a8463; // 0x70: beq x21, x22, 8       (B-Type) (Salta a 0x78)
        u_stage_if.u_imem.mem[29] = 32'h00000013; // 0x74: nop                   (Ignorado por salto)
        u_stage_if.u_imem.mem[30] = 32'h000a9463; // 0x78: bne x21, x0, 8        (B-Type) (Salta a 0x80)
        u_stage_if.u_imem.mem[31] = 32'h00000013; // 0x7C: nop
        u_stage_if.u_imem.mem[32] = 32'h00800d6f; // 0x80: jal x26, 8            (J-Type) (Salta a 0x88, x26=0x84)
        u_stage_if.u_imem.mem[33] = 32'h00000013; // 0x84: nop
        u_stage_if.u_imem.mem[34] = 32'h000d0067; // 0x88: jalr x0, x26, 0       (I-Type Salto) (Retorna a 0x84)
        u_stage_if.u_imem.mem[35] = 32'h00000013; // 0x8C: nop

        // Finalización extendida para permitir que todo el pipeline procese el programa
        #1000;
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