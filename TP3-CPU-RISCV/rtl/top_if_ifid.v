`timescale 1ns / 1ps
`default_nettype none

module top_if_id (
    input  wire        clk_100MHz, // Reloj principal (Pin E3)
    input  wire        btnC,       // Botón Central: Reset
    input  wire        btnU,       // Botón Arriba: Avanzar 1 ciclo de reloj (Step)
    input  wire [15:0] i_sw,         // Interruptores para señales de control
    output reg  [15:0] o_led         // o_leds para visualizar salidas de IF/ID
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
    wire w_if_en       = i_sw[0];
    wire w_stall       = i_sw[1];
    wire w_halt        = i_sw[2];
    wire w_branch_sel  = i_sw[3];
    wire w_if_id_en    = i_sw[4];
    wire w_flush       = i_sw[5];
    
    // Target del branch (i_sw[11:6])
    wire [31:0] w_branch_target = {26'd0, i_sw[11:6]};

    // Señales de interconexión
    wire [NB_PC-1:0]      w_pc_if;
    wire [DATA_WIDTH-1:0] w_instruction_if;
    wire                  w_halted;

    wire [NB_PC-1:0]      w_pc_id;
    wire [DATA_WIDTH-1:0] w_instruction_id;

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

    // Selector de visualización en o_leds extendido para depuración
    always @(*) begin
        // Usamos i_sw[15:14] para elegir qué datos mandar a los o_leds 14 a 0
        case(i_sw[15:14])
            2'b00: o_led[14:0] = w_pc_if[14:0];          // Muestra PC en etapa IF
            2'b01: o_led[14:0] = w_instruction_if[14:0]; // Muestra Instrucción en etapa IF
            2'b10: o_led[14:0] = w_pc_id[14:0];          // Muestra PC en etapa ID
            2'b11: o_led[14:0] = w_instruction_id[14:0]; // Muestra Instrucción en etapa ID
        endcase
        
        // El o_led 15 se mantiene fijo indicando si la etapa IF está en Halt
        o_led[15] = w_halted;
    end

endmodule