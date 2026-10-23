// Interface-flavoured front end for axi4l_regs_core.
//
// Use this one when your project already passes AXI around as an axi4l_if.
// It only forwards signals; all behaviour is documented in the core.

module axi4l_regs #(
    parameter int ADDR_W = 8,
    parameter int DATA_W = 32
) (
    axi4l_if.slave s
);
    axi4l_regs_core #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_core (
        .aclk    (s.aclk),
        .aresetn (s.aresetn),
        .awaddr  (s.awaddr),  .awvalid (s.awvalid), .awready (s.awready),
        .wdata   (s.wdata),   .wstrb   (s.wstrb),   .wvalid  (s.wvalid),  .wready (s.wready),
        .bresp   (s.bresp),   .bvalid  (s.bvalid),  .bready  (s.bready),
        .araddr  (s.araddr),  .arvalid (s.arvalid), .arready (s.arready),
        .rdata   (s.rdata),   .rresp   (s.rresp),   .rvalid  (s.rvalid),  .rready (s.rready)
    );
endmodule
