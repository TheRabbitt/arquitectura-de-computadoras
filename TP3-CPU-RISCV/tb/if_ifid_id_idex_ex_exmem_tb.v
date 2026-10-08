`timescale 1ns / 1ps
`default_nettype none

module tb_if_ifid_id_idex_ex_exmem;

    // -------------------------------------------------------------------------
    // Parámetros Globales
    // -------------------------------------------------------------------------
    localparam CLK_PERIOD = 10; // Reloj de 100 MHz (10ns)

    // -------------------------------------------------------------------------
    // Señales Globales de Control y Reloj
    // -------------------------------------------------------------------------
    reg clk;
    reg rst;

    // Contador de ciclos para el reporte de consola
    integer cycle_count = 0;

    // -------------------------------------------------------------------------
    // Cables de Interconexión: Etapa IF -> Latch IF/ID
    // -------------------------------------------------------------------------
    wire [31:0] w_if_pc;
    wire [31:0] w_if_instruction;
    wire        w_if_halted;
    wire [31:0] w_if_debug_rdata;

    // Señales de programación de memoria de instrucciones (Carga vía UART)
    reg         tb_mem_we;
    reg  [9:0]  tb_write_addr;
    reg  [31:0] tb_write_data;

    // -------------------------------------------------------------------------
    // Cables de Interconexión: Latch IF/ID -> Etapa ID
    // -------------------------------------------------------------------------
    wire [31:0] w_if_id_pc;
    wire [31:0] w_if_id_instruction;

    // -------------------------------------------------------------------------
    // Cables de Interconexión: Etapa ID -> Latch ID/EX y Etapa IF
    // -------------------------------------------------------------------------
    wire        w_id_pc_write;
    wire        w_id_if_id_write;
    wire        w_id_pc_src;
    wire [31:0] w_id_branch_target;

    // Control hacia ID/EX
    wire        w_id_wb_reg_write;
    wire        w_id_wb_mem_to_reg;
    wire        w_id_m_mem_read;
    wire        w_id_m_mem_write;
    wire        w_id_ex_alu_src;
    wire [2:0]  w_id_ex_alu_op;

    // Datapath hacia ID/EX
    wire [31:0] w_id_pc_out;
    wire [31:0] w_id_rs1_data;
    wire [31:0] w_id_rs2_data;
    wire [31:0] w_id_imm;
    wire [4:0]  w_id_rs1;
    wire [4:0]  w_id_rs2;
    wire [4:0]  w_id_rd;
    wire [2:0]  w_id_funct3;
    wire        w_id_funct7_5;

    // Debug Register File
    reg         tb_rf_debug_re;
    reg  [4:0]  tb_rf_debug_addr;
    wire [31:0] w_rf_debug_rdata;

    // -------------------------------------------------------------------------
    // Cables de Interconexión: Latch ID/EX -> Etapa EX
    // -------------------------------------------------------------------------
    wire        w_id_ex_wb_reg_write;
    wire        w_id_ex_wb_mem_to_reg;
    wire        w_id_ex_m_mem_read;
    wire        w_id_ex_m_mem_write;
    wire        w_id_ex_alu_src_out;
    wire [2:0]  w_id_ex_alu_op_out;

    wire [31:0] w_id_ex_pc;
    wire [31:0] w_id_ex_rs1_data;
    wire [31:0] w_id_ex_rs2_data;
    wire [31:0] w_id_ex_imm;
    wire [4:0]  w_id_ex_rs1;
    wire [4:0]  w_id_ex_rs2;
    wire [4:0]  w_id_ex_rd;
    wire [2:0]  w_id_ex_funct3;
    wire        w_id_ex_funct7_5;
    wire [153:0] w_debug_id_ex;

    // -------------------------------------------------------------------------
    // Cables de Interconexión: Etapa EX -> Latch EX/MEM
    // -------------------------------------------------------------------------
    wire [31:0] w_ex_alu_result;
    wire [31:0] w_ex_rs2_data;

    // -------------------------------------------------------------------------
    // Cables de Interconexión: Latch EX/MEM -> Salida (Etapa MEM)
    // -------------------------------------------------------------------------
    wire        w_ex_mem_wb_regwrite;
    wire        w_ex_mem_wb_memtoreg;
    wire        w_ex_mem_m_memread;
    wire        w_ex_mem_m_memwrite;
    wire [31:0] w_ex_mem_alu_result;
    wire [31:0] w_ex_mem_rs2_data;
    wire [4:0]  w_ex_mem_rd;

    // -------------------------------------------------------------------------
    // Retroalimentación Simulada de la Etapa WB (Write-Back)
    // -------------------------------------------------------------------------
    reg        r_mem_wb_reg_write;
    reg [4:0]  r_mem_wb_rd;
    reg [31:0] r_mem_wb_data;

    // Simple simulación del anillo Write-Back para escribir en Register File
    always @(posedge clk) begin
        if (rst) begin
            r_mem_wb_reg_write <= 1'b0;
            r_mem_wb_rd        <= 5'b0;
            r_mem_wb_data      <= 32'b0;
        end else begin
            r_mem_wb_reg_write <= w_ex_mem_wb_regwrite;
            r_mem_wb_rd        <= w_ex_mem_rd;
            // Si es un Load Word simula dato desde memoria, si no el resultado de la ALU
            r_mem_wb_data      <= (w_ex_mem_wb_memtoreg) ? 32'h000000DE : w_ex_mem_alu_result;
        end
    end

    // -------------------------------------------------------------------------
    // Instanciación de Etapas y Latches del Pipeline
    // -------------------------------------------------------------------------

    // Etapa Instruction Fetch (IF)
    stage_if #(
        .NB_PC(32),
        .ADDR_WIDTH(10),
        .DATA_WIDTH(32)
    ) u_stage_if (
        .i_clk           (clk),
        .i_rst           (rst),
        .i_en            (1'b1),
        .i_stall         (~w_id_pc_write),      // Congela PC cuando HDU indica stall
        .i_halt          (1'b0),
        .i_branch_sel    (w_id_pc_src),        // Toma el salto cuando BEQ/BNE o JAL es tomado
        .i_branch_target (w_id_branch_target),
        .i_mem_we        (tb_mem_we),
        .i_debug_re      (1'b0),
        .i_debug_addr    (10'b0),
        .i_write_addr    (tb_write_addr),
        .i_write_data    (tb_write_data),
        .o_pc            (w_if_pc),
        .o_instruction   (w_if_instruction),
        .o_halted        (w_if_halted),
        .o_debug_rdata   (w_if_debug_rdata)
    );

    // Latch IF/ID
    if_id_register #(
        .NB(32),
        .NOP_INSTR(32'h00000013) // NOP: addi x0, x0, 0
    ) u_if_id_register (
        .i_clk         (clk),
        .i_rst         (rst),
        .i_en          (w_id_if_id_write),  // Controlado por HDU
        .i_flush       (w_id_pc_src),       // Flush cuando se confirma salto en ID
        .i_pc          (w_if_pc),
        .i_instruction (w_if_instruction),
        .o_pc          (w_if_id_pc),
        .o_instruction (w_if_id_instruction)
    );

    // Etapa Instruction Decode (ID)
    id_stage u_stage_id (
        .i_clk            (clk),
        .i_rst            (rst),
        .i_pc             (w_if_id_pc),
        .i_instruction    (w_if_id_instruction),
        .i_wb_reg_write   (r_mem_wb_reg_write),
        .i_wb_write_reg   (r_mem_wb_rd),
        .i_wb_write_data  (r_mem_wb_data),
        .i_id_ex_mem_read (w_id_ex_m_mem_read),
        .i_id_ex_rd       (w_id_ex_rd),
        .o_pc_write       (w_id_pc_write),
        .o_if_id_write    (w_id_if_id_write),
        .o_pc_src         (w_id_pc_src),
        .o_branch_target  (w_id_branch_target),
        .o_wb_reg_write   (w_id_wb_reg_write),
        .o_wb_mem_to_reg  (w_id_wb_mem_to_reg),
        .o_m_mem_read     (w_id_m_mem_read),
        .o_m_mem_write    (w_id_m_mem_write),
        .o_ex_alu_src     (w_id_ex_alu_src),
        .o_ex_alu_op      (w_id_ex_alu_op),
        .o_pc             (w_id_pc_out),
        .o_rs1_data       (w_id_rs1_data),
        .o_rs2_data       (w_id_rs2_data),
        .o_imm            (w_id_imm),
        .o_rs1            (w_id_rs1),
        .o_rs2            (w_id_rs2),
        .o_rd             (w_id_rd),
        .o_funct3         (w_id_funct3),
        .o_funct7_5       (w_id_funct7_5),
        .i_rf_debug_re    (tb_rf_debug_re),
        .i_rf_debug_addr  (tb_rf_debug_addr),
        .o_rf_debug_rdata (w_rf_debug_rdata)
    );

    // Latch ID/EX
    id_ex_register #(
        .NB_DATA(32),
        .NB_REG(5)
    ) u_id_ex_register (
        .i_clk           (clk),
        .i_rst           (rst),
        .i_en            (1'b1),
        .i_wb_reg_write  (w_id_wb_reg_write),
        .i_wb_mem_to_reg (w_id_wb_mem_to_reg),
        .i_m_mem_read    (w_id_m_mem_read),
        .i_m_mem_write   (w_id_m_mem_write),
        .i_ex_alu_src    (w_id_ex_alu_src),
        .i_ex_alu_op     (w_id_ex_alu_op),
        .i_pc            (w_id_pc_out),
        .i_rs1_data      (w_id_rs1_data),
        .i_rs2_data      (w_id_rs2_data),
        .i_imm           (w_id_imm),
        .i_rs1           (w_id_rs1),
        .i_rs2           (w_id_rs2),
        .i_rd            (w_id_rd),
        .i_funct3        (w_id_funct3),
        .i_funct7_5      (w_id_funct7_5),
        .o_wb_reg_write  (w_id_ex_wb_reg_write),
        .o_wb_mem_to_reg (w_id_ex_wb_mem_to_reg),
        .o_m_mem_read    (w_id_ex_m_mem_read),
        .o_m_mem_write   (w_id_ex_m_mem_write),
        .o_ex_alu_src    (w_id_ex_alu_src_out),
        .o_ex_alu_op     (w_id_ex_alu_op_out),
        .o_pc            (w_id_ex_pc),
        .o_rs1_data      (w_id_ex_rs1_data),
        .o_rs2_data      (w_id_ex_rs2_data),
        .o_imm           (w_id_ex_imm),
        .o_rs1           (w_id_ex_rs1),
        .o_rs2           (w_id_ex_rs2),
        .o_rd            (w_id_ex_rd),
        .o_funct3        (w_id_ex_funct3),
        .o_funct7_5      (w_id_ex_funct7_5),
        .o_debug_id_ex   (w_debug_id_ex)
    );

    // Etapa Execute (EX)
    stage_ex u_stage_ex (
        .i_alu_op            (w_id_ex_alu_op_out),
        .i_alusrc            (w_id_ex_alu_src_out),
        .i_funct3            (w_id_ex_funct3),
        .i_funct7_5          (w_id_ex_funct7_5),
        .i_rs1               (w_id_ex_rs1),
        .i_rs2               (w_id_ex_rs2),
        .i_read_data1        (w_id_ex_rs1_data),
        .i_read_data2        (w_id_ex_rs2_data),
        .i_imm               (w_id_ex_imm),
        .i_ex_mem_rd         (w_ex_mem_rd),
        .i_ex_mem_regwrite   (w_ex_mem_wb_regwrite),
        .i_ex_mem_alu_result (w_ex_mem_alu_result),
        .i_mem_wb_rd         (r_mem_wb_rd),
        .i_mem_wb_regwrite   (r_mem_wb_reg_write),
        .i_mem_wb_data       (r_mem_wb_data),
        .o_alu_result        (w_ex_alu_result),
        .o_rs2_data          (w_ex_rs2_data)
    );

    // Latch EX/MEM
    ex_mem_latch #(
        .DEBUG_WIDTH(75)
    ) u_ex_mem_latch (
        .clk           (clk),
        .rst           (rst),
        .i_enable      (1'b1),
        .i_wb_regwrite (w_id_ex_wb_reg_write),
        .i_wb_memtoreg (w_id_ex_wb_mem_to_reg),
        .i_m_memread   (w_id_ex_m_mem_read),
        .i_m_memwrite  (w_id_ex_m_mem_write),
        .i_alu_result  (w_ex_alu_result),
        .i_rs2_data    (w_ex_rs2_data),
        .i_rd          (w_id_ex_rd),
        .o_wb_regwrite (w_ex_mem_wb_regwrite),
        .o_wb_memtoreg (w_ex_mem_wb_memtoreg),
        .o_m_memread   (w_ex_mem_m_memread),
        .o_m_memwrite  (w_ex_mem_m_memwrite),
        .o_alu_result  (w_ex_mem_alu_result),
        .o_rs2_data    (w_ex_mem_rs2_data),
        .o_rd          (w_ex_mem_rd)
    );

    // -------------------------------------------------------------------------
    // Generador de Reloj
    // -------------------------------------------------------------------------
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Función auxiliar para formatear la mnemónica en consola
    // -------------------------------------------------------------------------
    function [8*12:1] get_mnemonic(input [31:0] inst);
        begin
            if (inst == 32'h00000013) get_mnemonic = "NOP / STALL";
            else case (inst[6:0])
                7'b0110111: get_mnemonic = "LUI";
                7'b0010011: get_mnemonic = "ADDI";
                7'b0110011: get_mnemonic = (inst[30]) ? "SUB" : "ADD";
                7'b0000011: get_mnemonic = "LW";
                7'b0100011: get_mnemonic = "SW";
                7'b1100011: get_mnemonic = "BEQ";
                default:    get_mnemonic = "OTRA";
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Tarea para cargar una instrucción en la memoria
    // -------------------------------------------------------------------------
    task load_instruction(input [9:0] word_addr, input [31:0] instr);
        begin
            tb_mem_we     = 1'b1;
            tb_write_addr = word_addr;
            tb_write_data = instr;
            #CLK_PERIOD;
            tb_mem_we     = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Secuencia Principal de Simulación
    // -------------------------------------------------------------------------
    initial begin
        $display("==========================================================================================");
        $display("                INICIO DE SIMULACION DE INTEGRACION PIPELINE (5 ETAPAS)                   ");
        $display("==========================================================================================");

        // Inicialización
        clk = 0;
        rst = 1;
        tb_mem_we = 0;
        tb_write_addr = 0;
        tb_write_data = 0;
        tb_rf_debug_re = 0;
        tb_rf_debug_addr = 0;

        #15;
        // ---------------------------------------------------------------------
        // CARGA DE PROGRAMA DE PRUEBA REAL EN MEMORIA DE INSTRUCCIONES
        // ---------------------------------------------------------------------
        // 0x00: LUI x1, 0x12345        -> x1 = 0x12345000 (Operación LUI)
        load_instruction(10'd0, 32'h123450b7);

        // 0x04: ADDI x2, x0, 10        -> x2 = 10 (Operación con inmediato ALUSrc=1)
        load_instruction(10'd1, 32'h00a00113);

        // 0x08: ADD x3, x1, x2         -> x3 = x1 + x2 (Riesgo de datos -> Forwarding desde EX/MEM y MEM/WB)
        load_instruction(10'd2, 32'h002081b3);

        // 0x0C: LW x4, 0(x2)           -> x4 = Mem[10] (Instrucción de Carga / Load Word)
        load_instruction(10'd3, 32'h00012203);

        // 0x10: ADD x5, x4, x2         -> Usa x4 inmediatamente (Load-Use Hazard -> HDU debe insertar STALL)
        load_instruction(10'd4, 32'h002202b3);

        // 0x14: SW x3, 4(x2)           -> Mem[10+4] = x3 (Store Word)
        load_instruction(10'd5, 32'h00312223);

        // 0x18: SUB x6, x3, x2         -> x6 = x3 - x2 (Resta R-type)
        load_instruction(10'd6, 32'h40218333);

        // 0x1C: BEQ x2, x2, 8          -> Salta a PC + 8 = 0x24 (Salto tomado -> Debe hacer FLUSH de 0x20)
        load_instruction(10'd7, 32'h00210463);

        // 0x20: ADDI x7, x0, 99        -> Instrucción víctima de FLUSH (No debe ejecutarse)
        load_instruction(10'd8, 32'h06300393);

        // 0x24: ADDI x8, x2, 5         -> Target del Salto (x8 = 10 + 5 = 15)
        load_instruction(10'd9, 32'h00510413);

        // Liberar Reset
        rst = 1'b0;
        $display("[INFO] Reset liberado. Iniciando ejecucion de instrucciones...");
        $display("------------------------------------------------------------------------------------------");
    end

    // -------------------------------------------------------------------------
    // Monitoreo de Señales Internas de Forwarding (Ruta Jerárquica)
    // Se accede a los cables w_forward_a y w_forward_b dentro de u_stage_ex
    // -------------------------------------------------------------------------
    wire [1:0] monitor_fwd_a = u_stage_ex.w_forward_a; 
    wire [1:0] monitor_fwd_b = u_stage_ex.w_forward_b;

    // -------------------------------------------------------------------------
    // Monitoreo Ciclo a Ciclo de cada Etapa del Pipeline
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst) begin
            cycle_count = cycle_count + 1;
            $display("\n>>> CICLO DE RELOJ %0d (Time: %0t ns) <<<", cycle_count, $time);
            
            // Etapa IF
            $display(" [IF]     PC: 0x%08h | Instr: 0x%08h (%-11s)", 
                     w_if_pc, w_if_instruction, get_mnemonic(w_if_instruction));

            // Etapa ID
            $display(" [ID]     PC: 0x%08h | Instr: 0x%08h (%-11s) | RS1: x%0d, RS2: x%0d, RD: x%0d | Imm: 0x%0h", 
                     w_if_id_pc, w_if_id_instruction, get_mnemonic(w_if_id_instruction),
                     w_id_rs1, w_id_rs2, w_id_rd, w_id_imm);

            // Detección visual de Stall o Flush en ID
            if (!w_id_pc_write) 
                $display("          *** [HDU] LOAD-USE HAZARD DETECTADO -> INSERTANDO STALL (BUBBLE) ***");
            if (w_id_pc_src) 
                $display("          *** [BRANCH TAKEN] SALTO TOMADO -> FLUSH EN LATCH IF/ID ***");

            // Etapa EX
            $display(" [EX]     PC: 0x%08h | RD: x%0d | ALU_Src: %b | ALU_Result: 0x%08h | RS1_Val: 0x%0h, RS2_Val: 0x%0h | RegWrite: %b | MemWrite: %b", 
                     w_id_ex_pc, w_id_ex_rd, w_id_ex_alu_src_out, w_ex_alu_result, w_id_ex_rs1_data, w_id_ex_rs2_data, w_id_ex_wb_reg_write, w_id_ex_m_mem_write);

            // Reporte dinámico de Forwarding en etapa EX
            if (monitor_fwd_a == 2'b10)
                $display("          *** [FORWARDING] RS1 <- Adelantando dato desde EX/MEM ***");
            else if (monitor_fwd_a == 2'b01)
                $display("          *** [FORWARDING] RS1 <- Adelantando dato desde MEM/WB ***");

            if (monitor_fwd_b == 2'b10)
                $display("          *** [FORWARDING] RS2 <- Adelantando dato desde EX/MEM ***");
            else if (monitor_fwd_b == 2'b01)
                $display("          *** [FORWARDING] RS2 <- Adelantando dato desde MEM/WB ***");

            // Etapa MEM (Latch EX/MEM)
            $display(" [MEM]    RD: x%0d | RegWrite: %b | MemWrite: %b | MemToReg: %b | ALU_Result: 0x%08h | Data_Store: 0x%08h", 
                     w_ex_mem_rd, w_ex_mem_wb_regwrite, w_ex_mem_m_memwrite, w_ex_mem_wb_memtoreg, w_ex_mem_alu_result, w_ex_mem_rs2_data);

            // Finalización de la prueba tras 16 ciclos
            if (cycle_count == 16) begin
                $display("\n==========================================================================================");
                $display("                    PRUEBA DE INTEGRACION PIPELINE COMPLETADA                             ");
                $display("==========================================================================================");
                $finish;
            end
        end
    end

endmodule
`default_nettype wire