// Hooks the slave up to ZipCPU's independent AXI4-Lite property checker
// (faxil_slave, from wb2axip; see scripts/fetch_deps.sh). The checker brings
// its own idea of what a legal slave looks like, so it is a second opinion
// that does not share assumptions with our own harness.

module ext_check (input aclk);
    localparam AW = 8, DW = 32;

    (* anyseq *) wire aresetn;
    (* anyseq *) wire [AW-1:0] awaddr;  (* anyseq *) wire awvalid;
    (* anyseq *) wire [DW-1:0] wdata;   (* anyseq *) wire [3:0] wstrb;  (* anyseq *) wire wvalid;
    (* anyseq *) wire bready;
    (* anyseq *) wire [AW-1:0] araddr;  (* anyseq *) wire arvalid;
    (* anyseq *) wire rready;
    (* anyseq *) wire [2:0] awprot, arprot;   // the core ignores PROT; the checker wants it

    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0]    bresp, rresp;
    wire [DW-1:0] rdata;

    axi4l_regs_core #(.ADDR_W(AW), .DATA_W(DW)) dut (.*);

    wire [3:0] f_rd, f_wr, f_awr;
    faxil_slave #(
        .C_AXI_DATA_WIDTH(DW), .C_AXI_ADDR_WIDTH(AW),
        .F_OPT_ASSUME_RESET(1'b1),
        .F_AXI_MAXWAIT(0), .F_AXI_MAXDELAY(0), .F_AXI_MAXRSTALL(0)
    ) chk (
        .i_clk(aclk), .i_axi_reset_n(aresetn),
        .i_axi_awvalid(awvalid), .i_axi_awready(awready), .i_axi_awaddr(awaddr), .i_axi_awprot(awprot),
        .i_axi_wvalid (wvalid),  .i_axi_wready (wready),  .i_axi_wdata (wdata),  .i_axi_wstrb(wstrb),
        .i_axi_bvalid (bvalid),  .i_axi_bready (bready),  .i_axi_bresp (bresp),
        .i_axi_arvalid(arvalid), .i_axi_arready(arready), .i_axi_araddr(araddr), .i_axi_arprot(arprot),
        .i_axi_rvalid (rvalid),  .i_axi_rready (rready),  .i_axi_rdata (rdata),  .i_axi_rresp(rresp),
        .f_axi_rd_outstanding(f_rd), .f_axi_wr_outstanding(f_wr), .f_axi_awr_outstanding(f_awr)
    );
endmodule
