module spec_vector #(parameter  NUM_TAG         = 4,
                     parameter  NUM_REG         = 8,
                     parameter  SPEC_DEPTH      = 4,
                     parameter  PC_BIT          = 4,
                     parameter  INST_ID_BIT     = 8,
                     parameter  REG_ID_BIT      = $clog2(NUM_REG),
                     parameter  TAG_ID_BIT      = $clog2(NUM_TAG),
                     parameter  SPEC_LEVEL_BIT  = $clog2(SPEC_DEPTH)+1)
(
    input                                   clk,
    input                                   rst_n,
    
    // TODO: CPU should only send speculative branches, so if branch_cond_reg is not wr_pend,
    //       or is write back at the same T, then branch_vld should be off
    //       => What if the write back is not the branch reg but will cause a rollback?
    //          To simplify design, when rollback occurs branch_vld should also be off
    input                                   br_vld,
    input       [REG_ID_BIT         -1:0]   br_cond_reg,
    // TODO: If two branches takes the same br_cond_reg, then
    //       they must have the same br_predicted_val, otherwise
    //       we may have branch pred succes and fail at the same time when the cond reg wb
    input                                   br_cond_predicted_val,
    input       [PC_BIT             -1:0]   br_rollback_pc,
    input       [INST_ID_BIT        -1:0]   br_rollback_id,
    input       [NUM_TAG*REG_ID_BIT -1:0]   br_rollback_tag_map,
    
    output reg  [SPEC_LEVEL_BIT     -1:0]   cur_spec_level,     // The spec_level of instructions executed in this cycle
                                                                // Should consider cond_wb_vld in this cycle
                                                                // but don't need to consider br_vld since it won't write any register
                                                                // and cur_spec_level is used to keep track the spec level of each register write
    input                                   cond_wb_vld,
    input       [REG_ID_BIT         -1:0]   cond_wb_reg,
    input                                   cond_wb_val,
    
    output                                          br_pred_vld,
    output                                          br_pred_succ,    // predict success
                                                            // If predict fail all deeper level should be cleaned
                                                            // If predict success, it's possible that we hit a branch
                                                            // in the same clock so specuation level didn't change
                                                            // However, this should be considered in cur_spec_level
                                                            // If speculation success in this cycle, then cur_spec_level
                                                            // should -1 in the same cycle
    output      [SPEC_LEVEL_BIT*(SPEC_DEPTH+1)-1:0] br_pred_succ_nxt_levels,   // The new levels after spec success
                                                                            // We need multiple entries because a conditonal register may be used in multiple spec levels

    output      [SPEC_LEVEL_BIT               -1:0] br_pred_fail_level,   // all spec levels >= this should rollback if !spec_cond_wb_succ
    output      [NUM_TAG*REG_ID_BIT           -1:0] br_pred_fail_tag_map,
    output      [PC_BIT                       -1:0] br_pred_fail_pc,
    output      [INST_ID_BIT                  -1:0] br_pred_fail_id
);

    reg     [SPEC_DEPTH         -1:0]   entry_vld;
    reg     [REG_ID_BIT         -1:0]   entry_cond_reg      [SPEC_DEPTH-1:0];
    reg                                 entry_cond_pred_val [SPEC_DEPTH-1:0];
    reg     [PC_BIT             -1:0]   entry_fail_pc       [SPEC_DEPTH-1:0];
    reg     [INST_ID_BIT        -1:0]   entry_fail_id       [SPEC_DEPTH-1:0];
    reg     [NUM_TAG*REG_ID_BIT -1:0]   entry_fail_tag_map  [SPEC_DEPTH-1:0];
    
    reg     [SPEC_DEPTH         -1:0]   match_wb_reg;
    wire    [SPEC_LEVEL_BIT     -1:0]   top_match_level;

    always @* begin: gen_match_wb_reg
        integer i;
        for (i=0; i<SPEC_DEPTH; i=i+1) begin
            match_wb_reg[i] = entry_vld[i] && entry_cond_reg[i] == cond_wb_reg;
        end
    end

    leading_zero_one_cnt    #(.DATA_WIDTH(SPEC_DEPTH), .COUNT_ZERO(1))
    find_top_match_level(.in (match_wb_reg),
                         .cnt(top_match_level));

    assign  br_pred_vld             = cond_wb_vld && ~top_match_level[SPEC_LEVEL_BIT-1];
    assign  br_pred_succ            = cond_wb_val == entry_cond_pred_val[top_match_level];

    assign  br_pred_fail_level      = top_match_level+1;
    assign  br_pred_fail_tag_map    = entry_fail_tag_map    [top_match_level];
    assign  br_pred_fail_pc         = entry_fail_pc         [top_match_level];
    assign  br_pred_fail_id         = entry_fail_id         [top_match_level];
    
    
    wire    [SPEC_DEPTH*REG_ID_BIT          -1:0]   orig_entry_cond_reg;
    wire    [SPEC_DEPTH                     -1:0]   orig_entry_cond_pred_val;
    wire    [SPEC_DEPTH*PC_BIT              -1:0]   orig_entry_fail_pc;
    wire    [SPEC_DEPTH*INST_ID_BIT         -1:0]   orig_entry_fail_id;
    wire    [SPEC_DEPTH*NUM_TAG*REG_ID_BIT  -1:0]   orig_entry_fail_tag_map;
    
    generate
        genvar i;
        for (i=0; i<SPEC_DEPTH; i=i+1) begin: gen_orig
            assign  orig_entry_cond_reg     [i*REG_ID_BIT        +:REG_ID_BIT        ]  = entry_cond_reg     [i];
            assign  orig_entry_cond_pred_val[i                                       ]  = entry_cond_pred_val[i];
            assign  orig_entry_fail_pc      [i*PC_BIT            +:PC_BIT            ]  = entry_fail_pc      [i];
            assign  orig_entry_fail_id      [i*INST_ID_BIT       +:INST_ID_BIT       ]  = entry_fail_id      [i];
            assign  orig_entry_fail_tag_map [i*NUM_TAG*REG_ID_BIT+:NUM_TAG*REG_ID_BIT]  = entry_fail_tag_map [i];
        end
    endgenerate
    
    wire    [SPEC_DEPTH                     -1:0]   succ_entry_vld;
    wire    [SPEC_DEPTH*REG_ID_BIT          -1:0]   succ_entry_cond_reg;
    wire    [SPEC_DEPTH                     -1:0]   succ_entry_cond_pred_val;
    wire    [SPEC_DEPTH*PC_BIT              -1:0]   succ_entry_fail_pc;
    wire    [SPEC_DEPTH*INST_ID_BIT         -1:0]   succ_entry_fail_id;
    wire    [SPEC_DEPTH*NUM_TAG*REG_ID_BIT  -1:0]   succ_entry_fail_tag_map;
    
    wire    [SPEC_DEPTH*SPEC_LEVEL_BIT      -1:0]   succ_nxt_level;
    
    compact #(  .NUM_INPUT  (SPEC_DEPTH),
                .INPUT_SIZE (REG_ID_BIT))
    compact_cond_reg        (.in_vld    (entry_vld & ~match_wb_reg),
                             .in_data   (orig_entry_cond_reg),
                             .out_vld   (succ_entry_vld),
                             .out_data  (succ_entry_cond_reg));
    
    compact #(  .NUM_INPUT  (SPEC_DEPTH),
                .INPUT_SIZE (1))
    compact_cond_pred_val   (.in_vld    (entry_vld & ~match_wb_reg),
                             .in_data   (orig_entry_cond_pred_val),
                             .out_vld   (),
                             .out_data  (succ_entry_cond_pred_val));

    compact #(  .NUM_INPUT  (SPEC_DEPTH),
                .INPUT_SIZE (PC_BIT))
    compact_fail_pc         (.in_vld    (entry_vld & ~match_wb_reg),
                             .in_data   (orig_entry_fail_pc),
                             .out_vld   (),
                             .out_data  (succ_entry_fail_pc));
                             
    compact #(  .NUM_INPUT  (SPEC_DEPTH),
                .INPUT_SIZE (INST_ID_BIT))
    compact_fail_id         (.in_vld    (entry_vld & ~match_wb_reg),
                             .in_data   (orig_entry_fail_id),
                             .out_vld   (),
                             .out_data  (succ_entry_fail_id));
    
    compact #(  .NUM_INPUT  (SPEC_DEPTH),
                .INPUT_SIZE (NUM_TAG*REG_ID_BIT))
    compact_fail_tag_map    (.in_vld    (entry_vld & ~match_wb_reg),
                             .in_data   (orig_entry_fail_tag_map),
                             .out_vld   (),
                             .out_data  (succ_entry_fail_tag_map));
                             
    prefix_sum  #(  .NUM_INPUT  (SPEC_DEPTH),
                    .INPUT_SIZE (1),
                    .OUTPUT_SIZE(SPEC_LEVEL_BIT))
    count_succ_nxt_level(   .in (entry_vld & ~match_wb_reg),
                            .out(succ_nxt_level));

    // Add a 0 at first so level 0 remains level 0
    assign  br_pred_succ_nxt_levels  = {succ_nxt_level, {SPEC_LEVEL_BIT{1'b0}}};
    
    wire    [SPEC_LEVEL_BIT     -1:0]   entry_vld_cnt;
    wire    [SPEC_LEVEL_BIT     -1:0]   succ_entry_vld_cnt;
    
    leading_zero_one_cnt    #(  .DATA_WIDTH(SPEC_DEPTH),
                                .COUNT_ZERO(0))
    cnt_entry_vld0  (.in    (entry_vld),
                     .cnt   (entry_vld_cnt));

    // TODO: For better timing we may us population count on (entry_vld & ~match_wb_reg)
    leading_zero_one_cnt    #(  .DATA_WIDTH(SPEC_DEPTH),
                                .COUNT_ZERO(0))
    cnt_entry_vld1  (.in    (succ_entry_vld),
                     .cnt   (succ_entry_vld_cnt));
    
                         
    reg     [$clog2(SPEC_DEPTH) -1:0]   new_entry_idx;
    
    always @* begin
        if (br_pred_vld) begin
            // when branch pred fail, br_vld should not be on so new_entry_idx is don't care
            // when branch pred fail, no instruction will be executed at the same cycle, 
            // so cur_spec_level is also don't care
            new_entry_idx   = succ_entry_vld_cnt;
            cur_spec_level  = succ_entry_vld_cnt;
        end
        else begin
            new_entry_idx   = entry_vld_cnt;
            cur_spec_level  = entry_vld_cnt;
        end
    end
    
    generate
        for (i=0; i<SPEC_DEPTH; i=i+1) begin: gen_entry
            always@(posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    entry_vld   [i] <= 1'b0;
                end
                // This case may happen with cond write back
                else if (br_vld && i == new_entry_idx) begin
                    entry_vld   [i] <= 1'b1;
                end
                else if (br_pred_vld) begin
                    if (br_pred_succ) begin
                        entry_vld   [i] <= succ_entry_vld[i];
                    end
                    else begin
                        if (i >= top_match_level) begin
                            entry_vld   [i] <= 1'b0;
                        end
                    end
                end
            end
            
            always@(posedge clk) begin
                if (br_vld && i == new_entry_idx) begin
                    entry_cond_reg      [i] <= br_cond_reg;
                    entry_cond_pred_val [i] <= br_cond_predicted_val;
                    entry_fail_pc       [i] <= br_rollback_pc;
                    entry_fail_id       [i] <= br_rollback_id;
                    entry_fail_tag_map  [i] <= br_rollback_tag_map;
                end
                else if (br_pred_vld && br_pred_succ) begin
                    entry_cond_reg      [i] <= succ_entry_cond_reg      [i*REG_ID_BIT        +:REG_ID_BIT        ];
                    entry_cond_pred_val [i] <= succ_entry_cond_pred_val [i                                       ];
                    entry_fail_pc       [i] <= succ_entry_fail_pc       [i*PC_BIT            +:PC_BIT            ];
                    entry_fail_id       [i] <= succ_entry_fail_id       [i*INST_ID_BIT       +:INST_ID_BIT       ];
                    entry_fail_tag_map  [i] <= succ_entry_fail_tag_map  [i*NUM_TAG*REG_ID_BIT+:NUM_TAG*REG_ID_BIT];
                end
            end
        end
    endgenerate


endmodule
