module issue_fifo  #(parameter FIFO_SIZE        = 4,
                     parameter INST_ID_BIT      = 8,
                     parameter NUM_REG          = 8,
                     parameter IMM_BIT          = 4,
                     parameter SPEC_DEPTH       = 4,
                     parameter REG_ID_BIT       = $clog2(NUM_REG),
                     parameter SPEC_LEVEL_BIT   = $clog2(SPEC_DEPTH)+1)
(
    input                               clk,
    input                               rst_n,
           
    input                               in_vld,
    output                              in_rdy,
    input       [INST_ID_BIT    -1:0]   in_id,
    input       [REG_ID_BIT     -1:0]   in_dst_reg,
    input       [REG_ID_BIT     -1:0]   in_src_reg0,
    input       [REG_ID_BIT     -1:0]   in_src_reg1,
    input       [IMM_BIT        -1:0]   in_imm,
    input       [SPEC_LEVEL_BIT -1:0]   in_spec_level,
    
    output reg                          out_vld,
    input                               out_rdy,
    output      [INST_ID_BIT    -1:0]   out_id,
    output      [REG_ID_BIT     -1:0]   out_dst_reg,
    output      [REG_ID_BIT     -1:0]   out_src_reg0,
    output      [REG_ID_BIT     -1:0]   out_src_reg1,
    output      [IMM_BIT        -1:0]   out_imm,
    output reg  [SPEC_LEVEL_BIT -1:0]   out_spec_level,
    
    output      [NUM_REG        -1:0]   pending_read,
    output                              empty,
    
    input                              br_pred_vld,
    // Can set this when the FU is ready to rollback or clear speculation bit
    output                             br_pred_rdy,
    input                              br_pred_succ,
    input       [SPEC_LEVEL_BIT -1:0]  br_pred_fail_level,
    input       [SPEC_LEVEL_BIT*(SPEC_DEPTH+1)-1:0] br_pred_succ_nxt_levels
);

    localparam  PTR_BIT = $clog2(FIFO_SIZE);

    reg     [INST_ID_BIT    -1:0]   ids         [FIFO_SIZE-1:0];
    reg     [REG_ID_BIT     -1:0]   dst_regs    [FIFO_SIZE-1:0];
    reg     [REG_ID_BIT     -1:0]   src_reg0s   [FIFO_SIZE-1:0];
    reg     [REG_ID_BIT     -1:0]   src_reg1s   [FIFO_SIZE-1:0];
    reg     [IMM_BIT        -1:0]   imms        [FIFO_SIZE-1:0];
    reg     [SPEC_LEVEL_BIT -1:0]   spec_levels [FIFO_SIZE-1:0];
    reg                             rollbacks   [FIFO_SIZE-1:0];
    reg                             entry_vld   [FIFO_SIZE-1:0];

    reg     [PTR_BIT    -1:0]   rd_ptr;
    reg     [PTR_BIT    -1:0]   wr_ptr;
    
    wire    [SPEC_LEVEL_BIT-1:0]   br_pred_succ_nxt_level  [SPEC_DEPTH:0];

    wire    out_rollback = entry_vld[rd_ptr] && (rollbacks[rd_ptr] || (br_pred_vld && br_pred_rdy && !br_pred_succ && spec_levels[rd_ptr] >= br_pred_fail_level));
    
    assign  empty   = !entry_vld[rd_ptr];
    assign  br_pred_rdy = 1'b1;
    
    generate
        genvar i;
        
        for (i=0; i<=SPEC_DEPTH; i=i+1) begin: gen_br_pred_succ_nxt_level
            assign  br_pred_succ_nxt_level[i]   = br_pred_succ_nxt_levels[i*SPEC_LEVEL_BIT+:SPEC_LEVEL_BIT];
        end
        
        for (i=0; i<FIFO_SIZE; i=i+1) begin: gen_in
            always@(posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    entry_vld   [i] <= 1'b0;
                end
                else if (in_vld && in_rdy && i == wr_ptr) begin
                    entry_vld   [i] <= 1'b1;
                end
                else if (((out_vld && out_rdy) || out_rollback) && i == rd_ptr) begin
                    entry_vld   [i] <= 1'b0;
                end
            end
            
            always@(posedge clk) begin
                if (in_vld && in_rdy && i == wr_ptr) begin
                    ids         [i] <= in_id;
                    dst_regs    [i] <= in_dst_reg;
                    imms        [i] <= in_imm;
                end
            end
            
            always@(posedge clk) begin
                if (in_vld && in_rdy && i == wr_ptr) begin
                    rollbacks   [i] <= 1'b0;
                end
                else if (br_pred_vld && br_pred_rdy && !br_pred_succ && entry_vld[i] && spec_levels[i] >= br_pred_fail_level) begin
                    rollbacks   [i] <= 1'b1;
                end
            end
            
            always@(posedge clk) begin
                if (in_vld && in_rdy && i == wr_ptr) begin
                    // in_spec_level already considered the case that br_pred_succ in the same cycle
                    // so issue fifo only fix the level already stored in it
                    spec_levels [i] <= in_spec_level;
                end
                else if (br_pred_vld && br_pred_rdy && br_pred_succ && entry_vld[i]) begin
                    spec_levels [i] <= br_pred_succ_nxt_level[spec_levels[i]];
                end
            end
            
            // Should initial to 0 since we need to output pending_read
            // Or pending_read should depend on entry_vld
            always@(posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    src_reg0s   [i] <= 0;
                    src_reg1s   [i] <= 0;
                end
                else if (br_pred_vld && br_pred_rdy && !br_pred_succ && entry_vld[i] && spec_levels[i] >= br_pred_fail_level) begin
                    src_reg0s   [i] <= 0;
                    src_reg1s   [i] <= 0;
                end
                else if (in_vld && in_rdy && i == wr_ptr) begin
                    src_reg0s   [i] <= in_src_reg0;
                    src_reg1s   [i] <= in_src_reg1;
                end
                else if (out_vld && out_rdy && i == rd_ptr) begin
                    src_reg0s   [i] <= 0;
                    src_reg1s   [i] <= 0;
                end
            end
        end
    endgenerate
    
    assign  out_id          = ids       [rd_ptr];
    assign  out_dst_reg     = dst_regs  [rd_ptr];
    assign  out_src_reg0    = src_reg0s [rd_ptr];
    assign  out_src_reg1    = src_reg1s [rd_ptr];
    assign  out_imm         = imms      [rd_ptr];
    
    assign  in_rdy          = ~entry_vld[wr_ptr];
    
    always @* begin
        if (br_pred_vld && br_pred_rdy && !br_pred_succ) begin
            out_vld = entry_vld[rd_ptr] && !rollbacks[rd_ptr] && spec_levels[rd_ptr] < br_pred_fail_level;
        end
        else begin
            out_vld = entry_vld[rd_ptr] && !rollbacks[rd_ptr];
        end
    end
    
    always @* begin
        if (br_pred_vld && br_pred_rdy && br_pred_succ) begin
            out_spec_level  = br_pred_succ_nxt_level[spec_levels[rd_ptr]];
        end
        else begin
            out_spec_level  = spec_levels[rd_ptr];
        end
    end
    
    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            rd_ptr      <= 0;
        end
        else if ((out_vld && out_rdy) || out_rollback) begin
            rd_ptr      <= rd_ptr+1;
        end
    end
    
    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            wr_ptr      <= 0;
        end
        else if (in_vld && in_rdy) begin
            wr_ptr      <= wr_ptr+1;
        end
    end
    
    wire    [NUM_REG    -1:0]   src_reg0_mask               [FIFO_SIZE  -1:0];
    wire    [NUM_REG    -1:0]   src_reg1_mask               [FIFO_SIZE  -1:0];
    wire    [NUM_REG    -1:0]   pending_read_mask_at_entry  [FIFO_SIZE  -1:0];
    
    // In scoreboard, if we use pending read count for each register
    // we may save some combinational circuits
    generate
        for (i=0; i<FIFO_SIZE; i=i+1) begin: gen_decode
            decode  #(.DATA_WIDTH(REG_ID_BIT))
            src_reg0_decode (   .in (src_reg0s      [i]),
                                .out(src_reg0_mask  [i]));
            decode  #(.DATA_WIDTH(REG_ID_BIT))
            src_reg1_decode (   .in (src_reg1s      [i]),
                                .out(src_reg1_mask  [i]));
        end
        
        assign  pending_read_mask_at_entry  [0] =   src_reg0_mask   [0] |
                                                    src_reg1_mask   [0];
        
        for (i=1; i<FIFO_SIZE; i=i+1) begin: gen_mask
            assign pending_read_mask_at_entry   [i] =   pending_read_mask_at_entry [i-1] |
                                                        src_reg0_mask   [i] |
                                                        src_reg1_mask   [i];
        end
    endgenerate
    
    assign  pending_read    = pending_read_mask_at_entry  [FIFO_SIZE-1];

endmodule
