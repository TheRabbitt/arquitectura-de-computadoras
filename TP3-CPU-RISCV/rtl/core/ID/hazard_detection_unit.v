module hazard_detection_unit (
    // Entradas desde la etapa de ejecución (ID/EX)
    input wire id_ex_mem_read,      // Señal de control 'MemRead' de la instrucción en EX
    input wire [4:0] id_ex_rd,      // Registro destino de la instrucción en EX

    // Entradas desde la etapa de decodificación (IF/ID)
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
    end

endmodule