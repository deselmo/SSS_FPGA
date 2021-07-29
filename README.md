# SSS_FPGA
Framework able to solve problems modelled as state-space search for FPGA devices.

Users willing to use the framework have to implement only the OpenCL kernels to manage the communication with the host application and a kernel function that, given a state of the exploration, produces all the states reachable from it.
We also allow the user to define a replication factor NW.
The framework is able to grant a linear speedup if the problem generates enough tasks to make the pipeline work at full capacity.
When working at full capacity, the framework analyzes NW new exploration states every clock cycle of the FPGA.

As an application, we propose a brute force sudoku solver able to produce a new board every clock cycle and make the most from the framework.

The `assets/boards` file is taken from https://github.com/t-dillon/tdoku.
