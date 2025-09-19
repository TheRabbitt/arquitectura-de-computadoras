module top #(
    parameter NB_IN  = 8,
    parameter NB_OUT = 8,
    parameter NB_OP  = 6
)(
    input  wire                            clk          ,
    input  wire                            rst_n        , // Active low reset
    input  wire        [2       :0]        i_btn        ,
    input  wire        [NB_IN-1 :0]        i_sw_data    , 
    output wire        [NB_OUT-1:0]        o_leds_result,
    output wire                            o_carry      ,
    output wire                            o_zero       
);

reg        [NB_IN-1:0]   reg_a;
reg        [NB_IN-1:0]   reg_b;
reg        [NB_OP-1:0]  reg_op;


// Instanciación de la ALU
alu #(
    .NB_IN(NB_IN)  ,
    .NB_OUT(NB_OUT),
    .NB_OP(NB_OP)
) alu_inst (
    .i_a(reg_a)                ,
    .i_b(reg_b)                ,
    .i_op(reg_op)              ,
    .o_outresult(o_leds_result),
    .o_carry(o_carry)          ,
    .o_zero(o_zero)
);

always@(posedge clk ) begin
    if (rst_n) begin
        reg_a         <= {NB_IN{1'b0}} ;
        reg_b         <= {NB_IN{1'b0}} ;
        reg_op        <= {NB_OP{1'b0}} ;
    end
    else begin
        if (i_btn[0]) begin
            reg_a <= i_sw_data;
        end
        else if (i_btn[1]) begin 
            reg_b <= i_sw_data;
        end
        else if (i_btn[2]) begin 
            reg_op <= i_sw_data[NB_OP-1:0];
        end
    end
end
    

endmodule


