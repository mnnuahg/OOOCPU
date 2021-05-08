module test_bench();
    localparam  NUM_REG         = 16;
    localparam  NUM_TAG         = 4;
    localparam  REG_BIT         = 16;
    localparam  IMM_BIT         = 4;
    localparam  ISSUE_FIFO_SIZE = 4;
    localparam  INST_ID_BIT     = 8;
    localparam  NUM_FU          = 8;
    localparam  PC_BIT          = 8;
    
    localparam  REG_ID_BIT      = $clog2(NUM_REG);
    localparam  TAG_ID_BIT      = $clog2(NUM_TAG);
    localparam  OP_BIT          = $clog2(NUM_FU);
    localparam  INST_BIT        = OP_BIT+TAG_ID_BIT*3+IMM_BIT;
    
    localparam  OP_ST           = 3'd0;
    localparam  OP_ADD          = 3'd1;
    localparam  OP_ADD_IMM      = 3'd2;
    localparam  OP_SHL_IMM      = 3'd3;
    localparam  OP_SHR_IMM      = 3'd4;
    localparam  OP_SHL          = 3'd5;
    localparam  OP_SHR          = 3'd6;
    localparam  OP_MUL          = 3'd7;
    
    localparam  NUM_INST        = 32;
    localparam  RAND_GEN_INST   = 1;
    
    function automatic random_gen_inst(ref bit     [INST_BIT       -1:0]   inst    [NUM_INST-1:0], ref integer seed);
        bit [NUM_TAG    -1:0]   reg_initialized;
        
        bit [OP_BIT     -1:0]   op;
        bit [TAG_ID_BIT -1:0]   dst_reg;
        bit [TAG_ID_BIT -1:0]   src_reg0;
        bit [TAG_ID_BIT -1:0]   src_reg1;
        bit [IMM_BIT    -1:0]   imm;
        
        reg_initialized [0] = {{NUM_TAG-1{1'b0}}, 1'b1};
        
        for (int i=0; i<NUM_INST; i++) begin
            // Only gen store/add/add_imm/shl_imm otherwise the result will likely be 0
            // Use op = $random(seed) % 3; won't work, don't know why
            do begin
                op  = $random(seed);
            end while(op >= 4);
            
            do begin
                src_reg0 = $random(seed);
            end while(!reg_initialized[src_reg0]);
            
            if (op != OP_ADD_IMM && op != OP_SHL_IMM && op != OP_SHR_IMM) begin
                do begin
                    src_reg1 = $random(seed);
                end while(!reg_initialized[src_reg1]);
                imm = 0;
            end
            else begin
                src_reg1 = 0;
                imm = $random(seed);
            end
            
            if (op == OP_ST) begin
                dst_reg = 0;
            end
            else begin
                do begin
                    dst_reg = $random(seed);
                end while (dst_reg == 0);
            end
            
            reg_initialized [dst_reg] = 1'b1;
            inst            [i      ] = {op, dst_reg, src_reg1, src_reg0, imm};
            
            $display("inst[%d] = {%d'd%d, %d'd%d, %d'd%d, %d'd%d, %d'd%d};", i, OP_BIT, op, TAG_ID_BIT, dst_reg, TAG_ID_BIT, src_reg1, TAG_ID_BIT, src_reg0, IMM_BIT, imm);
        end
    endfunction
    
    function print_inst_golden(bit     [INST_BIT       -1:0]   inst    [NUM_INST-1:0]);
        logic   [REG_BIT    -1:0]   golden_regs [NUM_TAG-1:0];
    
        // Print expected store addr/data
        golden_regs [0] = 0;
        for (int i=1; i<NUM_TAG; i++) begin
            golden_regs [i] = {REG_BIT{1'bx}};
        end
        
        for (int pc=0; pc<NUM_INST; pc++) begin
            bit [OP_BIT     -1:0]   op;
            bit [TAG_ID_BIT -1:0]   dst_reg;
            bit [TAG_ID_BIT -1:0]   src_reg0;
            bit [TAG_ID_BIT -1:0]   src_reg1;
            bit [IMM_BIT    -1:0]   imm;

            bit [REG_BIT    -1:0]   exec_res;
        
            op          = inst[pc][IMM_BIT+TAG_ID_BIT*3+:OP_BIT    ];
            dst_reg     = inst[pc][IMM_BIT+TAG_ID_BIT*2+:TAG_ID_BIT];
            src_reg1    = inst[pc][IMM_BIT+TAG_ID_BIT  +:TAG_ID_BIT];
            src_reg0    = inst[pc][IMM_BIT             +:TAG_ID_BIT];
            imm         = inst[pc][0                   +:IMM_BIT   ];

            case (op)
                OP_ST:      exec_res    = golden_regs[src_reg1];
                OP_ADD_IMM: exec_res    = golden_regs[src_reg0] +  imm;
                OP_SHL_IMM: exec_res    = golden_regs[src_reg0] << imm;
                OP_SHR_IMM: exec_res    = golden_regs[src_reg0] >> imm;
                OP_ADD:     exec_res    = golden_regs[src_reg0] +  golden_regs[src_reg1];
                OP_SHL:     exec_res    = golden_regs[src_reg0] << golden_regs[src_reg1];
                OP_SHR:     exec_res    = golden_regs[src_reg0] >> golden_regs[src_reg1];
                OP_MUL:     exec_res    = golden_regs[src_reg0] *  golden_regs[src_reg1];
                default:    exec_res    = 0;
            endcase
            
            if (op == OP_ST) begin
                $display("Golden: Store addr %x, data %d", golden_regs[src_reg0], golden_regs[src_reg1]);
            end
            else begin
                //if (op == OP_ADD) begin
                //    $display("Golden[%d]: dst_reg %d, src_reg0 %d, src_reg1 %d", pc, exec_res, golden_regs[src_reg0], golden_regs[src_reg1]);
                //end
                //else if (op == OP_ADD_IMM || OP_SHL_IMM) begin
                //    $display("Golden[%d]: dst_reg %d, src_reg0 %d", pc, exec_res, golden_regs[src_reg0]);
                //end
                golden_regs[dst_reg]    = exec_res;
            end
        end
    endfunction
    
    integer seed;

    bit     clk;
    bit     rst_n;
    
    wire                            fetch_vld;
    wire                            fetch_rdy;
    wire    [INST_ID_BIT    -1:0]   fetch_id;
    wire    [PC_BIT         -1:0]   fetch_pc;
    
    wire                            inst_vld;
    wire                            inst_rdy;
    wire                            inst_last;
    wire    [OP_BIT         -1:0]   inst_op;
    bit     [INST_ID_BIT    -1:0]   inst_id;
    wire    [TAG_ID_BIT     -1:0]   inst_dst_reg;
    wire    [TAG_ID_BIT     -1:0]   inst_src_reg0;
    wire    [TAG_ID_BIT     -1:0]   inst_src_reg1;
    wire    [IMM_BIT        -1:0]   inst_imm;
    
    wire                            write_mem_vld;
    wire                            write_mem_rdy   = 1'b1;
    wire    [REG_BIT        -1:0]   write_mem_addr;
    wire    [REG_BIT        -1:0]   write_mem_data;
    
    wire                            exec_finish;
    
    cpu #(  .REG_BIT        (REG_BIT),
            .NUM_REG        (NUM_REG),
            .NUM_TAG        (NUM_TAG),
            .ISSUE_FIFO_SIZE(ISSUE_FIFO_SIZE),
            .INST_ID_BIT    (INST_ID_BIT),
            .NUM_FU         (NUM_FU),
            .PC_BIT         (PC_BIT))
            
    dut (   .clk            (clk),
            .rst_n          (rst_n),
            
            .fetch_vld      (fetch_vld),
            .fetch_rdy      (fetch_rdy),
            .fetch_id       (fetch_id),
            .fetch_pc       (fetch_pc),

            .inst_vld       (inst_vld),
            .inst_rdy       (inst_rdy),
            .inst_id        (inst_id),
            .inst_last      (inst_last),
            .inst_op        (inst_op),
            .inst_dst_reg   (inst_dst_reg),
            .inst_src_reg0  (inst_src_reg0),
            .inst_src_reg1  (inst_src_reg1),
            .inst_imm       (inst_imm),
            
            .write_mem_vld  (write_mem_vld),
            .write_mem_rdy  (write_mem_rdy),
            .write_mem_addr (write_mem_addr),
            .write_mem_data (write_mem_data),
            
            .exec_finish    (exec_finish));
            
            
    
    bit     [INST_BIT       -1:0]   inst    [NUM_INST-1:0];

    bit     [PC_BIT         -1:0]   cur_pc;
    bit                             cur_pc_vld;
    
    wire    [INST_BIT       -1:0]   cur_inst    = inst  [cur_pc];
    
    assign  fetch_rdy       = !cur_pc_vld || inst_rdy;
    
    assign  inst_vld        = cur_pc_vld;
    assign  inst_last       = cur_pc == NUM_INST-1;
    assign  inst_op         = cur_inst  [IMM_BIT+TAG_ID_BIT*3+:OP_BIT    ];
    assign  inst_dst_reg    = cur_inst  [IMM_BIT+TAG_ID_BIT*2+:TAG_ID_BIT];
    assign  inst_src_reg1   = cur_inst  [IMM_BIT+TAG_ID_BIT  +:TAG_ID_BIT];
    assign  inst_src_reg0   = cur_inst  [IMM_BIT             +:TAG_ID_BIT];
    assign  inst_imm        = cur_inst  [0                   +:IMM_BIT   ];
    
    initial begin
        seed        = 111;
    
        clk         = 1'b0;
        rst_n       = 1'b0;
        cur_pc      = 0;
        cur_pc_vld  = 1'b0;
        inst_id     = 0;
        
        if (!RAND_GEN_INST) begin
            for (int i=0; i<NUM_INST; i++) begin
                inst[i] = {INST_BIT{1'b0}};
            end
        
            inst[0] = {OP_ADD_IMM, TAG_ID_BIT'(1), TAG_ID_BIT'(0), TAG_ID_BIT'(0), IMM_BIT'(1)};
            inst[1] = {OP_SHL    , TAG_ID_BIT'(2), TAG_ID_BIT'(1), TAG_ID_BIT'(1), IMM_BIT'(0)};
            inst[2] = {OP_ADD_IMM, TAG_ID_BIT'(1), TAG_ID_BIT'(0), TAG_ID_BIT'(0), IMM_BIT'(2)};
            inst[3] = {OP_SHL    , TAG_ID_BIT'(1), TAG_ID_BIT'(1), TAG_ID_BIT'(1), IMM_BIT'(0)};
            inst[4] = {OP_ADD    , TAG_ID_BIT'(1), TAG_ID_BIT'(1), TAG_ID_BIT'(2), IMM_BIT'(0)};
            inst[5] = {OP_ST     , TAG_ID_BIT'(0), TAG_ID_BIT'(0), TAG_ID_BIT'(1), IMM_BIT'(0)};
        end
        else begin
            random_gen_inst(inst, seed);
        end
        
        print_inst_golden(inst);
        
        #0.1
        rst_n       = 1'b1;
        
        #2000
        $finish;
    end
    
    always@(posedge clk) begin: gen_more_inst
        if (~rst_n) disable gen_more_inst;
        
        if (exec_finish) begin
            $display("Time %d: Execution finished", $time);
            
            if (RAND_GEN_INST) begin
                #0.1
                rst_n   = 1'b0;
                random_gen_inst(inst, seed);
                print_inst_golden(inst);
                
                #0.1
                rst_n   = 1'b1;
            end
            else begin
                $finish;
            end
        end
    end
    
    always@(posedge clk) begin: print_store
        if (~rst_n) disable print_store;
        
        if (write_mem_vld && write_mem_rdy) begin
            $display("Simulation: Store addr %x, data %d", write_mem_addr, write_mem_data);
        end
    end
    
    always@(posedge clk) begin: fetch_response
        if (~rst_n) disable fetch_response;
        
        if (fetch_vld && fetch_rdy) begin
            #0.1
            cur_pc_vld  = 1'b1;
            cur_pc      = fetch_pc;
            inst_id     = fetch_id;
        end
        else if (inst_rdy) begin
            #0.1
            cur_pc_vld  = 1'b0;
        end
    end

    always #1 begin
        clk = ~clk;
    end
endmodule
