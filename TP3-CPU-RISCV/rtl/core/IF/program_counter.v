`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// registro_pc
//
//   SOLO el registro del PC. No suma, no multiplexa: eso vive en etapa_if.
//   Lo unico que se queda adentro es el estado que le pertenece al registro:
//   el latch sticky de HALT.
//
//   PREMISA: el clock corre libre a 100 MHz siempre. Se controla i_en.
//   Invariante: con i_en = 0 y i_rst = 0, ningun bit de estado cambia.
//
//   PRIORIDADES (mayor a menor):
//     1. i_rst   -> sincrono, ignora i_en (se resetea con el pipeline pausado)
//     2. i_halt  -> congela permanentemente (sticky)
//     3. i_stall -> congela un ciclo (hazard load-use)
//------------------------------------------------------------------------------
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