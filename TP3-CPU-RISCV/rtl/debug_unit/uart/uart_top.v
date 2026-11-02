`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Módulo: uart_top
// Descripción:
//   Encapsula y adapta los módulos UART existentes (uart_rx, uart_tx) junto con:
//   - Generador de baud-rate (baud_rate_generator) parametrizable.
//   - Sincronizador de doble flip-flop en la línea serial RX para evitar
//     metaestabilidad desde el pin externo de la FPGA.
//==============================================================================

module uart_top #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 115_200,
    parameter integer DBIT        = 8,
    parameter integer SB_TICK     = 16,
    parameter integer DVSR        = (CLK_FREQ_HZ + ((BAUD_RATE * SB_TICK) / 2)) / (BAUD_RATE * SB_TICK)
)(
    input  wire            i_clk,
    input  wire            i_rst,

    // Pines físicos UART
    input  wire            i_rx,
    output wire            o_tx,

    // Interfaz hacia la Debug Unit
    output wire            o_rx_done_tick,
    output wire [DBIT-1:0] o_rx_data,
    input  wire            i_tx_start,
    input  wire [DBIT-1:0] i_tx_data,
    output wire            o_tx_done_tick
);

    wire w_s_tick;

    // Sincronizador de 2 etapas para entrada asíncrona RX (idle en alto)
    reg r_rx_sync1;
    reg r_rx_sync2;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_rx_sync1 <= 1'b1;
            r_rx_sync2 <= 1'b1;
        end else begin
            r_rx_sync1 <= i_rx;
            r_rx_sync2 <= r_rx_sync1;
        end
    end

    baud_rate_generator #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .SB_TICK    (SB_TICK),
        .DVSR       (DVSR)
    ) u_baud_gen (
        .i_clk  (i_clk),
        .i_rst  (i_rst),
        .o_tick (w_s_tick)
    );

    uart_rx #(
        .DBIT   (DBIT),
        .SB_TICK(SB_TICK)
    ) u_uart_rx (
        .clk          (i_clk),
        .reset        (i_rst),
        .rx           (r_rx_sync2),
        .s_tick       (w_s_tick),
        .rx_done_tick (o_rx_done_tick),
        .dout         (o_rx_data)
    );

    uart_tx #(
        .DBIT   (DBIT),
        .SB_TICK(SB_TICK)
    ) u_uart_tx (
        .clk          (i_clk),
        .reset        (i_rst),
        .tx_start     (i_tx_start),
        .s_tick       (w_s_tick),
        .din          (i_tx_data),
        .tx_done_tick (o_tx_done_tick),
        .tx           (o_tx)
    );

endmodule
`default_nettype wire

