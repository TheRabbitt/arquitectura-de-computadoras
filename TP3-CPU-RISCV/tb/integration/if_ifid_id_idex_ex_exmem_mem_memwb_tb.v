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
    wire        if_halted;
    
    // ID -> IF (Retroalimentación de Control)
    wire        id_pc_write;
    wire        id_if_id_write;
    wire        id_pc_src;          // branch_sel y flush
    wire [31:0] id_branch_target;
    
    // IF/ID -> ID
    wire [31:0] if_id_pc;
    wire [31:0] if_id_instr;

    // WB -> ID (Retroalimentación al Banco de Registros)
    wire [31:0] wb_write_data;
    // (o_wb_reg_write y o_rd de la etapa MEM/WB)

    // ID -> ID/EX
    wire        id_wb_reg_write, id_wb_mem_to_reg;
    wire        id_m_mem_read, id_m_mem_write;
    wire        id_ex_alu_src;
    wire [2:0]  id_ex_alu_op;
    wire [31:0] id_pc_out, id_rs1_data, id_rs2_data, id_imm;
    wire [4:0]  id_rs1, id_rs2, id_rd;
    wire [2:0]  id_funct3;
    wire        id_funct7_5;

    // ID/EX -> EX
    wire        id_ex_wb_reg_write, id_ex_wb_mem_to_reg;
    wire        id_ex_m_mem_read, id_ex_m_mem_write;
    wire        id_ex_ex_alu_src;
    wire [2:0]  id_ex_ex_alu_op;
    wire [31:0] id_ex_pc, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;
    wire [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    wire [2:0]  id_ex_funct3;
    wire        id_ex_funct7_5;

    // EX -> EX/MEM
    wire [31:0] ex_alu_result, ex_rs2_data;

    // EX/MEM -> MEM
    wire        ex_mem_wb_reg_write, ex_mem_wb_mem_to_reg;
    wire        ex_mem_m_mem_read, ex_mem_m_mem_write;
    wire [31:0] ex_mem_alu_result, ex_mem_rs2_data;
    wire [4:0]  ex_mem_rd;

    // MEM -> MEM/WB
    wire        mem_wb_reg_write_out, mem_wb_mem_to_reg_out;
    wire [31:0] mem_read_data, mem_alu_result;
    wire [4:0]  mem_rd;

    // MEM/WB -> Salidas finales (y Forwarding)
    wire        wb_reg_write_final;
    wire        wb_mem_to_reg_final;
    wire [31:0] wb_read_data_final;
    wire [31:0] wb_alu_result_final;
    wire [4:0]  wb_rd_final;

    // =========================================================================
    // Instanciación de Etapas y Registros
    // =========================================================================

    // Etapa Instruction Fetch (IF)
    stage_if u_stage_if (
        .i_clk(clk),
        .i_rst(rst),
        .i_en(enable),
        .i_stall(~id_pc_write),       // 0 = Stall desde HDU
        .i_halt(1'b0),
        .i_branch_sel(id_pc_src),     // Salto desde ID
        .i_branch_target(id_branch_target),
        
        .i_mem_we(1'b0), .i_debug_re(1'b0), .i_debug_addr(10'b0), 
        .i_write_addr(10'b0), .i_write_data(32'b0), // Debug ports sin uso activo
        
        .o_pc(if_pc),
        .o_instruction(if_instr),
        .o_halted(if_halted),
        .o_debug_rdata()
    );

    // Latch IF/ID
    if_id_register u_if_id (
        .i_clk(clk),
        .i_rst(rst),
        .i_en(id_if_id_write),
        .i_flush(id_pc_src), // Flush al saltar
        .i_pc(if_pc),
        .i_instruction(if_instr),
        .o_pc(if_id_pc),
        .o_instruction(if_id_instr)
    );

    // Etapa Instruction Decode (ID)
    id_stage u_stage_id (
        .i_clk(clk),
        .i_rst(rst),
        .i_pc(if_id_pc),
        .i_instruction(if_id_instr),
        
        // Retroalimentación WB
        .i_wb_reg_write(wb_reg_write_final),
        .i_wb_write_reg(wb_rd_final),
        .i_wb_write_data(wb_write_data),
        
        // Entradas para Hazard Detection Unit y Forwarding (desde ID/EX y EX/MEM)
        .i_id_ex_mem_read(id_ex_m_mem_read),
        .i_id_ex_reg_write(id_ex_wb_reg_write),
        .i_id_ex_rd(id_ex_rd),
        
        .i_ex_mem_reg_write(ex_mem_wb_reg_write),
        .i_ex_mem_mem_read(ex_mem_m_mem_read),
        .i_ex_mem_rd(ex_mem_rd),
        .i_ex_mem_alu_result(ex_mem_alu_result),
        
        // Salidas Control
        .o_pc_write(id_pc_write),
        .o_if_id_write(id_if_id_write),
        .o_pc_src(id_pc_src),
        .o_branch_target(id_branch_target),
        
        // Salidas Latch
        .o_wb_reg_write(id_wb_reg_write),
        .o_wb_mem_to_reg(id_wb_mem_to_reg),
        .o_m_mem_read(id_m_mem_read),
        .o_m_mem_write(id_m_mem_write),
        .o_ex_alu_src(id_ex_alu_src),
        .o_ex_alu_op(id_ex_alu_op),
        
        .o_pc(id_pc_out),
        .o_rs1_data(id_rs1_data), .o_rs2_data(id_rs2_data), .o_imm(id_imm),
        .o_rs1(id_rs1), .o_rs2(id_rs2), .o_rd(id_rd),
        .o_funct3(id_funct3), .o_funct7_5(id_funct7_5),
        
        .i_rf_debug_re(1'b0), .i_rf_debug_addr(5'b0), .o_rf_debug_rdata()
    );

    // Latch ID/EX
    id_ex_register u_id_ex (
        .i_clk(clk),
        .i_rst(rst),
        .i_en(enable),
        
        .i_wb_reg_write(id_wb_reg_write), .i_wb_mem_to_reg(id_wb_mem_to_reg),
        .i_m_mem_read(id_m_mem_read), .i_m_mem_write(id_m_mem_write),
        .i_ex_alu_src(id_ex_alu_src), .i_ex_alu_op(id_ex_alu_op),
        
        .i_pc(id_pc_out), .i_rs1_data(id_rs1_data), .i_rs2_data(id_rs2_data), .i_imm(id_imm),
        .i_rs1(id_rs1), .i_rs2(id_rs2), .i_rd(id_rd),
        .i_funct3(id_funct3), .i_funct7_5(id_funct7_5),
        
        .o_wb_reg_write(id_ex_wb_reg_write), .o_wb_mem_to_reg(id_ex_wb_mem_to_reg),
        .o_m_mem_read(id_ex_m_mem_read), .o_m_mem_write(id_ex_m_mem_write),
        .o_ex_alu_src(id_ex_ex_alu_src), .o_ex_alu_op(id_ex_ex_alu_op),
        
        .o_pc(id_ex_pc), .o_rs1_data(id_ex_rs1_data), .o_rs2_data(id_ex_rs2_data), .o_imm(id_ex_imm),
        .o_rs1(id_ex_rs1), .o_rs2(id_ex_rs2), .o_rd(id_ex_rd),
        .o_funct3(id_ex_funct3), .o_funct7_5(id_ex_funct7_5),
        
        .o_debug_id_ex()
    );

    // Etapa Execution (EX)
    stage_ex u_stage_ex (
        .i_alu_op(id_ex_ex_alu_op), .i_alusrc(id_ex_ex_alu_src),
        .i_funct3(id_ex_funct3), .i_funct7_5(id_ex_funct7_5),
        .i_rs1(id_ex_rs1), .i_rs2(id_ex_rs2),
        .i_read_data1(id_ex_rs1_data), .i_read_data2(id_ex_rs2_data), .i_imm(id_ex_imm),
        
        // Forwarding desde EX/MEM
        .i_ex_mem_rd(ex_mem_rd),
        .i_ex_mem_regwrite(ex_mem_wb_reg_write),
        .i_ex_mem_alu_result(ex_mem_alu_result),
        
        // Forwarding desde MEM/WB
        .i_mem_wb_rd(wb_rd_final),
        .i_mem_wb_regwrite(wb_reg_write_final),
        .i_mem_wb_data(wb_write_data),
        
        .o_alu_result(ex_alu_result),
        .o_rs2_data(ex_rs2_data)
    );

    // Latch EX/MEM
    ex_mem_latch u_ex_mem (
        .clk(clk),
        .rst(rst),
        .i_enable(enable),
        
        .i_wb_regwrite(id_ex_wb_reg_write), .i_wb_memtoreg(id_ex_wb_mem_to_reg),
        .i_m_memread(id_ex_m_mem_read), .i_m_memwrite(id_ex_m_mem_write),
        
        .i_alu_result(ex_alu_result), .i_rs2_data(ex_rs2_data), .i_rd(id_ex_rd),
        
        .o_wb_regwrite(ex_mem_wb_reg_write), .o_wb_memtoreg(ex_mem_wb_mem_to_reg),
        .o_m_memread(ex_mem_m_mem_read), .o_m_memwrite(ex_mem_m_mem_write),
        
        .o_alu_result(ex_mem_alu_result), .o_rs2_data(ex_mem_rs2_data), .o_rd(ex_mem_rd)
    );

    // Etapa Memory (MEM)
    stage_mem u_stage_mem (
        .i_clk(clk),
        
        .i_wb_reg_write(ex_mem_wb_reg_write), .i_wb_mem_to_reg(ex_mem_wb_mem_to_reg),
        .i_m_mem_read(ex_mem_m_mem_read), .i_m_mem_write(ex_mem_m_mem_write),
        
        .i_alu_result(ex_mem_alu_result), .i_rs2_data(ex_mem_rs2_data), .i_rd(ex_mem_rd),
        
        .i_debug_re(1'b0), .i_debug_addr(8'b0), .o_debug_rdata(),
        
        .o_wb_reg_write(mem_wb_reg_write_out), .o_wb_mem_to_reg(mem_wb_mem_to_reg_out),
        .o_read_data(mem_read_data), .o_alu_result(mem_alu_result), .o_rd(mem_rd)
    );

    // Latch MEM/WB
    mem_wb_latch u_mem_wb (
        .i_clk(clk),
        .i_rst(rst),
        .i_enable(enable),
        
        .i_wb_reg_write(mem_wb_reg_write_out), .i_wb_mem_to_reg(mem_wb_mem_to_reg_out),
        .i_read_data(mem_read_data), .i_alu_result(mem_alu_result), .i_rd(mem_rd),
        
        .o_wb_reg_write(wb_reg_write_final), .o_wb_mem_to_reg(wb_mem_to_reg_final),
        .o_read_data(wb_read_data_final), .o_alu_result(wb_alu_result_final), .o_rd(wb_rd_final)
    );

    // Lógica Write-Back Mux
    assign wb_write_data = (wb_mem_to_reg_final) ? wb_read_data_final : wb_alu_result_final;

    // =========================================================================
    // Inicialización de Memoria y Tareas de Prueba
    // =========================================================================
    initial begin
        // Reset inicial
        rst = 1;
        #17;
        rst = 0;

        // Carga manual del programa de prueba en la RAM (Instruction Fetch)
        // Programa ensamblado en HEX que prueba: I-Type, R-Type, S-Type, Riesgos y Saltos
        u_stage_if.u_imem.mem[0]  = 32'h00a00093; // 0x00: addi x1, x0, 10      (I-Type)
        u_stage_if.u_imem.mem[1]  = 32'h01400113; // 0x04: addi x2, x0, 20      (I-Type)
        u_stage_if.u_imem.mem[2]  = 32'h002081b3; // 0x08: add  x3, x1, x2      (R-Type - Riesgo EX/EX Forwarding: x3 = 30)
        u_stage_if.u_imem.mem[3]  = 32'h00302023; // 0x0C: sw   x3, 0(x0)       (S-Type - Guardar 30 en addr 0)
        u_stage_if.u_imem.mem[4]  = 32'h00002203; // 0x10: lw   x4, 0(x0)       (I-Type - Cargar 30 en x4)
        u_stage_if.u_imem.mem[5]  = 32'h401202b3; // 0x14: sub  x5, x4, x1      (R-Type - Load-Use Hazard de x4, Stall automático)
        u_stage_if.u_imem.mem[6]  = 32'h00228463; // 0x18: beq  x5, x2, 8       (B-Type - (30-10=20) == 20? Salta a 0x20)
        u_stage_if.u_imem.mem[7]  = 32'h06300313; // 0x1C: addi x6, x0, 99      (Instrucción que será limpiada / FLUSH)
        u_stage_if.u_imem.mem[8]  = 32'h008003ef; // 0x20: jal  x7, 8           (J-Type - Salta a 0x28, x7 = 0x24)
        u_stage_if.u_imem.mem[9]  = 32'h06400313; // 0x24: addi x6, x0, 100     (Instrucción que será limpiada / FLUSH)
        u_stage_if.u_imem.mem[10] = 32'h00038067; // 0x28: jalr x0, x7, 0       (I-Type/Salto - Salta a 0x24)
        u_stage_if.u_imem.mem[11] = 32'h00000013; // 0x2C: nop

        // Finalización automática tras 30 ciclos
        #300;
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

    // Se imprime en el flanco negativo para garantizar que las señales del ciclo ya se hayan establecido
    always @(negedge clk) begin
        if (!rst) begin
            #1; // Pequeño retardo para asegurar que las señales estén estables
            $display("%7t | PC:%4h Inst:%8h | PC:%4h Inst:%8h | ALU_Res:%8h | MemData:%8h MemWr:%b | RegWr:%b RD:%2d Data:%8h",
                $time, 
                if_pc[15:0], if_instr,                         // IF
                if_id_pc[15:0], if_id_instr,                   // ID
                ex_alu_result,                                 // EX
                mem_read_data, ex_mem_m_mem_write,             // MEM
                wb_reg_write_final, wb_rd_final, wb_write_data // WB
            );
        end
    end

endmodule
`default_nettype wire