`timescale 1ns / 1ps
`default_nettype none

module ex_mem_latch #(
    parameter DEBUG_WIDTH = 128 // 4 palabras de 32 bits = 16 bytes para debug
)(
    input  wire        clk,
    input  wire        rst,
    
    // Control de flujo para Debug / Stall
    // i_enable = 1: El pipeline avanza normalmente.
    // i_enable = 0: El latch congela su estado para que la UART pueda transmitirlo.
    input  wire        i_enable,
    input  wire        i_valid,

    // --------------------------------------------------------
    // Entradas desde la etapa EX (Execution)
    // --------------------------------------------------------
    // Señales de Control (WB)
    input  wire        i_wb_regwrite,
    input  wire        i_wb_memtoreg,
    input  wire        i_wb_jump,

    // Señales de Control (M)
    input  wire        i_m_memread,
    input  wire        i_m_memwrite,

    // Datos y direcciones
    input  wire [31:0] i_alu_result,
    input  wire [31:0] i_rs2_data,
    input  wire [4:0]  i_rd,
    input  wire [2:0]  i_funct3,
    input  wire [31:0] i_pc_plus_4,

    // --------------------------------------------------------
    // Salidas hacia la etapa MEM (Memory)
    // --------------------------------------------------------
    output reg         o_wb_regwrite,
    output reg         o_wb_memtoreg,
    output reg         o_wb_jump,
    output reg         o_m_memread,
    output reg         o_m_memwrite,
    output reg         o_valid,

    output reg  [31:0] o_alu_result,
    output reg  [31:0] o_rs2_data,
    output reg  [4:0]  o_rd,
    output reg  [2:0]  o_funct3,
    output reg  [31:0] o_pc_plus_4,

    // --------------------------------------------------------
    // Salida para la Unidad de UART / Debug (4 palabras = 16 bytes)
    // --------------------------------------------------------
    output wire [DEBUG_WIDTH-1:0] o_debug_ex_mem
);

    // Lógica secuencial del registro pipeline con Enable
    always @(posedge clk) begin
        if (rst) begin
            // Reset sincrónico: Limpia todas las señales
            o_wb_regwrite <= 1'b0;
            o_wb_memtoreg <= 1'b0;
            o_wb_jump     <= 1'b0;

            o_m_memread   <= 1'b0;
            o_m_memwrite  <= 1'b0;
            o_valid       <= 1'b0;

            o_alu_result  <= 32'b0;
            o_rs2_data    <= 32'b0;
            o_rd          <= 5'b0;
            o_funct3      <= 3'b0;
            o_pc_plus_4   <= 32'b0;
        end 
        else if (i_enable) begin
            // Solo actualiza si el pipeline está habilitado
            o_wb_regwrite <= i_wb_regwrite;
            o_wb_memtoreg <= i_wb_memtoreg;
            o_wb_jump     <= i_wb_jump;

            o_m_memread   <= i_m_memread;
            o_m_memwrite  <= i_m_memwrite;
            o_valid       <= i_valid;

            o_alu_result  <= i_alu_result;
            o_rs2_data    <= i_rs2_data;
            o_rd          <= i_rd;
            o_funct3      <= i_funct3;
            o_pc_plus_4   <= i_pc_plus_4;
        end
        // Si i_enable es 0, los registros mantienen su valor actual (Hold)
    end

    // Empaquetado alineado a palabras de 32 bits (4 palabras = 16 bytes):
    // Word 0 [31:0]   : o_alu_result
    // Word 1 [63:32]  : o_rs2_data
    // Word 2 [95:64]  : o_pc_plus_4
    // Word 3 [127:96] : {18'd0, o_valid, o_wb_jump, o_wb_memtoreg, o_wb_regwrite,
    //                    o_m_memwrite, o_m_memread, o_funct3, o_rd}
    wire [31:0] w_ctrl_word = {
        18'd0,
        o_valid,       // [13]
        o_wb_jump,     // [12]
        o_wb_memtoreg, // [11]
        o_wb_regwrite, // [10]
        o_m_memwrite,  // [9]
        o_m_memread,   // [8]
        o_funct3,      // [7:5]
        o_rd           // [4:0]
    };

    assign o_debug_ex_mem = {
        w_ctrl_word,
        o_pc_plus_4,
        o_rs2_data,
        o_alu_result
    };

endmodule
`default_nettype wire
