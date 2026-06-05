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

    // Main event loop
    while (!contextp->gotFinish()) {
	// instead of increase time 1ps, jump to next timeslot for performance
	if (top->eventsPending()) {
            contextp->time(top->nextTimeSlot());
        }
        top->eval();

        if (contextp->time() > 2000000000) {
            std::cout << "Simulation Timeout!" << std::endl;
            break;
        }
    }

    top->final();
    delete top;
    delete contextp;
    return 0;
}
