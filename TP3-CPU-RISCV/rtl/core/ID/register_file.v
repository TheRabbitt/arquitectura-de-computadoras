`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: register_file
// Descripción: Banco de registros para la etapa ID del procesador RISC-V.
//   - 32 registros de 32 bits.
//   - Registro x0 siempre lee 0.
//   - Internal Forwarding (Write-Through): Permite leer el dato actualizado
//     en el mismo ciclo en el que se escribe (simulando escritura en la 1ra
//     mitad del ciclo y lectura en la 2da mitad).
//==============================================================================

module register_file (
    input  wire        i_clk,
    input  wire        i_rst,
    
    // Señales de Control
    input  wire        i_reg_write,
    
    // Direcciones
    input  wire [4:0]  i_read_reg1,
    input  wire [4:0]  i_read_reg2,
    input  wire [4:0]  i_write_reg,
    
    // Datos
    input  wire [31:0] i_write_data,

    output wire [31:0] o_read_data1,
    output wire [31:0] o_read_data2
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

    // Lectura Combinacional con Internal Forwarding (Write-Through)
    // 1. Si el registro es 0, devuelve 0.
    // 2. Si hay una escritura activa al mismo registro que se quiere leer, 
    //    devuelve el i_write_data directamente (dato nuevo).
    // 3. Si no, devuelve el valor almacenado en la memoria (dato viejo).
    
    assign o_read_data1 = (i_read_reg1 == 5'd0) ? 32'd0 :
                          (i_reg_write && (i_write_reg == i_read_reg1)) ? i_write_data :
                          registers[i_read_reg1];

    assign o_read_data2 = (i_read_reg2 == 5'd0) ? 32'd0 :
                          (i_reg_write && (i_write_reg == i_read_reg2)) ? i_write_data :
                          registers[i_read_reg2];

endmodule
`default_nettype wire