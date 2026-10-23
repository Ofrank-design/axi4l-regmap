# Design notes

## Structure

```
axi4l_regs  (interface wrapper)
  └── axi4l_regs_core  (all the logic; flat ports)
        ├── write path : AW + W captured separately -> commit -> B
        ├── read path  : AR -> data/response -> R
        └── regs[4]    : 4 x 32-bit storage
```

One write and one read may be outstanding at once (independently). Neither
path accepts a new request while its response is still waiting for the master.

### Write path

`aw_got` / `w_got` record that the address / data half has been accepted.
AWREADY and WREADY are each low once their half is held, and both are low
while a B response is pending. When both halves are held and no response is
pending, the register update happens, `BVALID` rises, and the held flags clear.
Because the halves are held independently, AW-before-W, W-before-AW and
same-cycle all work, with any gap between them.

### Read path

`ARREADY` is high whenever no R response is pending. On acceptance the data
and response are registered and `RVALID` rises; they stay put until `RREADY`.

### Reset

Synchronous, active-low. Clears the registers, held address/data, flags and
both responses. A request offered while reset is low is ignored (AXI requires masters to hold VALID low during reset anyway).

## Requirement traceability

The numbering follows the project spec's functional requirements (section 2.1).

| # | Requirement | Where / how it is checked |
|---|-------------|---------------------------|
| 1 | Four 32-bit registers | `regs[4]`; `test_readback` |
| 2 | Exposed over AXI4-Lite slave | `axi4l_regs`, `axi4l_regs_core` |
| 3 | CPU reads and writes | unit bench, crossbar bench |
| 4 | Independent AW / W arrival | `test_random` (random per-channel delays), `test_back_to_back` |
| 5 | WSTRB honoured | `test_byte_strobes` (all 16 patterns), crossbar bench |
| 6 | Correct write response | OKAY / SLVERR checked in every write test |
| 7 | Reads return the register | `check_all_regs` after each phase |
| 8 | Responses held until accepted | assertions `a_b_stable`/`a_r_stable`; formal; random RREADY/BREADY delays |
| 9 | Invalid addresses handled | `test_bad_addresses`; SLVERR through the crossbar |
| 10 | Deterministic reset | `test_reset_values`, `test_reset_in_flight` |
| 11 | No latches / multiple drivers | Yosys synthesis: no latch cells; Verilator lint clean |
| 12 | Synthesizes | Yosys (`make synth`), iCE40 place-and-route (`make pnr`) |
| 13 | Protocol sim + assertions | unit bench, in-RTL assertions, passive monitor |
| 14 | Integrates with an AXI environment | `tb_axi4l_xbar` behind ZipCPU `axilxbar` |

Also covered: parameter checks (`DATA_W` must be 32, `ADDR_W` at least 4) fire
at elaboration, and the core has no dependency on the SystemVerilog interface
(only `axi4l_regs` uses it), so flows without interface support can use the
core alone.

## Verification summary

| Check | Result |
|-------|--------|
| Unit bench (directed + 500 random transactions, seeds 1/7/42/99) | passes |
| Reset hitting an incomplete write, a pending B, a pending R, a request made during reset | passes |
| Read/write concurrency, same-register same-cycle | passes |
| Passive monitor: no B without AW+W, no R without AR | clean |
| Crossbar integration (two blocks, routing, strobes, SLVERR) | passes |
| Formal, own properties, 30-cycle bounded check | no counterexample |
| Formal, own properties, k-induction (unbounded) | proven (k = 1, with the invariants in the core) |
| Formal, independent `faxil_slave` checker, 40-cycle bounded check | no counterexample |
| Synthesis (Yosys, generic gates) | 450 cells, 210 flip-flops, no latches |
| Place-and-route, iCE40 HX8K (example device) | 367 / 7680 LCs, Fmax ~117 MHz at a 50 MHz target |

The harnesses were also run against deliberately broken copies of the RTL
(BVALID dropping without BREADY, an illegal response code, READY stuck high);
each is caught, so the passes are not vacuous.

## What has not been verified

- **Your target device.** The place-and-route figures are for an iCE40, chosen
  only because it has an open-source flow. Run Vivado or Quartus on the real
  part and constraints for actual utilization and timing.
- **Your real master or interconnect.** The crossbar test uses one open-source
  fabric. Your CPU or vendor interconnect may have quirks (for example
  requiring PROT bits or specific error handling); check them in your system.
- **Hardware.** Nothing here has run on a board.
- **Formal depth.** The independent-checker run is bounded (40 cycles); the
  unbounded proof covers our own properties only.

## Design choices worth revisiting

- Write latency is one cycle after both halves are accepted. If you need
  single-cycle writes, the commit can move into the cycle the second half
  arrives, at the cost of a combinational path from the bus into the registers.
- Error policy is SLVERR for bad addresses. Some systems want DECERR or a
  silent OKAY; change `RESP_SLVERR` in one place.
- Synchronous reset suits most FPGA flows. Switch to asynchronous by adding
  `negedge aresetn` to the two `always_ff` sensitivity lists and handling
  reset-release timing in your constraints.
