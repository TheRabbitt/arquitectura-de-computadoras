module id_forwarding_unit (
    // Entradas desde la etapa de decodificación (IF/ID)
    input wire [4:0] if_id_rs1,     // Registro fuente 1 del salto
    input wire [4:0] if_id_rs2,     // Registro fuente 2 del salto

    // Entradas desde la etapa de memoria (EX/MEM)
    input wire ex_mem_reg_write,    // Señal 'RegWrite' en EX/MEM
    input wire [4:0] ex_mem_rd,     // Registro destino en EX/MEM

    // Entradas desde la etapa de Write-Back (MEM/WB)
    input wire mem_wb_reg_write,    // Señal 'RegWrite' en MEM/WB
    input wire [4:0] mem_wb_rd,     // Registro destino en MEM/WB

    // Salidas hacia los multiplexores en la etapa ID
    output reg [1:0] forward_a_id,  // Selector para el operando 1 del comparador
    output reg [1:0] forward_b_id   // Selector para el operando 2 del comparador
);

    always @(*) begin
        // Valores por defecto (00): Tomar los datos del banco de registros
        forward_a_id = 2'b00;
        forward_b_id = 2'b00;

        // --------------------------------------------------------
        // Lógica de adelantamiento para RS1 (Operando A)
        // --------------------------------------------------------
        // Prioridad 1: Riesgo con EX/MEM (Dato más reciente)
        if (ex_mem_reg_write == 1'b1 && (ex_mem_rd != 5'b0) && (ex_mem_rd == if_id_rs1)) begin
            forward_a_id = 2'b10;
        end
        // Prioridad 2: Riesgo con MEM/WB
        else if (mem_wb_reg_write == 1'b1 && (mem_wb_rd != 5'b0) && (mem_wb_rd == if_id_rs1)) begin
            forward_a_id = 2'b01;
        end

        // --------------------------------------------------------
        // Lógica de adelantamiento para RS2 (Operando B)
        // --------------------------------------------------------
        // Prioridad 1: Riesgo con EX/MEM (Dato más reciente)
        if (ex_mem_reg_write == 1'b1 && (ex_mem_rd != 5'b0) && (ex_mem_rd == if_id_rs2)) begin
            forward_b_id = 2'b10;
        end
        // Prioridad 2: Riesgo con MEM/WB
        else if (mem_wb_reg_write == 1'b1 && (mem_wb_rd != 5'b0) && (mem_wb_rd == if_id_rs2)) begin
            forward_b_id = 2'b01;
        end
    end

endmodule