`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// registro_pc_tb
//   Prueba el registro AISLADO: prioridades reset / halt / stall / enable.
//   Como ya no hay sumador adentro, i_next_pc se fuerza a valores arbitrarios
//   (0xAAAA...), lo que hace mas facil ver si el registro carga o no carga.
//------------------------------------------------------------------------------
module registro_pc_tb;

    localparam integer     NB_PC    = 32;
    localparam [NB_PC-1:0] PC_RESET = 32'h0000_0000;
    localparam integer     T        = 10;

    reg                 tb_clk     ;
    reg                 tb_rst     ;
    reg                 tb_en      ;
    reg                 tb_stall   ;
    reg                 tb_halt    ;
    reg  [NB_PC-1:0]    tb_next_pc ;

    wire [NB_PC-1:0]    tb_pc      ;
    wire                tb_halted  ;

    integer errores;
    integer i;

    registro_pc #(
        .NB_PC     (NB_PC),
        .PC_RESET  (PC_RESET)
    ) u_dut (
        .i_clk     (tb_clk),
        .i_rst     (tb_rst),
        .i_en      (tb_en),
        .i_stall   (tb_stall),
        .i_halt    (tb_halt),
        .i_next_pc (tb_next_pc),
        .o_pc      (tb_pc),
        .o_halted  (tb_halted)
    );

    initial tb_clk = 1'b0;
    always #(T/2) tb_clk = ~tb_clk;

    task ciclo;
        begin
            @(posedge tb_clk);
            #1;
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

    task check_bit;
        input          valor;
        input          esperado;
        input [8*44:1] nombre;
        begin
            if (valor !== esperado) begin
                $display("[FAIL] %0s | %b (esperado %b)", nombre, valor, esperado);
                errores = errores + 1;
            end
            else $display("[ OK ] %0s | %b", nombre, valor);
        end
    endtask

    initial begin
        $dumpfile("registro_pc_tb.vcd");
        $dumpvars(0, registro_pc_tb);

        errores    = 0;
        tb_rst     = 1'b1;
        tb_en      = 1'b0;
        tb_stall   = 1'b0;
        tb_halt    = 1'b0;
        tb_next_pc = 32'hAAAA_AAA0;

        $display("\n=== 1. Reset ===");
        ciclo();
        tb_rst = 1'b0;
        check_pc(PC_RESET, "PC tras reset");
        check_bit(tb_halted, 1'b0, "halted bajo");

        $display("\n=== 2. Carga con en=1 ===");
        tb_en = 1'b1;
        ciclo();
        check_pc(32'hAAAA_AAA0, "carga i_next_pc");
        tb_next_pc = 32'hBBBB_BBB0;
        ciclo();
        check_pc(32'hBBBB_BBB0, "carga el siguiente valor");

        $display("\n=== 3. en=0 : congelado (el clock sigue) ===");
        tb_en      = 1'b0;
        tb_next_pc = 32'hCCCC_CCC0;
        for (i = 0; i < 5; i = i + 1) ciclo();
        check_pc(32'hBBBB_BBB0, "no cargo en 5 ciclos con en=0");

        $display("\n=== 4. Paso a paso ===");
        tb_en = 1'b1; ciclo(); tb_en = 1'b0;
        check_pc(32'hCCCC_CCC0, "un pulso de en = una carga");
        tb_next_pc = 32'hDDDD_DDD0;
        ciclo(); ciclo();
        check_pc(32'hCCCC_CCC0, "quieto entre pasos");

        $display("\n=== 5. Stall ===");
        tb_en    = 1'b1;
        tb_stall = 1'b1;
        for (i = 0; i < 3; i = i + 1) ciclo();
        check_pc(32'hCCCC_CCC0, "stall bloquea la carga");
        tb_stall = 1'b0;
        ciclo();
        check_pc(32'hDDDD_DDD0, "al soltar, carga");

        $display("\n=== 6. HALT STICKY ===");
        tb_next_pc = 32'hEEEE_EEE0;
        tb_halt    = 1'b1;
        ciclo();
        check_pc(32'hDDDD_DDD0, "HALT congela en el acto");
        check_bit(tb_halted, 1'b1, "o_halted alto");
        tb_halt = 1'b0;                     // el HALT avanza de ID a EX
        for (i = 0; i < 10; i = i + 1) ciclo();
        check_pc(32'hDDDD_DDD0, "sigue congelado con i_halt YA BAJO");
        check_bit(tb_halted, 1'b1, "o_halted sticky");

        $display("\n=== 7. Reset con en=0 : prioridad absoluta ===");
        tb_en  = 1'b0;
        tb_rst = 1'b1;
        ciclo();
        tb_rst = 1'b0;
        check_pc(PC_RESET, "resetea con el pipeline pausado");
        check_bit(tb_halted, 1'b0, "el reset limpia el halt");

        $display("\n--------------------------------------------------");
        if (errores == 0) $display(">>> TEST PASSED : registro_pc");
        else              $display(">>> TEST FAILED : %0d errores", errores);
        $display("--------------------------------------------------\n");
        $finish;
    end

endmodule

`default_nettype wire