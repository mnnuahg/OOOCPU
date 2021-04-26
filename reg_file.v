module reg_file #(  parameter NUM_REG       = 8,
                    parameter REG_BIT       = 16,
                    parameter NUM_R_PORT    = 2,
                    parameter NUM_W_PORT    = 2)
(
    input                                       clk,
    input                                       rst_n,

    input   [NUM_R_PORT                -1:0]    rd_addr_vld,
    output  [NUM_R_PORT                -1:0]    rd_addr_rdy,
    input   [NUM_R_PORT*$clog2(NUM_REG)-1:0]    rd_addr0,
    input   [NUM_R_PORT*$clog2(NUM_REG)-1:0]    rd_addr1,
    
    // For simplicity, assuming a read port can read 2 data...
    output  [NUM_R_PORT                -1:0]    rd_data_vld,
    input   [NUM_R_PORT                -1:0]    rd_data_rdy,
    output  [NUM_R_PORT*REG_BIT        -1:0]    rd_data0,
    output  [NUM_R_PORT*REG_BIT        -1:0]    rd_data1,
    
    input   [NUM_W_PORT                -1:0]    wr_vld,
    output  [NUM_W_PORT                -1:0]    wr_rdy,
    input   [NUM_W_PORT*$clog2(NUM_REG)-1:0]    wr_addr,
    input   [NUM_W_PORT*REG_BIT        -1:0]    wr_data
);

    localparam  REG_ID_BIT  = $clog2(NUM_REG);
    localparam  PORT_ID_BIT = $clog2(NUM_W_PORT);

    reg     [REG_BIT    -1:0]   regs                [NUM_REG    -1:0];
    
    
    reg                         rd_addrs_vld        [NUM_R_PORT -1:0];
    reg     [REG_ID_BIT -1:0]   rd_addr0s           [NUM_R_PORT -1:0];
    reg     [REG_ID_BIT -1:0]   rd_addr1s           [NUM_R_PORT -1:0];
    
    wire    [NUM_REG    -1:0]   write_mask_of_port  [NUM_W_PORT -1:0];
    wire    [NUM_W_PORT -1:0]   port_write_to_reg   [NUM_REG    -1:0];
    
    wire                        reg_wr_vld          [NUM_REG    -1:0];
    wire    [PORT_ID_BIT-1:0]   reg_wr_data_sel     [NUM_REG    -1:0];
    
    assign  wr_rdy  = {NUM_W_PORT{1'b1}};
    
    generate
        genvar i, j;
        
        for (i=0; i<NUM_R_PORT; i=i+1) begin: gen_rd_addr_data
            always@(posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    rd_addrs_vld[i] <= 1'b0;
                end
                else if (rd_addr_vld[i] && rd_addr_rdy[i]) begin
                    rd_addrs_vld[i] <= 1'b1;
                end
                else if (rd_data_rdy[i]) begin
                    rd_addrs_vld[i] <= 1'b0;
                end
            end
            
            always@(posedge clk) begin
                if (rd_addr_vld[i] && rd_addr_rdy[i]) begin
                    rd_addr0s   [i] <= rd_addr0[i*REG_ID_BIT+:REG_ID_BIT];
                    rd_addr1s   [i] <= rd_addr1[i*REG_ID_BIT+:REG_ID_BIT];
                end
            end

            assign  rd_addr_rdy [i                 ] = !rd_addrs_vld [i] || rd_data_rdy[i];
            assign  rd_data_vld [i                 ] = rd_addrs_vld  [i];
            assign  rd_data0    [i*REG_BIT+:REG_BIT] = regs          [rd_addr0s[i]];
            assign  rd_data1    [i*REG_BIT+:REG_BIT] = regs          [rd_addr1s[i]];
        end
        
        for (i=0; i<NUM_W_PORT; i=i+1) begin: gen_wr_reg_decode
            decode  #(.DATA_WIDTH(REG_ID_BIT))
            wr_reg_decode   (   .in (wr_vld[i] ? wr_addr[i*REG_ID_BIT+:REG_ID_BIT] : 0),
                                .out(write_mask_of_port[i]));
        end
        
        for (i=0; i<NUM_REG; i=i+1) begin: gen_port_write_to_reg_i
            for (j=0; j<NUM_W_PORT; j=j+1) begin: gen_port_write_to_reg_i_j
                assign port_write_to_reg[i][j] = write_mask_of_port[j][i];
            end
        end
        
        assign  reg_wr_vld      [0] = 0;
        assign  reg_wr_data_sel [0] = 0;
        
        for (i=1; i<NUM_REG; i=i+1) begin: gen_wr_sel
            assign  reg_wr_vld[i]   = |port_write_to_reg[i];
            
            leading_zero_one_cnt    #(  .DATA_WIDTH (NUM_W_PORT),
                                        .COUNT_ZERO (1))
            gen_wr_data_sel (   .in (port_write_to_reg  [i]),
                                .cnt(reg_wr_data_sel    [i]));
        end
        
        for (i=0; i<NUM_REG; i=i+1) begin: gen_wr_data
            always@(posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    regs    [i] <=  0;
                end
                else if (reg_wr_vld[i]) begin
                    regs    [i] <=  wr_data [reg_wr_data_sel[i]*REG_BIT+:REG_BIT];
                end
            end
        end

    endgenerate
    
endmodule
