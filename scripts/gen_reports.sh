#!/bin/sh
# Regenerate the evidence under docs/reports/ from a fresh run.
# Usage: scripts/gen_reports.sh [build-dir]
set -e
cd "$(dirname "$0")/.."
B=${1:-build}
OUT=docs/reports
mkdir -p "$OUT" "$B"

{ echo "tools: $(verilator --version | head -1) | $(yosys -V)"; echo "date: $(date -u +%Y-%m-%d)"; } > $OUT/tools.txt

for s in 1 7 42 99; do
    make -s sim BUILD="$B" SEED=$s > /dev/null
    echo "seed $s: $(grep -E '^(PASS|FAIL)' $B/sim.log)"
done > $OUT/sim.txt

make -s sim-xbar BUILD="$B" > /dev/null
grep -E '^(PASS|FAIL)' $B/xbar.log > $OUT/xbar.txt

make -s synth > $OUT/synth.txt

{
  echo "== own properties, bounded (30 cycles) =="
  yosys -s formal/bmc.ys    | grep -E "SUCCESS|FAIL|ERROR"
  echo "== own properties, k-induction (unbounded) =="
  yosys -s formal/induct.ys | grep -E "Induction step (proven|failed)|SUCCESS|FAIL|ERROR" | tail -1
  echo "== independent faxil_slave checker, bounded (40 cycles) =="
  yosys -s formal/ext_bmc.ys | grep -E "SUCCESS|FAIL|ERROR"
} > $OUT/formal.txt

if command -v nextpnr-ice40 >/dev/null 2>&1; then
    yosys -q -p "read_verilog -sv -DSYNTHESIS rtl/axi4l_regs_core.sv; synth_ice40 -top axi4l_regs_core -json $B/core.json"
    nextpnr-ice40 --hx8k --package ct256 --json $B/core.json --freq 50 --pcf-allow-unconstrained \
        > $B/pnr_full.log 2>&1 || true
    { grep -E "ICESTORM_LC:|SB_IO:|ICESTORM_RAM:" $B/pnr_full.log | tail -3
      grep -E "Max frequency" $B/pnr_full.log | tail -1
      echo "-- critical path (post-route) --"
      awk '/Critical path report for clock/{c++} c>=1' $B/pnr_full.log | sed -n '1,14p'
    } > $OUT/pnr_ice40.txt
fi
echo "reports written to $OUT"
