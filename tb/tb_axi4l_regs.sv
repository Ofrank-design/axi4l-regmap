`timescale 1ns/1ps

// Self-checking testbench for axi4l_regs.
//
// Timing convention: the bus is driven with blocking assignments 1 ns after a
// clock edge and sampled right at the edge, before the DUT's nonblocking
// updates land. That keeps the bench race-free in any simulator.
//
// Randomised traffic is reproducible: the seed is printed at start, rerun
// with +seed=N to repeat a run.

module tb_axi4l_regs;
    localparam int ADDR_W = 8;
    localparam int DATA_W = 32;

    logic aclk    = 1'b0;
    logic aresetn = 1'b0;
    always #5 aclk = ~aclk;

    axi4l_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) bus (aclk, aresetn);
    axi4l_regs #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) dut (.s(bus));

    // Reference model of the four registers.
    logic [31:0] model [4];

    int errors = 0;
    int seed   = 1;

    // ------------------------------------------------------------------
    // Passive monitor: a response must never show up without its request.
    // ------------------------------------------------------------------
    int n_aw, n_w, n_b, n_ar, n_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            n_aw = 0; n_w = 0; n_b = 0; n_ar = 0; n_r = 0;
        end else begin
            if (bus.awvalid && bus.awready) n_aw++;
            if (bus.wvalid  && bus.wready ) n_w++;
            if (bus.bvalid  && bus.bready ) n_b++;
            if (bus.arvalid && bus.arready) n_ar++;
            if (bus.rvalid  && bus.rready ) n_r++;
            if (n_b > n_aw || n_b > n_w) begin errors++; $display("[FAIL] %0t B without AW+W", $time); end
            if (n_r > n_ar)              begin errors++; $display("[FAIL] %0t R without AR",    $time); end
        end
    end

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    task automatic check(input bit ok, input string what);
        if (!ok) begin
            errors++;
            $display("[FAIL] %0t %s", $time, what);
        end
    endtask

    task automatic bus_idle();
        bus.awvalid = 0; bus.wvalid = 0; bus.bready = 0;
        bus.arvalid = 0; bus.rready = 0;
        bus.awaddr  = 0; bus.wdata  = 0; bus.wstrb  = 0; bus.araddr = 0;
        bus.awprot  = 0; bus.arprot = 0;
    endtask

    task automatic pulse_reset(input int cycles);
        #1 aresetn = 0;
        repeat (cycles) @(posedge aclk);
        #1 aresetn = 1;
        @(posedge aclk);
    endtask

    // Apply a byte-strobed write to the reference model.
    task automatic model_write(input int idx, input logic [31:0] data, input logic [3:0] strb);
        for (int b = 0; b < 4; b++)
            if (strb[b]) model[idx][8*b +: 8] = data[8*b +: 8];
    endtask

    // Full write transaction. aw_dly / w_dly delay each channel independently,
    // b_dly delays BREADY after both have been accepted.
    task automatic axi_write(input logic [ADDR_W-1:0] addr, input logic [31:0] data,
                             input logic [3:0] strb,
                             input int aw_dly, input int w_dly, input int b_dly,
                             output logic [1:0] resp);
        fork
            begin
                repeat (aw_dly) @(posedge aclk);
                #1 bus.awaddr = addr; bus.awvalid = 1;
                do @(posedge aclk); while (!bus.awready);
                #1 bus.awvalid = 0;
            end
            begin
                repeat (w_dly) @(posedge aclk);
                #1 bus.wdata = data; bus.wstrb = strb; bus.wvalid = 1;
                do @(posedge aclk); while (!bus.wready);
                #1 bus.wvalid = 0;
            end
        join
        repeat (b_dly) @(posedge aclk);
        #1 bus.bready = 1;
        do @(posedge aclk); while (!bus.bvalid);
        resp = bus.bresp;
        #1 bus.bready = 0;
    endtask

    // Full read transaction; r_dly delays RREADY after the address is accepted.
    task automatic axi_read(input logic [ADDR_W-1:0] addr, input int r_dly,
                            output logic [31:0] data, output logic [1:0] resp);
        #1 bus.araddr = addr; bus.arvalid = 1;
        do @(posedge aclk); while (!bus.arready);
        #1 bus.arvalid = 0;
        repeat (r_dly) @(posedge aclk);
        #1 bus.rready = 1;
        do @(posedge aclk); while (!bus.rvalid);
        data = bus.rdata;
        resp = bus.rresp;
        #1 bus.rready = 0;
    endtask

    // Read every register and compare against the model.
    task automatic check_all_regs(input string tag);
        logic [31:0] d;
        logic [1:0]  r;
        for (int i = 0; i < 4; i++) begin
            axi_read(i*4, 0, d, r);
            check(d == model[i] && r == 2'b00, $sformatf("%s: reg%0d", tag, i));
        end
    endtask

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------
    task automatic test_reset_values();
        foreach (model[i]) model[i] = 0;
        check_all_regs("reset value");
    endtask

    // Corner-case data patterns on every register: zeros, ones, alternating
    // bits both ways, and values with only the top / bottom bit set.
    task automatic test_readback();
        localparam logic [31:0] PAT [6] = '{32'h0000_0000, 32'hFFFF_FFFF, 32'hAAAA_AAAA,
                                            32'h5555_5555, 32'h8000_0000, 32'h0000_0001};
        logic [31:0] got;
        logic [1:0]  r;
        for (int i = 0; i < 4; i++) begin
            for (int p = 0; p < 6; p++) begin
                axi_write(i*4, PAT[p], 4'hF, 0, 0, 0, r);
                check(r == 2'b00, "write OKAY");
                model[i] = PAT[p];
                axi_read(i*4, 0, got, r);
                check(got == PAT[p] && r == 2'b00, $sformatf("pattern %h on reg%0d", PAT[p], i));
            end
        end
        check_all_regs("readback");
    endtask

    // Every strobe pattern on every register, starting from a known background
    // so a lane that wrongly changes (or wrongly doesn't) shows up.
    task automatic test_byte_strobes();
        logic [31:0] d, got;
        logic [1:0]  r;
        for (int i = 0; i < 4; i++) begin
            for (int s = 0; s < 16; s++) begin
                axi_write(i*4, 32'hC3C3_C3C3, 4'hF, 0, 0, 0, r);
                model[i] = 32'hC3C3_C3C3;
                d = $urandom;
                axi_write(i*4, d, s[3:0], 0, 0, 0, r);
                check(r == 2'b00, "strobe write OKAY");
                model_write(i, d, s[3:0]);
                axi_read(i*4, 0, got, r);
                check(got == model[i], $sformatf("reg%0d strobe %b", i, s[3:0]));
            end
        end
    endtask

    task automatic test_bad_addresses();
        logic [31:0] d;
        logic [1:0]  r;
        axi_write(8'h10, 32'hDEAD_BEEF, 4'hF, 0, 0, 0, r); check(r == 2'b10, "write 0x10 -> SLVERR");
        axi_write(8'h05, 32'hDEAD_BEEF, 4'hF, 0, 0, 0, r); check(r == 2'b10, "write 0x05 (unaligned) -> SLVERR");
        axi_read (8'h10, 0, d, r); check(r == 2'b10 && d == 0, "read 0x10 -> SLVERR, zero data");
        axi_read (8'h07, 0, d, r); check(r == 2'b10 && d == 0, "read 0x07 (unaligned) -> SLVERR");
        check_all_regs("after bad accesses");   // nothing may have been disturbed
    endtask

    // Random addresses, data, strobes and handshake delays against the model.
    task automatic test_random(input int n);
        logic [31:0] d, got;
        logic [3:0]  st;
        logic [1:0]  r;
        int a;
        for (int k = 0; k < n; k++) begin
            a = $urandom_range(0, 3);
            if ($urandom_range(0, 1)) begin
                d = $urandom; st = $urandom;
                axi_write(a*4, d, st, $urandom_range(0,4), $urandom_range(0,4), $urandom_range(0,4), r);
                model_write(a, d, st);
                check(r == 2'b00, "random write OKAY");
            end else begin
                axi_read(a*4, $urandom_range(0,4), got, r);
                check(got == model[a] && r == 2'b00, $sformatf("random read reg%0d", a));
            end
        end
    endtask

    // W arriving well before AW, then four writes back to back.
    task automatic test_back_to_back();
        logic [1:0] r;
        for (int i = 0; i < 4; i++) begin
            axi_write(i*4, 32'hB000_0000 + i, 4'hF, 3, 0, 0, r);
            model[i] = 32'hB000_0000 + i;
        end
        check_all_regs("back-to-back");
    endtask

    // Read and write running at the same time.
    task automatic test_concurrency();
        logic [31:0] got;
        logic [1:0]  r_rd, r_wr;

        // Different registers: both must complete and see the right data.
        model[1] = 32'h1111_1111;
        model[2] = 32'h2222_2222;
        axi_write(4, model[1], 4'hF, 0, 0, 0, r_wr);
        axi_write(8, model[2], 4'hF, 0, 0, 0, r_wr);
        fork
            axi_write(4, 32'hCAFE_F00D, 4'hF, 0, 1, 2, r_wr);
            axi_read (8, 1, got, r_rd);
        join
        model[1] = 32'hCAFE_F00D;
        check(got == model[2] && r_rd == 2'b00, "concurrent: read of other reg");
        check_all_regs("concurrent: after");

        // Same register, same moment: the read returns the old value.
        axi_write(0, 32'h0000_0AAA, 4'hF, 0, 0, 0, r_wr);
        fork
            axi_write(0, 32'h0000_0BBB, 4'hF, 0, 0, 0, r_wr);
            axi_read (0, 0, got, r_rd);
        join
        model[0] = 32'h0000_0BBB;
        check(got == 32'h0000_0AAA, "same-cycle read returns old value");
        check_all_regs("same-cycle: after");
    endtask

    // A new request must not be accepted while the previous response is still
    // waiting for the master, and the waiting response must not change.
    task automatic test_response_backpressure();
        logic [31:0] got;
        logic [1:0]  r, held_resp;

        // Write: take AW+W of write #1, leave BREADY low, then offer write #2.
        #1 bus.awaddr = 0; bus.awvalid = 1; bus.wdata = 32'h0000_00F1; bus.wstrb = 4'hF; bus.wvalid = 1;
        do @(posedge aclk); while (!(bus.awready && bus.wready));
        #1 bus.awaddr = 4; bus.wdata = 32'h0000_00F2;          // write #2 offered immediately
        repeat (2) @(posedge aclk);
        held_resp = bus.bresp;
        repeat (4) begin
            @(posedge aclk);
            check(bus.bvalid && bus.bresp == held_resp, "B holds while stalled");
            check(!bus.awready && !bus.wready,          "no new AW/W while B pending");
        end
        axi_read(4, 0, got, r);
        check(got == model[1], "write #2 not committed while B pending");
        model[0] = 32'h0000_00F1;
        #1 bus.bready = 1;                                      // master finally takes B #1
        @(posedge aclk);
        #1 bus.bready = 0;
        // Write #2 is now accepted and completes.
        do @(posedge aclk); while (!(bus.awready && bus.wready) && !bus.bvalid);
        #1 bus.awvalid = 0; bus.wvalid = 0;
        #1 bus.bready = 1;
        do @(posedge aclk); while (!bus.bvalid);
        #1 bus.bready = 0;
        model[1] = 32'h0000_00F2;
        check_all_regs("after write backpressure");

        // Read: take AR #1, leave RREADY low, offer AR #2.
        #1 bus.araddr = 0; bus.arvalid = 1;
        do @(posedge aclk); while (!bus.arready);
        #1 bus.araddr = 4;
        repeat (3) @(posedge aclk);
        check(bus.rvalid && bus.rdata == model[0], "R holds data while stalled");
        check(!bus.arready, "no new AR while R pending");
        #1 bus.rready = 1;
        @(posedge aclk);
        #1 bus.rready = 0;
        do @(posedge aclk); while (!bus.rvalid);                 // R #2 for the second AR
        check(bus.rdata == model[1], "second read returns its own register");
        #1 bus.arvalid = 0; bus.rready = 1;
        @(posedge aclk);
        #1 bus.rready = 0;
    endtask

    // Reset hitting a transaction at each stage. Whatever was in flight must
    // vanish, and the registers must come back at zero.
    task automatic test_reset_in_flight();
        logic [31:0] d;
        logic [1:0]  r;

        // AW accepted, W never arrives.
        #1 bus.awaddr = 0; bus.awvalid = 1;
        do @(posedge aclk); while (!bus.awready);
        #1 bus.awvalid = 0;
        pulse_reset(2);
        check(!bus.bvalid, "reset mid-write: no B");
        foreach (model[i]) model[i] = 0;
        check_all_regs("reset mid-write");

        // W accepted, AW never arrives.
        #1 bus.wdata = 32'hDEAD_0001; bus.wstrb = 4'hF; bus.wvalid = 1;
        do @(posedge aclk); while (!bus.wready);
        #1 bus.wvalid = 0;
        pulse_reset(2);
        check(!bus.bvalid, "reset with W held: no B");
        check_all_regs("reset with W held");

        // Write response stalled (BREADY low).
        #1 bus.awaddr = 4; bus.awvalid = 1;
        bus.wdata = 32'h1234_5678; bus.wstrb = 4'hF; bus.wvalid = 1;
        do @(posedge aclk); while (!(bus.awready && bus.wready));
        #1 bus.awvalid = 0; bus.wvalid = 0;
        repeat (4) @(posedge aclk);
        check(bus.bvalid, "B pending before reset");
        pulse_reset(2);
        check(!bus.bvalid, "reset clears pending B");
        check_all_regs("reset with B pending");

        // Read response stalled (RREADY low).
        axi_write(0, 32'hFEED_FACE, 4'hF, 0, 0, 0, r);
        #1 bus.araddr = 0; bus.arvalid = 1;
        do @(posedge aclk); while (!bus.arready);
        #1 bus.arvalid = 0;
        repeat (3) @(posedge aclk);
        check(bus.rvalid && bus.rdata == 32'hFEED_FACE, "R pending before reset");
        pulse_reset(2);
        check(!bus.rvalid && bus.rdata == 0, "reset clears pending R");

        // ARVALID held while reset is active, then released: must not be served.
        #1 aresetn = 0; bus.araddr = 4; bus.arvalid = 1;
        repeat (2) @(posedge aclk);
        #1 bus.arvalid = 0; aresetn = 1;
        @(posedge aclk);
        check(!bus.rvalid, "no R for a request made during reset");

        // And the slave still works afterwards.
        axi_write(4, 32'h55AA_55AA, 4'hF, 0, 0, 0, r);
        axi_read (4, 0, d, r);
        check(d == 32'h55AA_55AA, "recovers after reset");
        foreach (model[i]) model[i] = 0;
        model[1] = 32'h55AA_55AA;
    endtask

    // ------------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------------
    initial begin
        bus_idle();
        if ($value$plusargs("seed=%d", seed)) ;
        void'($urandom(seed));
        $display("random seed = %0d (rerun with +seed=N)", seed);

        repeat (3) @(posedge aclk);
        aresetn = 1;
        repeat (2) @(posedge aclk);

        test_reset_values();
        test_readback();
        test_byte_strobes();
        test_bad_addresses();
        test_random(500);
        test_concurrency();
        test_back_to_back();
        test_response_backpressure();
        test_reset_in_flight();

        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAIL: %0d error(s)", errors);
        $finish;
    end

    // Watchdog, in case a handshake ever hangs.
    initial begin
        #2_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
