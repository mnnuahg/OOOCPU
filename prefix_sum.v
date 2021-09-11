module prefix_sum #(parameter   NUM_INPUT   = 8,
                    parameter   INPUT_SIZE  = 4,
                    parameter   OUTPUT_SIZE = 4)
(
    input   [NUM_INPUT*INPUT_SIZE -1:0] in,
    output  [NUM_INPUT*OUTPUT_SIZE-1:0] out
);

    wire    [NUM_INPUT*OUTPUT_SIZE-1:0] stages  [$clog2(NUM_INPUT):0];
    
    generate
        genvar i, j;
        
        for (i=0; i<NUM_INPUT; i=i+1) begin: gen_stages0
            assign  stages[0][i*OUTPUT_SIZE+:OUTPUT_SIZE] = in[i];
        end
        
        for (j=0; j<$clog2(NUM_INPUT); j=j+1) begin: gen_stages1
            for (i=0; i<NUM_INPUT; i=i+1) begin: gen_stages2
                if (i < (1<<j)) begin: gen_sel0
                    assign  stages[j+1][i*OUTPUT_SIZE+:OUTPUT_SIZE] = stages[j][i*OUTPUT_SIZE+:OUTPUT_SIZE];
                end
                else begin: gen_sel1
                    assign  stages[j+1][i*OUTPUT_SIZE+:OUTPUT_SIZE] = stages[j][i*OUTPUT_SIZE+:OUTPUT_SIZE]+stages[j][(i-(1<<j))*OUTPUT_SIZE+:OUTPUT_SIZE];
                end
            end
        end
    endgenerate
    
    assign out = stages[$clog2(NUM_INPUT)];

endmodule
