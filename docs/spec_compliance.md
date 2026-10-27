# Spec compliance

Status of the project spec's production-readiness checklist (section 14) and
build plan (section 15) against this repository. Evidence lives in
[`reports/`](reports/) and can be regenerated with `make reports`.

Legend: **Done** = built and checked here. **Stand-in** = checked, but on a
substitute for your real target. **Open** = needs your platform or hardware.

## Protocol correctness

| Checklist item | Status | Evidence |
|---|---|---|
| All five AXI4-Lite channels implemented | Done | `rtl/axi4l_regs_core.sv`; all five exercised in every bench |
| AW and W can arrive independently | Done | random per-channel delays, `test_back_to_back`, W-only/AW-only reset cases |
| Responses stable until accepted | Done | assertions `a_b_stable`/`a_r_stable`; formal property (proven, unbounded) |
| Backpressure handled | Done | `test_response_backpressure`; random BREADY/RREADY delays |
| Read and write paths independent | Done | `test_concurrency` |
| Invalid-address behaviour documented and tested | Done | `docs/register_map.md`; `test_bad_addresses`; SLVERR through the crossbar |
| Outstanding-transaction limits enforced | Done | `test_response_backpressure`; formal: READY low while a response is pending |

## Register behaviour

| Checklist item | Status | Evidence |
|---|---|---|
| Four registers at documented offsets | Done | all four read and written in every test |
| Reset values correct | Done | `test_reset_values`; reset tests |
| Byte strobes work | Done | all 16 strobe patterns on **each** of the four registers; formal write-correctness invariant (enabled lanes written, all others untouched) |
| Unsupported writes modify nothing | Done | `test_bad_addresses`; formal (proven, unbounded) |
| Read data corresponds to the accepted address | Done | scoreboard in `test_random`; formal: a failed read returns zero |
| Software and RTL definitions match | Done | `make check-sw` checks the C header against the documented offsets; the benches address registers at the same offsets |

## RTL quality

| Checklist item | Status | Evidence |
|---|---|---|
| Compiles in the target toolchain | Stand-in | Verilator 5.020 and Yosys 0.33 only; your vendor tool is untested |
| No unintended latches | Done | no latch cells in the Yosys netlist |
| No accidental multiple drivers | Done | Verilator `-Wall` lint clean on the core |
| Widths and signedness explicit | Done | width warnings enabled in `make lint`, none reported |
| Reset behaviour consistent | Done | single synchronous active-low reset for all state |
| No unsupported interface features remain | Done | logic is in a flat-port core; the interface lives only in the wrapper |

## Verification

| Checklist item | Status | Evidence |
|---|---|---|
| All registers pass read/write tests | Done | six corner-case patterns (0, all-ones, both alternating, MSB-only, LSB-only) on every register |
| Address/data channel independence tested | Done | see above |
| Byte-strobe tests pass | Done | see above |
| Invalid-address tests pass | Done | writes and reads, aligned-out-of-range and unaligned |
| Response-stall tests pass | Done | write and read |
| Concurrent read/write tests pass | Done | different registers and same register, same cycle |
| Reset interruption tests pass | Done | idle, AW only, W only, pending B, pending R, request during reset |
| Randomized scoreboard tests pass | Done | 500 transactions per seed, seeds 1/7/42/99 in `reports/sim.txt`; seed reproducible with `+seed=N` |
| Assertions pass | Done | in-RTL assertions run under Verilator; none waived |

The new tests were checked against deliberately broken copies of the RTL
(a READY that ignores a pending response, a dead byte lane on one register,
a wrong register on read); each is caught.

## FPGA implementation

| Checklist item | Status | Evidence |
|---|---|---|
| Synthesis succeeds | Done | `reports/synth.txt` (Yosys), `reports/pnr_ice40.txt` |
| Timing constraints correct | Stand-in | `constraints/axi4l.sdc` is a starting point; not run through a vendor tool |
| Timing closure achieved | Stand-in | iCE40 HX8K: Fmax 117.83 MHz vs a 50 MHz target (about 11 ns of slack, derived from Fmax) |
| Resource utilization recorded | Stand-in | iCE40 HX8K: 367 / 7680 LCs, 0 RAM |
| AXI integration validated | Stand-in | ZipCPU `axilxbar` and independent `faxil_slave` checker; your own interconnect is untested |
| Physical hardware tests | Open | nothing has run on a board |

Section 12.2 timing items: clock period (50 MHz example) and critical path are
in `reports/pnr_ice40.txt`. The open-source flow does not report hold timing,
so hold is **Open** for your target.

## Build plan (section 15)

| Phase | Status | Note |
|---|---|---|
| 1. Repository autopsy | n/a | no existing code was provided; the design was built from the spec |
| 2. Interface and register map | Done | `docs/register_map.md`, `rtl/axi4l_if.sv` |
| 3. RTL implementation | Done | `rtl/` |
| 4. Protocol verification | Done | `tb/`, `formal/` |
| 5. Synthesis and timing | Stand-in | open-source flow on iCE40; vendor flow on your part is Open |
| 6. SoC integration | Stand-in | crossbar test; your system is Open |
| 7. Release readiness | Done for what exists | regression in `make all`, reports in `docs/reports`, limits in `design_notes.md` |

## Decisions the spec left open (and what was chosen)

| Decision | Choice | Where to change |
|---|---|---|
| Reset style | synchronous, active-low | `always_ff` sensitivity lists (see design notes) |
| Error policy | `SLVERR` for out-of-range and unaligned | `RESP_SLVERR` |
| Register semantics | plain read/write storage; names are intent only | `docs/register_map.md` |
| Same-cycle read/write to one register | read returns the old value | tested in `test_concurrency` |
| `WSTRB = 0` | `OKAY`, no change | tested in `test_byte_strobes` |
