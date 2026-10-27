`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Testbench de Integración: Etapas IF e ID + Debug Unit + Señales de Control
//==============================================================================

module tb_if_id_integration;

    // -------------------------------------------------------------------------
    // Generación de Reloj y Reset
    // -------------------------------------------------------------------------
    reg clk;
    reg rst;
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // Periodo de 10ns (100 MHz)
    end

    // -------------------------------------------------------------------------
    // Declaración de Señales de Interconexión
    // -------------------------------------------------------------------------
    
    // Señales de la etapa IF
    wire [31:0] next_pc, pc_out, pc_plus_4, if_instr;
    wire pc_src; 

    // Señales de control del pipeline (desde HDU)
    wire pc_write, if_id_write, ctrl_mux_sel;

    // Señales del registro IF/ID
    wire [31:0] id_pc, id_instr;

    // Señales de la etapa ID
    wire [31:0] rs1_data, rs2_data, id_imm, branch_target;
    wire take_branch;
    
    // Señales de la Unidad de Control
    wire id_branch, id_mem_read, id_mem_to_reg, id_mem_write, id_alu_src, id_reg_write;
    wire [1:0] id_alu_op;

    // Señales de Depuración (Memoria de Instrucciones)
    reg         imem_debug_we;
    reg         imem_debug_re;
    reg  [9:0]  imem_debug_addr;
    reg  [31:0] imem_debug_wdata;
    wire [31:0] imem_debug_rdata;

    // Señales de Depuración (Banco de Registros)
    reg         rf_debug_re;
    reg  [4:0]  rf_debug_addr;
    wire [31:0] rf_debug_rdata;

    // -------------------------------------------------------------------------
    // Instanciación del Hardware
    // -------------------------------------------------------------------------

    mux2 #(.NB(32)) mux_next_pc (
        .i_sel(pc_src),
        .i_d0(pc_plus_4),
        .i_d1(branch_target),
        .o_out(next_pc)
    );

    registro_pc #(.NB_PC(32)) pc_reg (
        .i_clk(clk),
        .i_rst(rst),
        .i_en(pc_write),       
        .i_stall(1'b0),
        .i_halt(1'b0),
        .i_next_pc(next_pc),
        .o_pc(pc_out),
        .o_halted()
    );

    sumador #(.NB_SUM(32)) add_pc4 (
        .i_a(pc_out),
        .i_b(32'd4),
        .o_result(pc_plus_4)
    );

    // Memoria de Instrucciones con puertos de Debug conectados
    InstructionMemory imem (
        .i_clk(clk),
        .i_pc(pc_out),
        .i_read_enable(1'b1),
        .o_instruction(if_instr), // Instrucción que está siendo fetcheada
        
        .i_write_en(imem_debug_we),
        .i_debug_re(imem_debug_re),
        .i_debug_addr(imem_debug_addr),
        .i_write_addr(imem_debug_addr),
        .i_write_data(imem_debug_wdata),
        .o_debug_rdata(imem_debug_rdata)
    );

    // Latch Segmentado IF/ID
    if_id_register #(.NB(32)) if_id_latch (
        .i_clk(clk),
        .i_rst(rst),
        .i_en(if_id_write),    
        .i_flush(pc_src),      
        .i_pc(pc_out),
        .i_instruction(if_instr),
        .o_pc(id_pc),
        .o_instruction(id_instr) // Instrucción que cruzó a la etapa ID
    );

    hazard_detection_unit hdu (
        .id_ex_mem_read(1'b0), 
        .id_ex_rd(5'd0),       
        .if_id_rs1(id_instr[19:15]),
        .if_id_rs2(id_instr[24:20]),
        .pc_write(pc_write),
        .if_id_write(if_id_write),
        .ctrl_mux_sel(ctrl_mux_sel)
    );

    control_unit ctrl (
        .i_opcode(id_instr[6:0]),
        .o_branch(id_branch),
        .o_mem_read(id_mem_read),
        .o_mem_to_reg(id_mem_to_reg),
        .o_alu_op(id_alu_op),
        .o_mem_write(id_mem_write),
        .o_alu_src(id_alu_src),
        .o_reg_write(id_reg_write)
    );

    // Banco de Registros con puerto de Debug conectado
    register_file rf (
        .i_clk(clk),
        .i_rst(rst),
        .i_reg_write(1'b0), // Fijo en 0 porque aún no está conectada la etapa Write-Back
        .i_read_reg1(id_instr[19:15]),
        .i_read_reg2(id_instr[24:20]),
        .i_write_reg(5'd0),
        .i_write_data(32'd0),
        .o_read_data1(rs1_data),
        .o_read_data2(rs2_data),
        
        .i_debug_re(rf_debug_re),
        .i_debug_reg_addr(rf_debug_addr),
        .o_debug_reg_data(rf_debug_rdata)
    );

    imm_gen ig (
        .i_instruction(id_instr),
        .o_imm(id_imm)
    );

    branch_comparator bc (
        .i_data1(rs1_data),
        .i_data2(rs2_data),
        .i_funct3(id_instr[14:12]),
        .o_take_branch(take_branch)
    );

    sumador #(.NB_SUM(32)) add_branch_target (
        .i_a(id_pc),
        .i_b(id_imm),
        .o_result(branch_target)
    );

    assign pc_src = id_branch & take_branch;

    // -------------------------------------------------------------------------
    // Monitoreo Dinámico del Pipeline (Impresión en cada ciclo)
    // -------------------------------------------------------------------------
    always @(negedge clk) begin
        if (!rst) begin
            $display("-------------------------------------------------------------------------");
            $display("T=%0t | ETAPA IF -> PC: %h | Instrucción leída: %h", $time, pc_out, if_instr);
            $display("        ETAPA ID -> PC: %h | Instrucción actual: %h", id_pc, id_instr);
            $display("        SEÑALES  -> Branch: %b | MemRead: %b | MemToReg: %b | ALUOp: %b | MemWrite: %b | ALUSrc: %b | RegWrite: %b", 
                     id_branch, id_mem_read, id_mem_to_reg, id_alu_op, id_mem_write, id_alu_src, id_reg_write);
        end
    end

    // -------------------------------------------------------------------------
    // Secuencia de Pruebas y Uso de la Debug Unit
    // -------------------------------------------------------------------------
    initial begin
        $display("=========================================================================");
        $display("                     INICIO TESTBENCH IF e ID                            ");
        $display("=========================================================================");

        // Inicialización
        imem_debug_we = 0; imem_debug_re = 0; imem_debug_addr = 0; imem_debug_wdata = 0;
        rf_debug_re = 0; rf_debug_addr = 0;
        rst = 1;
        #10;
        
        // 1. Cargar programa de prueba variado para disparar todas las señales
        imem_debug_we = 1;
        imem_debug_addr = 10'd0; imem_debug_wdata = 32'h00500093; // ADDI x1, x0, 5 (Tipo I: ALUSrc=1, RegWrite=1)
        #10;
        imem_debug_addr = 10'd1; imem_debug_wdata = 32'h002081b3; // ADD x3, x1, x2 (Tipo R: RegWrite=1, ALUOp=10)
        #10;
        imem_debug_addr = 10'd2; imem_debug_wdata = 32'h00302023; // SW x3, 0(x0)   (Tipo S: ALUSrc=1, MemWrite=1)
        #10;
        imem_debug_addr = 10'd3; imem_debug_wdata = 32'h00002203; // LW x4, 0(x0)   (Tipo I/Load: MemRead=1, MemToReg=1)
        #10;
        imem_debug_addr = 10'd4; imem_debug_wdata = 32'h00208463; // BEQ x1, x2, +8 (Tipo B: Branch=1, ALUOp=01)
        #10;
        imem_debug_addr = 10'd5; imem_debug_wdata = 32'h00000013; // NOP
        #10;
        imem_debug_we = 0;
        
        // 2. Liberar Reset y dejar fluir las instrucciones por el pipeline
        $display("\n>>> ARRANCANDO PIPELINE <<<");
        rst = 0;
        
        // Dejamos correr 7 ciclos (suficiente para que todas las instrucciones pasen por ID)
        #70;

        // 3. Prueba de lectura a través de la Debug Unit (Memoria de Instrucciones)
        $display("\n>>> PRUEBA DE LECTURA DEBUG: MEMORIA DE INSTRUCCIONES <<<");
        imem_debug_re = 1;
        imem_debug_addr = 10'd2; // Vamos a leer la dirección 2 (SW x3, 0(x0))
        #10;
        $display("T=%0t | Debug IMEM -> Dirección: %d | Dato Leído: %h (Esperado: 00302023)", $time, imem_debug_addr, imem_debug_rdata);
        
        imem_debug_addr = 10'd4; // Vamos a leer la dirección 4 (BEQ)
        #10;
        $display("T=%0t | Debug IMEM -> Dirección: %d | Dato Leído: %h (Esperado: 00208463)", $time, imem_debug_addr, imem_debug_rdata);
        imem_debug_re = 0;

        // 4. Prueba de lectura a través de la Debug Unit (Banco de Registros)
        $display("\n>>> PRUEBA DE LECTURA DEBUG: BANCO DE REGISTROS <<<");
        // Nota: Como la etapa WB no está conectada, todos los registros valen 0 en esta simulación.
        rf_debug_re = 1;
        rf_debug_addr = 5'd1; // Leemos x1
        #10;
        $display("T=%0t | Debug RF -> Registro: x%d | Dato Leído: %h (Esperado: 00000000 ya que WB no está)", $time, rf_debug_addr, rf_debug_rdata);
        
        rf_debug_addr = 5'd3; // Leemos x3
        #10;
        $display("T=%0t | Debug RF -> Registro: x%d | Dato Leído: %h (Esperado: 00000000 ya que WB no está)", $time, rf_debug_addr, rf_debug_rdata);
        rf_debug_re = 0;
        
        $display("\n=========================================================================");
        $display("                        FIN DEL TESTBENCH                                ");
        $display("=========================================================================");
        $finish;
    end

endmodule
`default_nettype wire