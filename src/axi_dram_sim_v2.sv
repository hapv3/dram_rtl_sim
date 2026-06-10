// Copyright 2023 ETH Zurich and
// University of Bologna

// Solderpad Hardware License
// Version 0.51, see LICENSE for details.

// SPDX-License-Identifier: SHL-0.51

// Author: Chi Zhang <chizhang@iis.ee.ethz.ch>, ETH Zurich
// Date: 07.June.2023

// An axi wrapped dram model

`include "axi/assign.svh"
`include "axi/typedef.svh"

module axi_dram_sim_v2 #(
    // AXI Parameter
    parameter int unsigned AxiAddrWidth     = 32,
    parameter int unsigned AxiDataWidth     = 256,
    parameter int unsigned AxiIdWidth       = 5,
    parameter int unsigned AxiUserWidth     = 1,
    //DRAM Base Addr
    parameter longint unsigned BASE         = 64'h80000000,
    //DRAM type
    parameter              DRAMType         = "DDR4",
    parameter              CustomerDRAM     = "none",
    // AXI interface
    parameter type         axi_req_t        = logic,
    parameter type         axi_resp_t       = logic,
    parameter type         axi_ar_t         = logic,
    parameter type         axi_r_t          = logic,
    parameter type         axi_aw_t         = logic,
    parameter type         axi_w_t          = logic,
    parameter type         axi_b_t          = logic
    )(
    /// Clock, positive edge triggered.
    input   logic                           clk_i,
    /// Reset, active low.
    input   logic                           rst_ni,
    /// Axi
    input   axi_req_t                       axi_req_i,
    output  axi_resp_t                      axi_resp_o
 );

    //define port to DRAM (512-bit internal bus)
    localparam int unsigned DramAddrWidth   = AxiAddrWidth;
    localparam int unsigned DramDataWidth   = 512;
    localparam int unsigned DramIdWidth     = AxiIdWidth;
    localparam int unsigned DramUserWidth   = AxiUserWidth;
    typedef logic [DramAddrWidth-1:0]       addr_t;
    typedef logic [DramDataWidth-1:0]       data_t;
    typedef logic [DramDataWidth/8-1:0]     strb_t;
    typedef logic [DramIdWidth-1:0]         id_t;
    typedef logic [DramUserWidth-1:0]       user_t;
    `AXI_TYPEDEF_ALL(dram_axi, addr_t, id_t, data_t, strb_t, user_t)

    dram_axi_req_t                          dram_axi_req;
    dram_axi_resp_t                         dram_axi_resp;


    axi_dw_converter #(
        .AxiMaxReads        (64),
        .AxiSlvPortDataWidth(AxiDataWidth),
        .AxiMstPortDataWidth(DramDataWidth),
        .AxiAddrWidth       (AxiAddrWidth),
        .AxiIdWidth         (AxiIdWidth),
        .aw_chan_t          (axi_aw_t),
        .mst_w_chan_t       (dram_axi_w_chan_t),
        .slv_w_chan_t       (axi_w_t),
        .b_chan_t           (axi_b_t),
        .ar_chan_t          (axi_ar_t),
        .mst_r_chan_t       (dram_axi_r_chan_t),
        .slv_r_chan_t       (axi_r_t),
        .axi_mst_req_t      (dram_axi_req_t),
        .axi_mst_resp_t     (dram_axi_resp_t),
        .axi_slv_req_t      (axi_req_t),
        .axi_slv_resp_t     (axi_resp_t)
    ) i_axi_dw_converter (
        .clk_i,
        .rst_ni,
        .slv_req_i (axi_req_i ),
        .slv_resp_o(axi_resp_o),
        .mst_req_o (dram_axi_req ),
        .mst_resp_i(dram_axi_resp)
    );


    //====================================================//
    // Full AXI4 Slave → DRAMSys (via DPI-C)             //
    // Replaces: axi_to_axi_lite + stream_arbiter + sim_dram
    //====================================================//

    sim_dram_v2 #(
        .DataWidth     (DramDataWidth),
        .AddrWidth     (DramAddrWidth),
        .IdWidth       (DramIdWidth),
        .UserWidth     (DramUserWidth),
        .BASE          (BASE),
        .DRAMType      (DRAMType),
        .CustomerDRAM  (CustomerDRAM),
        .MaxOutstanding(16),
        .axi_req_t     (dram_axi_req_t),
        .axi_resp_t    (dram_axi_resp_t)
    ) i_sim_dram_v2 (
        .clk_i,
        .rst_ni,
        .axi_req_i (dram_axi_req),
        .axi_resp_o(dram_axi_resp)
    );



endmodule : axi_dram_sim_v2
