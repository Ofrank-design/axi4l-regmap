// Formal harness for axi4l_regs_core (own properties).
//
// Every input is free (anyseq) except that the master has to follow the AXI
// rule "once VALID is up, hold it and the payload until READY". The slave's
// internal invariants live in the core under `ifdef FORMAL.
//
// Checked here, at the pins:
//   * a stalled B or R response keeps VALID and its payload;
//   * reset clears both responses on the next cycle;
//   * responses are only ever OKAY or SLVERR;
//   * READY is low on the channels that would overwrite a pending response.

module formal_axi4l (input aclk);
    localparam AW = 8, DW = 32;

    (* anyseq *) wire aresetn;
    (* anyseq *) wire [AW-1:0] awaddr;  (* anyseq *) wire awvalid;
    (* anyseq *) wire [DW-1:0] wdata;   (* anyseq *) wire [3:0] wstrb;  (* anyseq *) wire wvalid;
    (* anyseq *) wire bready;
    (* anyseq *) wire [AW-1:0] araddr;  (* anyseq *) wire arvalid;
    (* anyseq *) wire rready;

    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0]    bresp, rresp;
    wire [DW-1:0] rdata;

    axi4l_regs_core #(.ADDR_W(AW), .DATA_W(DW)) dut (.*);

    // One-cycle-old copies of the bus, so properties can talk about "last cycle".
    reg init   = 1'b1;
    reg p_rstn = 1'b0;
    reg p_awv, p_awr, p_wv, p_wr, p_arv, p_arr, p_bv, p_br, p_rv, p_rr;
    reg [AW-1:0] p_awaddr, p_araddr;
    reg [DW-1:0] p_wdata, p_rdata;
    reg [3:0]    p_wstrb;
    reg [1:0]    p_bresp, p_rresp;

    always @(posedge aclk) begin
        init   <= 1'b0;
        p_rstn <= aresetn;
        p_awv <= awvalid; p_awr <= awready; p_wv <= wvalid; p_wr <= wready;
        p_arv <= arvalid; p_arr <= arready; p_bv <= bvalid; p_br <= bready;
        p_rv  <= rvalid;  p_rr  <= rready;
        p_awaddr <= awaddr; p_araddr <= araddr;
        p_wdata <= wdata;   p_wstrb <= wstrb;
        p_rdata <= rdata;   p_bresp <= bresp;  p_rresp <= rresp;
    end

    always @* begin
        if (init) assume(!aresetn);

        // Master obligations.
        if (!init && p_rstn) begin
            if (p_awv && !p_awr) begin assume(awvalid); assume(awaddr == p_awaddr); end
            if (p_wv  && !p_wr ) begin assume(wvalid);  assume(wdata == p_wdata); assume(wstrb == p_wstrb); end
            if (p_arv && !p_arr) begin assume(arvalid); assume(araddr == p_araddr); end
        end

        // Slave obligations.
        if (!init && p_rstn) begin
            if (p_bv && !p_br) begin assert(bvalid); assert(bresp == p_bresp); end
            if (p_rv && !p_rr) begin assert(rvalid); assert(rdata == p_rdata); assert(rresp == p_rresp); end
        end
        if (!init && !p_rstn) begin
            assert(!bvalid);
            assert(!rvalid);
        end
        if (!init) begin
            if (bvalid) begin assert(!awready); assert(!wready); assert(bresp == 2'b00 || bresp == 2'b10); end
            if (rvalid) begin assert(!arready); assert(rresp == 2'b00 || rresp == 2'b10); end
        end
    end
endmodule
