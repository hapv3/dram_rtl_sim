# 🚀 DRAM Simulation Tool for RTL

This tool aids in system-level hardware simulations, particularly for large chip designs (RTL models) that require co-simulation with modern off-chip DRAMs (e.g., LPDDR, DDR, HBM). It utilizes [DRAMSys5.0](https://github.com/tukl-msd/DRAMSys) for the simulation of DRAM + CTRL models, setting up a co-simulation environment between RTL and DRAMSys5.0 effectively.

## 🚀 Getting Started

### 🔧 Prerequisites

- This tool leverages [`bender`](https://github.com/pulp-platform/bender) for dependency management and automatic generation of compilation scripts.
- Note: We currently do not offer an open-source simulation setup. Instead, we have utilized `Questasim` for simulation.
- For building DRAMSys, cmake version >= 3.28.1 is required.

### 🔨 Build DRAMSys Dynamic Linkable Library

To download, patch, and build the DRAMSys dynamic linkable libraries, run
```shell
make -j dramsys
```

After building, two key libraries will be available in `dramsys_lib/DRAMSys/build/lib`:
- `libsystemc.so`
- `libDRAMSys_Simulator.so`

### 🧪 (Optional) Test RTL-DRAMSys Co-simulation

From the root folder of this repository, use the command `make all` or `make gui` to run an RTL testbench that attempts to access DDR4-DIMM data using Questasim.
Alternatively, use `make all_vcs` for VCS or `make all_verilator` for Verilator.

### 📚 Using DRAMSys Dynamic Linkable Library for System-Level RTL+DRAMSys Co-simulation

**Steps**:

1. Include the following three SystemVerilog files from the `src` directory into your project. For example, you can add them to your `Bender.yml` source list:
   - `src/sim_dram.sv`
   - `src/axi_dram_sim.sv`
   - `src/dram_sim_engine.sv`

2. Instantiate **only one** `dram_sim_engine` in your design and set the parameter for your design's `clk period in ns`. It is recommended to place it in your top-level design.

3. Utilize the `axi_dram_sim` module as a standard SystemVerilog module with an AXI4 interface by:
   - Passing basic AXI interface parameters.
   - Specifying the DRAM model to simulate with the `DRAMType` parameter (defaults to `DDR4`).
   - Providing the base address of the DRAM model in your design.

4. For simulation in Modelsim, link Modelsim to the built libraries (`libsystemc.so` and `libDRAMSys_Simulator.so`) and specify the location of configuration files by passing the following arguments to your command:
    ```shell
    -sv_lib <library folder path>/libsystemc -sv_lib <library folder path>/libDRAMSys_Simulator +DRAMSYS_RES=<path to dramsys_lib/resources>
    ```
   For simulation in vcs, please refer Makefile with *_vcs option for more information. 
   For simulation in Verilator, you can link against the DRAMSys libraries by adding `-LDFLAGS "-Wl,-rpath,<library folder path> -L<library folder path> -lDRAMSys_Simulator -lsystemc"` to your Verilator build options. Refer to the `all_verilator` target in the Makefile for an example. 
5. 💡 Now, you are ready to enjoy your DRAM simulation!

## 🚧 Planned Architectural Upgrade (Roadmap)

To accurately model the behavior, latency, and throughput of a real Memory Controller, we plan to refactor the current RTL wrapper to support **Full AXI4 Outstanding Transactions, Out-of-Order Execution, and Burst Transactions**.

### 1. Removing Bottlenecks in RTL Frontend
- **Remove `axi_to_axi_lite` & `stream_arbiter`**: The current wrapper uses AXI-Lite and merges AR and AW channels into a single stream. This creates *Head-of-Line Blocking* and forces Read/Write interleaving, significantly reducing throughput due to constant read-to-write turnaround penalties.
- **Implement 5 Independent AXI Channels**: `sim_dram.sv` will act as a Full AXI4 Slave, allowing AR and AW requests to be queued and passed to DRAMSys independently, preserving their `ARID` and `AWID`.
- **Burst Data Buffering**: Instead of stripping bursts into single-beat transactions, the RTL will buffer the full burst payload (using `WLAST`) and pass it entirely to DRAMSys in a single DPI-C call.

### 2. Upgrading C++ DPI-C Backend (DRAMSys Wrapper)
- **ID Tracking & Out-of-Order Responses**: Update the DPI-C interface (`dram_send_req`) to pass the AXI `ID`. The internal SystemC TLM wrapper (`dramsys_conv.h`) will be rewritten to drop the forced in-order synchronization queue. It will use a new `std::queue<std::pair<int, uint8_t>>` to push out responses as soon as DRAMSys finishes them.
- **Independent R/W Queues**: Separate `dram_can_accept_req` into `dram_can_accept_ar` and `dram_can_accept_aw`.

### 3. Benefits
This upgrade will allow the underlying DRAMSys engine's FR-FCFS scheduler to see a global view of all outstanding memory requests, enabling **Zero-penalty Batching** (grouping reads and writes) and **Out-of-Order Row Buffer Hit Optimization**, producing highly accurate performance profiling metrics for the SoC.

## 🎉 License

All hardware sources and tool scripts are licensed under the Solderpad Hardware License 0.51 (see `LICENSE`). [DRAMSys5.0](https://github.com/tukl-msd/DRAMSys) is employed for DRAM simulations; please adhere to their [license](https://github.com/tukl-msd/DRAMSys) as well.
