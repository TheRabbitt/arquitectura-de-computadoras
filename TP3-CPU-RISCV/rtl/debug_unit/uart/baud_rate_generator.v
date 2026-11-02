`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: baud_rate_generator
// Descripción:
//   Generador de pulsos de sobremuestreo (s_tick) de 1 ciclo de reloj para UART.
//   Cumple estrictamente la regla de no intervenir el clock: genera una señal
//   sincrónica de habilitación a frecuencia (BAUD_RATE * SB_TICK).
//
//   Por defecto (100 MHz, 115200 baudios, 16 ticks/bit):
//     DVSR = round(100_000_000 / (115200 * 16)) = 54  (error +0.47%)
//==============================================================================

module baud_rate_generator #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 115_200,
    parameter integer SB_TICK     = 16,
    parameter integer DVSR        = (CLK_FREQ_HZ + ((BAUD_RATE * SB_TICK) / 2)) / (BAUD_RATE * SB_TICK)
)(
    input  wire i_clk,
    input  wire i_rst,
    output wire o_tick
);

    localparam integer CNT_WIDTH = (DVSR <= 2) ? 2 : $clog2(DVSR);

    reg [CNT_WIDTH-1:0] r_cnt;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_cnt <= {CNT_WIDTH{1'b0}};
        end else if (r_cnt == (DVSR - 1)) begin
            r_cnt <= {CNT_WIDTH{1'b0}};
        end else begin
            r_cnt <= r_cnt + {{(CNT_WIDTH-1){1'b0}}, 1'b1};
        end
    end

    assign o_tick = (r_cnt == (DVSR - 1));

endmodule
`default_nettype wire

