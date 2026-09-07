`timescale 1ns / 1ps
`default_nettype none

module top_if_id_test (
    input  wire        clk_100MHz, // Reloj principal (Pin E3)
    input  wire        btnC,       // Botón Central: Reset
    input  wire        btnU,       // Botón Arriba: Avanzar 1 ciclo de reloj (Step)
    input  wire [15:0] sw,         // Interruptores para señales de control
    output wire [15:0] led         // LEDs para visualizar salidas de IF/ID
);

    // Parámetros
    localparam NB_PC      = 32;
    localparam ADDR_WIDTH = 10;
    localparam DATA_WIDTH = 32;

    // Acondicionador de Botón (Single Stepper)
    wire w_step;
    button_pulser u_stepper (
        .i_clk   (clk_100MHz),
        .i_rst   (btnC),
        .i_btn   (btnU),
        .o_pulse (w_step)
    );

    // Mapeo de Interruptores (Control)
    wire w_if_en       = sw[0];
    wire w_stall       = sw[1];
    wire w_halt        = sw[2];
    wire w_branch_sel  = sw[3];
    wire w_if_id_en    = sw[4];
    wire w_flush       = sw[5];
    
    // Target del branch (sw[11:6])
    wire [31:0] w_branch_target = {26'd0, sw[11:6]};

    // Señales de interconexión (Marcadas para ILA Debug)
    (* mark_debug = "true" *) wire [NB_PC-1:0]      w_pc_if;
    (* mark_debug = "true" *) wire [DATA_WIDTH-1:0] w_instruction_if;
    (* mark_debug = "true" *) wire                  w_halted;

    (* mark_debug = "true" *) wire [NB_PC-1:0]      w_pc_id;
    (* mark_debug = "true" *) wire [DATA_WIDTH-1:0] w_instruction_id;

    // Etapa IF (Fetch)
    stage_if #(
        .NB_PC(NB_PC),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_stage_if (
        .i_clk           (clk_100MHz),
        .i_rst           (btnC),
        .i_en            (w_if_en & w_step), // Avanza solo con el botón
        .i_stall         (w_stall),
        .i_halt          (w_halt),
        .i_branch_sel    (w_branch_sel),
        .i_branch_target (w_branch_target),
        .i_mem_we        (1'b0),
        .i_debug_re      (1'b0),
        .i_debug_addr    (10'd0),
        .i_write_addr    (10'd0),
        .i_write_data    (32'd0),
        .o_pc            (w_pc_if),
        .o_instruction   (w_instruction_if),
        .o_halted        (w_halted),
        .o_debug_rdata   ()
    );

    // Registro IF/ID
    if_id_register #(
        .NB(NB_PC)
    ) u_if_id (
        .i_clk         (clk_100MHz),
        .i_rst         (btnC),
        .i_en          (w_if_id_en & w_step), // Captura solo con el botón
        .i_flush       (w_flush),
        .i_pc          (w_pc_if),
        .i_instruction (w_instruction_if),
        .o_pc          (w_pc_id),
        .o_instruction (w_instruction_id)
    );

    // Selector de visualización en LEDs (sw[15])
    // sw[15] = 0 -> Muestra los 16 bits bajos del PC en la etapa ID
    // sw[15] = 1 -> Muestra los 16 bits bajos de la instrucción en la etapa ID
    assign led = sw[15] ? w_instruction_id[15:0] : w_pc_id[15:0];

endmodule