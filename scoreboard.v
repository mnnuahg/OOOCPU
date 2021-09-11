module scoreboard #(parameter   NUM_REG         = 8,
                    parameter   NUM_TAG         = 4,
                    parameter   NUM_FU          = 4,
                    parameter   REG_BIT         = 16,
                    parameter   SPEC_DEPTH      = 4,
  
                    parameter   REG_ID_BIT      = $clog2(NUM_REG),
                    parameter   TAG_ID_BIT      = $clog2(NUM_TAG),
                    parameter   FU_ID_BIT       = $clog2(NUM_FU),
                    parameter   SPEC_LEVEL_BIT  = $clog2(SPEC_DEPTH)+1)

(
    input                               clk,
    input                               rst_n,
    
    input       [NUM_FU           -1:0] fu_available,
    input       [NUM_REG          -1:0] reg_read_pending,
    
    output reg  [NUM_REG          -1:0] reg_write_pending,
    output      [NUM_TAG*REG_ID_BIT -1:0]    cur_tag_map,
                              
    input                               issue_vld,              // Single issue per cycle
    output                              issue_rdy,
    input       [FU_ID_BIT        -1:0] issue_fu,
    input       [TAG_ID_BIT       -1:0] issue_dst_reg,          // 0 means the FU don't produce value
    input       [TAG_ID_BIT       -1:0] issue_src_reg0,         // 0 means the FU don't consume value
    input       [TAG_ID_BIT       -1:0] issue_src_reg1,
    input       [SPEC_LEVEL_BIT   -1:0] issue_spec_level,
    output      [REG_ID_BIT       -1:0] issue_dst_reg_rename,   // Assume the RSs are external module
    output      [REG_ID_BIT       -1:0] issue_src_reg0_rename,  // so we just output the rename result
    output      [REG_ID_BIT       -1:0] issue_src_reg1_rename,
    
    input       [NUM_FU           -1:0] fu2sb_read_reg_id_vld,
    output      [NUM_FU           -1:0] fu2sb_read_reg_id_rdy,
    input       [NUM_FU*REG_ID_BIT-1:0] fu2sb_read_reg0_id,
    input       [NUM_FU*REG_ID_BIT-1:0] fu2sb_read_reg1_id,
    input       [NUM_FU*REG_ID_BIT-1:0] fu2sb_write_reg_id_nxt, // This is used to resolve the condition like r3 = add r3, r2,
                                                                // in this case write_pending of r3 will be on but the read of r3 still can be issued
    output      [NUM_FU           -1:0] sb2rf_read_reg_id_vld,
    input       [NUM_FU           -1:0] sb2rf_read_reg_id_rdy,
    output      [NUM_FU*REG_ID_BIT-1:0] sb2rf_read_reg0_id,
    output      [NUM_FU*REG_ID_BIT-1:0] sb2rf_read_reg1_id,

    input       [NUM_FU           -1:0] fu2sb_write_reg_id_vld, // We don't need rdy if in the issue stage we ensure the renamed dst reg is retired and no one need it
    output      [NUM_FU           -1:0] fu2sb_write_reg_id_rdy,
    input       [NUM_FU*REG_ID_BIT-1:0] fu2sb_write_reg_id,
    input       [NUM_FU*REG_BIT   -1:0] fu2sb_write_data,

    output      [NUM_FU           -1:0] sb2rf_write_reg_id_vld,
    input       [NUM_FU           -1:0] sb2rf_write_reg_id_rdy,
    output      [NUM_FU*REG_ID_BIT-1:0] sb2rf_write_reg_id,
    output      [NUM_FU*REG_BIT   -1:0] sb2rf_write_data,
    
    // This will be valid once conditional reg is write back,
    // no matter speculation success or fail
    input                                           br_pred_vld,
    input                                           br_pred_succ,    // predict success
                                                            // If predict fail all deeper level should be cleaned
                                                            // If predict success, it's possible that we hit a branch
                                                            // in the same clock so specuation level didn't change
                                                            // However, this should be considered in cur_spec_level
                                                            // If speculation success in this cycle, then cur_spec_level
                                                            // should -1 in the same cycle
    input       [SPEC_LEVEL_BIT*(SPEC_DEPTH+1)-1:0] br_pred_succ_nxt_levels,   // The new levels after spec success
                                                                            // We need multiple entries because a conditonal register may be used in multiple spec levels

    input       [SPEC_LEVEL_BIT               -1:0] br_pred_fail_level,   // all spec levels >= this should rollback if !spec_cond_wb_succ
    input       [NUM_TAG*REG_ID_BIT           -1:0] br_pred_fail_tag_map
);

    wire [REG_ID_BIT    -1:0]   read_reg0_of_fu         [NUM_FU     -1:0];
    wire [REG_ID_BIT    -1:0]   read_reg1_of_fu         [NUM_FU     -1:0];
    wire [REG_ID_BIT    -1:0]   write_reg_of_fu_nxt     [NUM_FU     -1:0];
    wire [REG_ID_BIT    -1:0]   write_reg_of_fu         [NUM_FU     -1:0];

    wire                        read_reg_of_fu_rdy      [NUM_FU     -1:0];

    reg  [REG_ID_BIT    -1:0]   reg_rename              [NUM_TAG    -1:0];
    reg                         reg_retire              [NUM_REG    -1:0];
    reg  [SPEC_LEVEL_BIT-1:0]   reg_wr_spec_level       [NUM_REG    -1:0];
    reg  [SPEC_LEVEL_BIT-1:0]   reg_retire_spec_level   [NUM_REG    -1:0];
    wire [NUM_REG       -1:0]   reg_free;
 
    wire                        free_dst_reg_available  = |reg_free;
    wire [REG_ID_BIT    -1:0]   free_dst_reg;
    
    wire [REG_ID_BIT      :0]   find_free_reg_out;
    leading_zero_one_cnt    #(.DATA_WIDTH(NUM_REG), .COUNT_ZERO(1))
    find_free_reg   (   .in (reg_free),
                        .cnt(find_free_reg_out));
                        
    // Bitmap indicating which regsters will be written in this cycle.
    // Should decode each vld fu2sb_write_reg_id and or the result
    wire [NUM_REG   -1:0]   reg_write_mask_of_fu    [NUM_FU     -1:0];
    wire [NUM_REG   -1:0]   reg_write_mask_at_fu    [NUM_FU     -1:0];
    
    wire [NUM_REG   -1:0]   reg_write_back;
    
    wire [SPEC_LEVEL_BIT    -1:0]   br_pred_succ_nxt_level  [SPEC_DEPTH:0];
    
    assign free_dst_reg             = find_free_reg_out[REG_ID_BIT-1:0];
    
    assign issue_rdy                = fu_available[issue_fu] && (issue_dst_reg == 0 || free_dst_reg_available);
    assign issue_dst_reg_rename     = issue_dst_reg != 0 ? free_dst_reg : 0;
    assign issue_src_reg0_rename    = reg_rename[issue_src_reg0];
    assign issue_src_reg1_rename    = reg_rename[issue_src_reg1];
    
    assign fu2sb_write_reg_id_rdy   = sb2rf_write_reg_id_rdy;
    assign sb2rf_write_reg_id_vld   = fu2sb_write_reg_id_vld;
    assign sb2rf_write_reg_id       = fu2sb_write_reg_id;
    assign sb2rf_write_data         = fu2sb_write_data;
    
    assign reg_free [0] = 1'b0;
    generate
        genvar i;
        
        for (i=0; i<=SPEC_DEPTH; i=i+1) begin: gen_br_pred_succ_nxt_level
            assign  br_pred_succ_nxt_level[i]   = br_pred_succ_nxt_levels[i*SPEC_LEVEL_BIT+:SPEC_LEVEL_BIT];
        end
        
        // If branch pred success, then some regs may be free at next cycle,
        // However, we don't consider selecting these regs in this cycle because it's a little complicated.
        // Not only the conditions for reg_free need modification, but also the next cycle's reg_wr_spec_level and reg_retire_spec_level
        for (i=1; i<NUM_REG; i=i+1) begin: gen_reg_free
            assign  reg_free    [i] = !reg_read_pending[i] &&
                                      !reg_write_pending[i] &&
                                      ((reg_retire[i] && reg_retire_spec_level[i] == 0 && reg_wr_spec_level[i] == 0) ||
                                       (i == reg_rename[issue_dst_reg] && issue_spec_level == reg_wr_spec_level[i]));
        end
        
        for (i=0; i<NUM_TAG; i=i+1) begin: gen_cur_tag_map
            assign  cur_tag_map[i*REG_ID_BIT+:REG_ID_BIT]   = reg_rename[i];
        end

        for (i=0; i<NUM_TAG; i=i+1) begin: gen_reg_rename
            always@(posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    reg_rename  [i] <= 0;
                end
                // When rollback, issue_vld should not be on
                else if (br_pred_vld && !br_pred_succ) begin
                    reg_rename  [i] <= br_pred_fail_tag_map[i*REG_ID_BIT+:REG_ID_BIT];
                end
                else if (issue_vld && issue_rdy && issue_dst_reg != 0 && i == issue_dst_reg) begin
                    reg_rename  [i] <= free_dst_reg;
                end
            end
        end
        
        for (i=0; i<NUM_REG; i=i+1) begin: gen_reg_write_pending
            always@(posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    reg_write_pending   [i] <= 1'b0;
                end
                // Issue should not be vld when branch predict fail
                else if (issue_vld && issue_rdy && issue_dst_reg != 0 && i == free_dst_reg) begin
                    reg_write_pending   [i] <= 1'b1;
                end
                // This may happen when branch predict fail if the write has lower speculation level than the failed branch
                else if (reg_write_back[i]) begin
                    reg_write_pending   [i] <= 1'b0;
                end
                // We have to rollback to the state before speculative write, and since the reg is chosen for speculative write,
                // there must be no pending write before the speculative write
                else if (br_pred_vld && !br_pred_succ && reg_wr_spec_level[i] >= br_pred_fail_level) begin
                    reg_write_pending   [i] <= 1'b0;
                end
            end
        
            always@(posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    reg_retire  [i] <= 1'b1;
                end
                else if (issue_vld && issue_rdy && issue_dst_reg != 0 && i == free_dst_reg) begin
                    reg_retire  [i] <= 1'b0;
                end
                // dst_reg is going to be overwritten, so its value (in renamed register) can be retired
                // Actually free_dst_reg may be the same as reg_rename[issue_dst_reg]
                // so here we must use priority if
                else if (issue_vld && issue_rdy && issue_dst_reg != 0 && i == reg_rename[issue_dst_reg]) begin
                    reg_retire  [i] <= 1'b1;
                end
                else if (br_pred_vld && !br_pred_succ) begin
                    // We have to rollback to the state before speculative write, and since the reg is chosen for speculative write,
                    // it's must be retired before the speculative write
                    if (reg_wr_spec_level[i] >= br_pred_fail_level) begin
                        reg_retire  [i] <= 1'b1;
                    end
                    // The reg write is not rollbacked yet, only rollback the retire
                    // The reg may be write_pending or not 
                    else if (reg_retire[i] && reg_retire_spec_level[i] >= br_pred_fail_level) begin
                        reg_retire  [i] <= 1'b0;
                    end
                    
                end
            end
            
            always@(posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    reg_wr_spec_level       [i] <= 0;
                    reg_retire_spec_level   [i] <= 0;
                end
                else if (issue_vld && issue_rdy && issue_dst_reg != 0 && i == free_dst_reg) begin
                    // issue_spec_level already consider the case that branch pred success at the same cycle
                    // Here we must have reg_retire_spec_level[i] == 0 othwerwise if reg_retire_spec_level == reg_wr_spec_level
                    // something unexpected may happen
                    reg_wr_spec_level       [i] <= issue_spec_level;
                end
                else if (issue_vld && issue_rdy && issue_dst_reg != 0 && i == reg_rename[issue_dst_reg]) begin
                    // The reg is speculative write and retire at the same level, so it becomes free again
                    // (after no pending read)
                    if (br_pred_vld) begin
                        if (br_pred_succ_nxt_level[reg_wr_spec_level[i]] == issue_spec_level) begin
                            reg_wr_spec_level       [i] <= 0;
                            reg_retire_spec_level   [i] <= 0;
                        end
                        else begin
                            reg_retire_spec_level   [i] <= issue_spec_level;
                        end
                    end
                    else begin
                        if (reg_wr_spec_level[i] == issue_spec_level) begin
                            reg_wr_spec_level       [i] <= 0;
                            reg_retire_spec_level   [i] <= 0;
                        end
                        else begin
                            reg_retire_spec_level   [i] <= issue_spec_level;
                        end
                    end
                end
                else if (br_pred_vld) begin
                    if (br_pred_succ) begin
                        if (reg_retire[i] && br_pred_succ_nxt_level[reg_wr_spec_level[i]] == br_pred_succ_nxt_level[reg_retire_spec_level[i]]) begin
                            reg_wr_spec_level       [i] <= 0;
                            reg_retire_spec_level   [i] <= 0;
                        end
                        else begin
                            reg_wr_spec_level       [i] <= br_pred_succ_nxt_level[reg_wr_spec_level    [i]];
                            reg_retire_spec_level   [i] <= br_pred_succ_nxt_level[reg_retire_spec_level[i]];
                        end
                    end
                    else begin
                        if (reg_wr_spec_level[i] >= br_pred_fail_level) begin
                            reg_wr_spec_level       [i] <= 0;
                            reg_retire_spec_level   [i] <= 0;
                        end
                        else if (reg_retire[i] && reg_retire_spec_level[i] >= br_pred_fail_level) begin
                            reg_retire_spec_level   [i] <= 0;
                        end
                    end
                end
            end
        end
        
        for (i=0; i<NUM_FU; i=i+1) begin: gen_read_write_reg
            assign read_reg0_of_fu      [i] = fu2sb_read_reg0_id    [i*REG_ID_BIT+:REG_ID_BIT];
            assign read_reg1_of_fu      [i] = fu2sb_read_reg1_id    [i*REG_ID_BIT+:REG_ID_BIT];
            assign write_reg_of_fu_nxt  [i] = fu2sb_write_reg_id_nxt[i*REG_ID_BIT+:REG_ID_BIT];
            assign write_reg_of_fu      [i] = sb2rf_write_reg_id_vld[i] && sb2rf_write_reg_id_rdy[i] ? sb2rf_write_reg_id [i*REG_ID_BIT+:REG_ID_BIT] : 0;

            // If read_reg == write_reg, then it's impossible that some other FUs is still writing read_reg,
            // since the renaming mechanism won't choose some write_pending regs as the renamed dst reg
            assign read_reg_of_fu_rdy   [i] = (!reg_write_pending[read_reg0_of_fu[i]] || read_reg0_of_fu[i] == write_reg_of_fu_nxt[i]) &&
                                              (!reg_write_pending[read_reg1_of_fu[i]] || read_reg1_of_fu[i] == write_reg_of_fu_nxt[i]);
                                              
            assign fu2sb_read_reg_id_rdy[i] = read_reg_of_fu_rdy[i] && sb2rf_read_reg_id_rdy[i];
            assign sb2rf_read_reg_id_vld[i] = read_reg_of_fu_rdy[i] && fu2sb_read_reg_id_vld[i];

            decode  #(.DATA_WIDTH(REG_ID_BIT))
            write_reg_dec   (   .in (write_reg_of_fu     [i]),
                                .out(reg_write_mask_of_fu[i]));
            
        end
    endgenerate
    
    assign sb2rf_read_reg0_id   = fu2sb_read_reg0_id;
    assign sb2rf_read_reg1_id   = fu2sb_read_reg1_id;
    
    assign reg_write_mask_at_fu[0]  = reg_write_mask_of_fu[0];
    generate
        for (i=1; i<NUM_FU; i=i+1) begin: gen_reg_write_mask
            assign reg_write_mask_at_fu[i]  = reg_write_mask_at_fu[i-1] |
                                              reg_write_mask_of_fu[i  ];
        end
    endgenerate
    
    assign reg_write_back                   = reg_write_mask_at_fu[NUM_FU-1];

endmodule
