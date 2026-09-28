`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: register_file
// Descripción: Banco de registros para la etapa ID del procesador RISC-V.
//   - 32 registros de 32 bits.
//   - Registro x0 siempre lee 0.
//   - Internal Forwarding (Write-Through): Permite leer el dato actualizado
//     en el mismo ciclo en el que se escribe.
//   - Puerto de Depuración: Permite a la UART leer el estado de los registros.
//==============================================================================

module register_file (
    input  wire        i_clk,
    input  wire        i_rst,
    
    // Señales de Control (Datapath)
    input  wire        i_reg_write,
    
    // Direcciones (Datapath)
    input  wire [4:0]  i_read_reg1,
    input  wire [4:0]  i_read_reg2,
    input  wire [4:0]  i_write_reg,
    
    // Datos (Datapath)
    input  wire [31:0] i_write_data,

    output wire [31:0] o_read_data1,
    output wire [31:0] o_read_data2,

    // Puerto de Depuración (Debug Unit / UART)
    input  wire        i_debug_re,       // Habilitación de lectura debug
    input  wire [4:0]  i_debug_reg_addr, // Dirección del registro a leer (0 a 31)
    output reg  [31:0] o_debug_reg_data  // Dato enviado a la UART
);

    reg [31:0] registers [0:31];
    integer i;

    // Escritura Sincrónica
    always @(posedge i_clk) begin
        if (i_rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                registers[i] <= 32'd0;
            end
        end else begin
            if (i_reg_write && (i_write_reg != 5'd0)) begin
                registers[i_write_reg] <= i_write_data;
            end
        end
    end

    // Lectura Sincrónica para Depuración (UART)
    // Se hace sincrónica para no sumar retardo combinacional al pipeline principal.
    always @(posedge i_clk) begin
        if (i_debug_re) begin
            // Mantenemos la regla de que x0 siempre vale 0, incluso en debug
            if (i_debug_reg_addr == 5'd0) begin
                o_debug_reg_data <= 32'd0;
            end else begin
                o_debug_reg_data <= registers[i_debug_reg_addr];
            end
        end
    end

    // Lectura Combinacional con Internal Forwarding (Write-Through) para Datapath
    assign o_read_data1 = (i_read_reg1 == 5'd0) ? 32'd0 :
                          (i_reg_write && (i_write_reg == i_read_reg1)) ? i_write_data :
                          registers[i_read_reg1];

    assign o_read_data2 = (i_read_reg2 == 5'd0) ? 32'd0 :
                          (i_reg_write && (i_write_reg == i_read_reg2)) ? i_write_data :
                          registers[i_read_reg2];

endmodule
`default_nettype wire