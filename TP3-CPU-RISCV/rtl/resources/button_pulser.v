module button_pulser (
    input  wire i_clk,
    input  wire i_rst,
    input  wire i_btn,
    output wire o_pulse
);
    localparam CNT_MAX = 20'd1_000_000; // ~10ms a 100MHz, ajustable
    reg [19:0] cnt;
    reg        btn_stable, btn_stable_d;

    always @(posedge i_clk) begin
        if (i_rst) begin
            cnt <= 0; btn_stable <= 0; btn_stable_d <= 0;
        end else begin
            if (i_btn != btn_stable) begin
                cnt <= cnt + 1;
                if (cnt == CNT_MAX) begin
                    btn_stable <= i_btn;
                    cnt <= 0;
                end
            end else begin
                cnt <= 0;
            end
            btn_stable_d <= btn_stable;
        end
    end

    assign o_pulse = btn_stable & ~btn_stable_d;
endmodule