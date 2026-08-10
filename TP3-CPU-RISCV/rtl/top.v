`timescale 1ns / 1ps
`default_nettype none

// ---------------------------------------------------------------------------
// top.v  -  FASE 0
//
// Objetivo unico: probar que el flujo completo funciona
// (VS Code -> git -> script TCL -> Vivado -> bitstream -> placa).
//
// No hace nada util todavia. led[0] parpadea a 1 Hz, led[1] refleja el boton
// de reset. Si eso se ve en la Nexys 4, el XDC, el clock y el programador
// estan bien y podemos empezar a construir cosas de verdad encima.
//
// OJO: en la Nexys 4 el boton CPU_RESETN es ACTIVO EN BAJO (vale 1 en reposo).
// ---------------------------------------------------------------------------

module top #(
    parameter integer CLK_HZ   = 100_000_000,  // reloj de la placa
    parameter integer BLINK_HZ = 1             // parpadeos por segundo
) (
    input  wire       clk,     // CLK100MHZ, pin E3
    input  wire       rst_n,   // CPU_RESETN, pin C12 (activo en bajo)
    output wire [1:0] led
);

    // Reset sincronico interno, activo en alto.
    // Sincronizamos el boton porque es asincronico respecto de clk.
    reg [1:0] rst_sync = 2'b11;
    wire      rst = rst_sync[1];

    always @(posedge clk) begin
        rst_sync <= {rst_sync[0], ~rst_n};
    end

    // Divisor: DIV ciclos por medio periodo del parpadeo.
    localparam integer DIV = CLK_HZ / (2 * BLINK_HZ);
    localparam integer W   = (DIV > 1) ? $clog2(DIV) : 1;

    reg [W-1:0] cnt  = {W{1'b0}};
    reg         beat = 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            cnt  <= {W{1'b0}};
            beat <= 1'b0;
        end else if (cnt == DIV - 1) begin
            cnt  <= {W{1'b0}};
            beat <= ~beat;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

    assign led = {rst, beat};

endmodule

`default_nettype wire
