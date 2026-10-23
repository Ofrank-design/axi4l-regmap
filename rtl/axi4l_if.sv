// AXI4-Lite bus bundle.
//
// Groups the five channels so a slave takes one port instead of twenty-odd
// wires. Directions are fixed by the two modports; a slave should only ever
// see `slave`, a testbench or bus master `master`.

interface axi4l_if #(
    parameter int ADDR_W = 8,
    parameter int DATA_W = 32
) (
    input logic aclk,
    input logic aresetn
);
    localparam int STRB_W = DATA_W / 8;

    // Write address
    logic [ADDR_W-1:0] awaddr;
    logic [2:0]        awprot;
    logic              awvalid, awready;

    // Write data
    logic [DATA_W-1:0] wdata;
    logic [STRB_W-1:0] wstrb;
    logic              wvalid, wready;

    // Write response
    logic [1:0]        bresp;
    logic              bvalid, bready;

    // Read address
    logic [ADDR_W-1:0] araddr;
    logic [2:0]        arprot;
    logic              arvalid, arready;

    // Read data
    logic [DATA_W-1:0] rdata;
    logic [1:0]        rresp;
    logic              rvalid, rready;

    modport master (
        input  aclk, aresetn,
        output awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready,
               araddr, arprot, arvalid, rready,
        input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid
    );

    modport slave (
        input  aclk, aresetn,
        input  awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready,
               araddr, arprot, arvalid, rready,
        output awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid
    );
endinterface
