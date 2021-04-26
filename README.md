# Outline
This is a toy project to test my understanding of out-of-order scheduling algorithm. 
I implemented a toy CPU which has out-of-order execution and register renaming capablilty.
The register renaming algorithm is based on remapping table instead of reservation stations (Tomasulo algorithm).
In this algorithm, the register indices of instructions are used merely as tags instead of the physical register.
The remapping table records the mapping between tags and physical registers.
When an instruction is issued, remapping table will be looked up to find the actual source registers of the instruction.
The algorithm will also find a free register as the destination register and fill the mapping into the remapping table.
When a tag is overwritten, the original mapped register of the tag will be labeled as retired, which means its value
won't be used by newly issued instructions. And once all pending read (from previously issued instructions) of the register
are completed, the register will be free again and be mapped from other tags.

# How to run
This project was compiled and simulated on Intel Quartus Prime Lite and ModelSim. However, you may use whatever verilog simulators you like.
test_bench.sv will generate a random list of instructions and print the expected output (memory store address and data) and the actual output of the simulation.
Uncomment //`define PRINT_STAGE at top of binary_func_unit.v will allow the simulator to show various pipeline stages of each function unit.
