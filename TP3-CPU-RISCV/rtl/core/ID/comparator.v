`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: branch_comparator
// Descripción: Unidad de evaluación temprana de saltos para la etapa ID.
// Soporta las instrucciones condicionales RV32I: BEQ y BNE.
//==============================================================================

module branch_comparator (
    input  wire [31:0] i_data1,       // Dato leído del registro fuente 1 (rs1)
    input  wire [31:0] i_data2,       // Dato leído del registro fuente 2 (rs2)
    input  wire [2:0]  i_funct3,      // Campo funct3 de la instrucción para identificar el tipo de salto
    output wire        o_take_branch  // Señal de control: 1 si el salto debe tomarse, 0 en caso contrario
);

    // Parámetros locales para los códigos funct3 de las instrucciones soportadas
    // localparam FUNCT3_BEQ = 3'b000;
    // localparam FUNCT3_BNE = 3'b001;

    // Señal interna para el resultado de la comparación de igualdad
    wire is_equal;

    // Lógica combinacional de comparación
    // A nivel de hardware, los sintetizadores implementan esto típicamente como 
    // una compuerta XOR de 32 bits seguida de un árbol NOR gigante.
    assign is_equal = (i_data1 == i_data2);

    // Alternativa ultraligera utilizando compuerta XOR como inversor programable
    assign o_take_branch = is_equal ^ i_funct3[0];

endmodule
`default_nettype wire