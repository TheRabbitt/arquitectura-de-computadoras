`timescale 1ns / 1ps
`default_nettype none

// ---------------------------------------------------------------------------
// top_tb.v
//
// Testbench AUTOVERIFICANTE: no hay que mirar ondas para saber si paso.
// Termina con "TEST PASSED" o "TEST FAILED" y un codigo de salida.
//
// Este es el patron que van a repetir en TODOS los modulos del proyecto.
// Un testbench que solo genera un .vcd para mirar a ojo no sirve como
// regresion: dentro de dos semanas nadie se acuerda de que tenia que ver.
// ---------------------------------------------------------------------------

module top_tb;

    // Parametros chicos para que la simulacion sea corta.
    // DIV = 1000/(2*100) = 5 ciclos por medio periodo.
    localparam integer CLK_HZ   = 1000;
    localparam integer BLINK_HZ = 100;
    localparam integer DIV      = CLK_HZ / (2 * BLINK_HZ);

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    wire [1:0] led;

    integer errors = 0;

    always #5 clk = ~clk;   // 100 MHz simulados

    top #(
        .CLK_HZ  (CLK_HZ),
        .BLINK_HZ(BLINK_HZ)
    ) dut (
        .clk  (clk),
        .rst_n(rst_n),
        .led  (led)
    );

    task check(input condicion, input [8*64-1:0] nombre);
        begin
            if (condicion) begin
                $display("  [ok]   %0s", nombre);
            end else begin
                $display("  [FAIL] %0s", nombre);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/top_tb.vcd");
        $dumpvars(0, top_tb);

        $display("== top_tb ==");

        // --- Test 1: durante el reset, el heartbeat queda quieto en 0 ---
        rst_n = 1'b0;                 // boton apretado -> reset activo
        repeat (10) @(posedge clk);
        check(led[0] === 1'b0, "heartbeat en 0 durante reset");
        check(led[1] === 1'b1, "led de reset encendido durante reset");

        // --- Test 2: soltamos el reset y el heartbeat arranca ---
        rst_n = 1'b1;
        repeat (4) @(posedge clk);    // 2 ciclos de sincronizador + margen
        check(led[1] === 1'b0, "led de reset apagado tras soltar");

        // --- Test 3: el heartbeat togglea con el periodo esperado ---
        @(posedge led[0]);            // esperamos el primer flanco
        begin : medir
            integer t0, t1;
            t0 = $time;
            @(negedge led[0]);
            t1 = $time;
            // medio periodo = DIV ciclos de 10 ns
            check((t1 - t0) == DIV * 10, "medio periodo del heartbeat correcto");
        end

        $display("== resultado: %0d error(es) ==", errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED");

        if (errors != 0) $fatal(1);
        $finish;
    end

    // Red de seguridad: si algo se cuelga, no simulamos para siempre.
    initial begin
        #100_000;
        $display("TEST FAILED (timeout)");
        $fatal(1);
    end

endmodule

`default_nettype wire
