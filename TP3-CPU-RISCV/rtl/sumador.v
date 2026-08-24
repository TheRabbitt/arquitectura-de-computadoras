module sumador
#(
    parameter NB_IN  = 32,
    parameter NB_OUT = 32,
)(

    input  wire signed         [NB_IN-1:0]   i_a        ,
    input  wire signed         [NB_IN-1:0]   i_b        ,

    output wire                [NB_OUT-1:0]  o_outresult, 
);
    reg signed                 [NB_OUT-1:0]   result    ;

always@(*)begin 
    result     = i_a + i_b;
end

    assign o_outresult = result;

endmodule