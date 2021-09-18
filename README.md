# Outline
This is a toy CPU with out-of-order execution and register renaming capablilty.
It also supports multiple level of speculative branches.

The register renaming algorithm is based on remapping table instead of reservation stations (Tomasulo algorithm).
In this algorithm, the register indices of instructions are used merely as tags instead of the physical register.
The remapping table records the mapping between tags and physical registers.
When an instruction is issued, remapping table will be looked up to find the actual source registers of the instruction.
The algorithm will also find a free register as the destination register and fill the mapping into the remapping table.
When a tag is overwritten, the original mapped register of the tag will be labeled as retired, which means its value
won't be used by newly issued instructions. And once all pending read (from previously issued instructions) of the register
are completed, the register will be free again and be mapped from other tags.

Branch prediction happens when a branch is encountered and the branch condition register is not written back yet.
Instructions issued between branch prediction and the write back of the branch condition register are considered speculative.
We support multiple levels of speculative branches, so instructions may be issued with different level of speculation.
Non-speculative instructions will have speculation level 0.
The speculation level of the issued instructions will be carried through the pipeline stages and stored into register write/retire record,
and will be updated at the write back of branch conditional registers.
If the write back value matches the predicted value (branch predict success), then the branch becomes non-speculative, 
and all deeper level of speculations become one level less speculative.
If the write back value doesn't match the predicted value (branch predict fail), then all pipeline data with the same or deeper level of speculation
will be cleared. Moreover, register write/retire flags will be rolled back as well. If a register is written with the same or deeper level of speculation, 
then the register will be free after the rollback; otherwise, if the register is retired with the same or deeper level of speculation, then the retire flag
will be cleared, which means its value is still in use.
Since register retire may be speculative, retire flag along doesn't guarantee that a register is free,
one more condition should be considered: the speculation level of the retire should be no larger than the speculation level of the register write.

# How to run
This project was compiled and simulated on Intel Quartus Prime Lite and ModelSim. However, you may use whatever verilog simulators you like.
test_bench.sv will generate a random list of instructions and print the expected output (memory store address and data) and the actual output of the simulation.
Uncomment //`define PRINT_STAGE at top of binary_func_unit.v will allow the simulator to show various pipeline stages of each function unit.
