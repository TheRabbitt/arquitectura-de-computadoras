`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: id_ex_register
// Descripción: Latch/Registro de Pipeline entre las etapas ID (Instruction Decode)
//              y EX (Execute) para un procesador RISC-V de 5 etapas.
//              Almacena las señales de control (WB, M, EX), bit de validez y
//              datos del datapath. Incluye bus de depuración (o_debug_id_ex).
//==============================================================================

module id_ex_register #(
    parameter NB_DATA = 32,
    parameter NB_REG  = 5
)(
    input  wire                 i_clk,
    input  wire                 i_rst,
    input  wire                 i_en,      // Enable/Stall (1: actualiza, 0: congela el latch)
    input  wire                 i_valid,   // Indica si la instrucción que entra desde ID es válida

    // -------------------------------------------------------------------------
    // Entradas de Control (desde Control Unit / Mux de Hazards en ID)
    // -------------------------------------------------------------------------
    // Grupo WB (Write-Back)
    input  wire                 i_wb_reg_write,
    input  wire                 i_wb_mem_to_reg,
    
    // Grupo M (Memory)
    input  wire                 i_m_mem_read,
    input  wire                 i_m_mem_write,
    
    // Grupo EX (Execution)
    input  wire                 i_ex_alu_src,
    input  wire [2:0]           i_ex_alu_op,

    // -------------------------------------------------------------------------
    // Entradas de Datapath (desde ID)
    // -------------------------------------------------------------------------
    input  wire [NB_DATA-1:0]   i_pc,
    input  wire [NB_DATA-1:0]   i_pc_plus_4,
    input  wire [NB_DATA-1:0]   i_rs1_data,
    input  wire [NB_DATA-1:0]   i_rs2_data,
    input  wire [NB_DATA-1:0]   i_imm,
    input  wire [NB_REG-1:0]    i_rs1,        // Necesario para la Forwarding Unit en EX
    input  wire [NB_REG-1:0]    i_rs2,        // Necesario para la Forwarding Unit en EX
    input  wire [NB_REG-1:0]    i_rd,         // Registro destino para etapas WB / Forwarding
    input  wire [2:0]           i_funct3,     // Selecciona operación específica en ALU Control
    input  wire                 i_funct7_5,   // Bit 30 de la instrucción (distingue ADD/SUB, SRL/SRA)
    input  wire                 i_wb_jump,    // Señal de control para indicar salto incondicional en WB

    // -------------------------------------------------------------------------
    // Salidas de Control (hacia etapa EX y latches posteriores)
    // -------------------------------------------------------------------------
    output reg                  o_wb_reg_write,
    output reg                  o_wb_mem_to_reg,
    output reg                  o_m_mem_read,
    output reg                  o_m_mem_write,
    output reg                  o_ex_alu_src,
    output reg  [2:0]           o_ex_alu_op,
    output reg                  o_valid,

    // -------------------------------------------------------------------------
    // Salidas de Datapath (hacia etapa EX)
    // -------------------------------------------------------------------------
    output reg  [NB_DATA-1:0]   o_pc,
    output reg  [NB_DATA-1:0]   o_pc_plus_4,
    output reg  [NB_DATA-1:0]   o_rs1_data,
    output reg  [NB_DATA-1:0]   o_rs2_data,
    output reg  [NB_DATA-1:0]   o_imm,
    output reg  [NB_REG-1:0]    o_rs1,
    output reg  [NB_REG-1:0]    o_rs2,
    output reg  [NB_REG-1:0]    o_rd,
    output reg  [2:0]           o_funct3,
    output reg                  o_funct7_5,
    output reg                  o_wb_jump,

    // -------------------------------------------------------------------------
    // Puerto de Depuración (Debug Unit / UART): 6 palabras de 32 bits = 24 bytes
    // -------------------------------------------------------------------------
    output wire [191:0]         o_debug_id_ex
);

    // -------------------------------------------------------------------------
    // Lógica Secuencial del Registro ID/EX
    // -------------------------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            // Reset Sincrónico: Poner a cero todas las salidas
            o_wb_reg_write  <= 1'b0;
            o_wb_mem_to_reg <= 1'b0;
            o_m_mem_read    <= 1'b0;
            o_m_mem_write   <= 1'b0;
            o_ex_alu_src    <= 1'b0;
            o_ex_alu_op     <= 3'b000;
            o_valid         <= 1'b0;
            
            o_pc            <= {NB_DATA{1'b0}};
            o_pc_plus_4     <= {NB_DATA{1'b0}};
            o_rs1_data      <= {NB_DATA{1'b0}};
            o_rs2_data      <= {NB_DATA{1'b0}};
            o_imm           <= {NB_DATA{1'b0}};
            o_rs1           <= {NB_REG{1'b0}};
            o_rs2           <= {NB_REG{1'b0}};
            o_rd            <= {NB_REG{1'b0}};
            o_funct3        <= 3'b000;
            o_funct7_5      <= 1'b0;
            o_wb_jump       <= 1'b0;
        end
        else if (i_en) begin
            // Operación Normal: Se propagan las señales de ID hacia EX
            o_wb_reg_write  <= i_wb_reg_write;
            o_wb_mem_to_reg <= i_wb_mem_to_reg;
            o_m_mem_read    <= i_m_mem_read;
            o_m_mem_write   <= i_m_mem_write;
            o_ex_alu_src    <= i_ex_alu_src;
            o_ex_alu_op     <= i_ex_alu_op;
            o_valid         <= i_valid;
                
            o_pc            <= i_pc;
            o_pc_plus_4     <= i_pc_plus_4;
            o_rs1_data      <= i_rs1_data;
            o_rs2_data      <= i_rs2_data;
            o_imm           <= i_imm;
            o_rs1           <= i_rs1;
            o_rs2           <= i_rs2;
            o_rd            <= i_rd;
            o_funct3        <= i_funct3;
            o_funct7_5      <= i_funct7_5;
            o_wb_jump       <= i_wb_jump;
        end
    end

    // -------------------------------------------------------------------------
    // Empaquetado alineado a palabras de 32 bits (6 palabras = 24 bytes):
    // Word 0 [31:0]    : o_pc
    // Word 1 [63:32]   : o_pc_plus_4
    // Word 2 [95:64]   : o_rs1_data
    // Word 3 [127:96]  : o_rs2_data
    // Word 4 [159:128] : o_imm
    // Word 5 [191:160] : {3'b0, o_valid, o_wb_jump, o_wb_mem_to_reg, o_wb_reg_write,
    //                     o_m_mem_write, o_m_mem_read, o_ex_alu_src, o_ex_alu_op,
    //                     o_funct7_5, o_funct3, o_rd, o_rs2, o_rs1}
    // -------------------------------------------------------------------------
    wire [31:0] w_ctrl_word = {
        3'b000,
        o_valid,         // [28]
        o_wb_jump,       // [27]
        o_wb_mem_to_reg, // [26]
        o_wb_reg_write,  // [25]
        o_m_mem_write,   // [24]
        o_m_mem_read,    // [23]
        o_ex_alu_src,    // [22]
        o_ex_alu_op,     // [21:19]
        o_funct7_5,      // [18]
        o_funct3,        // [17:15]
        o_rd,            // [14:10]
        o_rs2,           // [9:5]
        o_rs1            // [4:0]
    };

    assign o_debug_id_ex = {
        w_ctrl_word,
        o_imm,
        o_rs2_data,
        o_rs1_data,
        o_pc_plus_4,
        o_pc
    };

endmodule
`default_nettype wire
