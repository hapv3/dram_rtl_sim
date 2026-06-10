// Copyright 2023 ETH Zurich and
// University of Bologna

// Solderpad Hardware License
// Version 0.51, see LICENSE for details.

// SPDX-License-Identifier: SHL-0.51

// Author: Chi Zhang <chizhang@iis.ee.ethz.ch>, ETH Zurich
// Modified: AXI4 Full Outstanding Transaction Support

// Full AXI4 Slave wrapper for DRAMSys co-simulation.
// Replaces the old sim_dram + axi_to_axi_lite + stream_arbiter pipeline
// to support outstanding transactions, out-of-order responses, and burst.

module sim_dram_v2 #(
    parameter int unsigned DataWidth      = 32'd512,
    parameter int unsigned AddrWidth      = 32'd64,
    parameter int unsigned IdWidth        = 32'd5,
    parameter int unsigned UserWidth      = 32'd1,
    parameter longint unsigned BASE       = 64'h80000000,
    parameter              DRAMType       = "DDR4",
    parameter              CustomerDRAM   = "none",
    parameter int unsigned MaxOutstanding = 16,
    // AXI interface types (parameterized from wrapper)
    parameter type         axi_req_t      = logic,
    parameter type         axi_resp_t     = logic
)(
    input  logic       clk_i,
    input  logic       rst_ni,
    input  axi_req_t   axi_req_i,
    output axi_resp_t  axi_resp_o
);

// DPI-C imports (v2 functions with AXI ID)
import "DPI-C" function int  add_dram(input string resources_path, input string simulationJson_path, input longint dram_base_addr);
import "DPI-C" function void dram_send_req_id(input int dram_id, input int axi_id, input longint addr, input longint length, input longint is_write, input longint strob_enable);
import "DPI-C" function int  dram_can_accept_ar(input int dram_id);
import "DPI-C" function int  dram_can_accept_aw(input int dram_id);
import "DPI-C" function void dram_write_buffer(input int dram_id, input int byte_int, input int idx);
import "DPI-C" function void dram_write_strobe(input int dram_id, input int strob_int, input int idx);
import "DPI-C" function int  dram_has_read_rsp_v2(input int dram_id);
import "DPI-C" function int  dram_read_rsp_id(input int dram_id);
import "DPI-C" function byte dram_peek_read_rsp_byte_v2(input int dram_id, input int byte_idx);
import "DPI-C" function void dram_pop_read_rsp_v2(input int dram_id, input int bytes_to_pop);
import "DPI-C" function void dram_pop_read_rsp(input int dram_id);
import "DPI-C" function int  dram_has_write_rsp(input int dram_id);
import "DPI-C" function int  dram_write_rsp_id(input int dram_id);
import "DPI-C" function void dram_pop_write_rsp(input int dram_id);
import "DPI-C" function int  dram_get_write_rsp(input int dram_id);
import "DPI-C" function void dram_load_elf(input string app_path);
import "DPI-C" function void dram_load_memfile(input int dram_id, input longint addr_ofst, input string mem_path);
import "DPI-C" function void dram_preload_byte(input int dram_id, input longint dram_addr_ofst, input int byte_int);
import "DPI-C" function int  dram_check_byte(input int dram_id, input longint dram_addr_ofst);
import "DPI-C" function void close_dram(input int dram_id);
// Bulk DPI-C (performance optimization) — packed bit vectors for Verilator compat
import "DPI-C" function void dram_write_buffer_bulk(input int dram_id, input bit [511:0] data, input bit [63:0] strb, input int offset, input int len);
import "DPI-C" function void dram_peek_read_rsp_bulk(input int dram_id, output bit [511:0] data, input int len);

localparam int unsigned BytesPerBeat = DataWidth / 8;
localparam int unsigned MaxIds       = 2**IdWidth;

// ====================================================================
// Initialization (identical to original sim_dram.sv)
// ====================================================================
int dram_id;

initial begin
    string resources_path;
    string simulationJson_path;
    string app_path;
    string mem_path;
    void'($value$plusargs("DRAMSYS_RES=%s", resources_path));
    case (DRAMType)
        "DDR4":   simulationJson_path = {resources_path, "/ddr4-example.json"} ;
        "DDR3":   simulationJson_path = {resources_path, "/ddr3-example.json"};
        "HBM2":   simulationJson_path = {resources_path, "/hbm2-example.json"};
        "LPDDR4": simulationJson_path = {resources_path, "/lpddr4-example.json"};
        default:  simulationJson_path = {resources_path, "/ddr4-example.json"};
    endcase

    if (CustomerDRAM != "none") begin
        simulationJson_path = {resources_path, "/", CustomerDRAM, ".json"};
        $display("[DRAMSys] Use Customer DRAM configuration: %s",simulationJson_path);
    end

    $display("[DRAMSys] resources_path=%s", resources_path);
    $display("[DRAMSys] simulationJson_path=%s", simulationJson_path);
    if (resources_path.len() == 0 || simulationJson_path.len() == 0) begin
        $fatal(1,"[DRAMSys] no DRAMsys configuration found!");
    end
    dram_id = add_dram(resources_path, simulationJson_path, BASE);
    void'($value$plusargs("ONE_DRAM_PRELOAD=%s", app_path));
    if (app_path.len() != 0) begin
        $display("[DRAMSys] Preloading elf: %s\n", app_path);
        dram_load_elf(app_path);
    end

    void'($value$plusargs("MEM=%s", mem_path));
    if (mem_path.len() != 0) begin
        $display("[DRAMSys] Preloading mem: %s\n", mem_path);
        dram_load_memfile(dram_id, 0, mem_path);
    end
end

// Manual DRAM access tasks (preserved from sim_dram.sv)
task load_a_byte_to_dram(input longint dram_addr_ofst, input int data_byte);
    dram_preload_byte(dram_id, dram_addr_ofst, data_byte);
endtask

task check_a_byte_in_dram(input longint dram_addr_ofst, output logic[7:0] data_byte);
    automatic int byte_int;
    byte_int = dram_check_byte(dram_id, dram_addr_ofst);
    data_byte = byte_int;
endtask

task preload_elf_binary(input string elf_binary);
    dram_load_elf(elf_binary);
endtask

// ====================================================================
// Outstanding Read Burst Tracking (for RLAST generation)
// ====================================================================

    // Tracking tables
    logic [MaxOutstanding-1:0] rd_track_valid;
    logic [IdWidth-1:0]        rd_track_id        [MaxOutstanding];
    logic [9:0]                rd_track_remaining [MaxOutstanding];

    logic [MaxOutstanding-1:0] wr_track_valid;
    logic [IdWidth-1:0]        wr_track_id        [MaxOutstanding];
    logic [9:0]                wr_track_remaining [MaxOutstanding];

    wire rd_track_full = &rd_track_valid;
    wire wr_track_full = &wr_track_valid;

// ====================================================================
// B Response FIFO (ring buffer)
// ====================================================================
localparam int unsigned BFifoDepth = MaxOutstanding;
logic [IdWidth-1:0]               b_fifo_data [BFifoDepth];
logic [$clog2(BFifoDepth):0]      b_fifo_wptr;
logic [$clog2(BFifoDepth):0]      b_fifo_rptr;
wire  b_fifo_empty = (b_fifo_wptr == b_fifo_rptr);
wire  b_fifo_full  = (b_fifo_wptr[$clog2(BFifoDepth)] != b_fifo_rptr[$clog2(BFifoDepth)]) &&
                     (b_fifo_wptr[$clog2(BFifoDepth)-1:0] == b_fifo_rptr[$clog2(BFifoDepth)-1:0]);

// ====================================================================
// Internal state
// ====================================================================

// AR channel state
logic                    ar_busy;
logic [IdWidth-1:0]      ar_id_q;
logic [AddrWidth-1:0]    ar_addr_q;
logic [7:0]              ar_len_q;
logic [2:0]              ar_size_q;
logic [7:0]              ar_beat_cnt;

// AW FIFO for outstanding write transactions
localparam int unsigned AwFifoDepth = MaxOutstanding;
logic [IdWidth-1:0]      aw_fifo_id   [AwFifoDepth];
logic [AddrWidth-1:0]    aw_fifo_addr [AwFifoDepth];
logic [7:0]              aw_fifo_len  [AwFifoDepth];
logic [2:0]              aw_fifo_size [AwFifoDepth];
logic [$clog2(AwFifoDepth):0] aw_fifo_wptr;
logic [$clog2(AwFifoDepth):0] aw_fifo_rptr;

wire aw_fifo_empty = (aw_fifo_wptr == aw_fifo_rptr);
wire aw_fifo_full  = (aw_fifo_wptr[$clog2(AwFifoDepth)] != aw_fifo_rptr[$clog2(AwFifoDepth)]) &&
                     (aw_fifo_wptr[$clog2(AwFifoDepth)-1:0] == aw_fifo_rptr[$clog2(AwFifoDepth)-1:0]);

// W channel state
logic [7:0]              aw_beat_cnt;

// R channel state
logic                    r_pending;
logic [DataWidth-1:0]    r_data_q;
logic [IdWidth-1:0]      r_id_q;
logic                    r_last_q;

logic                    r_pending_next;
logic [DataWidth-1:0]    r_data_next;
logic [IdWidth-1:0]      r_id_next;
logic                    r_last_next;

// ====================================================================
// Main Sequential Logic
// ====================================================================
always_ff @(posedge clk_i or negedge rst_ni) begin : proc_main
    if (~rst_ni) begin
        // Reset all state
        ar_busy       <= 1'b0;
        ar_beat_cnt   <= '0;
        aw_fifo_wptr  <= '0;
        aw_fifo_rptr  <= '0;
        // Handled by continuous assignment
        // Note: r channel is combinatorial, so no reset here
        aw_beat_cnt   <= '0;
        r_pending     <= 1'b0;
        r_data_q      <= '0;
        r_id_q        <= '0;
        r_last_q      <= 1'b0;
        b_fifo_wptr   <= '0;
        b_fifo_rptr   <= '0;

        for (int i = 0; i < MaxOutstanding; i++) begin
            rd_track_valid[i]     <= 1'b0;
            rd_track_remaining[i] <= '0;
            wr_track_valid[i]     <= 1'b0;
            wr_track_remaining[i] <= '0;
        end
    end else begin
        // Use blocking temporaries for correct same-cycle readback
        automatic logic                    ar_busy_next     = ar_busy;
        automatic logic [7:0]              ar_beat_cnt_next = ar_beat_cnt;
        automatic logic [$clog2(AwFifoDepth):0] aw_wptr_next = aw_fifo_wptr;
        automatic logic [$clog2(AwFifoDepth):0] aw_rptr_next = aw_fifo_rptr;
        automatic logic [7:0]              aw_beat_cnt_next = aw_beat_cnt;
        automatic logic                    r_pending_next   = r_pending;
        automatic logic [$clog2(BFifoDepth):0] b_wptr_next = b_fifo_wptr;
        automatic logic [$clog2(BFifoDepth):0] b_rptr_next = b_fifo_rptr;

        // ================================================
        // AR Channel: Accept burst, send one beat per cycle
        // ================================================


        // ================================================
        // AR Channel: Accept burst and send to DRAMSys
        // ================================================
        if (!ar_busy_next && !rd_track_full && axi_req_i.ar_valid) begin
            // Accept new AR burst
            ar_id_q        <= axi_req_i.ar.id;
            ar_addr_q      <= axi_req_i.ar.addr;
            ar_len_q       <= axi_req_i.ar.len;
            ar_size_q      <= axi_req_i.ar.size;
            ar_beat_cnt_next = '0;
            ar_busy_next     = 1'b1;
        end

        if (ar_busy) begin
            if (dram_can_accept_ar(dram_id)) begin
                // Send entire read burst via DPI-C
                automatic longint aligned_base = (longint'(ar_addr_q) >> $clog2(BytesPerBeat)) << $clog2(BytesPerBeat);
                dram_send_req_id(dram_id, int'(ar_id_q), aligned_base, longint'(BytesPerBeat) * longint'(ar_len_q + 1), 0, 0);
                ar_busy_next = 1'b0;

                // Allocate read tracking entry for the single response
                for (int i = 0; i < MaxOutstanding; i++) begin
                    if (!rd_track_valid[i]) begin
                        rd_track_valid[i]     <= 1'b1;
                        rd_track_id[i]        <= ar_id_q;
                        rd_track_remaining[i] <= {1'b0, ar_len_q} + 9'd1;
                        break;
                    end
                end
            end
        end

        ar_busy     <= ar_busy_next;
        ar_beat_cnt <= ar_beat_cnt_next;

        // AR ready: accept when not busy and tracking table not full
        // (Handled by continuous assignment below)

        // ================================================
        // AW + W Channel: Accept AW, then process W beats
        // ================================================
        if (!aw_fifo_full && !wr_track_full && axi_req_i.aw_valid) begin
            // Accept new AW burst
            aw_fifo_id  [aw_wptr_next[$clog2(AwFifoDepth)-1:0]] <= axi_req_i.aw.id;
            aw_fifo_addr[aw_wptr_next[$clog2(AwFifoDepth)-1:0]] <= axi_req_i.aw.addr;
            aw_fifo_len [aw_wptr_next[$clog2(AwFifoDepth)-1:0]] <= axi_req_i.aw.len;
            aw_fifo_size[aw_wptr_next[$clog2(AwFifoDepth)-1:0]] <= axi_req_i.aw.size;
            aw_wptr_next = aw_wptr_next + 1;

            // Allocate write tracking entry when AW is accepted
            for (int i = 0; i < MaxOutstanding; i++) begin
                if (!wr_track_valid[i]) begin
                    wr_track_valid[i]     <= 1'b1;
                    wr_track_id[i]        <= axi_req_i.aw.id;
                    wr_track_remaining[i] <= {1'b0, axi_req_i.aw.len} + 9'd1;
                    break;
                end
            end
        end

        // W channel: process one beat per cycle when AW FIFO is not empty
        // (Handled by continuous assignment below)

        if (!aw_fifo_empty && axi_req_i.w_valid && axi_resp_o.w_ready) begin
            automatic logic [IdWidth-1:0]   front_id   = aw_fifo_id  [aw_rptr_next[$clog2(AwFifoDepth)-1:0]];
            automatic logic [AddrWidth-1:0] front_addr = aw_fifo_addr[aw_rptr_next[$clog2(AwFifoDepth)-1:0]];
            automatic logic [7:0]           front_len  = aw_fifo_len [aw_rptr_next[$clog2(AwFifoDepth)-1:0]];

            // Fill write buffer via bulk DPI-C (1 call instead of 128)
            dram_write_buffer_bulk(dram_id, 512'(axi_req_i.w.data),
                                            64'(axi_req_i.w.strb),
                                            aw_beat_cnt * BytesPerBeat, BytesPerBeat);

            aw_beat_cnt_next = aw_beat_cnt_next + 8'd1;

            if (axi_req_i.w.last) begin
                // Send entire write burst via DPI-C
                automatic longint aligned_base = (longint'(front_addr) >> $clog2(BytesPerBeat)) << $clog2(BytesPerBeat);
                automatic int strob_en = (!(&axi_req_i.w.strb)) ? 1 : 0;
                dram_send_req_id(dram_id, int'(front_id), aligned_base, longint'(BytesPerBeat) * longint'(front_len + 1), 1, longint'(strob_en));

                aw_rptr_next = aw_rptr_next + 1; // Pop AW FIFO
                aw_beat_cnt_next = '0;
            end
        end

        aw_fifo_wptr <= aw_wptr_next;
        aw_fifo_rptr <= aw_rptr_next;
        aw_beat_cnt  <= aw_beat_cnt_next;

        // AW ready: accept when FIFO is not full and tracking table is not full
        // (Handled by continuous assignment below)

        // ================================================
        // R Channel: Poll C++ read responses, output beats
        // ================================================
        r_pending_next = r_pending;
        r_data_next    = r_data_q;
        r_id_next      = r_id_q;
        r_last_next    = r_last_q;

        if (r_pending && axi_req_i.r_ready) begin
            automatic int bytes_to_copy = BytesPerBeat;
            dram_pop_read_rsp_v2(dram_id, bytes_to_copy);
            r_pending_next = 1'b0;
        end

        // Try to load next response
        if (!r_pending_next) begin
            if (dram_has_read_rsp_v2(dram_id)) begin
                automatic int rsp_id_int = dram_read_rsp_id(dram_id);
                r_pending_next = 1'b1;

                r_id_next = rsp_id_int[IdWidth-1:0];

                // Bulk read response data (1 call instead of 64)
                begin
                    automatic bit [511:0] r_data_packed;
                    dram_peek_read_rsp_bulk(dram_id, r_data_packed, BytesPerBeat);
                    r_data_next = r_data_packed;
                end

                // RLAST tracking: decrement burst counter for this ID
                r_last_next = 1'b0;
                for (int i = 0; i < MaxOutstanding; i++) begin
                    if (rd_track_valid[i] && rd_track_id[i] == rsp_id_int[IdWidth-1:0]) begin
                        rd_track_remaining[i] <= rd_track_remaining[i] - 9'd1;
                        if (rd_track_remaining[i] == 9'd1) begin
                            r_last_next = 1'b1;
                            rd_track_valid[i] <= 1'b0;
                        end
                        break;
                    end
                end
            end
        end

        r_pending <= r_pending_next;
        r_data_q  <= r_data_next;
        r_id_q    <= r_id_next;
        r_last_q  <= r_last_next;



        // ================================================
        // B Channel: Aggregate write responses, output B
        // ================================================

        // Consume C++ write responses and count toward burst completion
        if (dram_has_write_rsp(dram_id)) begin
            automatic int wr_id_int = dram_write_rsp_id(dram_id);
            dram_pop_write_rsp(dram_id);

            // Find matching write tracking entry
            for (int i = 0; i < MaxOutstanding; i++) begin
                if (wr_track_valid[i] && wr_track_id[i] == wr_id_int[IdWidth-1:0]) begin
                    // Entire burst acknowledged by single response → push B response
                    wr_track_valid[i] <= 1'b0;
                    b_fifo_data[b_wptr_next[$clog2(BFifoDepth)-1:0]] <= wr_id_int[IdWidth-1:0];
                    b_wptr_next = b_wptr_next + 1;
                    break;
                end
            end
        end

        // B channel output from FIFO
        if (!b_fifo_empty && axi_req_i.b_ready) begin
            b_rptr_next = b_rptr_next + 1;
        end

        // axi_resp_o.b handled by continuous assignment

        b_fifo_wptr <= b_wptr_next;
        b_fifo_rptr <= b_rptr_next;
    end
end

// ====================================================================
// Combinational AXI Responses
// ====================================================================

always_comb begin
    axi_resp_o.aw_ready = !aw_fifo_full && !wr_track_full;
    axi_resp_o.w_ready  = !aw_fifo_empty && dram_can_accept_aw(dram_id);
    axi_resp_o.b_valid  = !b_fifo_empty;
    axi_resp_o.b.id     = b_fifo_data[b_fifo_rptr[$clog2(BFifoDepth)-1:0]];
    axi_resp_o.b.resp   = '0;
    axi_resp_o.b.user   = '0;
    axi_resp_o.ar_ready = !ar_busy && !rd_track_full;
end

// ====================================================================
// Cleanup
// ====================================================================
final begin
    close_dram(dram_id);
end

assign axi_resp_o.r_valid = r_pending;
assign axi_resp_o.r.data  = r_data_q;
assign axi_resp_o.r.id    = r_id_q;
assign axi_resp_o.r.last  = r_last_q;
assign axi_resp_o.r.resp  = '0;
assign axi_resp_o.r.user  = '0;

endmodule : sim_dram_v2
