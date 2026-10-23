`timescale 1ns/1ps

// Integration test: two axi4l_regs_core instances behind a third-party AXI4-Lite
// crossbar (ZipCPU's axilxbar, fetched by scripts/fetch_deps.sh).
//
//   master (this bench) --> axilxbar --+--> regs A  at 0x00..0x7F
//                                      +--> regs B  at 0x80..0xFF
//
// The crossbar passes full addresses through, so slave B gets its address with
// bit 7 stripped. That is the usual job of the bus fabric's address window.
// What this proves: a stock interconnect can drive the slave, routing by base
// address works, and the SLVERR / byte-strobe behaviour survives the crossbar.

module tb_axi4l_xbar;
    localparam int AW = 8;
    localparam int DW = 32;
    localparam int NS = 2;

    logic clk = 1'b0, rstn = 1'b0;
    always #5 clk = ~clk;

    // Master side (this bench)
    logic          m_awvalid = 0, m_wvalid = 0, m_bready = 0, m_arvalid = 0, m_rready = 0;
    logic [AW-1:0] m_awaddr = 0, m_araddr = 0;
    logic [DW-1:0] m_wdata = 0;
    logic [3:0]    m_wstrb = 0;
    wire           m_awready, m_wready, m_bvalid, m_arready, m_rvalid;
    wire  [1:0]    m_bresp, m_rresp;
    wire  [DW-1:0] m_rdata;

    // Crossbar slave-side outputs (towards the two register blocks)
    wire [NS*AW-1:0]   x_awaddr, x_araddr;
    wire [NS-1:0]      x_awvalid, x_awready, x_wvalid, x_wready, x_bvalid, x_bready;
    wire [NS-1:0]      x_arvalid, x_arready, x_rvalid, x_rready;
    wire [NS*DW-1:0]   x_wdata, x_rdata;
    wire [NS*DW/8-1:0] x_wstrb;
    wire [NS*2-1:0]    x_bresp, x_rresp;
    wire [NS*3-1:0]    x_awprot, x_arprot;

    axilxbar #(
        .C_AXI_DATA_WIDTH(DW), .C_AXI_ADDR_WIDTH(AW), .NM(1), .NS(NS),
        .SLAVE_ADDR({8'h80, 8'h00}),
        .SLAVE_MASK({8'h80, 8'h80})
    ) xbar (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(rstn),
        .S_AXI_AWVALID(m_awvalid), .S_AXI_AWREADY(m_awready), .S_AXI_AWADDR(m_awaddr), .S_AXI_AWPROT(3'b0),
        .S_AXI_WVALID (m_wvalid),  .S_AXI_WREADY (m_wready),  .S_AXI_WDATA (m_wdata),  .S_AXI_WSTRB(m_wstrb),
        .S_AXI_BVALID (m_bvalid),  .S_AXI_BREADY (m_bready),  .S_AXI_BRESP (m_bresp),
        .S_AXI_ARVALID(m_arvalid), .S_AXI_ARREADY(m_arready), .S_AXI_ARADDR(m_araddr), .S_AXI_ARPROT(3'b0),
        .S_AXI_RVALID (m_rvalid),  .S_AXI_RREADY (m_rready),  .S_AXI_RDATA (m_rdata),  .S_AXI_RRESP(m_rresp),
        .M_AXI_AWVALID(x_awvalid), .M_AXI_AWREADY(x_awready), .M_AXI_AWADDR(x_awaddr), .M_AXI_AWPROT(x_awprot),
        .M_AXI_WVALID (x_wvalid),  .M_AXI_WREADY (x_wready),  .M_AXI_WDATA (x_wdata),  .M_AXI_WSTRB(x_wstrb),
        .M_AXI_BVALID (x_bvalid),  .M_AXI_BREADY (x_bready),  .M_AXI_BRESP (x_bresp),
        .M_AXI_ARVALID(x_arvalid), .M_AXI_ARREADY(x_arready), .M_AXI_ARADDR(x_araddr), .M_AXI_ARPROT(x_arprot),
        .M_AXI_RVALID (x_rvalid),  .M_AXI_RREADY (x_rready),  .M_AXI_RDATA (x_rdata),  .M_AXI_RRESP(x_rresp)
    );

    for (genvar n = 0; n < NS; n++) begin : g_regs
        // Strip the window-select bit so the block sees offsets 0x00..0x7F.
        wire [AW-1:0] awaddr_local = {1'b0, x_awaddr[n*AW +: AW-1]};
        wire [AW-1:0] araddr_local = {1'b0, x_araddr[n*AW +: AW-1]};

        axi4l_regs_core #(.ADDR_W(AW), .DATA_W(DW)) u_regs (
            .aclk(clk), .aresetn(rstn),
            .awaddr(awaddr_local), .awvalid(x_awvalid[n]), .awready(x_awready[n]),
            .wdata(x_wdata[n*DW +: DW]), .wstrb(x_wstrb[n*DW/8 +: DW/8]),
            .wvalid(x_wvalid[n]), .wready(x_wready[n]),
            .bresp(x_bresp[n*2 +: 2]), .bvalid(x_bvalid[n]), .bready(x_bready[n]),
            .araddr(araddr_local), .arvalid(x_arvalid[n]), .arready(x_arready[n]),
            .rdata(x_rdata[n*DW +: DW]), .rresp(x_rresp[n*2 +: 2]),
            .rvalid(x_rvalid[n]), .rready(x_rready[n])
        );
    end

    int errors = 0;

    task automatic check(input bit ok, input string what);
        if (!ok) begin errors++; $display("[FAIL] %0t %s", $time, what); end
    endtask

    // Same drive-after-edge / sample-at-edge convention as the unit bench.
    task automatic write(input logic [AW-1:0] a, input logic [DW-1:0] d,
                         input logic [3:0] s, output logic [1:0] resp);
        #1 m_awaddr = a; m_awvalid = 1; m_wdata = d; m_wstrb = s; m_wvalid = 1;
        fork
            begin do @(posedge clk); while (!m_awready); #1 m_awvalid = 0; end
            begin do @(posedge clk); while (!m_wready);  #1 m_wvalid  = 0; end
        join
        #1 m_bready = 1;
        do @(posedge clk); while (!m_bvalid);
        resp = m_bresp;
        #1 m_bready = 0;
    endtask

    task automatic read(input logic [AW-1:0] a, output logic [DW-1:0] d, output logic [1:0] resp);
        #1 m_araddr = a; m_arvalid = 1;
        do @(posedge clk); while (!m_arready);
        #1 m_arvalid = 0; m_rready = 1;
        do @(posedge clk); while (!m_rvalid);
        d = m_rdata; resp = m_rresp;
        #1 m_rready = 0;
    endtask

    logic [DW-1:0] d;
    logic [1:0]    r;

    initial begin
        repeat (4) @(posedge clk);
        rstn = 1;
        repeat (3) @(posedge clk);

        // Each block answers at its own base address, with independent state.
        for (int i = 0; i < 4; i++) begin
            write(8'h00 + i*4, 32'hA000_0000 + i, 4'hF, r); check(r == 0, "write A");
            write(8'h80 + i*4, 32'hB000_0000 + i, 4'hF, r); check(r == 0, "write B");
        end
        for (int i = 0; i < 4; i++) begin
            read(8'h00 + i*4, d, r); check(d == 32'hA000_0000 + i && r == 0, $sformatf("read A reg%0d", i));
            read(8'h80 + i*4, d, r); check(d == 32'hB000_0000 + i && r == 0, $sformatf("read B reg%0d", i));
        end

        // Byte strobes still work through the fabric (B reg1 was 0xB0000001).
        write(8'h84, 32'hFFFF_FFFF, 4'b0101, r);
        read (8'h84, d, r);
        check(d == 32'hB0FF_00FF, "byte strobes through xbar");

        // Out-of-range offset inside a block's window -> SLVERR from the slave.
        write(8'h10, 32'h1, 4'hF, r); check(r == 2'b10, "SLVERR propagates (write)");
        read (8'h90, d, r);           check(r == 2'b10 && d == 0, "SLVERR propagates (read)");

        // A and B really are independent.
        read(8'h00, d, r); check(d == 32'hA000_0000, "A untouched by B traffic");

        if (errors == 0) $display("PASS: xbar integration");
        else             $display("FAIL: %0d error(s)", errors);
        $finish;
    end

    initial begin #500_000; $display("FAIL: timeout"); $finish; end
endmodule
