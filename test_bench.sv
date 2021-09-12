`timescale 1ns/1ps

module test_bench();
    localparam  NUM_REG         = 16;
    localparam  NUM_TAG         = 4;
    localparam  REG_BIT         = 16;
    localparam  IMM_BIT         = 8;
    localparam  ISSUE_FIFO_SIZE = 4;
    localparam  INST_ID_BIT     = 8;
    localparam  NUM_FU          = 7;
    localparam  PC_BIT          = 8;
    localparam  FU_DELAY_BIT    = 3;
    
    localparam  REG_ID_BIT      = $clog2(NUM_REG);
    localparam  TAG_ID_BIT      = $clog2(NUM_TAG);
    localparam  OP_BIT          = $clog2(NUM_FU);
    localparam  INST_BIT        = OP_BIT+TAG_ID_BIT*3+IMM_BIT;
    
    localparam  OP_ST           = 3'd0;
    localparam  OP_CMP_GT       = 3'd1;
    localparam  OP_ADD_IMM      = 3'd2;
    localparam  OP_ADD          = 3'd3;
    localparam  OP_SHL          = 3'd4;
    localparam  OP_SHR          = 3'd5;
    localparam  OP_MUL          = 3'd6;
    localparam  OP_BZ           = 3'd7;
    
    localparam  NUM_INST        = 32;
    localparam  NUM_CYCLE       = 1000;
    localparam  NUM_TEST        = 10;
    localparam  RAND_GEN_INST   = 0;
    
    function automatic random_gen_inst(ref bit [INST_BIT-1:0] inst [NUM_INST-1:0], ref integer seed);
        bit [NUM_TAG    -1:0]   reg_initialized;
        
        bit [OP_BIT     -1:0]   op;
        bit [TAG_ID_BIT -1:0]   dst_reg;
        bit [TAG_ID_BIT -1:0]   src_reg0;
        bit [TAG_ID_BIT -1:0]   src_reg1;
        bit [IMM_BIT    -1:0]   imm;
        bit [NUM_INST   -1:0]   is_br_target;
        bit [NUM_INST   -1:0]   is_br_inst;
        
        is_br_target        = {NUM_INST{1'b0}};
        is_br_inst          = {NUM_INST{1'b0}};

        // Just initialize all register at start otherwise it's hard to check
        // whether a register is initialized if there are branches
        for (int i=1; i<NUM_TAG; i++) begin
            op = OP_ADD_IMM;
            src_reg0 = 0;
            src_reg1 = 0;
            imm = $random(seed);
            dst_reg = i;
            
            inst[i-1] = {op, dst_reg, src_reg1, src_reg0, imm};
            $display("inst[%d] = {%d'd%d, %d'd%d, %d'd%d, %d'd%d, %d'd%d};", i-1, OP_BIT, op, TAG_ID_BIT, dst_reg, TAG_ID_BIT, src_reg1, TAG_ID_BIT, src_reg0, IMM_BIT, imm);
        end
        
        for (int i=NUM_TAG-1; i<NUM_INST; i++) begin
            // Don't generate OP_BZ here, just append a BZ after CMP_GT
            // Use op = $random(seed) % 3; won't work, don't know why
            do begin
                op  = $random(seed);
            end while (op == OP_BZ || (op == OP_CMP_GT && (i >= NUM_INST-2 || is_br_target[i+1])));
            
            if (op == OP_CMP_GT) begin
                src_reg0 = $random(seed);
                src_reg1 = $random(seed);
                imm = 0;
                do begin
                    dst_reg = $random(seed);
                end while (dst_reg == 0);
                
                inst[i] = {op, dst_reg, src_reg1, src_reg0, imm};
                $display("inst[%d] = {%d'd%d, %d'd%d, %d'd%d, %d'd%d, %d'd%d};", i, OP_BIT, op, TAG_ID_BIT, dst_reg, TAG_ID_BIT, src_reg1, TAG_ID_BIT, src_reg0, IMM_BIT, imm);
                
                op = OP_BZ;
                src_reg0 = dst_reg;
                src_reg1 = 0;
                dst_reg = 0;
                do begin
                    imm = $random()%NUM_INST;
                end while (imm > NUM_INST || imm == i+1 || (imm < i && is_br_inst[i]));
                
                inst[i+1] = {op, dst_reg, src_reg1, src_reg0, imm};
                $display("inst[%d] = {%d'd%d, %d'd%d, %d'd%d, %d'd%d, %d'd%d};", i+1, OP_BIT, op, TAG_ID_BIT, dst_reg, TAG_ID_BIT, src_reg1, TAG_ID_BIT, src_reg0, IMM_BIT, imm);
                is_br_inst[i+1] = 1'b1;
                is_br_target[imm] = 1'b1;
                
                i++;
            end
            else if (op == OP_ST) begin
                src_reg0 = $random(seed);
                src_reg1 = $random(seed);
                imm = 0;
                dst_reg = 0;
                
                inst[i] = {op, dst_reg, src_reg1, src_reg0, imm};
                $display("inst[%d] = {%d'd%d, %d'd%d, %d'd%d, %d'd%d, %d'd%d};", i, OP_BIT, op, TAG_ID_BIT, dst_reg, TAG_ID_BIT, src_reg1, TAG_ID_BIT, src_reg0, IMM_BIT, imm);
            end
            else if (op == OP_ADD || op == OP_SHL || op == OP_SHR || op == OP_MUL) begin
                src_reg0 = $random(seed);
                src_reg1 = $random(seed);
                imm = 0;
                do begin
                    dst_reg = $random(seed);
                end while (dst_reg == 0);
                
                inst[i] = {op, dst_reg, src_reg1, src_reg0, imm};
                $display("inst[%d] = {%d'd%d, %d'd%d, %d'd%d, %d'd%d, %d'd%d};", i, OP_BIT, op, TAG_ID_BIT, dst_reg, TAG_ID_BIT, src_reg1, TAG_ID_BIT, src_reg0, IMM_BIT, imm);
            end
            else begin
                src_reg0 = $random(seed);
                src_reg1 = 0;
                imm = $random(seed);
                do begin
                    dst_reg = $random(seed);
                end while (dst_reg == 0);
                
                inst[i] = {op, dst_reg, src_reg1, src_reg0, imm};
                $display("inst[%d] = {%d'd%d, %d'd%d, %d'd%d, %d'd%d, %d'd%d};", i, OP_BIT, op, TAG_ID_BIT, dst_reg, TAG_ID_BIT, src_reg1, TAG_ID_BIT, src_reg0, IMM_BIT, imm);
            end
        end
    endfunction
    
    function print_inst_golden(bit [INST_BIT       -1:0] inst [NUM_INST-1:0], int num_cycle);
        logic   [REG_BIT    -1:0]   golden_regs [NUM_TAG-1:0];
        int pc;
        int cycle;
    
        // Print expected store addr/data
        golden_regs [0] = 0;
        for (int i=1; i<NUM_TAG; i++) begin
            golden_regs [i] = {REG_BIT{1'bx}};
        end
        
        pc = 0;
        
        for (cycle=0; cycle<num_cycle && pc < NUM_INST; cycle++) begin
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
            
            //$write("pc: %d, reg: ", pc);
            //for (int i=0; i<NUM_TAG; i++) begin
            //    $write("%d, ", golden_regs[i]);
            //end
            //$write("\n");

            case (op)
                OP_ST:      exec_res    = golden_regs[src_reg1];
                OP_CMP_GT:  exec_res    = golden_regs[src_reg0] >  golden_regs[src_reg1] ? 1 : 0;
                OP_ADD_IMM: exec_res    = golden_regs[src_reg0] +  imm;
                OP_ADD:     exec_res    = golden_regs[src_reg0] +  golden_regs[src_reg1];
                OP_SHL:     exec_res    = golden_regs[src_reg0] << golden_regs[src_reg1];
                OP_SHR:     exec_res    = golden_regs[src_reg0] >> golden_regs[src_reg1];
                OP_MUL:     exec_res    = golden_regs[src_reg0] *  golden_regs[src_reg1];
                default:    exec_res    = 0;
            endcase
            
            if (op == OP_ST) begin
                $display("Golden(%d): Store addr %x, data %d", cycle, golden_regs[src_reg0], golden_regs[src_reg1]);
                pc = pc+1;
            end
            else if (op == OP_BZ) begin
                if (golden_regs[src_reg0] == 0) begin
                    pc = imm;
                end
                else begin
                    pc = pc+1;
                end
            end
            else begin
                //if (op == OP_ADD) begin
                //    $display("Golden[%d]: dst_reg %d, src_reg0 %d, src_reg1 %d", pc, exec_res, golden_regs[src_reg0], golden_regs[src_reg1]);
                //end
                //else if (op == OP_ADD_IMM || OP_SHL_IMM) begin
                //    $display("Golden[%d]: dst_reg %d, src_reg0 %d", pc, exec_res, golden_regs[src_reg0]);
                //end
                golden_regs[dst_reg]    = exec_res;
                pc = pc+1;
            end
        end
        
        if (pc == NUM_INST) begin
            $display("Golden(%d): Execution finish", cycle);
        end
        else begin
            $display("Golden(%d): Execution timeout", cycle);
        end
        
    endfunction
    
    function automatic random_gen_delay(ref bit [NUM_FU*FU_DELAY_BIT-1:0] fu_stage0_delays,
                                        ref bit [NUM_FU*FU_DELAY_BIT-1:0] fu_stage1_delays,
                                        ref bit [NUM_FU*FU_DELAY_BIT-1:0] fu_stage2_delays,
                                        ref integer seed);
        for (int i=0; i<NUM_FU; i++) begin
            fu_stage0_delays[i*FU_DELAY_BIT+:FU_DELAY_BIT] = $random(seed);
            fu_stage1_delays[i*FU_DELAY_BIT+:FU_DELAY_BIT] = $random(seed);
            fu_stage2_delays[i*FU_DELAY_BIT+:FU_DELAY_BIT] = $random(seed);
        end
    endfunction
    
    integer inst_seed;
    integer delay_seed;

    bit     clk;
    bit     rst_n;
    
    int     clk_cnt;
    int     test_cnt;
    
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
    wire    [INST_ID_BIT    -1:0]   write_mem_id;
    wire    [REG_BIT        -1:0]   write_mem_addr;
    wire    [REG_BIT        -1:0]   write_mem_data;
    
    bit     [NUM_FU*FU_DELAY_BIT-1:0]   fu_stage0_delays;
    bit     [NUM_FU*FU_DELAY_BIT-1:0]   fu_stage1_delays;
    bit     [NUM_FU*FU_DELAY_BIT-1:0]   fu_stage2_delays;
    
    wire                            exec_finish;
    
    cpu #(  .REG_BIT        (REG_BIT),
            .IMM_BIT        (IMM_BIT),
            .NUM_REG        (NUM_REG),
            .NUM_TAG        (NUM_TAG),
            .ISSUE_FIFO_SIZE(ISSUE_FIFO_SIZE),
            .INST_ID_BIT    (INST_ID_BIT),
            .NUM_FU         (NUM_FU),
            .PC_BIT         (PC_BIT),
            .FU_DELAY_BIT   (FU_DELAY_BIT),
            .OP_ST          (OP_ST),
            .OP_CMP_GT      (OP_CMP_GT),
            .OP_ADD_IMM     (OP_ADD_IMM),
            .OP_ADD         (OP_ADD),
            .OP_SHL         (OP_SHL),
            .OP_SHR         (OP_SHR),
            .OP_MUL         (OP_MUL),
            .OP_BZ          (OP_BZ))
            
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
            .write_mem_id   (write_mem_id),
            .write_mem_addr (write_mem_addr),
            .write_mem_data (write_mem_data),
            
            .fu_stage0_delays   (fu_stage0_delays),
            .fu_stage1_delays   (fu_stage1_delays),
            .fu_stage2_delays   (fu_stage2_delays),
            
            .exec_finish    (exec_finish));
            
            
    
    bit     [INST_BIT       -1:0]   inst    [NUM_INST-1:0];

    bit     [PC_BIT         -1:0]   cur_pc;
    bit                             cur_pc_vld;
    
    wire    [INST_BIT       -1:0]   cur_inst    = inst  [cur_pc];
    
    assign  fetch_rdy       = 1'b1;
    
    assign  inst_vld        = cur_pc_vld;
    assign  inst_last       = cur_pc == NUM_INST-1;
    assign  inst_op         = cur_inst  [IMM_BIT+TAG_ID_BIT*3+:OP_BIT    ];
    assign  inst_dst_reg    = cur_inst  [IMM_BIT+TAG_ID_BIT*2+:TAG_ID_BIT];
    assign  inst_src_reg1   = cur_inst  [IMM_BIT+TAG_ID_BIT  +:TAG_ID_BIT];
    assign  inst_src_reg0   = cur_inst  [IMM_BIT             +:TAG_ID_BIT];
    assign  inst_imm        = cur_inst  [0                   +:IMM_BIT   ];
    
    initial begin
        inst_seed   = 567;
        delay_seed  = 0;
    
        clk         = 1'b0;
        rst_n       = 1'b1;
        cur_pc      = 0;
        cur_pc_vld  = 1'b0;
        inst_id     = 0;
        test_cnt    = 0;
        
        if (!RAND_GEN_INST) begin
            for (int i=0; i<NUM_INST; i++) begin
                inst[i] = {INST_BIT{1'b0}};
            end
        
            //         op        , dst_reg       , src_reg1      , src_reg0      , imm
            inst[0] = {OP_ADD_IMM, TAG_ID_BIT'(1), TAG_ID_BIT'(0), TAG_ID_BIT'(0), IMM_BIT'( 0)};
            inst[1] = {OP_ADD_IMM, TAG_ID_BIT'(2), TAG_ID_BIT'(0), TAG_ID_BIT'(0), IMM_BIT'(10)};
            inst[2] = {OP_ST     , TAG_ID_BIT'(0), TAG_ID_BIT'(2), TAG_ID_BIT'(1), IMM_BIT'( 0)};
            inst[3] = {OP_ADD_IMM, TAG_ID_BIT'(1), TAG_ID_BIT'(0), TAG_ID_BIT'(1), IMM_BIT'( 1)};
            inst[4] = {OP_CMP_GT , TAG_ID_BIT'(3), TAG_ID_BIT'(2), TAG_ID_BIT'(1), IMM_BIT'( 0)};
            inst[5] = {OP_BZ     , TAG_ID_BIT'(0), TAG_ID_BIT'(0), TAG_ID_BIT'(3), IMM_BIT'( 2)};
            inst[6] = {OP_ST     , TAG_ID_BIT'(0), TAG_ID_BIT'(2), TAG_ID_BIT'(1), IMM_BIT'( 0)};
        end
        else begin
            random_gen_inst(inst, inst_seed);
        end
        
        print_inst_golden(inst, 300);
        
        random_gen_delay(fu_stage0_delays, fu_stage1_delays, fu_stage2_delays, delay_seed);
        
        // Initialize delays in function units...
        #0.1
        rst_n       = 1'b0;
        
        #1
        rst_n       = 1'b1;
    end
    
    always@(posedge clk) begin
        random_gen_delay(fu_stage0_delays, fu_stage1_delays, fu_stage2_delays, delay_seed);
    end
    
    always@(posedge clk) begin: gen_more_inst
        if (~rst_n) disable gen_more_inst;
        
        if (exec_finish) begin
            $display("Time %d: Execution finished", $time);
            
            if (RAND_GEN_INST && test_cnt < NUM_TEST) begin
                #0.1
                rst_n   = 1'b0;
                random_gen_inst(inst, inst_seed);
                print_inst_golden(inst, 300);
                test_cnt = test_cnt+1;
                delay_seed = 0;
                
                #2
                rst_n   = 1'b1;
            end
            else begin
                $finish;
            end
        end
        else if (clk_cnt > NUM_CYCLE) begin
            $display("Time %d: Execution timeout", $time);
            
            if (RAND_GEN_INST && test_cnt < NUM_TEST) begin
                #0.1
                rst_n   = 1'b0;
                random_gen_inst(inst, inst_seed);
                print_inst_golden(inst, 300);
                test_cnt = test_cnt+1;
                delay_seed = 0;
                
                #2
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
            $display("Simulation(%d): Store addr %x, data %d", write_mem_id, write_mem_addr, write_mem_data);
        end
    end
    
    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            cur_pc_vld  <= 1'b0;
        end
        else if (fetch_vld && fetch_rdy) begin
            cur_pc_vld  <= 1'b1;
        end
        else if (inst_rdy) begin
            cur_pc_vld  <= 1'b0;
        end
    end
    
    always@(posedge clk) begin: fetch_response
        if (fetch_vld && fetch_rdy) begin
            cur_pc      <= fetch_pc;
            inst_id     <= fetch_id;
        end
    end
    
    always@(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            clk_cnt <= 0;
        end
        else begin
            clk_cnt <= clk_cnt+1;
        end
    end

    always #1 begin
        clk = ~clk;
    end
endmodule
