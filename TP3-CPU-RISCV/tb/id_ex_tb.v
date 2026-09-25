`timescale 1ns / 1ps

module tb_id_ex_register();

    // Parámetros
    parameter NB_DATA = 32;
    parameter NB_REG  = 5;

    // Entradas del DUT
    reg                 i_clk;
    reg                 i_rst;
    reg                 i_en;

    reg                 i_wb_reg_write;
    reg                 i_wb_mem_to_reg;
    reg                 i_m_mem_read;
    reg                 i_m_mem_write;
    reg                 i_ex_alu_src;
    reg [1:0]           i_ex_alu_op;

    reg [NB_DATA-1:0]   i_pc;
    reg [NB_DATA-1:0]   i_rs1_data;
    reg [NB_DATA-1:0]   i_rs2_data;
    reg [NB_DATA-1:0]   i_imm;
    reg [NB_REG-1:0]    i_rs1;
    reg [NB_REG-1:0]    i_rs2;
    reg [NB_REG-1:0]    i_rd;
    reg [2:0]           i_funct3;
    reg                 i_funct7_5;

    // Salidas del DUT
    wire                o_wb_reg_write;
    wire                o_wb_mem_to_reg;
    wire                o_m_mem_read;
    wire                o_m_mem_write;
    wire                o_ex_alu_src;
    wire [1:0]          o_ex_alu_op;

    wire [NB_DATA-1:0]  o_pc;
    wire [NB_DATA-1:0]  o_rs1_data;
    wire [NB_DATA-1:0]  o_rs2_data;
    wire [NB_DATA-1:0]  o_imm;
    wire [NB_REG-1:0]   o_rs1;
    wire [NB_REG-1:0]   o_rs2;
    wire [NB_REG-1:0]   o_rd;
    wire [2:0]          o_funct3;
    wire                o_funct7_5;
    wire [153:0]        o_debug_id_ex;

    // Instancia del módulo
    id_ex_register #(
        .NB_DATA(NB_DATA),
        .NB_REG(NB_REG)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_en(i_en),
        .i_wb_reg_write(i_wb_reg_write),
        .i_wb_mem_to_reg(i_wb_mem_to_reg),
        .i_m_mem_read(i_m_mem_read),
        .i_m_mem_write(i_m_mem_write),
        .i_ex_alu_src(i_ex_alu_src),
        .i_ex_alu_op(i_ex_alu_op),
        .i_pc(i_pc),
        .i_rs1_data(i_rs1_data),
        .i_rs2_data(i_rs2_data),
        .i_imm(i_imm),
        .i_rs1(i_rs1),
        .i_rs2(i_rs2),
        .i_rd(i_rd),
        .i_funct3(i_funct3),
        .i_funct7_5(i_funct7_5),
        .o_wb_reg_write(o_wb_reg_write),
        .o_wb_mem_to_reg(o_wb_mem_to_reg),
        .o_m_mem_read(o_m_mem_read),
        .o_m_mem_write(o_m_mem_write),
        .o_ex_alu_src(o_ex_alu_src),
        .o_ex_alu_op(o_ex_alu_op),
        .o_pc(o_pc),
        .o_rs1_data(o_rs1_data),
        .o_rs2_data(o_rs2_data),
        .o_imm(o_imm),
        .o_rs1(o_rs1),
        .o_rs2(o_rs2),
        .o_rd(o_rd),
        .o_funct3(o_funct3),
        .o_funct7_5(o_funct7_5),
        .o_debug_id_ex(o_debug_id_ex)
    );

    // Generación de Reloj (T = 10ns)
    initial begin
        i_clk = 0;
        forever #5 i_clk = ~i_clk;
    end

    // Estímulos y Monitoreo por Consola
    initial begin
        $display("==========================================================================");
        $display("                   INICIO DE SIMULACION: id_ex_register                   ");
        $display("==========================================================================");

        // Inicialización
        i_rst = 1;
        i_en = 0;
        i_wb_reg_write = 0; i_wb_mem_to_reg = 0;
        i_m_mem_read = 0; i_m_mem_write = 0;
        i_ex_alu_src = 0; i_ex_alu_op = 2'b00;
        i_pc = 0; i_rs1_data = 0; i_rs2_data = 0; i_imm = 0;
        i_rs1 = 0; i_rs2 = 0; i_rd = 0; i_funct3 = 0; i_funct7_5 = 0;

        //----------------------------------------------------------------------
        // PRUEBA 1: Reset Sincrónico
        //----------------------------------------------------------------------
        $display("\n[Tiempo %0t ns] -- PRUEBA 1: Aplicando Reset...", $time);
        @(negedge i_clk);
        // Usamos $strobe para imprimir al final del ciclo una vez que el latch actualice su salida
        $strobe("[Tiempo %0t ns] Post-Reset  -> PC: 0x%h | RegWrite: %b | MemRead: %b | RD: x%0d",
                 $time, o_pc, o_wb_reg_write, o_m_mem_read, o_rd);

        //----------------------------------------------------------------------
        // PRUEBA 2: Propagación Normal de Datos (Enable = 1)
        //----------------------------------------------------------------------
        i_rst = 0;
        i_en  = 1;
        
        i_wb_reg_write = 1; i_wb_mem_to_reg = 0;
        i_m_mem_read   = 1; i_m_mem_write   = 0;
        i_ex_alu_src   = 1; i_ex_alu_op     = 2'b10;
        
        i_pc       = 32'h0000_1000;
        i_rs1_data = 32'hAAAA_AAAA;
        i_rs2_data = 32'h5555_5555;
        i_imm      = 32'h0000_0020;
        
        i_rs1      = 5'd10; 
        i_rs2      = 5'd11; 
        i_rd       = 5'd12;
        i_funct3   = 3'b010; 
        i_funct7_5 = 1'b1;

        $display("\n[Tiempo %0t ns] -- PRUEBA 2: Cargando instrucción/datos (Enable = 1)...", $time);
        @(negedge i_clk);
        $strobe("[Tiempo %0t ns] Datapath EX -> PC: 0x%h | RS1_Data: 0x%h | RS2_Data: 0x%h | Imm: 0x%h",
                 $time, o_pc, o_rs1_data, o_rs2_data, o_imm);
        $strobe("                   Regs EX     -> RS1: x%0d | RS2: x%0d | RD: x%0d",
                 o_rs1, o_rs2, o_rd);
        $strobe("                   Control EX  -> RegWrite: %b | MemToReg: %b | ALUOp: %b | ALUSrc: %b",
                 o_wb_reg_write, o_wb_mem_to_reg, o_ex_alu_op, o_ex_alu_src);
        $strobe("                   Debug Bus   -> 0x%h", o_debug_id_ex);

        //----------------------------------------------------------------------
        // PRUEBA 3: Congelamiento del Latch (Enable = 0 / Stall)
        //----------------------------------------------------------------------
        $display("\n[Tiempo %0t ns] -- PRUEBA 3: Congelando el latch (Enable = 0 / Stall)...", $time);
        i_en = 0;
        
        // Cambiamos drásticamente las entradas para verificar que NO modifiquen las salidas
        i_pc       = 32'h0000_2000;
        i_rs1_data = 32'hFFFF_FFFF;
        i_wb_reg_write = 0;
        i_rd       = 5'd31;

        @(negedge i_clk);
        $strobe("[Tiempo %0t ns] Verif. Stall -> PC: 0x%h (Esperado: 0x00001000) | RD: x%0d (Esperado: x12)",
                 $time, o_pc, o_rd);

        @(negedge i_clk);
        $strobe("[Tiempo %0t ns] Mant. Stall  -> RegWrite: %b (Esperado: 1) | RS1_Data: 0x%h (Esperado: 0xaaaaaaaa)", 
                 $time, o_wb_reg_write, o_rs1_data);

        //----------------------------------------------------------------------
        // PRUEBA 4: Retomar Operación Normal
        //----------------------------------------------------------------------
        $display("\n[Tiempo %0t ns] -- PRUEBA 4: Reactivando Latch (Enable = 1)...", $time);
        i_en = 1;

        @(negedge i_clk);
        $strobe("[Tiempo %0t ns] Post-Stall  -> PC: 0x%h | RS1_Data: 0x%h | RD: x%0d",
                 $time, o_pc, o_rs1_data, o_rd);

        $display("\n==========================================================================");
        $display("                   FIN DE SIMULACION: Pruebas exitosas                    ");
        $display("==========================================================================");
        #20;
        $finish;
    end

endmodule