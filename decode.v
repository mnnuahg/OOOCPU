module decode #(parameter DATA_WIDTH = 16)
(
    input   [DATA_WIDTH     -1:0]   in,
    output  [(1<<DATA_WIDTH)-1:0]   out
);

    localparam  OUT_BIT = (1<<DATA_WIDTH);
    
    wire    [OUT_BIT-1:0]   stages[DATA_WIDTH-1:0];
    
    generate
        genvar i, j;
        
        for (j=0; j<OUT_BIT; j=j+1) begin: gen_stage_0
            assign stages[0][j] = j[0] ? in[0] : ~in[0];
        end
        
        for (i=1; i<DATA_WIDTH; i=i+1) begin: gen_stage_i
            for (j=0; j<OUT_BIT; j=j+1) begin: gen_stage_i_j
                assign  stages[i][j] = (j[i] ? in[i] : ~in[i]) & stages[i-1][j];
            end
        end
    endgenerate
    
    assign out = stages[DATA_WIDTH-1];

endmodule
