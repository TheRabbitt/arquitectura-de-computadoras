`timescale 1ns / 1ps
`default_nettype none

module forwarding_unit (
    // Entradas desde el registro de segmentación ID/EX
    input  wire [4:0] i_id_ex_rs1,
    input  wire [4:0] i_id_ex_rs2,

    // Entradas desde el registro de segmentación EX/MEM
    input  wire [4:0] i_ex_mem_rd,
    input  wire       i_ex_mem_regwrite,

    // Entradas desde el registro de segmentación MEM/WB
    input  wire [4:0] i_mem_wb_rd,
    input  wire       i_mem_wb_regwrite,

    // Salidas hacia los multiplexores de la ALU
    output reg  [1:0] o_forward_a,
    output reg  [1:0] o_forward_b
);

    always @(*) begin
        // --------------------------------------------------------
        // Lógica para ForwardA (Operando 1 de la ALU)
        // --------------------------------------------------------
        // Riesgo EX: El dato más reciente está en la etapa EX/MEM
        if (i_ex_mem_regwrite && (i_ex_mem_rd != 5'b00000) && (i_ex_mem_rd == i_id_ex_rs1)) begin
            o_forward_a = 2'b10; 
        end 
        // Riesgo MEM: El dato está en la etapa MEM/WB
        // (Solo se adelanta si NO se adelantó ya desde EX/MEM)
        else if (i_mem_wb_regwrite && (i_mem_wb_rd != 5'b00000) && (i_mem_wb_rd == i_id_ex_rs1)) begin
            o_forward_a = 2'b01;
        end 
        // Sin riesgo: Se usa el valor leído del banco de registros en ID
        else begin
            o_forward_a = 2'b00;
        end

        // --------------------------------------------------------
        // Lógica para ForwardB (Operando 2 de la ALU)
        // --------------------------------------------------------
        // Riesgo EX: El dato más reciente está en la etapa EX/MEM
        if (i_ex_mem_regwrite && (i_ex_mem_rd != 5'b00000) && (i_ex_mem_rd == i_id_ex_rs2)) begin
            o_forward_b = 2'b10;
        end 
        // Riesgo MEM: El dato está en la etapa MEM/WB
        else if (i_mem_wb_regwrite && (i_mem_wb_rd != 5'b00000) && (i_mem_wb_rd == i_id_ex_rs2)) begin
            o_forward_b = 2'b01;
        end 
        // Sin riesgo: Se usa el valor leído del banco de registros en ID
        else begin
            o_forward_b = 2'b00;
        end
    end

endmodule
`default_nettype wire