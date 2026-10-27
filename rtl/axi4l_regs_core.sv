// AXI4-Lite slave with four 32-bit read/write registers.
//
// This is the flat-port version. axi4l_regs.sv wraps it in the SystemVerilog
// interface; the logic lives here so tools that can't handle interfaces
// (older Yosys, some vendor flows) can still use it.
//
// Behaviour you should know about before integrating:
//
//   * Reset is synchronous and active-low. Anything in flight is dropped:
//     no half-finished write gets committed and no stale response survives.
//   * One write and one read can be outstanding at the same time, but never
//     two of the same kind. READY stays low until the pending response has
//     been taken, so nothing in flight is ever overwritten.
//   * AW and W are captured independently, in any order and with any gap
//     between them. The write happens (and BVALID rises) the cycle after both
//     have been accepted.
//   * WSTRB is honoured per byte. A write with WSTRB == 0 completes with OKAY
//     and changes nothing.
//   * Addresses at or above 0x10, or not word-aligned, get SLVERR. Writes of
//     that kind touch no register; reads of that kind return zero.
//   * A read and a write to the same register in the same cycle: the read
//     sees the old value.

module axi4l_regs_core #(
    parameter int ADDR_W = 8,
    parameter int DATA_W = 32
) (
    input  logic                aclk,
    input  logic                aresetn,

    input  logic [ADDR_W-1:0]   awaddr,
    input  logic                awvalid,
    output logic                awready,

    input  logic [DATA_W-1:0]   wdata,
    input  logic [DATA_W/8-1:0] wstrb,
    input  logic                wvalid,
    output logic                wready,

    output logic [1:0]          bresp,
    output logic                bvalid,
    input  logic                bready,

    input  logic [ADDR_W-1:0]   araddr,
    input  logic                arvalid,
    output logic                arready,

    output logic [DATA_W-1:0]   rdata,
    output logic [1:0]          rresp,
    output logic                rvalid,
    input  logic                rready
);
    localparam int NREG   = 4;
    localparam int STRB_W = DATA_W / 8;

    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    // The register decode below is hard-wired to four word-sized registers.
    if (DATA_W != 32) begin : g_bad_data_w
        $error("axi4l_regs_core: DATA_W must be 32 (got %0d)", DATA_W);
    end
    if (ADDR_W < 4) begin : g_bad_addr_w
        $error("axi4l_regs_core: ADDR_W must be at least 4 to cover 16 bytes (got %0d)", ADDR_W);
    end

    logic [DATA_W-1:0] regs [NREG];

    // A valid register address is word-aligned and inside the 16-byte window.
    function automatic logic addr_ok(input logic [ADDR_W-1:0] a);
        addr_ok = (a[ADDR_W-1:4] == '0) && (a[1:0] == 2'b00);
    endfunction

    // ------------------------------------------------------------------
    // Write path
    // ------------------------------------------------------------------
    logic              aw_got, w_got;     // address / data held, waiting for the other
    logic [ADDR_W-1:0] aw_addr_q;
    logic [DATA_W-1:0] w_data_q;
    logic [STRB_W-1:0] w_strb_q;
    logic              bvalid_q;
    logic [1:0]        bresp_q;

    assign awready = !aw_got && !bvalid_q;
    assign wready  = !w_got  && !bvalid_q;
    assign bvalid  = bvalid_q;
    assign bresp   = bresp_q;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            for (int i = 0; i < NREG; i++) regs[i] <= '0;
            aw_got    <= 1'b0;
            w_got     <= 1'b0;
            aw_addr_q <= '0;
            w_data_q  <= '0;
            w_strb_q  <= '0;
            bvalid_q  <= 1'b0;
            bresp_q   <= RESP_OKAY;
        end else begin
            if (awvalid && awready) begin
                aw_addr_q <= awaddr;
                aw_got    <= 1'b1;
            end
            if (wvalid && wready) begin
                w_data_q <= wdata;
                w_strb_q <= wstrb;
                w_got    <= 1'b1;
            end

            if (aw_got && w_got && !bvalid_q) begin
                // Both halves are in: do the write and raise the response.
                aw_got   <= 1'b0;
                w_got    <= 1'b0;
                bvalid_q <= 1'b1;
                if (addr_ok(aw_addr_q)) begin
                    for (int b = 0; b < STRB_W; b++)
                        if (w_strb_q[b])
                            regs[aw_addr_q[3:2]][8*b +: 8] <= w_data_q[8*b +: 8];
                    bresp_q <= RESP_OKAY;
                end else begin
                    bresp_q <= RESP_SLVERR;
                end
            end else if (bvalid_q && bready) begin
                bvalid_q <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // Read path
    // ------------------------------------------------------------------
    logic              rvalid_q;
    logic [DATA_W-1:0] rdata_q;
    logic [1:0]        rresp_q;

    assign arready = !rvalid_q;
    assign rvalid  = rvalid_q;
    assign rdata   = rdata_q;
    assign rresp   = rresp_q;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            rvalid_q <= 1'b0;
            rdata_q  <= '0;
            rresp_q  <= RESP_OKAY;
        end else begin
            if (arvalid && arready) begin
                rvalid_q <= 1'b1;
                if (addr_ok(araddr)) begin
                    rdata_q <= regs[araddr[3:2]];
                    rresp_q <= RESP_OKAY;
                end else begin
                    rdata_q <= '0;
                    rresp_q <= RESP_SLVERR;
                end
            end else if (rvalid_q && rready) begin
                rvalid_q <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // Checks (simulation and formal only; compiled out for synthesis)
    // ------------------------------------------------------------------
`ifndef SYNTHESIS
    // A stalled response must hold still until the master takes it.
    a_b_stable: assert property (@(posedge aclk) disable iff (!aresetn)
        (bvalid && !bready) |=> (bvalid && $stable(bresp)));
    a_r_stable: assert property (@(posedge aclk) disable iff (!aresetn)
        (rvalid && !rready) |=> (rvalid && $stable(rdata) && $stable(rresp)));
`endif

`ifdef FORMAL
    // Helper state and invariants that let the unbounded proof close.
    // f_*_seen remember "this half of a transaction has been accepted and its
    // response not yet taken".
    reg f_aw_seen = 1'b0, f_w_seen = 1'b0, f_ar_seen = 1'b0;

    always @(posedge aclk) begin
        if (!aresetn) begin
            f_aw_seen <= 1'b0;
            f_w_seen  <= 1'b0;
            f_ar_seen <= 1'b0;
        end else begin
            if (awvalid && awready) f_aw_seen <= 1'b1;
            if (wvalid  && wready ) f_w_seen  <= 1'b1;
            if (arvalid && arready) f_ar_seen <= 1'b1;
            if (bvalid_q && bready) begin f_aw_seen <= 1'b0; f_w_seen <= 1'b0; end
            if (rvalid_q && rready) f_ar_seen <= 1'b0;
        end
    end

    always @* begin
        assert(!bresp_q[0]);                          // only OKAY or SLVERR
        assert(!rresp_q[0]);
        if (bvalid_q) assert(!aw_got && !w_got);      // response pending => inputs consumed
        if (aw_got)   assert(f_aw_seen);
        if (w_got)    assert(f_w_seen);
        if (bvalid_q) assert(f_aw_seen && f_w_seen);  // no B without both AW and W
        if (rvalid_q) assert(f_ar_seen);              // no R without an AR
        if (rresp_q[1]) assert(rdata_q == '0);        // a failed read never leaks register data
    end

    // Write-correctness check. These remember what the commit step saw last
    // cycle, so the registers can be compared against the write that happened.
    reg [DATA_W-1:0] f_regs_q [NREG];
    reg [DATA_W-1:0] f_wdata_q;
    reg [STRB_W-1:0] f_strb_q;
    reg [1:0]        f_idx_q;
    reg              f_commit_q = 1'b0, f_ok_q = 1'b0, f_rst_q = 1'b1;

    always @(posedge aclk) begin
        for (int i = 0; i < NREG; i++) f_regs_q[i] <= regs[i];
        f_rst_q    <= !aresetn;
        f_commit_q <= aresetn && aw_got && w_got && !bvalid_q;
        f_ok_q     <= addr_ok(aw_addr_q);
        f_idx_q    <= aw_addr_q[3:2];
        f_wdata_q  <= w_data_q;
        f_strb_q   <= w_strb_q;
    end

    always @* begin
        if (!f_rst_q) begin
            for (int i = 0; i < NREG; i++) begin
                for (int b = 0; b < STRB_W; b++) begin
                    if (f_commit_q && f_ok_q && f_idx_q == i && f_strb_q[b])
                        assert(regs[i][8*b +: 8] == f_wdata_q[8*b +: 8]);   // enabled lane written
                    else
                        assert(regs[i][8*b +: 8] == f_regs_q[i][8*b +: 8]); // everything else untouched
                end
            end
        end
    end
`endif
endmodule
