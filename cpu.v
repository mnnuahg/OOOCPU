module cpu  #   (parameter  REG_BIT         = 16,
                 parameter  IMM_BIT         = 8,
                 parameter  NUM_REG         = 16,
                 parameter  NUM_TAG         = 8,
                 parameter  ISSUE_FIFO_SIZE = 4,
                 parameter  INST_ID_BIT     = 8,
                 parameter  SPEC_DEPTH      = 4,
                 parameter  NUM_FU          = 7,
                 parameter  PC_BIT          = 8,
                 parameter  OP_ST           = 3'd0,
                 parameter  OP_CMP_GT       = 3'd1,
                 parameter  OP_ADD_IMM      = 3'd2,
                 parameter  OP_ADD          = 3'd3,
                 parameter  OP_SHL          = 3'd4,
                 parameter  OP_SHR          = 3'd5,
                 parameter  OP_MUL          = 3'd6,
                 parameter  OP_BZ           = 3'd7,
                 parameter  REG_ID_BIT      = $clog2(NUM_REG),
                 parameter  TAG_ID_BIT      = $clog2(NUM_TAG),
                 parameter  SPEC_LEVEL_BIT  = $clog2(SPEC_DEPTH)+1,
                 parameter  FU_ID_BIT       = $clog2(NUM_FU),
                 parameter  FU_DELAY_BIT    = 3)
(
    input                                   clk,
    input                                   rst_n,
    
    /* Here we assume fetch_rdy is always 1 and the instruction will be ready the next cycle when fetch_vld is 1 */
    output                                  fetch_vld,
    input                                   fetch_rdy,
    output      [INST_ID_BIT        -1:0]   fetch_id,
    output      [PC_BIT             -1:0]   fetch_pc,
    
    /* If inst_rdy is 1 and fetch_vld is 0, then next cycle inst_vld will be 0 */
    input                                   inst_vld,
    output reg                              inst_rdy,
    input                                   inst_last,
    input       [FU_ID_BIT          -1:0]   inst_op,
    input       [INST_ID_BIT        -1:0]   inst_id,
    input       [TAG_ID_BIT         -1:0]   inst_dst_reg,
    input       [TAG_ID_BIT         -1:0]   inst_src_reg0,
    input       [TAG_ID_BIT         -1:0]   inst_src_reg1,
    input       [IMM_BIT            -1:0]   inst_imm,
    
    output                                  write_mem_vld,
    input                                   write_mem_rdy,
    output      [INST_ID_BIT        -1:0]   write_mem_id,
    output      [REG_BIT            -1:0]   write_mem_addr,
    output      [REG_BIT            -1:0]   write_mem_data,
    
    // Just for random test
    input       [NUM_FU*FU_DELAY_BIT-1:0]   fu_stage0_delays,
    input       [NUM_FU*FU_DELAY_BIT-1:0]   fu_stage1_delays,
    input       [NUM_FU*FU_DELAY_BIT-1:0]   fu_stage2_delays,
    
    output                                  exec_finish
);

    reg     last_inst_issued;

    reg     [PC_BIT     -1:0]    cur_pc;
    reg     [PC_BIT     -1:0]    nxt_pc;
    reg     [INST_ID_BIT-1:0]    cur_id;
    reg     [INST_ID_BIT-1:0]    nxt_id;
    
    wire    [NUM_TAG*REG_ID_BIT -1:0]   cur_tag_map;
    
    // These are from spec_vector
    wire                                           br_pred_vld;
    wire                                           br_pred_succ;
    wire       [SPEC_LEVEL_BIT               -1:0] br_pred_fail_level;
    wire       [SPEC_LEVEL_BIT*(SPEC_DEPTH+1)-1:0] br_pred_succ_nxt_levels;
    wire       [NUM_TAG*REG_ID_BIT           -1:0] br_pred_fail_tag_map;
    wire       [PC_BIT                       -1:0] br_pred_fail_pc;
    wire       [INST_ID_BIT                  -1:0] br_pred_fail_id;
    
    wire    rollback_vld    = br_pred_vld && !br_pred_succ;

    wire                        br_vld;
    wire                        br_rdy;
    reg                         br_speculative;
    wire       [REG_ID_BIT-1:0] br_cond_reg                  = cur_tag_map[inst_src_reg0*REG_ID_BIT+:REG_ID_BIT];
    wire       [IMM_BIT   -1:0] br_target                    = inst_imm;
    wire                        br_cond_predicted_val        = 1'b0;
    
    // These depends on the branch is BZ or BNZ
    wire       [PC_BIT    -1:0] br_predicted_pc              = br_cond_predicted_val ? cur_pc + 1 : br_target;
    wire       [PC_BIT    -1:0] br_predicted_fail_pc         = br_cond_predicted_val ? br_target  : cur_pc + 1;

    // Even if the branch is not speculative, the branch cond reg still need 1T to read out
    // so we still speculatively fetch instruction of one branch direction, and fetch another direction
    // when predict fail
    wire                    br_cond_rd_addr_vld = br_vld && !br_speculative;
    wire                    br_cond_rd_val_vld;
    wire    [REG_BIT-1:0]   br_cond_rd_val;
    reg     [PC_BIT -1:0]   br_cond_rd_val_predict_fail_pc;
    
    assign  br_vld                       = inst_vld && inst_op == OP_BZ && !rollback_vld && (!br_cond_rd_val_vld || br_cond_rd_val == br_cond_predicted_val);
    
    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            last_inst_issued        <= 1'b0;
        end
        else if (inst_vld && inst_rdy && inst_last && !rollback_vld) begin
            last_inst_issued        <= 1'b1;
        end
        else if (rollback_vld) begin
            last_inst_issued        <= 1'b0;
        end
    end
    
    always@(posedge clk) begin
        if (br_vld && !br_speculative) begin
            br_cond_rd_val_predict_fail_pc  <= br_predicted_fail_pc;
        end
    end
    
    assign  fetch_vld   = rollback_vld ||
                          (br_cond_rd_val_vld && br_cond_rd_val[0] != br_cond_predicted_val) ||
                          (!last_inst_issued && (!inst_vld || (inst_rdy && !inst_last)));
    assign  fetch_pc    = nxt_pc;
    assign  fetch_id    = nxt_id;
    
    always @* begin
        if (rollback_vld) begin
            nxt_pc  = br_pred_fail_pc;
            nxt_id  = br_pred_fail_id;
        end
        else if (br_cond_rd_val_vld && br_cond_rd_val != br_cond_predicted_val) begin
            nxt_pc  = br_cond_rd_val_predict_fail_pc;
            nxt_id  = cur_id;
        end
        else if (br_vld) begin
            nxt_pc  = br_predicted_pc;
            nxt_id  = cur_id + 1;
        end
        else if (inst_vld) begin
            nxt_pc  = cur_pc + 1;
            nxt_id  = cur_id + 1;
        end
        else begin
            nxt_pc  = cur_pc;
            nxt_id  = cur_id;
        end
    end

    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            cur_id  <= 0;
            cur_pc  <= 0;
        end
        else if (fetch_vld && fetch_rdy) begin
            cur_id  <= nxt_id;
            cur_pc  <= nxt_pc;
        end
    end
    
    wire                                           inst_issue_vld  = inst_vld && inst_op != OP_BZ && !rollback_vld && (!br_cond_rd_val_vld || br_cond_rd_val == br_cond_predicted_val);
    wire                                           inst_issue_rdy;
    wire       [SPEC_LEVEL_BIT               -1:0] inst_issue_spec_level;
    
    always @* begin
        // When rollback we have to clear the fault instruction
        if (rollback_vld) begin
            inst_rdy    = 1'b1;
        end
        else if (br_cond_rd_val_vld && br_cond_rd_val != br_cond_predicted_val) begin
            inst_rdy    = 1'b1;
        end
        else if (inst_op != OP_BZ) begin
            inst_rdy    = inst_issue_rdy;
        end
        else begin
            inst_rdy    = !br_speculative || br_rdy;
        end
    end

    wire    [NUM_REG          -1:0] reg_read_pending;
    wire    [NUM_REG          -1:0] reg_write_pending;
    
    wire    [NUM_FU           -1:0] fu_issue_rdy;
    wire    [REG_ID_BIT       -1:0] fu_dst_reg;
    wire    [REG_ID_BIT       -1:0] fu_src_reg0;
    wire    [REG_ID_BIT       -1:0] fu_src_reg1;
    
    wire    [NUM_FU           -1:0] fu_read_reg_id_vld;
    wire    [NUM_FU           -1:0] fu_read_reg_id_rdy;
    wire    [NUM_FU*REG_ID_BIT-1:0] fu_read_reg0_id;
    wire    [NUM_FU*REG_ID_BIT-1:0] fu_read_reg1_id;
    wire    [NUM_FU*REG_ID_BIT-1:0] fu_write_reg_id_nxt;
    
    wire    [NUM_FU           -1:0] rf_read_reg_id_vld;
    wire    [NUM_FU           -1:0] rf_read_reg_id_rdy;
    wire    [NUM_FU*REG_ID_BIT-1:0] rf_read_reg0_id;
    wire    [NUM_FU*REG_ID_BIT-1:0] rf_read_reg1_id;
    
    wire    [NUM_FU           -1:0] rf_read_reg_data_vld;
    wire    [NUM_FU           -1:0] rf_read_reg_data_rdy;
    wire    [NUM_FU*REG_BIT   -1:0] rf_read_reg0_data;
    wire    [NUM_FU*REG_BIT   -1:0] rf_read_reg1_data;
    
    wire    [NUM_FU           -1:0] fu_write_reg_id_vld;
    wire    [NUM_FU           -1:0] fu_write_reg_id_rdy;
    wire    [NUM_FU*REG_ID_BIT-1:0] fu_write_reg_id;
    wire    [NUM_FU*REG_BIT   -1:0] fu_write_data;
    
    wire    [NUM_FU           -1:0] rf_write_reg_id_vld;
    wire    [NUM_FU           -1:0] rf_write_reg_id_rdy;
    wire    [NUM_FU*REG_ID_BIT-1:0] rf_write_reg_id;
    wire    [NUM_FU*REG_BIT   -1:0] rf_write_data;
    
    wire    [NUM_FU           -1:0] fu_idle;

    scoreboard  #(  .NUM_REG(NUM_REG),
                    .NUM_TAG(NUM_TAG),
                    .REG_BIT(REG_BIT),
                    .NUM_FU (NUM_FU))
    sb  (   .clk                    (clk),
            .rst_n                  (rst_n),
            
            .fu_available           (fu_issue_rdy),
            .reg_read_pending       (reg_read_pending),
            .reg_write_pending      (reg_write_pending),
            .cur_tag_map            (cur_tag_map),
            
            // rollback_vld means we have to mis-speculated and current PC is wrong
            // so it's no need to issue
            .issue_vld              (inst_issue_vld),
            .issue_rdy              (inst_issue_rdy),
            .issue_fu               (inst_op),
            .issue_dst_reg          (inst_dst_reg),
            .issue_src_reg0         (inst_src_reg0),
            .issue_src_reg1         (inst_src_reg1),
            .issue_spec_level       (inst_issue_spec_level),
            .issue_dst_reg_rename   (fu_dst_reg),
            .issue_src_reg0_rename  (fu_src_reg0),
            .issue_src_reg1_rename  (fu_src_reg1),
            
            .fu2sb_read_reg_id_vld  (fu_read_reg_id_vld),
            .fu2sb_read_reg_id_rdy  (fu_read_reg_id_rdy),
            .fu2sb_read_reg0_id     (fu_read_reg0_id),
            .fu2sb_read_reg1_id     (fu_read_reg1_id),
            .fu2sb_write_reg_id_nxt (fu_write_reg_id_nxt),
            
            .sb2rf_read_reg_id_vld  (rf_read_reg_id_vld),
            .sb2rf_read_reg_id_rdy  (rf_read_reg_id_rdy),
            .sb2rf_read_reg0_id     (rf_read_reg0_id),
            .sb2rf_read_reg1_id     (rf_read_reg1_id),
            
            .fu2sb_write_reg_id_vld (fu_write_reg_id_vld),
            .fu2sb_write_reg_id_rdy (fu_write_reg_id_rdy),
            .fu2sb_write_reg_id     (fu_write_reg_id),
            .fu2sb_write_data       (fu_write_data),
            
            .sb2rf_write_reg_id_vld (rf_write_reg_id_vld),
            .sb2rf_write_reg_id_rdy (rf_write_reg_id_rdy),
            .sb2rf_write_reg_id     (rf_write_reg_id),
            .sb2rf_write_data       (rf_write_data),
            
            .br_pred_vld            (br_pred_vld),
            .br_pred_succ           (br_pred_succ),
            .br_pred_succ_nxt_levels(br_pred_succ_nxt_levels),
            .br_pred_fail_level     (br_pred_fail_level),
            .br_pred_fail_tag_map   (br_pred_fail_tag_map));

    // The one extra read port is used for read branch condition reg
    reg_file    #(  .NUM_REG    (NUM_REG),
                    .REG_BIT    (REG_BIT),
                    .NUM_R_PORT (NUM_FU+1),
                    .NUM_W_PORT (NUM_FU))
    rf  (   .clk            (clk),
            .rst_n          (rst_n),
            
            // The last read port is for reading branch condition
            .rd_addr_vld    ({br_cond_rd_addr_vld, rf_read_reg_id_vld}),
            .rd_addr_rdy    (                      rf_read_reg_id_rdy),
            .rd_addr0       ({br_cond_reg,         rf_read_reg0_id}),
            .rd_addr1       (                      rf_read_reg1_id),
            
            .rd_data_vld    ({br_cond_rd_val_vld,  rf_read_reg_data_vld}),
            .rd_data_rdy    ({1'b1,                rf_read_reg_data_rdy}),
            .rd_data0       ({br_cond_rd_val,      rf_read_reg0_data}),
            .rd_data1       (                      rf_read_reg1_data),
            
            // TODO: FU must also output the speculation cond reg for the write
            //       If it's the same as current rollback reg then don't write it
            //       => It's seems OK to write as long as the scoreboard keep it as free?
            .wr_vld         (rf_write_reg_id_vld),
            .wr_rdy         (rf_write_reg_id_rdy),
            .wr_addr        (rf_write_reg_id),
            .wr_data        (rf_write_data));

    wire    [(1<<FU_ID_BIT) -1:0]   op_for_fu;
    decode  #(  .DATA_WIDTH (FU_ID_BIT))
    issue_fu_dec    (   .in (inst_op),
                        .out(op_for_fu));
                        
    wire    [NUM_REG-1:0]   pending_read_mask_of_fu [NUM_FU-1:0];
    
    wire                            stb_in_vld;
    wire                            stb_in_rdy;
    wire    [INST_ID_BIT    -1:0]   stb_in_id;
    wire    [REG_BIT        -1:0]   stb_in_addr;
    wire    [REG_BIT        -1:0]   stb_in_data;
    wire    [SPEC_LEVEL_BIT -1:0]   stb_in_spec_level;
    wire                            stb_empty;
    

    binary_func_unit    #(  .NUM_REG            (NUM_REG),
                            .REG_BIT            (REG_BIT),
                            .IMM_BIT            (IMM_BIT),
                            .INST_ID_BIT        (INST_ID_BIT),
                            .FUNC               (0),
                            .ISSUE_FIFO_SIZE    (ISSUE_FIFO_SIZE),
                            .DELAY_BIT          (3),
                            .FOLLOW_ISSUE_ORDER (1),
                            .OP_ST              (OP_ST),
                            .OP_CMP_GT          (OP_CMP_GT),
                            .OP_ADD_IMM         (OP_ADD_IMM),
                            .OP_ADD             (OP_ADD),
                            .OP_SHL             (OP_SHL),
                            .OP_SHR             (OP_SHR),
                            .OP_MUL             (OP_MUL))
    st_fu(  .clk                (clk),
            .rst_n              (rst_n),

            .issue_vld          (inst_issue_vld && inst_issue_rdy && op_for_fu[0]),
            .issue_rdy          (fu_issue_rdy   [0]),
            .issue_id           (inst_id),
            .issue_dst_reg      (fu_dst_reg),
            .issue_src_reg0     (fu_src_reg0),
            .issue_src_reg1     (fu_src_reg1),
            .issue_imm          (inst_imm),
            .issue_spec_level   (inst_issue_spec_level),

            .pending_read_mask  (pending_read_mask_of_fu[0]),
            .ready_reg_mask     (~reg_write_pending),

            .read_req_vld       (fu_read_reg_id_vld     [0]),
            .read_req_rdy       (fu_read_reg_id_rdy     [0]),
            .read_reg0_id       (fu_read_reg0_id        [0*REG_ID_BIT+:REG_ID_BIT]),
            .read_reg1_id       (fu_read_reg1_id        [0*REG_ID_BIT+:REG_ID_BIT]),
            .write_reg_id_nxt   (fu_write_reg_id_nxt    [0*REG_ID_BIT+:REG_ID_BIT]),

            .read_fbk_vld       (rf_read_reg_data_vld   [0]),
            .read_fbk_rdy       (rf_read_reg_data_rdy   [0]),
            .read_reg0_val      (rf_read_reg0_data      [0*REG_BIT+:REG_BIT]),
            .read_reg1_val      (rf_read_reg1_data      [0*REG_BIT+:REG_BIT]),
            
            // The write may be blocked
            .write_back_vld     (stb_in_vld),
            .write_back_rdy     (stb_in_rdy),
            .write_back_id      (stb_in_id),
            .write_back_reg_id  (),
            .write_back_addr    (stb_in_addr),
            .write_back_val     (stb_in_data),
            .write_back_spec_level  (stb_in_spec_level),
        
            .stage0_delay       (fu_stage0_delays       [0*FU_DELAY_BIT+:FU_DELAY_BIT]),
            .stage1_delay       (fu_stage1_delays       [0*FU_DELAY_BIT+:FU_DELAY_BIT]),
            .stage2_delay       (fu_stage2_delays       [0*FU_DELAY_BIT+:FU_DELAY_BIT]),
            
            .idle               (fu_idle                [0]),
            
            .br_pred_vld            (br_pred_vld),
            .br_pred_succ           (br_pred_succ),
            .br_pred_fail_level     (br_pred_fail_level),
            .br_pred_succ_nxt_levels(br_pred_succ_nxt_levels));
            
    assign  fu_write_reg_id_vld [0] = 1'b0;
    
    store_buf   #(  .INST_ID_BIT(INST_ID_BIT),
                    .ADDR_BIT   (REG_BIT),
                    .DATA_BIT   (REG_BIT),
                    .BUF_DEPTH  (16),
                    .SPEC_DEPTH (SPEC_DEPTH),
                    .REG_ID_BIT (REG_ID_BIT))
    stb (   .clk                    (clk),
            .rst_n                  (rst_n),
            
            .in_vld                 (stb_in_vld),
            .in_rdy                 (stb_in_rdy),
            .in_id                  (stb_in_id),
            .in_addr                (stb_in_addr),
            .in_data                (stb_in_data),
            .in_spec_level          (stb_in_spec_level),
            
            .out_vld                (write_mem_vld),
            .out_rdy                (write_mem_rdy),
            .out_id                 (write_mem_id),
            .out_addr               (write_mem_addr),
            .out_data               (write_mem_data),
            
            .empty                  (stb_empty),
            
            .br_pred_vld            (br_pred_vld),
            .br_pred_succ           (br_pred_succ),
            .br_pred_fail_level     (br_pred_fail_level),
            .br_pred_succ_nxt_levels(br_pred_succ_nxt_levels));
    
    generate
        genvar i;
        for (i=OP_CMP_GT; i<=OP_MUL; i=i+1) begin: gen_binary_fu
            binary_func_unit    #(  .NUM_REG            (NUM_REG),
                                    .REG_BIT            (REG_BIT),
                                    .IMM_BIT            (IMM_BIT),
                                    .INST_ID_BIT        (INST_ID_BIT),
                                    .FUNC               (i),
                                    .ISSUE_FIFO_SIZE    (ISSUE_FIFO_SIZE),
                                    .DELAY_BIT          (3),
                                    .FOLLOW_ISSUE_ORDER (0),
                                    .OP_ST              (OP_ST),
                                    .OP_CMP_GT          (OP_CMP_GT),
                                    .OP_ADD_IMM         (OP_ADD_IMM),
                                    .OP_ADD             (OP_ADD),
                                    .OP_SHL             (OP_SHL),
                                    .OP_SHR             (OP_SHR),
                                    .OP_MUL             (OP_MUL))
            fu  (   .clk                (clk),
                    .rst_n              (rst_n),
                    
                    .issue_vld          (inst_issue_vld && inst_issue_rdy && op_for_fu[i]),
                    .issue_rdy          (fu_issue_rdy   [i]),
                    .issue_id           (inst_id),
                    .issue_dst_reg      (fu_dst_reg),
                    .issue_src_reg0     (fu_src_reg0),
                    .issue_src_reg1     (fu_src_reg1),
                    .issue_imm          (inst_imm),
                    .issue_spec_level   (inst_issue_spec_level),
                    
                    .pending_read_mask  (pending_read_mask_of_fu[i]),
                    .ready_reg_mask     (~reg_write_pending),
                    
                    .read_req_vld       (fu_read_reg_id_vld     [i]),
                    .read_req_rdy       (fu_read_reg_id_rdy     [i]),
                    .read_reg0_id       (fu_read_reg0_id        [i*REG_ID_BIT+:REG_ID_BIT]),
                    .read_reg1_id       (fu_read_reg1_id        [i*REG_ID_BIT+:REG_ID_BIT]),
                    .write_reg_id_nxt   (fu_write_reg_id_nxt    [i*REG_ID_BIT+:REG_ID_BIT]),
                    
                    .read_fbk_vld       (rf_read_reg_data_vld   [i]),
                    .read_fbk_rdy       (rf_read_reg_data_rdy   [i]),
                    .read_reg0_val      (rf_read_reg0_data      [i*REG_BIT+:REG_BIT]),
                    .read_reg1_val      (rf_read_reg1_data      [i*REG_BIT+:REG_BIT]),
                    
                    .write_back_vld     (fu_write_reg_id_vld    [i]),
                    .write_back_rdy     (fu_write_reg_id_rdy    [i]),
                    .write_back_id      (),
                    .write_back_reg_id  (fu_write_reg_id        [i*REG_ID_BIT+:REG_ID_BIT]),
                    .write_back_addr    (),
                    .write_back_val     (fu_write_data          [i*REG_BIT   +:REG_BIT   ]),
                    
                    .stage0_delay       (fu_stage0_delays       [i*FU_DELAY_BIT+:FU_DELAY_BIT]),
                    .stage1_delay       (fu_stage1_delays       [i*FU_DELAY_BIT+:FU_DELAY_BIT]),
                    .stage2_delay       (fu_stage2_delays       [i*FU_DELAY_BIT+:FU_DELAY_BIT]),
                    
                    .idle               (fu_idle                [i]),
                    
                    .br_pred_vld            (br_pred_vld),
                    .br_pred_succ           (br_pred_succ),
                    .br_pred_fail_level     (br_pred_fail_level),
                    .br_pred_succ_nxt_levels(br_pred_succ_nxt_levels));
        end
    endgenerate
    
    wire    [NUM_REG-1:0]   pending_read_mask_at_fu [NUM_FU-1:0];
    
    assign  pending_read_mask_at_fu [0] = pending_read_mask_of_fu[0];
    generate
        for (i=1; i<NUM_FU; i=i+1) begin: gen_pending_read_mask
            assign  pending_read_mask_at_fu [i] = pending_read_mask_at_fu[i-1] |
                                                  pending_read_mask_of_fu[i  ];
        end
    endgenerate
    
    assign  reg_read_pending    = pending_read_mask_at_fu   [NUM_FU-1];
    
    always @* begin
        br_speculative = 1'b1;
        
        if (!reg_write_pending[br_cond_reg]) begin
            br_speculative = 1'b0;
        end
        // The branch condition writes back at this cycle, then it's not speculative
        // Although the write value is known in this cycle, we still speculatively
        // fetch the instruction of one branch direction, and read the branch condition at this cycle.
        // Restriction: 1. the branch condition must come from compare instruction
        //              2. the write must 
        else if (fu_write_reg_id_vld[OP_CMP_GT] && fu_write_reg_id[OP_CMP_GT*REG_ID_BIT+:REG_ID_BIT] == br_cond_reg) begin
            br_speculative = 1'b0;
        end
    end
    
    spec_vector #(  .NUM_TAG            (NUM_TAG),
                    .NUM_REG            (NUM_REG),
                    .SPEC_DEPTH         (SPEC_DEPTH),
                    .PC_BIT             (PC_BIT),
                    .INST_ID_BIT        (INST_ID_BIT))
    sv  (   .clk                    (clk),
            .rst_n                  (rst_n),
            
            .br_vld                 (br_vld && br_speculative),
            .br_rdy                 (br_rdy),
            .br_cond_reg            (br_cond_reg),
            .br_cond_predicted_val  (br_cond_predicted_val),
            .br_rollback_pc         (br_predicted_fail_pc),
            .br_rollback_id         (cur_id + 1),
            .br_rollback_tag_map    (cur_tag_map),
            
            .cur_spec_level         (inst_issue_spec_level),
            
            .cond_wb_vld            (fu_write_reg_id_vld[OP_CMP_GT]),
            .cond_wb_reg            (fu_write_reg_id[OP_CMP_GT*REG_ID_BIT+:REG_ID_BIT]),
            .cond_wb_val            (fu_write_data  [OP_CMP_GT*REG_BIT   +:REG_BIT   ]),
            
            .br_pred_vld            (br_pred_vld),
            .br_pred_succ           (br_pred_succ),
            .br_pred_succ_nxt_levels(br_pred_succ_nxt_levels),
            .br_pred_fail_level     (br_pred_fail_level),
            .br_pred_fail_tag_map   (br_pred_fail_tag_map),
            .br_pred_fail_pc        (br_pred_fail_pc),
            .br_pred_fail_id        (br_pred_fail_id));
            
    
    assign  exec_finish         = last_inst_issued && (&fu_idle) && stb_empty;
    
endmodule
