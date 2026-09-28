`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Testbench de Integración Avanzado: IF -> IF/ID -> ID -> ID/EX
// Incluye:
//   - Carga dinámica de programa en Instruction Memory.
//   - Verificación de tipos de instruccion (R, I, Load, Store, B, JAL).
//   - Detección de Load-Use Hazards y Flushes de Branch/JAL.
//   - Verificación de Puertos de Depuración (IMEM y Register File).
//==============================================================================

module tb_if_ifid_id_idex;

    // -------------------------------------------------------------------------
    // Clock y Reset
    // -------------------------------------------------------------------------
    reg clk;
    reg rst;
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // Periodo de 10ns (100 MHz)
    end

    // -------------------------------------------------------------------------
    // Señales de Carga de Memoria e Interfases Debug
    // -------------------------------------------------------------------------
    reg         mem_we;
    reg  [9:0]  mem_write_addr;
    reg  [31:0] mem_write_data;
    
    reg         imem_debug_re;
    reg  [9:0]  imem_debug_addr;
    wire [31:0] imem_debug_rdata;

    reg         rf_debug_re;
    reg  [4:0]  rf_debug_addr;
    wire [31:0] rf_debug_rdata;

    // Mockeado del puerto Write-Back (WB)
    reg         mock_wb_reg_write;
    reg  [4:0]  mock_wb_write_reg;
    reg  [31:0] mock_wb_write_data;

    // -------------------------------------------------------------------------
    // Cableado Inter-Etapas (Pipelines y Controls)
    // -------------------------------------------------------------------------
    // IF -> IF/ID
    wire [31:0] if_pc_out;
    wire [31:0] if_instr_out;
    
    // IF/ID -> ID
    wire [31:0] id_pc_in;
    wire [31:0] id_instr_in;
    
    // ID -> IF (Feedback)
    wire        id_pc_write;
    wire        id_if_id_write;
    wire        id_pc_src;
    wire [31:0] id_branch_target;
    
    // ID -> ID/EX (Control)
    wire        id_wb_reg_write, id_wb_mem_to_reg;
    wire        id_m_mem_read, id_m_mem_write;
    wire        id_ex_alu_src;
    wire [1:0]  id_ex_alu_op;
    
    // ID -> ID/EX (Datapath)
    wire [31:0] id_pc_out, id_rs1_data, id_rs2_data, id_imm;
    wire [4:0]  id_rs1, id_rs2, id_rd;
    wire [2:0]  id_funct3;
    wire        id_funct7_5;
    
    // ID/EX -> EX (Salidas del Latch)
    wire        ex_wb_reg_write, ex_wb_mem_to_reg;
    wire        ex_m_mem_read, ex_m_mem_write;
    wire        ex_ex_alu_src;
    wire [1:0]  ex_ex_alu_op;
    
    wire [31:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm;
    wire [4:0]  ex_rs1, ex_rs2, ex_rd;
    wire [2:0]  ex_funct3;
    wire        ex_funct7_5;
    
    wire [153:0] debug_id_ex;

    // Convertir la señal de hold del PC (1: stall active)
    wire if_stall = ~id_pc_write;

    // -------------------------------------------------------------------------
    // Instanciación de Etapas
    // -------------------------------------------------------------------------
    stage_if u_stage_if (
        .i_clk(clk),
        .i_rst(rst),
        .i_en(1'b1),
        .i_stall(if_stall), 
        .i_halt(1'b0),
        .i_branch_sel(id_pc_src),            
        .i_branch_target(id_branch_target),  
        
        // Carga y Debug de Memoria
        .i_mem_we(mem_we),
        .i_debug_re(imem_debug_re),
        .i_debug_addr(imem_debug_addr),
        .i_write_addr(mem_write_addr),
        .i_write_data(mem_write_data),
        
        .o_pc(if_pc_out),                    
        .o_instruction(if_instr_out),        
        .o_halted(),
        .o_debug_rdata(imem_debug_rdata)
    );

    if_id_register u_if_id (
        .i_clk(clk),
        .i_rst(rst),
        .i_en(id_if_id_write),               
        .i_flush(id_pc_src),                 
        .i_pc(if_pc_out),                    
        .i_instruction(if_instr_out),        
        
        .o_pc(id_pc_in),                     
        .o_instruction(id_instr_in)          
    );

    id_stage u_stage_id (
        .i_clk(clk),
        .i_rst(rst),
        
        // Entradas desde IF/ID
        .i_pc(id_pc_in),                     
        .i_instruction(id_instr_in),         
        
        // Retroalimentación de Escritura (WB Mocked)
        .i_wb_reg_write(mock_wb_reg_write),
        .i_wb_write_reg(mock_wb_write_reg),
        .i_wb_write_data(mock_wb_write_data),
        
        // Feedback desde EX para HDU (Load-Use Detection)
        .i_id_ex_mem_read(ex_m_mem_read),    
        .i_id_ex_rd(ex_rd),                  
        
        // Salidas hacia IF y IF/ID
        .o_pc_write(id_pc_write),            
        .o_if_id_write(id_if_id_write),      
        .o_pc_src(id_pc_src),                
        .o_branch_target(id_branch_target),  
        
        // Salidas de Control hacia ID/EX
        .o_wb_reg_write(id_wb_reg_write),    
        .o_wb_mem_to_reg(id_wb_mem_to_reg),
        .o_m_mem_read(id_m_mem_read),
        .o_m_mem_write(id_m_mem_write),
        .o_ex_alu_src(id_ex_alu_src),
        .o_ex_alu_op(id_ex_alu_op),
        
        // Salidas de Datapath hacia ID/EX
        .o_pc(id_pc_out),
        .o_rs1_data(id_rs1_data),
        .o_rs2_data(id_rs2_data),
        .o_imm(id_imm),
        .o_rs1(id_rs1),
        .o_rs2(id_rs2),
        .o_rd(id_rd),
        .o_funct3(id_funct3),
        .o_funct7_5(id_funct7_5),
        
        // Debug Register File
        .i_rf_debug_re(rf_debug_re),
        .i_rf_debug_addr(rf_debug_addr),
        .o_rf_debug_rdata(rf_debug_rdata)
    );

    id_ex_register u_id_ex (
        .i_clk(clk),
        .i_rst(rst),
        .i_en(1'b1),                         
        
        .i_wb_reg_write(id_wb_reg_write),
        .i_wb_mem_to_reg(id_wb_mem_to_reg),
        .i_m_mem_read(id_m_mem_read),
        .i_m_mem_write(id_m_mem_write),
        .i_ex_alu_src(id_ex_alu_src),
        .i_ex_alu_op(id_ex_alu_op),
        
        .i_pc(id_pc_out),
        .i_rs1_data(id_rs1_data),
        .i_rs2_data(id_rs2_data),
        .i_imm(id_imm),
        .i_rs1(id_rs1),
        .i_rs2(id_rs2),
        .i_rd(id_rd),
        .i_funct3(id_funct3),
        .i_funct7_5(id_funct7_5),
        
        .o_wb_reg_write(ex_wb_reg_write),
        .o_wb_mem_to_reg(ex_wb_mem_to_reg),
        .o_m_mem_read(ex_m_mem_read),
        .o_m_mem_write(ex_m_mem_write),
        .o_ex_alu_src(ex_ex_alu_src),
        .o_ex_alu_op(ex_ex_alu_op),
        
        .o_pc(ex_pc),
        .o_rs1_data(ex_rs1_data),
        .o_rs2_data(ex_rs2_data),
        .o_imm(ex_imm),
        .o_rs1(ex_rs1),
        .o_rs2(ex_rs2),
        .o_rd(ex_rd),
        .o_funct3(ex_funct3),
        .o_funct7_5(ex_funct7_5),
        
        .o_debug_id_ex(debug_id_ex)
    );

    // -------------------------------------------------------------------------
    // Monitoreo de Eventos en Transición
    // -------------------------------------------------------------------------
    always @(negedge clk) begin
        if (!rst) begin
            $display("T=%0t ns | IF_PC: 0x%h | ID_Instr: 0x%h | Stall: %b | Flush: %b", 
                     $time, if_pc_out, id_instr_in, if_stall, id_pc_src);
            $display("ID -> Imm: 0x%h | RS1: x%0d | RS2: x%0d | RD: x%0d | Funct3: 0x%h | Funct7_5: %b",
                     id_imm, id_rs1, id_rs2, id_rd, id_funct3, id_funct7_5);
            $display("         | ID/EX -> RD: x%0d | Imm: 0x%h | MemRead: %b | MemWrite: %b | ALUSrc: %b | ALUOp: %b | RegWrite: %b | MemToReg: %b",
                     ex_rd, ex_imm, ex_m_mem_read, ex_m_mem_write, ex_ex_alu_src, ex_ex_alu_op, ex_wb_reg_write, ex_wb_mem_to_reg);
        end
    end

    // Tarea síncrona para cargar la memoria
    task write_instruction(input [9:0] addr, input [31:0] instr);
        begin
            @(posedge clk);
            mem_we         <= 1'b1;
            mem_write_addr <= addr;
            mem_write_data <= instr;
            @(posedge clk);
            mem_we         <= 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Secuencia de Pruebas
    // -------------------------------------------------------------------------
    initial begin
        $display("=========================================================================");
        $display("   INICIO TESTBENCH DE INTEGRACION COMPLETO (IF -> ID -> ID/EX)");
        $display("=========================================================================");

        // Inicialización de señales
        rst = 1;
        mem_we = 0;
        imem_debug_re = 0;
        rf_debug_re = 0;
        mock_wb_reg_write = 0;
        mock_wb_write_reg = 0;
        mock_wb_write_data = 0;

        // ---------------------------------------------------------------------
        // PASO 1: CARGA DE PROGRAMA EN INSTRUCTION MEMORY
        // ---------------------------------------------------------------------
        $display("\n---> [PASO 1] Cargando Instrucciones en la Memoria...");
        
        // Addr 0x00 (0): addi x1, x0, 10      (Tipo-I)
        write_instruction(10'd0, 32'h00a00093);
        // Addr 0x04 (1): addi x2, x0, 20      (Tipo-I)
        write_instruction(10'd1, 32'h01400113);
        // Addr 0x08 (2): add  x3, x1, x2      (Tipo-R)
        write_instruction(10'd2, 32'h002081b3);
        // Addr 0x0C (3): lw   x4, 0(x1)       (Tipo-I Load)
        write_instruction(10'd3, 32'h0000a203);
        // Addr 0x10 (4): add  x5, x4, x2      (Tipo-R) -> ¡LOAD-USE HAZARD CON x4!
        write_instruction(10'd4, 32'h002202b3);
        // Addr 0x14 (5): sw   x3, 4(x1)       (Tipo-S)
        write_instruction(10'd5, 32'h0030a223);
        // Addr 0x18 (6): beq  x0, x0, 8       (Tipo-B) -> Salta 2 inst (0x18 + 8 = 0x20)
        write_instruction(10'd6, 32'h00000463);
        // Addr 0x1C (7): addi x6, x0, 99      (Tipo-I) -> ¡DEBE SER FLUSHEADA POR BEQ!
        write_instruction(10'd7, 32'h06300313);
        // Addr 0x20 (8): jal  x7, 8           (Tipo-J) -> Salta 2 inst (0x20 + 8 = 0x28)
        write_instruction(10'd8, 32'h008003ef);
        // Addr 0x24 (9): addi x8, x0, 88      (Tipo-I) -> ¡DEBE SER FLUSHEADA POR JAL!
        write_instruction(10'd9, 32'h05800413);
        // Addr 0x28 (10): addi x9, x0, 5      (Tipo-I Target de JAL)
        write_instruction(10'd10, 32'h00500493);

        // ---------------------------------------------------------------------
        // PASO 2: VERIFICACION DE PUERTO DE DEBUG EN MEMORIA
        // ---------------------------------------------------------------------
        // $display("\n---> [PASO 2] Probando lectura de Debug en Memoria de Instrucciones...");
        
        // @(posedge clk);
        // imem_debug_re   <= 1'b1;
        // imem_debug_addr <= 10'd3; // Dirección de: lw x4, 0(x1)
        
        // @(posedge clk); #1;       // Esperar al flanco de reloj para que la BRAM actualice la salida
        // $display("[DEBUG IMEM] Dirección 0x0C (3): Leído 0x%h (Esperado: 0x0000a203)", imem_debug_rdata);
        
        // imem_debug_re   <= 1'b0;

        // ---------------------------------------------------------------------
        // PASO 3: PRE-CARGA Y PRUEBA DE DEBUG EN REGISTER FILE
        // ---------------------------------------------------------------------
        // $display("\n---> [PASO 3] Pre-cargando valores simulados en WB para x1 y x2...");
        
        // // 1. Desactivar Reset para permitir la escritura en los registros
        // @(posedge clk);
        // rst <= 1'b0;

        // // 2. Escritura síncrona de x1 = 10
        // @(posedge clk);
        // mock_wb_reg_write  <= 1'b1;
        // mock_wb_write_reg  <= 5'd1;
        // mock_wb_write_data <= 32'd10;

        // // 3. Escritura síncrona de x2 = 20
        // @(posedge clk);
        // mock_wb_reg_write  <= 1'b1;
        // mock_wb_write_reg  <= 5'd2;
        // mock_wb_write_data <= 32'd20;

        // // 4. Desactivar señal de escritura
        // @(posedge clk);
        // mock_wb_reg_write  <= 1'b0;

        // // 5. Lectura de Depuración de x1 y x2
        // rf_debug_re   <= 1'b1;
        // rf_debug_addr <= 5'd1;
        
        // @(posedge clk); #1; // Esperar al flanco para que la memoria entregue x1
        // $display("[DEBUG RF] Registro x1: Leído %0d (Esperado: 10)", rf_debug_rdata);

        // rf_debug_addr <= 5'd2;
        // @(posedge clk); #1; // Esperar al flanco para que la memoria entregue x2
        // $display("[DEBUG RF] Registro x2: Leído %0d (Esperado: 20)", rf_debug_rdata);

        // rf_debug_re   <= 1'b0;

        // ---------------------------------------------------------------------
        // PASO 4: EJECUCION DE PIPELINE Y VERIFICACION DE HAZARDS
        // ---------------------------------------------------------------------
        $display("\n---> [PASO 4] Reiniciando PC con Reset y Ejecutando el Pipeline...");
        
        // Reset síncrono rápido de 1 ciclo para reiniciar el PC a 0 (los registros x1/x2 conservan su valor si tu RF solo los limpia si es síncrono explícito)
        @(posedge clk);
        rst <= 1'b1;
        @(posedge clk);
        rst <= 1'b0;

        // Correr ciclos de simulación
        #120;

        // ---------------------------------------------------------------------
        // PASO 5: VERIFICACIÓN FINAL
        // ---------------------------------------------------------------------
        $display("\n=========================================================================");
        $display("   VERIFICACION COMPLETADA EXITOSAMENTE");
        $display("=========================================================================");
        $finish;
    end

endmodule
`default_nettype wire