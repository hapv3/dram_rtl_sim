// Copyright 2023 ETH Zurich and
// University of Bologna

// Solderpad Hardware License
// Version 0.51, see LICENSE for details.

// SPDX-License-Identifier: SHL-0.51

// Author: Chi Zhang <chizhang@iis.ee.ethz.ch>, ETH Zurich
// Date: 07.June.2023

// Testbench for dram rtl simulator
`timescale 1ns/1ps

module axi_to_dram_v2_tb;

    `include "axi/assign.svh"
    `include "axi/typedef.svh"

    //////////////////////
    //  AXI Parameters  //
    //////////////////////

    localparam int unsigned                 AXI_ADDR_WIDTH              = 32;
    localparam int unsigned                 AXI_DATA_WIDTH              = 512;
    localparam int unsigned                 AXI_STRB_WIDTH              = AXI_DATA_WIDTH / 8;
    localparam int unsigned                 AXI_ID_WIDTH                = 5;
    localparam int unsigned                 AXI_USER_WIDTH              = 5;
    localparam int unsigned                 BASE                        = 32'h8000_0000;

    typedef logic [AXI_ADDR_WIDTH-1:0]      axi_addr_t;
    typedef logic [AXI_DATA_WIDTH-1:0]      axi_data_t;
    typedef logic [AXI_STRB_WIDTH-1:0]      axi_strb_t;
    typedef logic [AXI_ID_WIDTH-1:0]        axi_id_t;
    typedef logic [AXI_USER_WIDTH-1:0]      axi_user_t;

    `AXI_TYPEDEF_ALL(axi, axi_addr_t, axi_id_t, axi_data_t, axi_strb_t, axi_user_t)

    typedef logic [7:0] my_byte_t;

    //////////////////////////////////////
    //        Signal Definition         //
    //////////////////////////////////////

    localparam time ClkPeriod = 4ns;
    localparam time ApplTime =  1ns;
    localparam time TestTime =  3ns;

    logic  clk, rst_n;

    axi_req_t                   axi_req;
    axi_resp_t                  axi_resp;

    AXI_BUS_DV #(
        .AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH ),
        .AXI_DATA_WIDTH ( AXI_DATA_WIDTH ),
        .AXI_ID_WIDTH   ( AXI_ID_WIDTH  ),
        .AXI_USER_WIDTH ( AXI_USER_WIDTH )
    ) axi_bus_dv(clk);

    `AXI_ASSIGN_TO_REQ(axi_req,axi_bus_dv)
    `AXI_ASSIGN_FROM_RESP(axi_bus_dv, axi_resp)


    //////////////////////////////////////
    //        Clock Generation          //
    //////////////////////////////////////
    initial begin
        rst_n = 0;
        $display("start");
        repeat (3) begin
            #(ClkPeriod/2) clk = 0;
            #(ClkPeriod/2) clk = 1;
        end
        rst_n = 1;
        $display("rst up");
        forever begin
            #(ClkPeriod/2) clk = 0;
            #(ClkPeriod/2) clk = 1;
        end
    end

    //////////////////////
    //        DUT       //
    //////////////////////

    dram_sim_engine #(.ClkPeriod(ClkPeriod)) i_dram_sim_engine (.clk_i(clk), .rst_ni(rst_n));

    axi_dram_sim_v2 #(
        .AxiAddrWidth(AXI_ADDR_WIDTH),
        .AxiDataWidth(AXI_DATA_WIDTH),
        .AxiIdWidth  (AXI_ID_WIDTH),
        .AxiUserWidth(AXI_USER_WIDTH),
        .DRAMType    ("DDR4"),
        // .CustomerDRAM("ddr3-example2"),
        .BASE        (BASE),
        .axi_req_t   (axi_req_t),
        .axi_resp_t  (axi_resp_t),
        .axi_ar_t    (axi_ar_chan_t),
        .axi_r_t     (axi_r_chan_t),
        .axi_aw_t    (axi_aw_chan_t),
        .axi_w_t     (axi_w_chan_t),
        .axi_b_t     (axi_b_chan_t)
    ) i_axi_dram_sim_v2 (
        .clk_i     (clk     ),
        .rst_ni    (rst_n    ),
        .axi_req_i (axi_req ),
        .axi_resp_o(axi_resp)
    );

    //////////////////////////
    //        Driver        //
    //////////////////////////

    typedef axi_test::axi_rand_master #(
        // AXI interface parameters
        .AW ( AXI_ADDR_WIDTH ),
        .DW ( AXI_DATA_WIDTH ),
        .IW ( AXI_ID_WIDTH ),
        .UW ( AXI_USER_WIDTH ),
        .MAX_READ_TXNS(16),
        .MAX_WRITE_TXNS(16),
        .AX_MAX_WAIT_CYCLES(20),
        .AXI_BURST_FIXED(0),
        // Stimuli application and test time
        .TA ( ApplTime ),
        .TT ( TestTime )
    ) axi_master_t;

    typedef axi_test::axi_scoreboard #(
        // AXI interface parameters
        .AW ( AXI_ADDR_WIDTH ),
        .DW ( AXI_DATA_WIDTH ),
        .IW ( AXI_ID_WIDTH ),
        .UW ( AXI_USER_WIDTH ),
        // Stimuli application and test time
        .TT ( TestTime )
    ) axi_scoreboard_master_t;


    axi_master_t axi_master = new(axi_bus_dv);
    axi_scoreboard_master_t axi_scoreboard_master = new(axi_bus_dv);

    //Speed test
    task speedTestRead(int count);
        real time_start;
        real time_end;
        real bandwidth;
        automatic axi_master_t::ax_beat_t ar = new ;
        automatic axi_master_t::r_beat_t r = new ;

        ar = axi_master.new_rand_burst(0,0);
        ar.ax_len = 15;
        ar.ax_size = $clog2(AXI_DATA_WIDTH/8);
        ar.ax_atop = axi_pkg::ATOP_NONE;
        ar.ax_addr = (ar.ax_addr>>$clog2(AXI_DATA_WIDTH/8))<<$clog2(AXI_DATA_WIDTH/8);

        $display("----------Testing DRAM Bulk Read Speed ---------");
        time_start = $time();

        fork
            //send ar
            begin
                for (int i = 0; i < count; i++) begin
                    ar.ax_addr = ar.ax_addr + (64*(ar.ax_len+1));
                    axi_master.drv.send_ar(ar);
                end
            end
            //receive r
            begin
                for (int i = 0; i < count; i++) begin
                    for (int j = 0; j <= ar.ax_len; j++) begin
                        axi_master.drv.recv_r(r);
                    end
                end
            end
        join

        time_end = $time();
        bandwidth = (64*(ar.ax_len+1)*count) / (time_end - time_start);

        $display("speedTestRead done!: Bandwidth = %0f GB/s", bandwidth);
    endtask

    task speedTestWrite(int count);
        real time_start;
        real time_end;
        real bandwidth;
        automatic axi_master_t::ax_beat_t aw = new ;
        automatic axi_master_t::w_beat_t w = new ;
        automatic axi_master_t::b_beat_t b = new ;

        aw = axi_master.new_rand_burst(0,0);
        aw.ax_len = 15;
        aw.ax_size = $clog2(AXI_DATA_WIDTH/8);
        aw.ax_atop = axi_pkg::ATOP_NONE;
        aw.ax_addr = (aw.ax_addr>>$clog2(AXI_DATA_WIDTH/8))<<$clog2(AXI_DATA_WIDTH/8);

        $display("----------Testing DRAM Bulk Write Speed ---------");
        time_start = $time();

        fork
            //send aw
            begin
                for (int i = 0; i < count; i++) begin
                    aw.ax_addr = aw.ax_addr + (64*(aw.ax_len+1));
                    axi_master.drv.send_aw(aw);
                end
            end

            //send w
            begin
                for (int i = 0; i < count; i++) begin
                    for (int j = 0; j <= aw.ax_len; j++) begin
                        //w.randomize();
                        for(int k=0; k<512/32; k++) w.w_data[k*32 +: 32] = $urandom;
                        w.w_strb = {64{1'b1}};
                        w.w_last = 0;
                        if (j == aw.ax_len) begin
                            w.w_last = 1;
                        end
                        axi_master.drv.send_w(w);
                    end
                end
            end

            //receive b
            begin
                for (int i = 0; i < count; i++) begin
                    axi_master.drv.recv_b(b);
                end
            end
        join

        time_end = $time();
        bandwidth = (64*(aw.ax_len+1)*count) / (time_end - time_start);

        $display("speedTestWrite done!: Bandwidth = %0f GB/s", bandwidth);
    endtask

    // Test outstanding reads: send short bursts to different DRAM rows
    // This demonstrates V2's pipelining advantage: multiple AR requests
    // can be in-flight simultaneously, hiding DRAM row activation latency.
    task speedTestReadRandomRows(int count, int burst_len);
        real time_start;
        real time_end;
        real bandwidth;
        real total_bytes;
        automatic axi_master_t::ax_beat_t ar = new ;
        automatic axi_master_t::r_beat_t r = new ;

        ar = axi_master.new_rand_burst(0,0);
        ar.ax_len = burst_len;
        ar.ax_size = $clog2(AXI_DATA_WIDTH/8);
        ar.ax_atop = axi_pkg::ATOP_NONE;
        // Start from BASE-aligned address
        ar.ax_addr = BASE;

        total_bytes = real'(64) * real'(burst_len + 1) * real'(count);

        $display("---------- Outstanding Read Test: %0d bursts x %0d beats, spread rows ---------", count, burst_len+1);
        time_start = $time();

        fork
            //send ar — all bursts pipelined, addresses 8KB apart (different rows)
            begin
                for (int i = 0; i < count; i++) begin
                    ar.ax_addr = BASE + (i * 32'h2000); // 8KB stride → different DRAM rows
                    ar.ax_addr = (ar.ax_addr >> $clog2(AXI_DATA_WIDTH/8)) << $clog2(AXI_DATA_WIDTH/8);
                    axi_master.drv.send_ar(ar);
                end
            end
            //receive r
            begin
                for (int i = 0; i < count; i++) begin
                    for (int j = 0; j <= burst_len; j++) begin
                        axi_master.drv.recv_r(r);
                    end
                end
            end
        join

        time_end = $time();
        bandwidth = total_bytes / (time_end - time_start);

        $display("Outstanding Read done!: %0d bursts, BW = %0f GB/s, Time = %0f ns",
                 count, bandwidth, time_end - time_start);
    endtask

    // Data Integrity Test: Write to specific addresses, then read back
    // The axi_scoreboard will automatically verify that read data matches written data.
    task testDataIntegrity(int count, int burst_len);
        automatic axi_master_t::ax_beat_t aw = new;
        automatic axi_master_t::w_beat_t w = new;
        automatic axi_master_t::b_beat_t b = new;
        automatic axi_master_t::ax_beat_t ar = new;
        automatic axi_master_t::r_beat_t r = new;

        $display("---------- Data Integrity Test: %0d bursts x %0d beats ---------", count, burst_len+1);

        // 1. Write Data
        aw = axi_master.new_rand_burst(0,0);
        aw.ax_len = burst_len;
        aw.ax_size = $clog2(AXI_DATA_WIDTH/8);
        aw.ax_atop = axi_pkg::ATOP_NONE;

        fork
            begin
                for (int i = 0; i < count; i++) begin
                    aw.ax_addr = BASE + (i * 64 * (burst_len + 1));
                    axi_master.drv.send_aw(aw);
                end
            end
            begin
                for (int i = 0; i < count; i++) begin
                    for (int j = 0; j <= burst_len; j++) begin
                        for(int k=0; k<512/32; k++) w.w_data[k*32 +: 32] = $urandom;
                        w.w_strb = {64{1'b1}};
                        w.w_last = (j == burst_len) ? 1 : 0;
                        axi_master.drv.send_w(w);
                    end
                end
            end
            begin
                for (int i = 0; i < count; i++) begin
                    axi_master.drv.recv_b(b);
                end
            end
        join

        // 2. Read Data Back
        ar = axi_master.new_rand_burst(0,0);
        ar.ax_len = burst_len;
        ar.ax_size = $clog2(AXI_DATA_WIDTH/8);
        ar.ax_atop = axi_pkg::ATOP_NONE;

        fork
            begin
                for (int i = 0; i < count; i++) begin
                    ar.ax_addr = BASE + (i * 64 * (burst_len + 1));
                    axi_master.drv.send_ar(ar);
                end
            end
            begin
                for (int i = 0; i < count; i++) begin
                    for (int j = 0; j <= burst_len; j++) begin
                        axi_master.drv.recv_r(r);
                    end
                end
            end
        join

        $display("Data Integrity Test done!: Scoreboard verified all read data successfully.");
    endtask

    initial begin
        axi_master.reset();
        axi_scoreboard_master.enable_all_checks();
        axi_scoreboard_master.monitor();
        axi_master.add_memory_region(BASE + 0, BASE + 32'h0010_0000, axi_pkg::NORMAL_NONCACHEABLE_NONBUFFERABLE);
        @(posedge rst_n);

        // Data integrity check (writes and reads same addresses)
        testDataIntegrity(50, 15); // 50 bursts of 16 beats

        // Sequential bandwidth test
        speedTestWrite(1000);
        speedTestRead(1000);

        // Outstanding advantage test: short bursts to different rows
        speedTestReadRandomRows(10, 3);  // 10 bursts x 4 beats, spread rows

        $display("----------     ALL TESTS PASSED !!!        ---------");
        $finish;
    end






endmodule : axi_to_dram_v2_tb
