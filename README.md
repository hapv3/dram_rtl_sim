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

## 🚀 V2 Architecture Update

The `dram_rtl_sim` wrapper has been completely refactored in the **V2 Architecture** to support **Full AXI4 Outstanding Transactions, Out-of-Order Execution, and Burst Transactions**, significantly accelerating simulation speed and improving cycle accuracy.

### 1. Removing Bottlenecks in RTL Frontend
- **Removed `axi_to_axi_lite` & `stream_arbiter`**: The previous V1 wrapper stripped bursts into single-beat transactions and forced Read/Write interleaving. This created *Head-of-Line Blocking* and drastically reduced throughput.
- **5 Independent AXI Channels**: `sim_dram_v2.sv` now acts as a Full AXI4 Slave, allowing AR and AW requests to be queued and passed to DRAMSys independently, preserving their `ARID` and `AWID`.
- **Bulk Burst Data Buffering**: Instead of handling AXI beats individually through DPI-C, the RTL buffers the full burst payload in write FIFOs and passes the entire block to DRAMSys in a single DPI-C call. Responses are coalesced similarly, yielding a **>35x** simulation speedup.

### 2. Upgraded C++ DPI-C Backend (DRAMSys Wrapper)
- **ID Tracking & Out-of-Order Responses**: The DPI-C interface (`dram_send_req_id`) now tracks AXI `ID`s. The internal SystemC TLM wrapper (`dramsys_conv.h`) drops the forced in-order synchronization queue. It pushes out read/write responses as soon as DRAMSys schedules and completes them.
- **Independent R/W Queues**: R/W backpressure is handled seamlessly with `dram_can_accept_ar` and `dram_can_accept_aw`.

### 3. RTL Interface of V2

To use the V2 architecture in your project, instantiate the `axi_dram_sim_v2` module.

```systemverilog
    axi_dram_sim_v2 #(
        .AxiAddrWidth   ( 32 ),
        .AxiDataWidth   ( 512 ), // Configurable up to wide widths like 512-bit
        .AxiIdWidth     ( 5 ),
        .AxiUserWidth   ( 5 ),
        .DRAMType       ( "DDR4" ), // Defaults to DDR4
        .BASE           ( 32'h8000_0000 ), // Base address in the system
        
        // Custom Typedefs for your AXI structs
        .axi_req_t      ( axi_req_t ),
        .axi_resp_t     ( axi_resp_t ),
        .axi_ar_t       ( axi_ar_chan_t ),
        .axi_r_t        ( axi_r_chan_t ),
        .axi_aw_t       ( axi_aw_chan_t ),
        .axi_w_t        ( axi_w_chan_t ),
        .axi_b_t        ( axi_b_chan_t )
    ) i_axi_dram_sim_v2 (
        .clk_i          ( clk ),
        .rst_ni         ( rst_n ),
        .axi_req_i      ( axi_req ),
        .axi_resp_o     ( axi_resp )
    );
```

**Key Improvements in V2 Interface**:
1. **Direct Struct Mapping**: Pass your AXI structs directly. The wrapper takes care of internal mapping.
2. **Combinational Handshakes**: AXI `valid`/`ready` signals are purely combinational in V2 based on internal FIFOs, eliminating artificial multi-cycle delays and preventing deadlocks.
3. **Data Integrity Testbench**: The `test/axi_to_dram_v2_tb.sv` testbench includes a built-in `testDataIntegrity` task using `axi_scoreboard` to cryptographically ensure random writes accurately read back from the DRAMSys engine.

## 🎉 License

All hardware sources and tool scripts are licensed under the Solderpad Hardware License 0.51 (see `LICENSE`). [DRAMSys5.0](https://github.com/tukl-msd/DRAMSys) is employed for DRAM simulations; please adhere to their [license](https://github.com/tukl-msd/DRAMSys) as well.
