# AXI4-Lite register map - build and verification entry points.
# Tools: verilator (5.x), yosys, and optionally nextpnr-ice40 for the timing example.

RTL      := rtl/axi4l_if.sv rtl/axi4l_regs_core.sv rtl/axi4l_regs.sv
WB       := third_party/wb2axip/rtl
BUILD    := build
SEED     ?= 1

VFLAGS   := --binary --timing --assert -Wno-fatal -Wno-WIDTH -Wno-UNUSED \
            -Wno-DECLFILENAME -Wno-INITIALDLY -Wno-TIMESCALEMOD

.PHONY: help all deps lint sim sim-xbar synth formal formal-ext check-sw pnr reports clean

help:
	@echo "make lint         static lint of the synthesizable RTL"
	@echo "make sim          unit testbench (SEED=n to change the random seed)"
	@echo "make sim-xbar     integration test behind a third-party crossbar (needs make deps)"
	@echo "make synth        Yosys synthesis of the core, prints cell counts"
	@echo "make formal       bounded check + unbounded induction proof of our properties"
	@echo "make formal-ext   bounded check against the independent faxil_slave checker (needs make deps)"
	@echo "make check-sw     compile-check the C header against the documented offsets"
	@echo "make reports      regenerate docs/reports from a fresh run"
	@echo "make pnr          iCE40 HX8K place-and-route, reports Fmax and utilization"
	@echo "make all          lint, sim, sim-xbar, synth, formal, formal-ext, check-sw"

all: lint sim sim-xbar synth formal formal-ext check-sw

deps:
	sh scripts/fetch_deps.sh

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-UNDRIVEN \
	    -DNO_IF rtl/axi4l_regs_core.sv --top-module axi4l_regs_core
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-UNDRIVEN \
	    $(RTL) --top-module axi4l_regs

sim:
	@mkdir -p $(BUILD)
	verilator $(VFLAGS) $(RTL) tb/tb_axi4l_regs.sv --top-module tb_axi4l_regs -Mdir $(BUILD)/sim
	$(BUILD)/sim/Vtb_axi4l_regs +seed=$(SEED) | tee $(BUILD)/sim.log
	@grep -q "^PASS" $(BUILD)/sim.log

sim-xbar:
	@mkdir -p $(BUILD)
	verilator $(VFLAGS) -Wno-PINMISSING -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT \
	    rtl/axi4l_regs_core.sv $(WB)/axilxbar.v $(WB)/addrdecode.v $(WB)/skidbuffer.v \
	    tb/tb_axi4l_xbar.sv --top-module tb_axi4l_xbar -Mdir $(BUILD)/xbar
	$(BUILD)/xbar/Vtb_axi4l_xbar | tee $(BUILD)/xbar.log
	@grep -q "^PASS" $(BUILD)/xbar.log

synth:
	yosys -p "read_verilog -sv -DSYNTHESIS rtl/axi4l_regs_core.sv; \
	          synth -top axi4l_regs_core -flatten; stat" | sed -n '/Printing statistics/,$$p'

formal:
	yosys -s formal/bmc.ys    | grep -E "SUCCESS|FAIL|ERROR"
	yosys -s formal/induct.ys | grep -E "Induction step (proven|failed)|SUCCESS|FAIL|ERROR" | tail -1

formal-ext:
	yosys -s formal/ext_bmc.ys | grep -E "SUCCESS|FAIL|ERROR"

check-sw:
	@mkdir -p $(BUILD)
	cc -Wall -Werror -o $(BUILD)/test_header sw/test_header.c
	$(BUILD)/test_header

reports:
	sh scripts/gen_reports.sh $(BUILD)

pnr:
	mkdir -p $(BUILD)
	yosys -q -p "read_verilog -sv -DSYNTHESIS rtl/axi4l_regs_core.sv; \
	             synth_ice40 -top axi4l_regs_core -json $(BUILD)/core.json"
	nextpnr-ice40 --hx8k --package ct256 --json $(BUILD)/core.json --freq 50 \
	    --pcf-allow-unconstrained 2>&1 | grep -E "ICESTORM_LC:|SB_IO:|Max frequency" | tail -3

clean:
	rm -rf $(BUILD)
