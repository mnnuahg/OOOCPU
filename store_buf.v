/* This module stores memory write request and commit to memory
   when the request is no longer speculative */

module store_buf    #(parameter INST_ID_BIT     = 8,
                      parameter ADDR_BIT        = 16,
                      parameter DATA_BIT        = 16,
                      parameter BUF_DEPTH       = 16,
                      parameter SPEC_DEPTH      = 4,
                      parameter REG_ID_BIT      = 4,
                      parameter SPEC_LEVEL_BIT  = $clog2(SPEC_DEPTH)+1,
                      parameter PTR_BIT         = $clog2(BUF_DEPTH))
(
    input                               clk,
    input                               rst_n,
    
    input                               in_vld,
    output                              in_rdy,
    input       [INST_ID_BIT    -1:0]   in_id,
    input       [ADDR_BIT       -1:0]   in_addr,
    input       [DATA_BIT       -1:0]   in_data,
    input       [SPEC_LEVEL_BIT -1:0]   in_spec_level,
    
    // out_vld only when the lastest store is not speculative
    output                              out_vld,
    input                               out_rdy,
    output      [INST_ID_BIT    -1:0]   out_id,
    output      [ADDR_BIT       -1:0]   out_addr,
    output      [DATA_BIT       -1:0]   out_data,
    
    output                              empty,
    
    input                               br_pred_vld,
    input                               br_pred_succ,
    input       [SPEC_LEVEL_BIT -1:0]   br_pred_fail_level,
    input       [SPEC_LEVEL_BIT*(SPEC_DEPTH+1)-1:0] br_pred_succ_nxt_levels
);

    reg     [BUF_DEPTH      -1:0]   vlds;
    reg     [INST_ID_BIT    -1:0]   ids         [BUF_DEPTH-1:0];
    reg     [ADDR_BIT       -1:0]   addrs       [BUF_DEPTH-1:0];
    reg     [DATA_BIT       -1:0]   datas       [BUF_DEPTH-1:0];
    reg     [SPEC_LEVEL_BIT -1:0]   spec_levels [BUF_DEPTH-1:0];
    
    reg     [PTR_BIT        -1:0]   rptr;
    reg     [PTR_BIT        -1:0]   wptr;
    reg     [PTR_BIT          :0]   cnt;
    
    wire    [SPEC_LEVEL_BIT -1:0]   br_pred_succ_nxt_level  [SPEC_DEPTH:0];
    
    assign  empty   = ~(|vlds);
    
    generate
        genvar i;
            
    
        for (i=0; i<=SPEC_DEPTH; i=i+1) begin: gen_br_pred_succ_nxt_level
            assign  br_pred_succ_nxt_level[i]   = br_pred_succ_nxt_levels[i*SPEC_LEVEL_BIT+:SPEC_LEVEL_BIT];
        end
        
        for (i=0; i<BUF_DEPTH; i=i+1) begin: gen_signals
            always@(posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    vlds    [i] <= 1'b0;
                end
                // We don't need to consider the case that branch pred fail at the same cycle
                // since the store FU should consider it
                else if (in_vld && in_rdy && i == wptr) begin
                    vlds    [i] <= 1'b1;
                end
                else if (out_vld && out_rdy && i == rptr) begin
                    vlds    [i] <= 1'b0;
                end
                else if (br_pred_vld && !br_pred_succ && spec_levels[i] >= br_pred_fail_level) begin
                    vlds    [i] <= 1'b0;
                end
            end
            
            always@(posedge clk) begin
                if (in_vld && in_rdy && i == wptr) begin
                    spec_levels [i] <= in_spec_level;
                end
                else if (vlds[i] && br_pred_vld && br_pred_succ) begin
                    spec_levels [i] <= br_pred_succ_nxt_level   [spec_levels[i]];
                end
            end
            
            always@(posedge clk) begin
                if (in_vld && in_rdy && i == wptr) begin
                    ids     [i] <= in_id;
                    addrs   [i] <= in_addr;
                    datas   [i] <= in_data;
                end
            end
        end
    endgenerate
    
    assign  in_rdy      = cnt < BUF_DEPTH;
    assign  out_vld     = vlds[rptr] && spec_levels[rptr] == 0;
    
    assign  out_id      = ids  [rptr];
    assign  out_addr    = addrs[rptr];
    assign  out_data    = datas[rptr];
    
    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            rptr    <= 0;
        end
        else if (out_vld && out_rdy) begin
            rptr    <= rptr + 1;
        end
        else if (cnt > 0 && !vlds[rptr]) begin
            rptr    <= rptr + 1;
        end
    end
    
    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            wptr    <= 0;
        end
        else if (in_vld && in_rdy) begin
            wptr    <= wptr + 1;
        end
    end
    
    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            cnt <= 0;
        end
        else if (in_vld && in_rdy) begin
            if (!(out_vld && out_rdy) && !(cnt > 0 && !vlds[rptr])) begin
                cnt <= cnt + 1;
            end
        end
        else if (out_vld && out_rdy) begin
            cnt <= cnt - 1;
        end
        else if (cnt > 0 && !vlds[rptr]) begin
            cnt <= cnt - 1;
        end
    end

endmodule
