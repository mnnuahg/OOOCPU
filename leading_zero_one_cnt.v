module leading_zero_one_cnt #(  parameter DATA_WIDTH    = 16,
                                parameter COUNT_ZERO    = 1)
(
    input   [DATA_WIDTH         -1:0]    in,
    output  [$clog2(DATA_WIDTH)   :0]    cnt
);

    localparam  CNT_BIT = $clog2(DATA_WIDTH)+1;

    wire    [DATA_WIDTH -1:0]   stages[CNT_BIT-2:0];
    
    assign  stages  [CNT_BIT-2] = in;
    generate
        genvar i;
        
        if (COUNT_ZERO)
            assign  cnt[CNT_BIT-1]  = ~(|in);
        else
            assign  cnt[CNT_BIT-1]  =   &in;

        for (i=CNT_BIT-2; i>=0; i=i-1) begin: gen_cnt
            if (COUNT_ZERO)
                assign  cnt[i]  = ~(|stages[i][0+:1<<i]);
            else
                assign  cnt[i]  =   &stages[i][0+:1<<i];
        end
        
        for (i=CNT_BIT-3; i>=0; i=i-1) begin: gen_stage
            assign  stages[i][0+:1<<(i+1)]   = cnt[i+1] ? stages[i+1][1<<(i+1)+:1<<(i+1)] : stages[i+1][0+:1<<(i+1)];
        end
    endgenerate
endmodule
