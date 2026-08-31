`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: registro_pc
// Descripción: 
//   Registro del Program Counter (PC) para procesador RISC-V. 
//   Mantiene la dirección de la instrucción actual y controla el avance del flujo
//   del programa. Incorpora lógica para manejar detenciones temporales (Stall)
//   y un estado de parada definitiva (Halt) con memoria (sticky).
//
// Parámetros:
//   - NB_PC    : Ancho de bits del Program Counter (Por defecto: 32 bits).
//   - PC_RESET : Dirección de inicio tras un reset (Por defecto: 0).
//
// Entradas:
//   - i_clk     : Reloj principal del sistema.
//   - i_rst     : Reset sincrónico (activo en alto).
//   - i_en      : Habilitación global del registro.
//   - i_stall   : Señal de burbuja/espera. Congela el PC (ej. data/control hazards).
//   - i_halt    : Señal de detención total (ej. instrucción EBREAK/HALT).
//   - i_next_pc : Siguiente dirección a cargar (calculada por el datapath).
//
// Salidas:
//   - o_pc      : Dirección actual de la instrucción a buscar en memoria.
//   - o_halted  : Bandera activa si el PC está en estado de parada definitiva.
//
// Notas de Comportamiento:
//   - HALT Combinacional y Sticky: Para evitar que el PC avance un ciclo extra
//     mientras se decodifica la instrucción de HALT, la señal de detención 
//     impacta de forma combinacional inmediata, y al mismo tiempo se "enclava" 
//     en el registro interno 'halted' para mantener el procesador congelado 
//     aunque la señal 'i_halt' original desaparezca.
//==============================================================================

module registro_pc
#(
    parameter              NB_PC    = 32             ,
    parameter [NB_PC-1:0]  PC_RESET = {NB_PC{1'b0}}
)(
    input  wire            i_clk     ,
    input  wire            i_rst     ,
    input  wire            i_en      ,
    input  wire            i_stall   ,
    input  wire            i_halt    ,
    input  wire [NB_PC-1:0] i_next_pc,

    output wire [NB_PC-1:0] o_pc     ,
    output wire            o_halted
);

    reg  [NB_PC-1:0] pc          ;
    reg              halted      ;
    wire             halt_activo ;
    wire             avanza      ;

    // OR combinacional: sin el i_halt directo, el PC avanzaria un paso de mas
    // en el ciclo en que se decodifica el HALT.
    assign halt_activo = halted | i_halt;
    assign avanza      = i_en & ~i_stall & ~halt_activo;

    always @(posedge i_clk) begin
        if (i_rst) begin
            pc     <= PC_RESET;
            halted <= 1'b0;
        end
        else if (i_en) begin
            // STICKY: i_halt viene de ID y se baja solo cuando el HALT avanza
            // a EX. Sin este latch el PC se descongela y busca basura.
            if (i_halt)
                halted <= 1'b1;

            if (avanza)
                pc <= i_next_pc;
        end
    end

    assign o_pc     = pc         ;
    assign o_halted = halt_activo;

endmodule

`default_nettype wire