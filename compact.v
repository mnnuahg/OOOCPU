module compact #(parameter  NUM_INPUT   = 8,
                 parameter  INPUT_SIZE  = 4)
(
    input   [NUM_INPUT           -1:0]  in_vld,
    input   [NUM_INPUT*INPUT_SIZE-1:0]  in_data,
    output  [NUM_INPUT           -1:0]  out_vld,
    output  [NUM_INPUT*INPUT_SIZE-1:0]  out_data
);

    localparam  PSUM_SIZE   = $clog2(NUM_INPUT);
    
    wire    [NUM_INPUT*PSUM_SIZE    -1:0] in_psum;

    prefix_sum  #(.NUM_INPUT    (NUM_INPUT),
                  .INPUT_SIZE   (1),
                  .OUTPUT_SIZE  (PSUM_SIZE))
    vld_psum(  .in  (~in_vld),
               .out (in_psum));

    wire    [NUM_INPUT              -1:0] stages_vld  [$clog2(NUM_INPUT):0];
    wire    [NUM_INPUT*PSUM_SIZE    -1:0] stages_psum [$clog2(NUM_INPUT):0];
    wire    [NUM_INPUT*INPUT_SIZE   -1:0] stages_data [$clog2(NUM_INPUT):0];
    
    assign  stages_vld  [0] = in_vld;
    assign  stages_psum [0] = in_psum;
    assign  stages_data [0] = in_data;
    
    generate
        genvar i, j;
        
        for (j=0; j<$clog2(NUM_INPUT); j=j+1) begin: gen_stage0
            for (i=0; i<NUM_INPUT-(1<<j); i=i+1) begin: gen_stage1
                assign  stages_psum[j+1][i*PSUM_SIZE +:PSUM_SIZE ] = stages_vld[j][i] && !stages_psum[j][i*PSUM_SIZE+j] ? 
                                                                     stages_psum[j][ i        *PSUM_SIZE +:PSUM_SIZE ] :
                                                                     stages_psum[j][(i+(1<<j))*PSUM_SIZE +:PSUM_SIZE ];

                assign  stages_data[j+1][i*INPUT_SIZE+:INPUT_SIZE] = stages_vld[j][i] && !stages_psum[j][i*PSUM_SIZE+j] ? 
                                                                     stages_data[j][ i        *INPUT_SIZE+:INPUT_SIZE] :
                                                                     stages_data[j][(i+(1<<j))*INPUT_SIZE+:INPUT_SIZE];

                assign  stages_vld [j+1][i                       ] = stages_vld[j][i] && !stages_psum[j][i*PSUM_SIZE+j] ? 
                                                                     1'b1 :
                                                                     stages_vld[j][i+(1<<j)] && stages_psum[j][i*PSUM_SIZE+j];
            end
            
            for (i=NUM_INPUT-(1<<j); i<NUM_INPUT; i=i+1) begin: gen_stage2
                assign  stages_psum[j+1][i*PSUM_SIZE +:PSUM_SIZE ] = stages_psum[j][ i        *PSUM_SIZE +:PSUM_SIZE ];
                assign  stages_data[j+1][i*INPUT_SIZE+:INPUT_SIZE] = stages_data[j][ i        *INPUT_SIZE+:INPUT_SIZE];
                assign  stages_vld [j+1][i                       ] = stages_vld[j][i] && !stages_psum[j][i*PSUM_SIZE+j];
            end
        end
        
    endgenerate
    
    assign  out_vld     = stages_vld [$clog2(NUM_INPUT)];
    assign  out_data    = stages_data[$clog2(NUM_INPUT)];

endmodule



