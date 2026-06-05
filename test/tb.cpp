#include <verilated.h>
#include <iostream>

#if VM_TRACE
#include <verilated_vcd_c.h>
#endif

// Verilator 5 uses VerilatedContext for timing
// If using Verilator 5+ with --timing, top->eval() handles delays automatically 
// when using the timing-aware loop.

#ifdef VERILATOR_VERSION_MAJOR
#if VERILATOR_VERSION_MAJOR >= 5
#define USE_VERILATOR_5 1
#endif
#endif

// Forward declaration of top module class based on TOP_MODULE macro from Makefile
#ifndef TOP_MODULE
#define TOP_MODULE Vaxi_to_dram_tb
#endif

// Macro magic to include the right header
#define XSTR(s) STR(s)
#define STR(s) #s
#include XSTR(TOP_MODULE.h)

int main(int argc, char** argv) {
    VerilatedContext* contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    
    TOP_MODULE* top = new TOP_MODULE{contextp};

    top->clk = 0;
    top->rst_n = 0;

    // Wait 3 cycles (6 edges)
    for (int i = 0; i < 6; i++) {
        top->clk = !top->clk;
        top->eval();
        contextp->timeInc(2); // Assuming 2ns per half-cycle
    }
    top->rst_n = 1;

    // Main event loop
    while (!contextp->gotFinish()) {
        top->clk = !top->clk;
        top->eval();
        contextp->timeInc(2);

        if (contextp->time() > 2000000) {
            std::cout << "Simulation Timeout!" << std::endl;
            break;
        }
    }

    top->final();
    delete top;
    delete contextp;
    return 0;
}
