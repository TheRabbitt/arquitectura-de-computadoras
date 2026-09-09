`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// pc_subsystem_tb
// Prueba la integración de registro_pc, sumador (PC+4) y mux2 (Next PC).
//------------------------------------------------------------------------------
module pc_subsystem_tb;

    localparam integer NB_PC    = 32;
    localparam [NB_PC-1:0] PC_RESET = 32'h0000_0000;
    localparam integer T        = 10;

    // Señales de control (Estímulos)
    reg                 tb_clk;
    reg                 tb_rst;
    reg                 tb_en;
    reg                 tb_stall;
    reg                 tb_halt;
    
    reg                 tb_branch_sel;
    reg  [NB_PC-1:0]    tb_branch_target;

    // Cables de interconexión interna
    wire [NB_PC-1:0]    w_pc_plus_4;
    wire [NB_PC-1:0]    w_next_pc;

    // Salidas a observar
    wire [NB_PC-1:0]    tb_pc;
    wire                tb_halted;

    integer errores;
    integer i;

    // 1. Instancia del Registro PC
    registro_pc #(
        .NB_PC     (NB_PC),
        .PC_RESET  (PC_RESET)
    ) u_pc (
        .i_clk     (tb_clk),
        .i_rst     (tb_rst),
        .i_en      (tb_en),
        .i_stall   (tb_stall),
        .i_halt    (tb_halt),
        .i_next_pc (w_next_pc), // Conectado a la salida del MUX
        .o_pc      (tb_pc),
        .o_halted  (tb_halted)
    );

    // 2. Instancia del Sumador (Calcula PC + 4)
    sumador #(
        .NB_SUM    (NB_PC)
    ) u_adder_pc4 (
        .i_a       (tb_pc),
        .i_b       (32'd4),
        .o_result  (w_pc_plus_4)
    );

    // 3. Instancia del Multiplexor (Selecciona PC+4 o Branch)
    mux2 #(
        .NB        (NB_PC)
    ) u_mux_next_pc (
        .i_sel     (tb_branch_sel),
        .i_d0      (w_pc_plus_4),      // i_sel = 0 -> PC normal
        .i_d1      (tb_branch_target), // i_sel = 1 -> Salto
        .o_out     (w_next_pc)
    );

    // Generación de Reloj
    initial tb_clk = 1'b0;
    always #(T/2) tb_clk = ~tb_clk;

    // Tareas de verificación
    task ciclo;
        begin
            @(posedge tb_clk);
            #1; // Desplazamiento para leer datos estables
        end
    endtask

    task check_pc;
        input [NB_PC-1:0] esperado;
        input [8*44:1]    nombre;
        begin
            if (tb_pc !== esperado) begin
                $display("[FAIL] %0s | PC = %h (esperado %h)", nombre, tb_pc, esperado);
                errores = errores + 1;
            end
            else $display("[ OK ] %0s | PC = %h", nombre, tb_pc);
        end
    endtask

    // Secuencia de Pruebas
    initial begin
        $dumpfile("pc_subsystem_tb.vcd");
        $dumpvars(0, pc_subsystem_tb);

        errores          = 0;
        tb_rst           = 1'b1;
        tb_en            = 1'b0;
        tb_stall         = 1'b0;
        tb_halt          = 1'b0;
        tb_branch_sel    = 1'b0;
        tb_branch_target = 32'h0000_0000;

        $display("\n=== 1. Reset ===");
        ciclo();
        tb_rst = 1'b0;
        check_pc(32'h0000_0000, "PC tras reset debe ser 0");

        $display("\n=== 2. Ejecucion Normal (PC = PC + 4) ===");
        tb_en = 1'b1;
        ciclo(); check_pc(32'd4,  "Avance a PC+4");
        ciclo(); check_pc(32'd8,  "Avance a PC+8");
        ciclo(); check_pc(32'd12, "Avance a PC+12");

        $display("\n=== 3. Branch / Salto ===");
        tb_branch_target = 32'h0000_1000;
        tb_branch_sel    = 1'b1;
        ciclo(); 
        check_pc(32'h0000_1000, "Salto efectivo a direccion target");
        
        // Volvemos a ejecucion normal tras el salto
        tb_branch_sel = 1'b0;
        ciclo(); 
        check_pc(32'h0000_1004, "Suma +4 despues del salto");

        $display("\n=== 4. Prueba con Stall ===");
        tb_stall = 1'b1;
        ciclo();
        ciclo();
        check_pc(32'h0000_1004, "PC no avanza si stall=1");
        tb_stall = 1'b0;
        ciclo();
        check_pc(32'h0000_1008, "PC avanza normal al soltar stall");

        $display("\n=== 5. Prueba de Halt ===");
        tb_halt = 1'b1;
        ciclo();
        check_pc(32'h0000_1008, "PC congelado en cuanto halt=1");
        tb_halt = 1'b0;
        ciclo();
        check_pc(32'h0000_1008, "Halt sticky mantiene congelado el PC");

        $display("\n=== 6. Salir del halt con reset ===");
        tb_rst = 1'b1;
        ciclo();
        tb_rst = 1'b0;
        check_pc(32'h0000_0000, "PC tras reset debe ser 0");
        ciclo();
        check_pc(32'h0000_0004, "Avanza secuencialmente despues del reset");


        $display("\n--------------------------------------------------");
        if (errores == 0) $display(">>> TEST PASSED : Subsistema PC");
        else              $display(">>> TEST FAILED : %0d errores", errores);
        $display("--------------------------------------------------\n");
        $finish;
    end

endmodule
`default_nettype wire