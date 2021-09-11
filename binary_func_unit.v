//`define PRINT_STAGE

module binary_func_unit    #(parameter NUM_REG              = 8,
                             parameter REG_BIT              = 16,
                             parameter IMM_BIT              = 4,
                             parameter INST_ID_BIT          = 8,
                             parameter FUNC                 = 1,
                             parameter ISSUE_FIFO_SIZE      = 4,
                             parameter DELAY_BIT            = 3,
                             parameter FOLLOW_ISSUE_ORDER   = 0,
                             parameter SPEC_DEPTH           = 4,
                             parameter OP_ST                = 3'd0,
                             parameter OP_CMP_GT            = 3'd1,
                             parameter OP_ADD_IMM           = 3'd2,
                             parameter OP_ADD               = 3'd3,
                             parameter OP_SHL               = 3'd4,
                             parameter OP_SHR               = 3'd5,
                             parameter OP_MUL               = 3'd6,
                             parameter REG_ID_BIT           = $clog2(NUM_REG),
                             parameter SPEC_LEVEL_BIT       = $clog2(SPEC_DEPTH)+1)
(
    input                              clk,
    input                              rst_n,

    input                              issue_vld,
    output                             issue_rdy,          // connect to rs_available of scoreboard
    input       [INST_ID_BIT    -1:0]  issue_id,
    input       [REG_ID_BIT     -1:0]  issue_dst_reg,
    input       [REG_ID_BIT     -1:0]  issue_src_reg0,
    input       [REG_ID_BIT     -1:0]  issue_src_reg1,
    input       [IMM_BIT        -1:0]  issue_imm,
    input       [SPEC_LEVEL_BIT -1:0]  issue_spec_level,
    
    input       [NUM_REG        -1:0]  ready_reg_mask,
    output      [NUM_REG        -1:0]  pending_read_mask,
    
    output                             read_req_vld,
    input                              read_req_rdy,
    output      [REG_ID_BIT     -1:0]  read_reg0_id,
    output      [REG_ID_BIT     -1:0]  read_reg1_id,
    output      [REG_ID_BIT     -1:0]  write_reg_id_nxt,   // This is used to resolve the condition like r3 = add r3, r2
                                                        // Or we can use a bit to specify the src operand 0 is the same as dst operand
    input                              read_fbk_vld,
    output                             read_fbk_rdy,
    input       [REG_BIT        -1:0]  read_reg0_val,
    input       [REG_BIT        -1:0]  read_reg1_val,
    
    output                             write_back_vld,
    input                              write_back_rdy,
    output      [INST_ID_BIT    -1:0]  write_back_id,
    output      [REG_ID_BIT     -1:0]  write_back_reg_id,
    output      [REG_BIT        -1:0]  write_back_addr,
    output      [REG_BIT        -1:0]  write_back_val,
    output      [SPEC_LEVEL_BIT -1:0]  write_back_spec_level,
    
    // Just for random test
    input       [DELAY_BIT      -1:0]  stage0_delay,
    input       [DELAY_BIT      -1:0]  stage1_delay,
    input       [DELAY_BIT      -1:0]  stage2_delay,
    
    output                             idle,
    
    // This will be valid once conditional reg is write back,
    // no matter speculation success or fail
    input                              br_pred_vld,
    input                              br_pred_succ,
    input       [SPEC_LEVEL_BIT -1:0]  br_pred_fail_level,
    input       [SPEC_LEVEL_BIT*(SPEC_DEPTH+1)-1:0] br_pred_succ_nxt_levels
);

    // Issue stage, from the fifo
    
    wire                            fifo_out_vld;
    wire                            fifo_out_rdy;
    wire                            fifo_empty;
    wire    [NUM_REG        -1:0]   fifo_pending_read;
    
    wire    [INST_ID_BIT    -1:0]   stage0_out_id;
    wire    [REG_ID_BIT     -1:0]   stage0_out_dst_reg;
    wire    [REG_ID_BIT     -1:0]   stage0_out_src_reg0;
    wire    [REG_ID_BIT     -1:0]   stage0_out_src_reg1;
    wire    [IMM_BIT        -1:0]   stage0_out_imm;
    wire    [SPEC_LEVEL_BIT -1:0]   stage0_out_spec_level;
    
    reg     [DELAY_BIT      -1:0]   stage0_out_remain_cycle;
    wire                            stage0_out_vld;
    wire                            stage0_out_rdy;
    
    // Read stage
    
    wire                            stage1_sb_in_vld;
    wire                            stage1_sb_in_rdy;
    wire                            stage1_rf_in_vld;
    wire                            stage1_rf_in_rdy;
    
    reg                             stage1_sb_vld;
    reg                             stage1_rollback;
    reg     [SPEC_LEVEL_BIT -1:0]   stage1_spec_level;
    
    reg     [INST_ID_BIT    -1:0]   stage1_sb_out_id;
    reg     [REG_ID_BIT     -1:0]   stage1_sb_out_reg0_id;
    reg     [REG_ID_BIT     -1:0]   stage1_sb_out_reg1_id;
    reg     [IMM_BIT        -1:0]   stage1_sb_out_imm;
    reg     [REG_ID_BIT     -1:0]   stage1_sb_out_write_reg;
    reg     [SPEC_LEVEL_BIT -1:0]   stage1_sb_out_spec_level;
    
    wire    [REG_BIT        -1:0]   stage1_rf_out_reg0_val;
    wire    [REG_BIT        -1:0]   stage1_rf_out_reg1_val;
    
    wire                            stage1_out_rollback;
    
    reg     [DELAY_BIT      -1:0]   stage1_sb_out_remain_cycle;
    wire                            stage1_sb_out_vld;
    wire                            stage1_sb_out_rdy;
    
    wire                            stage1_rf_out_vld;
    wire                            stage1_rf_out_rdy;
    
    // Exec stage
    
    wire                            stage2_in_vld;
    wire                            stage2_in_rdy;
    
    reg                             stage2_data_vld;
    reg                             stage2_rollback;
    reg     [SPEC_LEVEL_BIT -1:0]   stage2_spec_level;
        
    reg     [INST_ID_BIT    -1:0]   stage2_out_id;
    reg     [REG_ID_BIT     -1:0]   stage2_out_write_reg;
    reg     [REG_BIT        -1:0]   stage2_out_reg0_val;
    reg     [REG_BIT        -1:0]   stage2_out_exec_val;
    reg     [SPEC_LEVEL_BIT -1:0]   stage2_out_spec_level;
    
    wire                            stage2_out_rollback;
    
    reg     [DELAY_BIT       -1:0]  stage2_out_remain_cycle;
    wire                            stage2_out_vld;
    wire                            stage2_out_rdy;
    
    assign  idle                = fifo_empty && !stage1_sb_vld && !stage2_data_vld;
    
    assign  stage0_out_vld      = fifo_out_vld && stage0_out_remain_cycle == 0;
    assign  stage0_out_rdy      = stage1_sb_in_rdy && stage1_rf_in_rdy;
    
    assign  stage1_sb_in_vld    = stage0_out_vld && stage1_rf_in_rdy;
    assign  stage1_rf_in_vld    = stage0_out_vld && stage1_sb_in_rdy;
    
    assign  fifo_out_rdy        = stage0_out_rdy && stage0_out_remain_cycle == 0;
    
    // We don't need to check !stage1_data_vld since !stage1_sb_vld already ensures no read request is sent to RF
    // and stage1_data_vld won't be on
    assign  stage1_sb_in_rdy    = !stage1_sb_vld || (stage1_sb_out_vld && stage1_sb_out_rdy);
    assign  stage1_rf_in_rdy    = read_req_rdy;
    
    assign  stage1_sb_out_vld   = stage1_sb_vld && stage1_sb_out_remain_cycle == 0;
    assign  stage1_rf_out_vld   = read_fbk_vld;

    assign  stage1_out_rollback = stage1_sb_out_vld && stage1_rf_out_vld && (stage1_rollback || (br_pred_vld && !br_pred_succ && stage1_spec_level >= br_pred_fail_level));
    
    assign  stage1_sb_out_rdy   = stage1_rf_out_vld && (stage2_in_rdy || stage1_out_rollback) && stage1_sb_out_remain_cycle == 0;
    assign  stage1_rf_out_rdy   = stage1_sb_out_vld && (stage2_in_rdy || stage1_out_rollback);
    
    assign  read_req_vld        = stage1_rf_in_vld;
    assign  read_fbk_rdy        = stage1_rf_out_rdy;

    assign  stage2_in_vld       = stage1_sb_out_vld && stage1_rf_out_vld && !stage1_out_rollback;
    assign  stage2_in_rdy       = !stage2_data_vld || (stage2_out_vld && stage2_out_rdy) || stage2_out_rollback;
    
    assign  stage2_out_vld      = stage2_data_vld && stage2_out_remain_cycle == 0 && !stage2_out_rollback;
    assign  stage2_out_rdy      = stage2_data_vld && (write_back_rdy || stage2_out_rollback) && stage2_out_remain_cycle == 0;
    
    /* TODO: For better timing, we may not need to cancel writeback at the cycle when branch predict fail */
    /*       However, for store we still need to cancel at the same cycle since the store address is not renamed */
    assign  write_back_vld      = stage2_out_vld;
    
    /* Branch prediction success/fail depends on the result of write back stage of CMP_GT,
       so the write back stage of CMP_GT won't be rollbacked depending on branch prediction success/fail,
       otherwise there will be combinational loop. */
    /* However, it's may be better to implement a separate module to monitor the write back of branch predicates,
       and rollback maybe 1T later when branch prediction fail. This way may reduce timing and allow us to use
       result of general operation as branch condition.
       In addition, when there are multiple conditional register write back at the same cycle, we may not need to
       handle all the branches at the same cycle. */
    generate
        if (FUNC == OP_CMP_GT) begin: gen_s2_rollback_0
            assign  stage2_out_rollback = 1'b0;
        end
        else begin: gen_s2_rollback_1
            assign  stage2_out_rollback = stage2_data_vld && (stage2_rollback || (br_pred_vld && !br_pred_succ && stage2_spec_level >= br_pred_fail_level));
        end
    endgenerate
    
    wire [SPEC_LEVEL_BIT    -1:0]   br_pred_succ_nxt_level  [SPEC_DEPTH:0];
    
    generate
        genvar i;
        for (i=0; i<=SPEC_DEPTH; i=i+1) begin: gen_br_pred_succ_nxt_level
            assign  br_pred_succ_nxt_level[i]   = br_pred_succ_nxt_levels[i*SPEC_LEVEL_BIT+:SPEC_LEVEL_BIT];
        end
    endgenerate
    
    generate
        if (FOLLOW_ISSUE_ORDER) begin
            issue_fifo  #(  .FIFO_SIZE  (ISSUE_FIFO_SIZE),
                            .INST_ID_BIT(INST_ID_BIT),
                            .NUM_REG    (NUM_REG),
                            .IMM_BIT    (IMM_BIT))
            fifo    (.clk           (clk),
                     .rst_n         (rst_n),
                     
                     .in_vld        (issue_vld),
                     .in_rdy        (issue_rdy),
                     .in_id         (issue_id),
                     .in_dst_reg    (issue_dst_reg),
                     .in_src_reg0   (issue_src_reg0),
                     .in_src_reg1   (issue_src_reg1),
                     .in_imm        (issue_imm),
                     .in_spec_level (issue_spec_level),

                     .pending_read  (fifo_pending_read),
                     
                     .out_vld       (fifo_out_vld),
                     .out_rdy       (fifo_out_rdy),
                     .out_id        (stage0_out_id),
                     .out_dst_reg   (stage0_out_dst_reg),
                     .out_src_reg0  (stage0_out_src_reg0),
                     .out_src_reg1  (stage0_out_src_reg1),
                     .out_imm       (stage0_out_imm),
                     .out_spec_level(stage0_out_spec_level),
                     
                     .empty         (fifo_empty),
                     
                     .br_pred_vld   (br_pred_vld),
                     .br_pred_succ  (br_pred_succ),
                     .br_pred_fail_level    (br_pred_fail_level),
                     .br_pred_succ_nxt_levels(br_pred_succ_nxt_levels));
        end
        else begin
            issue_station   #(  .STATION_SIZE   (ISSUE_FIFO_SIZE),
                                .INST_ID_BIT    (INST_ID_BIT),
                                .NUM_REG        (NUM_REG),
                                .IMM_BIT        (IMM_BIT))
            station (.clk           (clk),
                     .rst_n         (rst_n),
                     
                     .in_vld        (issue_vld),
                     .in_rdy        (issue_rdy),
                     .in_id         (issue_id),
                     .in_dst_reg    (issue_dst_reg),
                     .in_src_reg0   (issue_src_reg0),
                     .in_src_reg1   (issue_src_reg1),
                     .in_imm        (issue_imm),
                     .in_spec_level (issue_spec_level),

                     .ready_reg_mask(ready_reg_mask),
                     .pending_read  (fifo_pending_read),
                     
                     .out_vld       (fifo_out_vld),
                     .out_rdy       (fifo_out_rdy),
                     .out_id        (stage0_out_id),
                     .out_dst_reg   (stage0_out_dst_reg),
                     .out_src_reg0  (stage0_out_src_reg0),
                     .out_src_reg1  (stage0_out_src_reg1),
                     .out_imm       (stage0_out_imm),
                     .out_spec_level(stage0_out_spec_level),
                     
                     .empty         (fifo_empty),
                     
                     .br_pred_vld   (br_pred_vld),
                     .br_pred_succ  (br_pred_succ),
                     .br_pred_fail_level    (br_pred_fail_level),
                     .br_pred_succ_nxt_levels(br_pred_succ_nxt_levels));
        end
    endgenerate
    
    // (!stage1_out_vld || stage1_out_rdy) may be unnecessary since in current implementation
    // the read_vld only used to check whether the required value is ready and won't change scoreboard entries
    // pending_read_mask is the actual field for preserving WAR dependency 
    
    // However, if we use RF port arbiter then we can issue stage0_out_vld only when we are ready to receive it
    // since the arbiter may switch port to another FU in next cycle
    
    assign  read_reg0_id        = stage0_out_src_reg0;
    assign  read_reg1_id        = stage0_out_src_reg1;
    assign  write_reg_id_nxt    = stage0_out_dst_reg;
    
`ifdef PRINT_STAGE
    always@(posedge clk) begin: print_stage
        if (~rst_n) disable print_stage;
        
        if (issue_vld && issue_rdy) begin
            $display("Time %d: Inst %d issued, dst_reg %d, src_reg0 %d, src_reg1 %d, imm %d",
                     $time,
                     issue_id,
                     issue_dst_reg,
                     issue_src_reg0,
                     issue_src_reg1,
                     issue_imm);
        end
        
        if (read_req_vld && read_req_rdy) begin
            $display("Time %d: Inst %d read reg, reg0 %d, reg1 %d",
                     $time,
                     stage0_out_id,
                     read_reg0_id,
                     read_reg1_id);
        end
        
        if (read_fbk_vld && read_fbk_rdy) begin
            $display("Time %d: Inst %d read fbk, val0 %d, val1 %d",
                     $time,
                     stage1_out_id,
                     read_reg0_val,
                     read_reg1_val);
        end
        
        if (write_back_vld && write_back_rdy) begin
            $display("Time %d: Inst %d write back, reg %d, addr %d, val %d",
                     $time,
                     write_back_id,
                     write_back_reg_id,
                     write_back_addr,
                     write_back_val);
        end
    end
`endif
    
    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            stage0_out_remain_cycle <= 0;
        end
        else if (fifo_out_vld && stage0_out_remain_cycle != 0) begin
            stage0_out_remain_cycle <= stage0_out_remain_cycle-1;
        end
        else if (stage0_out_vld && stage0_out_rdy) begin
            stage0_out_remain_cycle <= stage0_delay;
        end
    end

    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            stage1_sb_vld   <= 1'b0;
        end
        else if (stage1_sb_in_vld && stage1_sb_in_rdy) begin
            stage1_sb_vld   <= 1'b1;
        end
        else if (stage1_sb_out_vld && stage1_sb_out_rdy) begin
            stage1_sb_vld   <= 1'b0;
        end
    end
    
    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            stage1_sb_out_remain_cycle <= 0;
        end
        else if (stage1_sb_vld && stage1_sb_out_remain_cycle > 0) begin
            stage1_sb_out_remain_cycle <= stage1_sb_out_remain_cycle-1;
        end
        else if (stage1_sb_out_vld && stage1_sb_out_rdy) begin
            stage1_sb_out_remain_cycle <= stage1_delay;
        end
    end
    
    assign  stage1_rf_out_reg0_val  = read_reg0_val;
    assign  stage1_rf_out_reg1_val  = read_reg1_val;
    
    always@(posedge clk) begin
        if (stage1_sb_in_vld && stage1_sb_in_rdy) begin
            stage1_sb_out_id           <= stage0_out_id;
            stage1_sb_out_reg0_id      <= stage0_out_src_reg0;
            stage1_sb_out_reg1_id      <= stage0_out_src_reg1;
            stage1_sb_out_imm          <= stage0_out_imm;
            stage1_sb_out_write_reg    <= stage0_out_dst_reg;
        end
    end
    
    always@(posedge clk) begin
        // The output of issue_fifo/issue_station already considered the case
        // that br_pred_vld is on at the same cycle
        if (stage1_sb_in_vld && stage1_sb_in_rdy) begin
            stage1_rollback     <= 1'b0;
        end
        else if (stage1_sb_vld && br_pred_vld && !br_pred_succ && stage1_spec_level >= br_pred_fail_level) begin
            stage1_rollback     <= 1'b1;
        end
    end
    
    always@(posedge clk) begin
        if (stage1_sb_in_vld && stage1_sb_in_rdy) begin
            stage1_spec_level   <= stage0_out_spec_level;
        end
        else if (stage1_sb_vld && br_pred_vld && br_pred_succ) begin
            stage1_spec_level   <= br_pred_succ_nxt_level[stage1_spec_level];
        end
    end
    
    always @* begin
        if (br_pred_vld && br_pred_succ) begin
            stage1_sb_out_spec_level  = br_pred_succ_nxt_level[stage1_spec_level];
        end
        else begin
            stage1_sb_out_spec_level  = stage1_spec_level;
        end
    end
    
    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            stage2_data_vld <= 1'b0;
        end
        else if (stage2_in_vld && stage2_in_rdy) begin
            stage2_data_vld <= 1'b1;
        end
        else if (stage2_out_vld && stage2_out_rdy) begin
            stage2_data_vld <= 1'b0;
        end
    end
    
    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            stage2_out_remain_cycle <= 0;
        end
        else if (stage2_data_vld && stage2_out_remain_cycle > 0) begin
            stage2_out_remain_cycle <= stage2_out_remain_cycle-1;
        end
        else if (stage2_out_vld && stage2_out_rdy) begin
            stage2_out_remain_cycle <= stage2_delay;
        end
    end
    
    always@(posedge clk) begin
        // The output of issue_fifo/issue_station already considered the case
        // that br_pred_vld is on at the same cycle
        if (stage2_in_vld && stage2_in_rdy) begin
            stage2_rollback     <= 1'b0;
        end
        else if (stage2_data_vld && br_pred_vld && !br_pred_succ && stage2_spec_level >= br_pred_fail_level) begin
            stage2_rollback     <= 1'b1;
        end
    end
    
    always@(posedge clk) begin
        if (stage2_in_vld && stage2_in_rdy) begin
            stage2_spec_level   <= stage1_sb_out_spec_level;
        end
        else if (stage2_data_vld && br_pred_vld && br_pred_succ) begin
            stage2_spec_level   <= br_pred_succ_nxt_level[stage2_spec_level];
        end
    end
    
    reg     [REG_BIT    -1:0]   stage2_exec_res;

    always@(posedge clk) begin
        if (stage2_in_vld && stage2_in_rdy) begin
            stage2_out_id           <= stage1_sb_out_id;
            stage2_out_write_reg    <= stage1_sb_out_write_reg;
            stage2_out_reg0_val     <= stage1_rf_out_reg0_val;
            stage2_out_exec_val     <= stage2_exec_res;
        end
    end
    
    always @* begin
        case (FUNC)
        OP_ST:      stage2_exec_res     = stage1_rf_out_reg1_val;
        OP_CMP_GT:  stage2_exec_res     = stage1_rf_out_reg0_val >  stage1_rf_out_reg1_val;
        OP_ADD_IMM: stage2_exec_res     = stage1_rf_out_reg0_val +  stage1_sb_out_imm;
        OP_ADD:     stage2_exec_res     = stage1_rf_out_reg0_val +  stage1_rf_out_reg1_val;
        OP_SHL:     stage2_exec_res     = stage1_rf_out_reg0_val << stage1_rf_out_reg1_val;
        OP_SHR:     stage2_exec_res     = stage1_rf_out_reg0_val >> stage1_rf_out_reg1_val;
        OP_MUL:     stage2_exec_res     = stage1_rf_out_reg0_val *  stage1_rf_out_reg1_val;
        default:    stage2_exec_res     = 0;
        endcase
    end
    
    always @* begin
        if (br_pred_vld && br_pred_succ) begin
            stage2_out_spec_level   = br_pred_succ_nxt_level[stage2_spec_level];
        end
        else begin
            stage2_out_spec_level   = stage2_spec_level;
        end
    end
    
    assign  write_back_id           = stage2_out_id;
    assign  write_back_reg_id       = stage2_out_write_reg;
    assign  write_back_addr         = stage2_out_reg0_val;
    assign  write_back_val          = stage2_out_exec_val;
    assign  write_back_spec_level   = stage2_out_spec_level;
    
    wire    [NUM_REG    -1:0]   stage1_pending_read_reg0_mask;
    wire    [NUM_REG    -1:0]   stage1_pending_read_reg1_mask;
    
    /* TODO: For better timing, we may not need to cancel read pending flag at the cycle when branch predict fail */
    decode  #(.DATA_WIDTH(REG_ID_BIT))
    stage1_reg0_id_dec  (.in    (stage1_sb_vld && !stage1_rollback ? stage1_sb_out_reg0_id : 0),
                         .out   (stage1_pending_read_reg0_mask));

    decode  #(.DATA_WIDTH(REG_ID_BIT))
    stage1_reg1_id_dec  (.in    (stage1_sb_vld && !stage1_rollback ? stage1_sb_out_reg1_id : 0),
                         .out   (stage1_pending_read_reg1_mask));

    assign  pending_read_mask   = fifo_pending_read | stage1_pending_read_reg0_mask | stage1_pending_read_reg1_mask;

endmodule
