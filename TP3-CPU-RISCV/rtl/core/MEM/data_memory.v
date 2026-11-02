`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: data_memory
// Descripción: Memoria de datos para la etapa MEM del pipeline RISC-V.
// Lectura y escritura sincrónicas para inferencia de Block RAM (BRAM) en Vivado
// con soporte completo para accesos de byte, media palabra y palabra
// (LB, LH, LW, LBU, LHU y SB, SH, SW) mediante byte-write enables.
// Incorpora un puerto de lectura dedicado para la UART.
//==============================================================================

module data_memory #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8  // 2^8 = 256 palabras de 32 bits (1 KB de memoria)
)(
    input  wire                  i_clk,
    
    // -------------------------------------------------------------------------
    // Interfaz Principal: Etapa MEM del Pipeline
    // -------------------------------------------------------------------------
    input  wire                  i_mem_write,
    input  wire                  i_mem_read,
    input  wire [2:0]            i_funct3,       // Tamaño y signo (LB/LH/LW/LBU/LHU, SB/SH/SW)
    input  wire [DATA_WIDTH-1:0] i_addr,         // Dirección calculada por la ALU
    input  wire [DATA_WIDTH-1:0] i_write_data,   // Dato a escribir (proveniente de RS2)
    output reg  [DATA_WIDTH-1:0] o_read_data,    // Dato leído y extendido hacia el latch MEM/WB
    
    // -------------------------------------------------------------------------
    // Interfaz Secundaria: Depuración (UART)
    // -------------------------------------------------------------------------
    input  wire                  i_debug_re,     // Habilitación de lectura desde UART
    input  wire [ADDR_WIDTH-1:0] i_debug_addr,   // Dirección solicitada por la UART
    output reg  [DATA_WIDTH-1:0] o_debug_rdata   // Dato devuelto a la UART
);

    // Códigos funct3 estándar RV32I para Loads y Stores
    localparam FUNCT3_BYTE = 3'b000; // LB / SB
    localparam FUNCT3_HALF = 3'b001; // LH / SH
    localparam FUNCT3_WORD = 3'b010; // LW / SW
    localparam FUNCT3_LBU  = 3'b100; // LBU
    localparam FUNCT3_LHU  = 3'b101; // LHU

    // Declaración del arreglo de memoria (RAM) y registro de lectura sincrónica
    reg [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];
    reg [DATA_WIDTH-1:0] raw_read_data;
    
    // Inicialización de la memoria en 0
    integer i;
    initial begin
        raw_read_data = {DATA_WIDTH{1'b0}};
        o_debug_rdata = {DATA_WIDTH{1'b0}};
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
            ram[i] = 32'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Mapeo de Direcciones
    // -------------------------------------------------------------------------
    // Dirección de palabra (32 bits) e índice de byte dentro de la palabra (Little-Endian)
    wire [ADDR_WIDTH-1:0] word_addr   = i_addr[ADDR_WIDTH+1:2];
    wire [1:0]            byte_offset = i_addr[1:0];

    // -------------------------------------------------------------------------
    // Alineación y Máscaras de Escritura por Byte (SB, SH, SW)
    // -------------------------------------------------------------------------
    reg [3:0]            byte_we;
    reg [DATA_WIDTH-1:0] aligned_write_data;

    always @(*) begin
        byte_we            = 4'b0000;
        aligned_write_data = i_write_data;

        case (i_funct3)
            FUNCT3_BYTE: begin // SB
                aligned_write_data = {4{i_write_data[7:0]}};
                case (byte_offset)
                    2'b00: byte_we = 4'b0001;
                    2'b01: byte_we = 4'b0010;
                    2'b10: byte_we = 4'b0100;
                    2'b11: byte_we = 4'b1000;
                endcase
            end

            FUNCT3_HALF: begin // SH
                aligned_write_data = {2{i_write_data[15:0]}};
                byte_we            = byte_offset[1] ? 4'b1100 : 4'b0011;
            end

            FUNCT3_WORD: begin // SW
                aligned_write_data = i_write_data;
                byte_we            = 4'b1111;
            end

            default: begin
                aligned_write_data = i_write_data;
                byte_we            = 4'b0000;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Lógica Sincrónica de Memoria (Infiere BRAM con Byte-Write Enable en Vivado)
    // -------------------------------------------------------------------------
    always @(negedge i_clk) begin
        // --- Puerto 1: Datapath del Pipeline ---
        if (i_mem_write) begin
            if (byte_we[0]) ram[word_addr][7:0]   <= aligned_write_data[7:0];
            if (byte_we[1]) ram[word_addr][15:8]  <= aligned_write_data[15:8];
            if (byte_we[2]) ram[word_addr][23:16] <= aligned_write_data[23:16];
            if (byte_we[3]) ram[word_addr][31:24] <= aligned_write_data[31:24];
        end
        
        if (i_mem_read) begin
            raw_read_data <= ram[word_addr];
        end
        
        // --- Puerto 2: Unidad de Depuración (UART) ---
        if (i_debug_re) begin
            o_debug_rdata <= ram[i_debug_addr];
        end else begin
            o_debug_rdata <= {DATA_WIDTH{1'b0}};
        end
    end

    // -------------------------------------------------------------------------
    // Selección de Sub-palabra y Extensión de Signo / Cero (LB, LH, LW, LBU, LHU)
    // -------------------------------------------------------------------------
    reg [7:0]  selected_byte;
    reg [15:0] selected_half;

    always @(*) begin
        case (byte_offset)
            2'b00: selected_byte = raw_read_data[7:0];
            2'b01: selected_byte = raw_read_data[15:8];
            2'b10: selected_byte = raw_read_data[23:16];
            2'b11: selected_byte = raw_read_data[31:24];
        endcase

        selected_half = byte_offset[1] ? raw_read_data[31:16] : raw_read_data[15:0];

        if (!i_mem_read) begin
            o_read_data = {DATA_WIDTH{1'b0}};
        end else begin
            case (i_funct3)
                FUNCT3_BYTE: o_read_data = {{24{selected_byte[7]}}, selected_byte};  // LB
                FUNCT3_HALF: o_read_data = {{16{selected_half[15]}}, selected_half}; // LH
                FUNCT3_WORD: o_read_data = raw_read_data;                            // LW
                FUNCT3_LBU:  o_read_data = {24'b0, selected_byte};                   // LBU
                FUNCT3_LHU:  o_read_data = {16'b0, selected_half};                   // LHU
                default:     o_read_data = raw_read_data;
            endcase
        end
    end

endmodule
`default_nettype wire