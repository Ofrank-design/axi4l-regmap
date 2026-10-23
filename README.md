# AXI4-Lite register map

A small, synthesizable AXI4-Lite slave in SystemVerilog: four 32-bit
read/write registers behind a standard AXI4-Lite port, with a clean interface
wrapper, a self-checking testbench, an interconnect integration test, formal
proofs, and an open-source synthesis and timing flow.

It is a real bus endpoint, not a toy: AW and W are accepted independently,
responses hold under backpressure, byte strobes work, bad addresses return
`SLVERR`, and reset drops anything in flight.

## Layout

```
rtl/           axi4l_if.sv (interface), axi4l_regs_core.sv (logic), axi4l_regs.sv (wrapper)
tb/            unit testbench and crossbar integration test
formal/        formal harnesses and Yosys scripts
sw/            C header with the register offsets
docs/          register map, design notes, verification summary
constraints/   starting-point SDC
scripts/       dependency fetch
```

## Quick start

You need Verilator 5.x and Yosys. `nextpnr-ice40` is optional (timing example).

```sh
make deps         # fetch the third-party AXI pieces (not vendored)
make all          # lint, unit sim, crossbar sim, synthesis, formal
make pnr          # optional: iCE40 place-and-route example
make sim SEED=7   # rerun the random tests with another seed
```

## Using it

Instantiate the interface version:

```systemverilog
axi4l_if #(.ADDR_W(8), .DATA_W(32)) axil (aclk, aresetn);
axi4l_regs #(.ADDR_W(8), .DATA_W(32)) u_regs (.s(axil));
```

or the flat-port core, if your tools don't take interfaces
(`rtl/axi4l_regs_core.sv` on its own):

```systemverilog
axi4l_regs_core #(.ADDR_W(8), .DATA_W(32)) u_regs (.aclk(aclk), .aresetn(aresetn), /* AXI ports */);
```

`DATA_W` must be 32; `ADDR_W` must be at least 4. The block decodes the low 4
address bits, so give it addresses relative to its base.

## Behaviour in brief

- Synchronous, active-low reset. Reset drops any transaction in flight.
- One write and one read outstanding at a time, independently.
- Writes commit one cycle after both address and data are accepted.
- `WSTRB` per byte; `WSTRB = 0` is a no-op that still returns `OKAY`.
- Offsets `0x00 0x04 0x08 0x0C` are valid; anything else gets `SLVERR`.
- A read and write to one register in the same cycle: the read sees the old value.

Full details: [docs/register_map.md](docs/register_map.md) and
[docs/design_notes.md](docs/design_notes.md).

## Status

Verified in simulation, with formal proofs and an independent protocol
checker, and synthesized and placed on an iCE40 as an example. Not yet run on
your target FPGA or against your interconnect or hardware; see "What has not
been verified" in the design notes before relying on it.

## License

MIT. See [LICENSE](LICENSE). Third-party code fetched by `make deps`
(ZipCPU wb2axip) is Apache-2.0 and is not included in this repository.
