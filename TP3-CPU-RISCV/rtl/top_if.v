`timescale 1ns / 1ps
`default_nettype none

module top_if_stage (
    input  wire        clk_100MHz, // Reloj principal de la Nexys 4 (Pin E3)
    input  wire        btnC,       // Botón Central: Reset
    input  wire        btnU,       // Botón Arriba: Avanzar 1 ciclo de reloj (Step)
    input  wire [15:0] i_sw,         // Interruptores para señales de control
    output wire [15:0] o_led         // o_leds para visualizar PC o Instrucción
);

    // Parámetros
    localparam NB_PC      = 32;
    localparam ADDR_WIDTH = 10;
    localparam DATA_WIDTH = 32;

    // Cables internos de la etapa IF
    wire [NB_PC-1:0]      w_next_pc;
    wire [NB_PC-1:0]      w_pc_plus_4;
    wire [NB_PC-1:0]      w_pc_actual;
    wire                  w_halted;
    wire [DATA_WIDTH-1:0] w_instruction;

    // Señales acondicionadas
    wire w_reset = btnC;
    wire w_step; // Pulso de 1 ciclo de reloj generado por btnU

    // -------------------------------------------------------------------------
    // Acondicionador de Botón (Single Stepper)
    // -------------------------------------------------------------------------
    // Convierte una pulsación humana en un único pulso de 10ns (1 ciclo a 100MHz)
    button_pulser u_stepper (
        .i_clk   (clk_100MHz),
        .i_rst   (w_reset),
        .i_btn   (btnU),
        .o_pulse (w_step)
    );

    // -------------------------------------------------------------------------
    // Mapeo de Interruptores (i_switches)
    // -------------------------------------------------------------------------
    wire        w_en          = i_sw[0];
    wire        w_stall       = i_sw[1];
    wire        w_halt        = i_sw[2];
    wire        w_branch_sel  = i_sw[3];
    
    // El target del branch lo sacamos de los i_switches [11:4] y lo rellenamos
    wire [31:0] w_branch_target = {24'd0, i_sw[11:4]};

    // -------------------------------------------------------------------------
    // INSTANCIAS DE LA ETAPA IF
    // -------------------------------------------------------------------------
    
    // Registro PC (Actualiza solo cuando presionamos el botón de Step)
    registro_pc #(
        .NB_PC(NB_PC),
        .PC_RESET(32'h0000_0000)
    ) u_pc (
        .i_clk     (clk_100MHz), // Usamos el reloj de 100MHz, pero frenado por i_en
        .i_rst     (w_reset),
        .i_en      (w_en & w_step), // Solo se habilita 1 ciclo al presionar btnU
        .i_stall   (w_stall),       
        .i_halt    (w_halt),       
        .i_next_pc (w_next_pc),    
        .o_pc      (w_pc_actual),   
        .o_halted  (w_halted)       
    );

    // Sumador (PC + 4)
    sumador #(.NB_SUM(NB_PC)) u_adder_pc4 (
        .i_a      (w_pc_actual), 
        .i_b      (32'd4),       
        .o_result (w_pc_plus_4) 
    );

    // MUX para seleccionar PC secuencial o Branch
    mux2 #(.NB(NB_PC)) u_mux_next_pc (
        .i_sel (w_branch_sel),    
        .i_d0  (w_pc_plus_4),     
        .i_d1  (w_branch_target), 
        .o_out (w_next_pc)        
    );

    // Memoria de Instrucciones
    InstructionMemory #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_imem (
        .i_clk         (clk_100MHz),    
        
        // Puerto A (Fetch)
        .i_pc          (w_pc_actual),    
        .i_read_enable (1'b1),          // Siempre leemos en esta prueba
        .o_instruction (w_instruction),  
        
        // Puerto B (Desactivado para esta prueba física manual)
        .i_write_en    (1'b0),           
        .i_debug_re    (1'b0),           
        .i_debug_addr  (10'd0),          
        .i_write_addr  (10'd0),          
        .i_write_data  (32'd0),          
        .o_debug_rdata ()                
    );

    // -------------------------------------------------------------------------
    // Visualización en o_leds
    // -------------------------------------------------------------------------
    // i_sw[15] = 0 -> Muestra los 16 bits bajos del PC
    // i_sw[15] = 1 -> Muestra los 16 bits bajos de la Instrucción Fetcheada
    assign o_led = i_sw[15] ? w_instruction[15:0] : w_pc_actual[15:0];

endmodule
`default_nettype wire