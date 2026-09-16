`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: control_unit
// Descripción: Unidad de Control principal para la etapa ID.
// Decodifica el opcode de la instrucción y genera 7 señales de control (8 bits).
//==============================================================================

module control_unit (
    input  wire [6:0] i_opcode,     // Instruction [6:0]
    
    // Señales de salida (7 puertos, 8 bits en total)
    output reg        o_branch,     // Habilita el salto condicional
    output reg        o_mem_read,   // Habilita lectura en memoria de datos
    output reg        o_mem_to_reg, // Selecciona origen para el banco de registros
    output reg [1:0]  o_alu_op,     // Define la categoría de operación para ALU control (2 bits)
    output reg        o_mem_write,  // Habilita escritura en memoria de datos
    output reg        o_alu_src,    // Selecciona operando de la ALU (Registro o Inmediato)
    output reg        o_reg_write   // Habilita escritura en el banco de registros
);

    // Códigos de operación (Opcodes) estándar de RV32I
    localparam OPCODE_R_TYPE = 7'b0110011; // Instrucciones aritmético-lógicas (add, sub, and, or)
    localparam OPCODE_LOAD   = 7'b0000011; // Instrucciones de carga (lw)
    localparam OPCODE_STORE  = 7'b0100011; // Instrucciones de almacenamiento (sw)
    localparam OPCODE_BRANCH = 7'b1100011; // Instrucciones de salto condicional (beq, bne)

    always @(*) begin
        // Valores por defecto (Previene la inferencia de latches y mantiene el procesador seguro)
        o_branch     = 1'b0;
        o_mem_read   = 1'b0;
        o_mem_to_reg = 1'b0;
        o_alu_op     = 2'b00;
        o_mem_write  = 1'b0;
        o_alu_src    = 1'b0;
        o_reg_write  = 1'b0;

        case (i_opcode)
            //------------------------------------------------------------------
            // Tipo R (Registro a Registro)
            //------------------------------------------------------------------
            OPCODE_R_TYPE: begin
                o_alu_src    = 1'b0;  // Operando 2 viene del registro (Read data 2)
                o_mem_to_reg = 1'b0;  // El dato a escribir viene de la ALU
                o_reg_write  = 1'b1;  // Se escribe en el banco de registros
                o_mem_read   = 1'b0;  // No se lee memoria
                o_mem_write  = 1'b0;  // No se escribe memoria
                o_branch     = 1'b0;  // No es un salto
                o_alu_op     = 2'b10; // ALUOp 10: Delegar la operación al funct3/funct7
            end

            //------------------------------------------------------------------
            // Tipo I (Load - Carga de memoria)
            //------------------------------------------------------------------
            OPCODE_LOAD: begin
                o_alu_src    = 1'b1;  // Operando 2 viene del inmediato extendido
                o_mem_to_reg = 1'b1;  // El dato a escribir viene de la memoria
                o_reg_write  = 1'b1;  // Se escribe en el banco de registros
                o_mem_read   = 1'b1;  // Se lee la memoria de datos
                o_mem_write  = 1'b0;  // No se escribe memoria
                o_branch     = 1'b0;  // No es un salto
                o_alu_op     = 2'b00; // ALUOp 00: Forzar a la ALU a sumar (Base + Offset)
            end

            //------------------------------------------------------------------
            // Tipo S (Store - Escritura en memoria)
            //------------------------------------------------------------------
            OPCODE_STORE: begin
                o_alu_src    = 1'b1;  // Operando 2 viene del inmediato extendido
                o_mem_to_reg = 1'b0;  // Don't care (se pone en 0 por seguridad)
                o_reg_write  = 1'b0;  // NO se escribe en el banco de registros
                o_mem_read   = 1'b0;  // No se lee memoria
                o_mem_write  = 1'b1;  // Se escribe en la memoria de datos
                o_branch     = 1'b0;  // No es un salto
                o_alu_op     = 2'b00; // ALUOp 00: Forzar a la ALU a sumar (Base + Offset)
            end

            //------------------------------------------------------------------
            // Tipo B (Branch - Salto condicional)
            //------------------------------------------------------------------
            OPCODE_BRANCH: begin
                o_alu_src    = 1'b0;  // Don't care (resolvemos la condición de salto con comparador en ID)
                o_mem_to_reg = 1'b0;  // Don't care
                o_reg_write  = 1'b0;  // NO se escribe en el banco de registros
                o_mem_read   = 1'b0;  // No se lee memoria
                o_mem_write  = 1'b0;  // No se escribe memoria
                o_branch     = 1'b1;  // Habilita la compuerta AND para el PC
                o_alu_op     = 2'b01; // Don't care (la ALU no se usa para la condición de salto)
            end

            // Default cubierto por las asignaciones iniciales
        endcase
    end

endmodule
`default_nettype wire