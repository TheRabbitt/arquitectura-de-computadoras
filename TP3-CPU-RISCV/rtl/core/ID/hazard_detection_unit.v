module hazard_detection_unit (
    // Entradas desde la etapa de ejecución (ID/EX)
    input wire id_ex_mem_read,      // Señal de control 'MemRead' de la instrucción en EX
    input wire id_ex_reg_write,     // Señal 'RegWrite' de la instrucción en EX
    input wire [4:0] id_ex_rd,      // Registro destino de la instrucción en EX

    // Entradas desde la etapa de memoria (EX/MEM)
    input wire ex_mem_mem_read,     // Señal 'MemRead' de la instrucción en MEM
    input wire [4:0] ex_mem_rd,     // Registro destino de la instrucción en MEM

    // Entradas desde la etapa de decodificación (IF/ID)
    input wire if_id_branch,        // Indica si la instrucción actual en ID es un salto
    input wire [4:0] if_id_rs1,     // Registro fuente 1 de la instrucción en ID
    input wire [4:0] if_id_rs2,     // Registro fuente 2 de la instrucción en ID

    // Salidas de control para detener el pipeline (Stall/Bubble)
    output reg pc_write,            // Habilita la escritura del Program Counter
    output reg if_id_write,         // Habilita la escritura del registro IF/ID
    output reg ctrl_mux_sel         // Selecciona entre señales de control reales (1) o ceros (0)
);

    always @(*) begin
        // Valores por defecto: No hay riesgo, el pipeline avanza normalmente
        pc_write = 1'b1;
        if_id_write = 1'b1;
        ctrl_mux_sel = 1'b1;

        // Condición de detección de riesgo "Load-Use"
        // Si la instrucción en EX es una lectura de memoria (Load) y su registro 
        // destino coincide con alguno de los registros fuente de la instrucción en ID...
        if (id_ex_mem_read == 1'b1 && 
            (id_ex_rd != 5'b0) && // ignorar el registro x0
            ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2))) begin
            
            // ...se detecta un riesgo. Hay que insertar una burbuja (stall).
            pc_write = 1'b0;       // Congela el PC (re-fecth de la misma instrucción)
            if_id_write = 1'b0;    // Congela IF/ID (mantiene la instrucción decodificándose)
            ctrl_mux_sel = 1'b0;   // Envía 0s al registro ID/EX (convierte la instrucción en un NOP)
        end

        // Riesgo Branch dependiente de una instrucción ALU en EX (Stall de 1 ciclo)
        // El salto se congela 1 ciclo hasta que la instrucción aritmética avance a MEM
        else if (if_id_branch == 1'b1 && id_ex_reg_write == 1'b1 && (id_ex_rd != 5'b0) &&
                ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2))) begin
            pc_write = 1'b0;
            if_id_write = 1'b0;
            ctrl_mux_sel = 1'b0;
        end

        // Riesgo Branch dependiente de un Load en MEM (2do ciclo de stall)
        // El Load avanzó a MEM, pero el dato de la RAM aún no se ha leído. 
        // Se congela 1 ciclo más hasta que el Load alcance la etapa WB.
        else if (if_id_branch == 1'b1 && ex_mem_mem_read == 1'b1 && (ex_mem_rd != 5'b0) &&
                ((ex_mem_rd == if_id_rs1) || (ex_mem_rd == if_id_rs2))) begin
            pc_write = 1'b0;
            if_id_write = 1'b0;
            ctrl_mux_sel = 1'b0;
        end
    end

endmodule