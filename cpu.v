module cpu  #   (parameter  REG_BIT         = 16,
                 parameter  IMM_BIT         = 4,
                 parameter  NUM_REG         = 8,
                 parameter  ISSUE_FIFO_SIZE = 4,
                 parameter  INST_ID_BIT     = 8,
                 parameter  NUM_FU          = 8,
                 parameter  PC_BIT          = 8,
                 parameter  REG_ID_BIT      = $clog2(NUM_REG))
(
    input                               clk,
    input                               rst_n,
    
    output                              fetch_vld,
    input                               fetch_rdy,
    output reg  [INST_ID_BIT    -1:0]   fetch_id,
    output reg  [PC_BIT         -1:0]   fetch_pc,
    
    input                               inst_vld,
    output                              inst_rdy,
    input                               inst_last,
    input       [$clog2(NUM_FU) -1:0]   inst_op,
    input       [INST_ID_BIT    -1:0]   inst_id,
    input       [$clog2(NUM_REG)-1:0]   inst_dst_reg,
    input       [$clog2(NUM_REG)-1:0]   inst_src_reg0,
    input       [$clog2(NUM_REG)-1:0]   inst_src_reg1,
    input       [IMM_BIT        -1:0]   inst_imm,
    
    output                              write_mem_vld,
    input                               write_mem_rdy,
    output      [REG_BIT        -1:0]   write_mem_addr,
    output      [REG_BIT        -1:0]   write_mem_data,
    
    output                              exec_finish
);

    reg     last_inst_issued;
    
    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            last_inst_issued    <= 1'b0;
        end
        else if (inst_vld && inst_rdy && inst_last) begin
            last_inst_issued    <= 1'b1;
        end
    end
    
    assign  fetch_vld   = !last_inst_issued && (!inst_vld || !inst_last);

    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            fetch_id    <= 0;
            fetch_pc    <= 0;
        end
        else if (fetch_vld && fetch_rdy) begin
            fetch_id    <= fetch_id+1;
            fetch_pc    <= fetch_pc+1;
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
    wire    [NUM_FU*REG_BIT   -1:0] fu_write_addr;
    wire    [NUM_FU*REG_BIT   -1:0] fu_write_data;
    
    wire    [NUM_FU           -1:0] rf_write_reg_id_vld;
    wire    [NUM_FU           -1:0] rf_write_reg_id_rdy;
    wire    [NUM_FU*REG_ID_BIT-1:0] rf_write_reg_id;
    wire    [NUM_FU*REG_BIT   -1:0] rf_write_data;
    
    wire    [NUM_FU           -1:0] fu_idle;

    scoreboard  #(  .NUM_REG(NUM_REG),
                    .REG_BIT(REG_BIT),
                    .NUM_FU (NUM_FU))
    sb  (   .clk                    (clk),
            .rst_n                  (rst_n),
            
            .fu_available           (fu_issue_rdy),
            .reg_read_pending       (reg_read_pending),
            .reg_write_pending      (reg_write_pending),
            
            .issue_vld              (inst_vld),
            .issue_rdy              (inst_rdy),
            .issue_fu               (inst_op),
            .issue_dst_reg          (inst_dst_reg),
            .issue_src_reg0         (inst_src_reg0),
            .issue_src_reg1         (inst_src_reg1),
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
            .sb2rf_write_data       (rf_write_data));

    reg_file    #(  .NUM_REG    (NUM_REG),
                    .REG_BIT    (REG_BIT),
                    .NUM_R_PORT (NUM_FU),
                    .NUM_W_PORT (NUM_FU))
    rf  (   .clk            (clk),
            .rst_n          (rst_n),
            
            .rd_addr_vld    (rf_read_reg_id_vld),
            .rd_addr_rdy    (rf_read_reg_id_rdy),
            .rd_addr0       (rf_read_reg0_id),
            .rd_addr1       (rf_read_reg1_id),
            
            .rd_data_vld    (rf_read_reg_data_vld),
            .rd_data_rdy    (rf_read_reg_data_rdy),
            .rd_data0       (rf_read_reg0_data),
            .rd_data1       (rf_read_reg1_data),
            
            .wr_vld         (rf_write_reg_id_vld),
            .wr_rdy         (rf_write_reg_id_rdy),
            .wr_addr        (rf_write_reg_id),
            .wr_data        (rf_write_data));

    wire    [NUM_FU -1:0]   op_for_fu;
    decode  #(  .DATA_WIDTH ($clog2(NUM_FU)))
    issue_fu_dec    (   .in (inst_op),
                        .out(op_for_fu));
                        
    wire    [NUM_REG-1:0]   pending_read_mask_of_fu [NUM_FU-1:0];

    binary_func_unit    #(  .NUM_REG            (NUM_REG),
                            .REG_BIT            (REG_BIT),
                            .IMM_BIT            (IMM_BIT),
                            .INST_ID_BIT        (INST_ID_BIT),
                            .FUNC               (0),
                            .ISSUE_FIFO_SIZE    (ISSUE_FIFO_SIZE),
                            .DELAY_BIT          (3),
                            .DELAY              (4),
                            .FOLLOW_ISSUE_ORDER (1))
    st_fu(  .clk                (clk),
            .rst_n              (rst_n),
            
            .issue_vld          (inst_vld && inst_rdy && op_for_fu[0]),
            .issue_rdy          (fu_issue_rdy   [0]),
            .issue_id           (inst_id),
            .issue_dst_reg      (fu_dst_reg),
            .issue_src_reg0     (fu_src_reg0),
            .issue_src_reg1     (fu_src_reg1),
            .issue_imm          (inst_imm),
            
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
            
            .write_back_vld     (write_mem_vld),
            .write_back_rdy     (write_mem_rdy),
            .write_back_id      (),
            .write_back_reg_id  (),
            .write_back_addr    (write_mem_addr),
            .write_back_val     (write_mem_data),
            
            .idle               (fu_idle                [0]));
            
    assign  fu_write_reg_id_vld [0] = 1'b0;
    
    generate
        genvar i;
        for (i=1; i<NUM_FU; i=i+1) begin: gen_binary_fu
            binary_func_unit    #(  .NUM_REG            (NUM_REG),
                                    .REG_BIT            (REG_BIT),
                                    .IMM_BIT            (IMM_BIT),
                                    .INST_ID_BIT        (INST_ID_BIT),
                                    .FUNC               (i),
                                    .ISSUE_FIFO_SIZE    (ISSUE_FIFO_SIZE),
                                    .DELAY_BIT          (3),
                                    .DELAY              (4),
                                    .FOLLOW_ISSUE_ORDER (0))
            fu  (   .clk                (clk),
                    .rst_n              (rst_n),
                    
                    .issue_vld          (inst_vld && inst_rdy && op_for_fu[i]),
                    .issue_rdy          (fu_issue_rdy   [i]),
                    .issue_id           (inst_id),
                    .issue_dst_reg      (fu_dst_reg),
                    .issue_src_reg0     (fu_src_reg0),
                    .issue_src_reg1     (fu_src_reg1),
                    .issue_imm          (inst_imm),
                    
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
                    .write_back_addr    (fu_write_addr          [i*REG_BIT   +:REG_BIT   ]),
                    .write_back_val     (fu_write_data          [i*REG_BIT   +:REG_BIT   ]),
                    
                    .idle               (fu_idle                [i]));
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
    
    assign  exec_finish         = last_inst_issued && (&fu_idle);
    
endmodule
