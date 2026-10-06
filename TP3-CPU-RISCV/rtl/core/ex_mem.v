`timescale 1ns / 1ps
`default_nettype none

module ex_mem_latch #(
    parameter DEBUG_WIDTH = 75 // Ancho total de bits empaquetados para debug
)(
    input  wire        clk,
    input  wire        rst,
    
    // Control de flujo para Debug / Stall
    // i_enable = 1: El pipeline avanza normalmente.
    // i_enable = 0: El latch congela su estado para que la UART pueda transmitirlo.
    input  wire        i_enable,

    // --------------------------------------------------------
    // Entradas desde la etapa EX (Execution)
    // --------------------------------------------------------
    // Señales de Control (WB)
    input  wire        i_wb_regwrite,
    input  wire        i_wb_memtoreg,

    // Señales de Control (M)
    input  wire        i_m_memread,
    input  wire        i_m_memwrite,

    // Datos y direcciones
    input  wire [31:0] i_alu_result,
    input  wire [31:0] i_rs2_data,
    input  wire [4:0]  i_rd,

    // --------------------------------------------------------
    // Salidas hacia la etapa MEM (Memory)
    // --------------------------------------------------------
    output reg         o_wb_regwrite,
    output reg         o_wb_memtoreg,

    output reg         o_m_memread,
    output reg         o_m_memwrite,

    output reg  [31:0] o_alu_result,
    output reg  [31:0] o_rs2_data,
    output reg  [4:0]  o_rd

    // --------------------------------------------------------
    // Salida para la Unidad de UART / Debug
    // --------------------------------------------------------
    // output wire [DEBUG_WIDTH-1:0] o_debug_ex_mem
);

    // Lógica secuencial del registro pipeline con Enable
    always @(posedge clk) begin
        if (rst) begin
            // Reset sincrónico: Limpia todas las señales
            o_wb_regwrite <= 1'b0;
            o_wb_memtoreg <= 1'b0;

            o_m_memread   <= 1'b0;
            o_m_memwrite  <= 1'b0;

            o_alu_result  <= 32'b0;
            o_rs2_data    <= 32'b0;
            o_rd          <= 5'b0;
        end 
        else if (i_enable) begin
            // Solo actualiza si el pipeline está habilitado
            o_wb_regwrite <= i_wb_regwrite;
            o_wb_memtoreg <= i_wb_memtoreg;

            o_m_memread   <= i_m_memread;
            o_m_memwrite  <= i_m_memwrite;

            o_alu_result  <= i_alu_result;
            o_rs2_data    <= i_rs2_data;
            o_rd          <= i_rd;
        end
        // Si i_enable es 0, los registros mantienen su valor actual (Hold)
    end

    // Empaquetado de todos los bits del latch en un único vector continuo
    // Total = 1 + 1 + 1 + 1 + 1 + 32 + 1 + 32 + 5 = 75 bits
    // assign o_debug_ex_mem = {
    //     o_wb_regwrite, // [74]
    //     o_wb_memtoreg, // [73]
    //     o_m_branch,    // [72]
    //     o_m_memread,   // [71]
    //     o_m_memwrite,  // [70]
    //     o_alu_result,  // [69:38]
    //     o_alu_zero,    // [37]
    //     o_rs2_data,    // [36:5]
    //     o_rd           // [4:0]
    // };

endmodule
`default_nettype wire