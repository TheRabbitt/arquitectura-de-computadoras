`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// sumador_tb
//   Testbench self-checking. Sin clock: el DUT es combinacional puro.
//   Corre casos dirigidos (los que realmente importan) + un barrido aleatorio.
//------------------------------------------------------------------------------
module sumador_tb;

    localparam integer NB        = 32;
    localparam integer N_RANDOM  = 200;
    localparam integer N_DIRIGID = 8;

    reg  [NB-1:0] tb_a      ;
    reg  [NB-1:0] tb_b      ;
    wire [NB-1:0] tb_result ;

    reg  [NB-1:0] esperado  ;
    integer       errores   ;
    integer       i         ;

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    sumador #(
        .NB_IN    (NB)
    ) u_dut (
        .i_a      (tb_a),
        .i_b      (tb_b),
        .o_result (tb_result)
    );

    //--------------------------------------------------------------------------
    // Tarea de chequeo
    //--------------------------------------------------------------------------
    task check;
        input [NB-1:0]   a      ;
        input [NB-1:0]   b      ;
        input [NB-1:0]   exp    ;
        input [8*40:1]   nombre ;
        begin
            tb_a = a;
            tb_b = b;
            #10;
            if (tb_result !== exp) begin
                $display("[FAIL] %0s | %h + %h -> %h (esperado %h)",
                         nombre, a, b, tb_result, exp);
                errores = errores + 1;
            end
            else begin
                $display("[ OK ] %0s | %h + %h -> %h", nombre, a, b, tb_result);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Estimulo
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("sumador_tb.vcd");
        $dumpvars(0, sumador_tb);

        errores = 0;
        tb_a    = {NB{1'b0}};
        tb_b    = {NB{1'b0}};
        #10;

        $display("=== Casos dirigidos ===");
        check(32'h0000_0000, 32'h0000_0000, 32'h0000_0000, "cero + cero              ");
        check(32'h0000_0000, 32'h0000_0004, 32'h0000_0004, "PC+4 desde reset         ");
        check(32'h0000_0010, 32'h0000_0004, 32'h0000_0014, "PC+4 generico            ");
        check(32'h0000_0040, 32'hFFFF_FFF0, 32'h0000_0030, "branch hacia atras (-16) ");
        check(32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0000, "wrap unsigned            ");
        check(32'h7FFF_FFFF, 32'h0000_0001, 32'h8000_0000, "overflow signed (envuelve)");
        check(32'h8000_0000, 32'h8000_0000, 32'h0000_0000, "min + min                ");
        check(32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFE, "(-1) + (-1)              ");

        $display("=== Barrido aleatorio (%0d vectores) ===", N_RANDOM);
        for (i = 0; i < N_RANDOM; i = i + 1) begin
            tb_a     = $random;
            tb_b     = $random;
            esperado = tb_a + tb_b;   // truncado a NB bits por el ancho de 'esperado'
            #10;
            if (tb_result !== esperado) begin
                $display("[FAIL] random %0d | %h + %h -> %h (esperado %h)",
                         i, tb_a, tb_b, tb_result, esperado);
                errores = errores + 1;
            end
        end

        $display("--------------------------------------------------");
        if (errores == 0)
            $display(">>> TEST PASSED (%0d dirigidos + %0d aleatorios)",
                     N_DIRIGID, N_RANDOM);
        else
            $display(">>> TEST FAILED: %0d errores", errores);
        $display("--------------------------------------------------");

        $finish;
    end

endmodule

`default_nettype wire