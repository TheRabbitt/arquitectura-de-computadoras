`timescale 1ns / 1ps
module button_pulser (
    input  wire i_clk,
    input  wire i_rst,
    input  wire i_btn,
    output wire o_pulse
);
    reg [2:0] shift_reg;
    
    always @(posedge i_clk) begin
        if (i_rst) begin
            shift_reg <= 3'b000;
        end else begin
            shift_reg <= {shift_reg[1:0], i_btn};
        end
    end
    
    // Detecta el flanco de subida (paso de 0 a 1)
    assign o_pulse = (~shift_reg[2] & shift_reg[1]);
endmodule