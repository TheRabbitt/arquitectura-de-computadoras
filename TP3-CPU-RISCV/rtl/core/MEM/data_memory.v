`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: data_memory
// Descripción: Memoria de datos para la etapa MEM del pipeline RISC-V.
// Incorpora un puerto de lectura dedicado para la UART, permitiendo
// transmitir el contenido de la memoria sin interferir con el Datapath.
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
    input  wire [DATA_WIDTH-1:0] i_addr,         // Dirección calculada por la ALU
    input  wire [DATA_WIDTH-1:0] i_write_data,   // Dato a escribir (proveniente de RS2)
    output wire [DATA_WIDTH-1:0] o_read_data,    // Dato leído hacia el latch MEM/WB
    
    // -------------------------------------------------------------------------
    // Interfaz Secundaria: Depuración (UART)
    // -------------------------------------------------------------------------
    input  wire                  i_debug_re,     // Habilitación de lectura desde UART
    input  wire [ADDR_WIDTH-1:0] i_debug_addr,   // Dirección solicitada por la UART
    output wire [DATA_WIDTH-1:0] o_debug_rdata   // Dato devuelto a la UART
);

    // Declaración del arreglo de memoria (RAM)
    reg [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];
    
    // Inicialización de la memoria en 0
    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
            ram[i] = 32'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Mapeo de Direcciones
    // -------------------------------------------------------------------------
    // La arquitectura RISC-V direcciona por bytes (byte-addressable), pero esta
    // memoria almacena palabras completas de 32 bits (4 bytes).
    // Para alinear la dirección, se descartan los 2 bits menos significativos.
    wire [ADDR_WIDTH-1:0] word_addr = i_addr[ADDR_WIDTH+1:2];

    // -------------------------------------------------------------------------
    // Lógica de Escritura (Sincrónica al reloj del pipeline)
    // -------------------------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_mem_write) begin
            ram[word_addr] <= i_write_data;
        end
    end

    // -------------------------------------------------------------------------
    // Lógica de Lectura para el Datapath (Asincrónica/Combinacional)
    // -------------------------------------------------------------------------
    // Se utiliza lectura combinacional para que el dato esté disponible en el 
    // mismo ciclo de reloj, cumpliendo el flujo clásico de la etapa MEM.
    assign o_read_data = (i_mem_read) ? ram[word_addr] : {DATA_WIDTH{1'b0}};
    
    // -------------------------------------------------------------------------
    // Lógica de Lectura para la UART / Unidad de Debug
    // -------------------------------------------------------------------------
    // La UART ingresa direcciones (i_debug_addr) mediante un contador interno
    // para ir leyendo y transmitiendo palabra por palabra.
    assign o_debug_rdata = (i_debug_re) ? ram[i_debug_addr] : {DATA_WIDTH{1'b0}};

endmodule
`default_nettype wire