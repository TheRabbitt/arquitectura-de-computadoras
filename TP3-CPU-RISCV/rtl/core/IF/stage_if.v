`timescale 1ns / 1ps
`default_nettype none

module stage_if #(
    parameter NB_PC      = 32,
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 32
)(
    input  wire                  i_clk,
    input  wire                  i_rst,
    
    // Control del flujo del programa
    input  wire                  i_en,          // Habilitación global de la etapa
    input  wire                  i_stall,       // Congela el PC (desde Hazard Unit)
    input  wire                  i_halt,        // Parada definitiva
    input  wire                  i_branch_sel,  // Selección de salto (desde etapa ID/EX)
    input  wire [NB_PC-1:0]      i_branch_target,
    
    // Puertos de Debug / Programación de Memoria (UART)
    input  wire                  i_mem_we,
    input  wire                  i_debug_re,
    input  wire [ADDR_WIDTH-1:0] i_debug_addr,
    input  wire [ADDR_WIDTH-1:0] i_write_addr,
    input  wire [DATA_WIDTH-1:0] i_write_data,
    
    // Salidas hacia el registro IF/ID
    output wire [NB_PC-1:0]      o_pc,
    output wire [DATA_WIDTH-1:0] o_instruction,
    
    // Salidas de Estado / Debug
    output wire                  o_halted,
    output wire [DATA_WIDTH-1:0] o_debug_rdata
);

    // Cables internos de la etapa
    wire [NB_PC-1:0] w_pc_plus_4;
    wire [NB_PC-1:0] w_next_pc;
    wire [NB_PC-1:0] w_pc_actual;

    // Registro PC
    registro_pc #(.NB_PC(NB_PC)) u_pc (
        .i_clk     (i_clk),
        .i_rst     (i_rst),
        .i_en      (i_en),
        .i_stall   (i_stall),
        .i_halt    (i_halt),
        .i_next_pc (w_next_pc),
        .o_pc      (w_pc_actual),
        .o_halted  (o_halted)
    );

    // Sumador PC + 4
    sumador #(.NB_SUM(NB_PC)) u_adder_pc4 (
        .i_a      (w_pc_actual),
        .i_b      (32'd4),
        .o_result (w_pc_plus_4)
    );

    // MUX para seleccionar PC secuencial o Salto
    mux2 #(.NB(NB_PC)) u_mux_next_pc (
        .i_sel (i_branch_sel),
        .i_d0  (w_pc_plus_4),
        .i_d1  (i_branch_target),
        .o_out (w_next_pc)
    );

    // Memoria de Instrucciones
    InstructionMemory #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_imem (
        .i_clk         (i_clk),
        .i_pc          (w_pc_actual),
        .i_read_enable (1'b1),           // Lectura constante
        .o_instruction (o_instruction),
        .i_write_en    (i_mem_we),
        .i_debug_re    (i_debug_re),
        .i_debug_addr  (i_debug_addr),
        .i_write_addr  (i_write_addr),
        .i_write_data  (i_write_data),
        .o_debug_rdata (o_debug_rdata)
    );

    // Asignación de salida directa hacia el registro IF/ID
    assign o_pc = w_pc_actual;

endmodule
`default_nettype wire