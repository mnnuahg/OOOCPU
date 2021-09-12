module issue_station    #(parameter STATION_SIZE    = 4,
                          parameter INST_ID_BIT     = 8,
                          parameter NUM_REG         = 8,
                          parameter IMM_BIT         = 4,
                          parameter SPEC_DEPTH      = 4,
                          parameter REG_ID_BIT      = $clog2(NUM_REG),
                          parameter STATION_ID_BIT  = $clog2(STATION_SIZE),
                          parameter SPEC_LEVEL_BIT  = $clog2(SPEC_DEPTH)+1)
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
    
    input       [NUM_REG        -1:0]   ready_reg_mask,

    // Will select one issue whose two src regs are both ready
    output                              out_vld,
    input                               out_rdy,
    output      [INST_ID_BIT    -1:0]   out_id,
    output      [REG_ID_BIT     -1:0]   out_dst_reg,
    output      [REG_ID_BIT     -1:0]   out_src_reg0,
    output      [REG_ID_BIT     -1:0]   out_src_reg1,
    output      [IMM_BIT        -1:0]   out_imm,
    output reg  [SPEC_LEVEL_BIT -1:0]   out_spec_level,
           
    output      [NUM_REG        -1:0]   pending_read,
    output                              empty,
    
    input                               br_pred_vld,
    // Can set this when the FU is ready to rollback or clear speculation bit
    output                              br_pred_rdy,
    input                               br_pred_succ,
    input       [SPEC_LEVEL_BIT -1:0]   br_pred_fail_level,
    input       [SPEC_LEVEL_BIT*(SPEC_DEPTH+1)-1:0] br_pred_succ_nxt_levels
);

    reg     [INST_ID_BIT    -1:0]   ids         [STATION_SIZE   -1:0];
    reg     [REG_ID_BIT     -1:0]   dst_regs    [STATION_SIZE   -1:0];
    reg     [REG_ID_BIT     -1:0]   src_reg0s   [STATION_SIZE   -1:0];
    reg     [REG_ID_BIT     -1:0]   src_reg1s   [STATION_SIZE   -1:0];
    reg     [IMM_BIT        -1:0]   imms        [STATION_SIZE   -1:0];
    reg     [SPEC_LEVEL_BIT -1:0]   spec_levels [STATION_SIZE   -1:0];
    
    reg     [STATION_SIZE   -1:0]   entry_vld;
    wire    [STATION_SIZE   -1:0]   station_rdy;
    wire    [STATION_SIZE   -1:0]   station_rollback;
    
    wire    [STATION_ID_BIT   :0]   rdy_station;
    wire    [STATION_ID_BIT   :0]   empty_station;
    
    wire    [STATION_ID_BIT -1:0]   rd_ptr          = rdy_station   [STATION_ID_BIT-1:0];
    wire    [STATION_ID_BIT -1:0]   wr_ptr          = empty_station [STATION_ID_BIT-1:0];
    
    wire    [SPEC_LEVEL_BIT-1:0]   br_pred_succ_nxt_level  [SPEC_DEPTH:0];

    assign  in_rdy  =   |(~entry_vld);
    assign  out_vld =   |  station_rdy;
    assign  empty   = !(|  entry_vld);

    assign  br_pred_rdy = 1'b1;
    
    leading_zero_one_cnt    #(.DATA_WIDTH(STATION_SIZE), .COUNT_ZERO(1))
    rdy_station_gen     (   .in (station_rdy),
                            .cnt(rdy_station));

    leading_zero_one_cnt    #(.DATA_WIDTH(STATION_SIZE), .COUNT_ZERO(1))
    empty_station_gen   (   .in (~entry_vld),
                            .cnt(empty_station));

    generate
        genvar i;
        
        for (i=0; i<=SPEC_DEPTH; i=i+1) begin: gen_br_pred_succ_nxt_level
            assign  br_pred_succ_nxt_level[i]   = br_pred_succ_nxt_levels[i*SPEC_LEVEL_BIT+:SPEC_LEVEL_BIT];
        end
        
        for (i=0; i<STATION_SIZE; i=i+1) begin: gen_in
            assign  station_rollback[i] = entry_vld[i] && br_pred_vld && br_pred_rdy && !br_pred_succ && spec_levels[i] >= br_pred_fail_level;
        
            // If my dst reg is ri, then it's impossible that some other FUs are still writing ri, so ri is ready to read for me
            // The reg is not in ready_reg_mask is because it still write pending (by me)
            assign  station_rdy [i] = entry_vld[i] && !station_rollback[i] && 
                                      (ready_reg_mask[src_reg0s[i]] || src_reg0s[i]==dst_regs[i]) &&
                                      (ready_reg_mask[src_reg1s[i]] || src_reg1s[i]==dst_regs[i]);
        
            always@(posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    entry_vld   [i] <= 1'b0;
                end
                else if (in_vld && in_rdy && i == wr_ptr) begin
                    entry_vld   [i] <= 1'b1;
                end
                else if (out_vld && out_rdy && i == rd_ptr) begin
                    entry_vld   [i] <= 1'b0;
                end
                else if (station_rollback[i]) begin
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
                else if (in_vld && in_rdy && i == wr_ptr) begin
                    src_reg0s   [i] <= in_src_reg0;
                    src_reg1s   [i] <= in_src_reg1;
                end
                else if (out_vld && out_rdy && i == rd_ptr) begin
                    src_reg0s   [i] <= 0;
                    src_reg1s   [i] <= 0;
                end
                else if (station_rollback[i]) begin
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
    
    always @* begin
        if (br_pred_vld && br_pred_rdy && br_pred_succ) begin
            out_spec_level  = br_pred_succ_nxt_level[spec_levels[rd_ptr]];
        end
        else begin
            out_spec_level  = spec_levels[rd_ptr];
        end
    end
    
    wire    [NUM_REG    -1:0]   src_reg0_mask               [STATION_SIZE  -1:0];
    wire    [NUM_REG    -1:0]   src_reg1_mask               [STATION_SIZE  -1:0];
    wire    [NUM_REG    -1:0]   pending_read_mask_at_entry  [STATION_SIZE  -1:0];
    
    // In scoreboard, if we use pending read count for each register
    // we may save some combinational circuits
    // Or we may just let the station to store the read mask instead of the src reg id
    generate
        for (i=0; i<STATION_SIZE; i=i+1) begin: gen_decode
            decode  #(.DATA_WIDTH(REG_ID_BIT))
            src_reg0_decode (   .in (src_reg0s      [i]),
                                .out(src_reg0_mask  [i]));
            decode  #(.DATA_WIDTH(REG_ID_BIT))
            src_reg1_decode (   .in (src_reg1s      [i]),
                                .out(src_reg1_mask  [i]));
        end
        
        assign  pending_read_mask_at_entry  [0] =   src_reg0_mask   [0] |
                                                    src_reg1_mask   [0];
        
        for (i=1; i<STATION_SIZE; i=i+1) begin: gen_mask
            assign pending_read_mask_at_entry   [i] =   pending_read_mask_at_entry [i-1] |
                                                        src_reg0_mask   [i] |
                                                        src_reg1_mask   [i];
        end
    endgenerate
    
    assign  pending_read    = pending_read_mask_at_entry  [STATION_SIZE-1];
    

endmodule
