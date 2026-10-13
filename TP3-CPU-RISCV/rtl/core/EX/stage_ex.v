`timescale 1ns / 1ps
`default_nettype none

module stage_ex (
    // -------------------------------------------------------------------------
    // Entradas desde la etapa ID (a través del registro ID/EX)
    // -------------------------------------------------------------------------
    // Señales de Control
    input  wire [2:0]  i_alu_op,      // Código de operación para la ALU
    input  wire        i_alusrc,      // Selecciona entre RS2 y el inmediato

    // Campos de la instrucción
    input  wire [2:0]  i_funct3,      // bits [14:12] de la instrucción
    input  wire        i_funct7_5,    // bit [30] de la instrucción
    input  wire [4:0]  i_rs1,         // Registro fuente 1
    input  wire [4:0]  i_rs2,         // Registro fuente 2

    // Datos
    input  wire [31:0] i_read_data1,  // Dato leído del registro RS1
    input  wire [31:0] i_read_data2,  // Dato leído del registro RS2
    input  wire [31:0] i_imm,         // Valor inmediato extendido

    // -------------------------------------------------------------------------
    // Entradas para Forwarding (Adelantamiento de datos)
    // -------------------------------------------------------------------------
    // Desde el Latch EX/MEM
    input  wire [4:0]  i_ex_mem_rd,
    input  wire        i_ex_mem_regwrite,
    input  wire [31:0] i_ex_mem_alu_result, // Dato más reciente de la ALU

    // Desde el Latch MEM/WB
    input  wire [4:0]  i_mem_wb_rd,
    input  wire        i_mem_wb_regwrite,
    input  wire [31:0] i_mem_wb_data,       // Dato que se va a escribir en registros

    // -------------------------------------------------------------------------
    // Salidas hacia la etapa MEM (a través del registro EX/MEM)
    // -------------------------------------------------------------------------
    output wire [31:0] o_alu_result,  // Resultado calculado por la ALU
    output wire [31:0] o_rs2_data     // Dato de RS2 (ya adelantado) para instrucciones Store
);

    // -------------------------------------------------------------------------
    // Cables de interconexión interna
    // -------------------------------------------------------------------------
    wire [1:0]  w_forward_a;
    wire [1:0]  w_forward_b;
    wire [3:0]  w_alu_ctrl;
    wire [31:0] w_mux3_a_out;
    wire [31:0] w_mux3_b_out;
    wire [31:0] w_mux2_b_out;

    // El dato a guardar en memoria (Store) es el resultado de RS2 con adelantamiento
    assign o_rs2_data = w_mux3_b_out;

    // -------------------------------------------------------------------------
    // Instanciación de la Forwarding Unit
    // -------------------------------------------------------------------------
    forwarding_unit u_forwarding_unit (
        .i_id_ex_rs1       (i_rs1),
        .i_id_ex_rs2       (i_rs2),
        .i_ex_mem_rd       (i_ex_mem_rd),
        .i_ex_mem_regwrite (i_ex_mem_regwrite),
        .i_mem_wb_rd       (i_mem_wb_rd),
        .i_mem_wb_regwrite (i_mem_wb_regwrite),
        .o_forward_a       (w_forward_a),
        .o_forward_b       (w_forward_b)
    );

    // -------------------------------------------------------------------------
    // Selección del Operando A de la ALU (ForwardA)
    // -------------------------------------------------------------------------
    // En la lógica de la forwarding_unit: 
    // 2'b10 (i_d2) corresponde al riesgo EX (dato más reciente en EX/MEM)
    // 2'b01 (i_d1) corresponde al riesgo MEM (dato en MEM/WB)
    // 2'b00 (i_d0) corresponde al dato original leído del banco de registros
    mux3 #(32) u_mux3_forward_a (
        .i_sel (w_forward_a),
        .i_d0  (i_read_data1),         // Sin adelantamiento
        .i_d1  (i_mem_wb_data),        // Adelantamiento desde MEM/WB (01)
        .i_d2  (i_ex_mem_alu_result),  // Adelantamiento desde EX/MEM (10)
        .o_out (w_mux3_a_out)
    );

    // -------------------------------------------------------------------------
    // Selección del Operando B de la ALU (Paso 1: ForwardB)
    // -------------------------------------------------------------------------
    mux3 #(32) u_mux3_forward_b (
        .i_sel (w_forward_b),
        .i_d0  (i_read_data2),         // Sin adelantamiento
        .i_d1  (i_mem_wb_data),        // Adelantamiento desde MEM/WB (01)
        .i_d2  (i_ex_mem_alu_result),  // Adelantamiento desde EX/MEM (10)
        .o_out (w_mux3_b_out)
    );

    // -------------------------------------------------------------------------
    // Selección del Operando B de la ALU (Paso 2: ALUSrc)
    // -------------------------------------------------------------------------
    // Si i_alusrc = 0 -> Toma el dato de registro (con posible adelantamiento)
    // Si i_alusrc = 1 -> Toma el inmediato
    mux2 #(32) u_mux2_alusrc (
        .i_sel (i_alusrc),
        .i_d0  (w_mux3_b_out), 
        .i_d1  (i_imm),
        .o_out (w_mux2_b_out)
    );

    // -------------------------------------------------------------------------
    // Instanciación del Control de la ALU
    // -------------------------------------------------------------------------
    alu_control u_alu_control (
        .i_alu_op   (i_alu_op),
        .i_funct3   (i_funct3),
        .i_funct7_5 (i_funct7_5),
        .o_alu_ctrl (w_alu_ctrl)
    );

    // -------------------------------------------------------------------------
    // Instanciación de la ALU Principal
    // -------------------------------------------------------------------------
    // El operando A ingresa directamente luego del mux de forwarding.
    // El operando B ingresa luego del mux2 controlado por ALUSrc.
    alu #(
        .NB_IN  (32),
        .NB_OUT (32),
        .NB_OP  (4)
    ) u_alu (
        .i_a         (w_mux3_a_out), 
        .i_b         (w_mux2_b_out), 
        .i_op        (w_alu_ctrl),
        .o_outresult (o_alu_result)
    );

endmodule
`default_nettype wire