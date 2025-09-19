module alu 
#(
    parameter NB_IN  = 8,
    parameter NB_OUT = 8,
    parameter NB_OP  = 6
)(

    input  wire signed         [NB_IN-1:0]   i_a        ,
    input  wire signed         [NB_IN-1:0]   i_b        ,
    input  wire                [NB_OP-1:0]   i_op       ,

    output wire                [NB_OUT-1:0]  o_outresult, 
    output wire                              o_carry    ,
    output wire                              o_zero
);
    reg signed                 [NB_OUT-1:0]   result    ;
    reg                                     carry_flag;

    localparam op_suma  =       6'b100000  ;
    localparam op_resta =       6'b100010  ;
    localparam op_and   =       6'b100100  ;
    localparam op_or    =       6'b100101  ;
    localparam op_xor   =       6'b100110  ;
    localparam op_sra   =       6'b000011  ;
    localparam op_srl   =       6'b000010  ;
    localparam op_nor   =       6'b100111  ;
    localparam max_val  =       8'b11111111;

always@(*)begin 
    carry_flag = 1'b0; // limpiar por defecto
    case(i_op)
        op_suma: begin // Operacion SUMA
            result     = i_a + i_b;
            carry_flag = (i_a[NB_IN-1] == i_b[NB_IN-1]) && 
                         (result[NB_OUT-1] != i_a[NB_IN-1]); // usar lógica de overflow con signo
        end

        op_resta: begin
            result     = i_a - i_b                         ; // Operacion RESTA
            carry_flag = (i_a[NB_IN-1] != i_b[NB_IN-1]) && 
                         (result[NB_OUT-1] != i_a[NB_IN-1]);
        end

        op_and:         result = i_a & i_b           ;      // Operacion AND
        op_or:          result = i_a | i_b           ;      // Operacion OR
        op_xor:         result = i_a ^ i_b           ;      // Operacion XOR
        op_sra:         result = (i_a) >>> i_b       ;      // Operación SRA con signo
        op_srl:         result = i_a >> i_b          ;      // Operacion SRL
        op_nor:         result = ~(i_a | i_b)        ;      // Operacion NOR
        default:        result = {NB_OUT{1'b0}}      ;      // Toda la salida en 0 por default
    endcase
end
   
    assign o_carry = carry_flag; // o_carry = 1 si hubo carry en la suma

    assign o_zero  = ~|result; // o_zero = 1 si todos los bits de result son 0

    assign o_outresult = result;

endmodule