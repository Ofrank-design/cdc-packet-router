# Everything is driven through scripts/ so CI and a local shell do the same
# thing. GHDL needs VHDL-2008 support.
GHDL ?= ghdl

.PHONY: all test mutate synth-check wave clean

all: test

test:
	@scripts/run_sims.sh

mutate:
	@scripts/mutation_check.sh

# Does the RTL elaborate as synthesizable hardware (no latches, no stray
# simulation-only constructs)? Uses GHDL's own synthesis front end.
synth-check:
	@mkdir -p build
	$(GHDL) -a --std=08 --workdir=build $$(grep '^rtl/' scripts/filelist.txt)
	$(GHDL) --synth --std=08 --workdir=build packet_router > build/packet_router_netlist.vhd
	@echo "synth-check OK"

# make wave TB=async_fifo_tb  ->  build/async_fifo_tb.ghw
TB ?= packet_router_tb
wave:
	@scripts/run_sims.sh >/dev/null
	$(GHDL) --elab-run --std=08 --workdir=build $(TB) --wave=build/$(TB).ghw
	@echo "open build/$(TB).ghw in GTKWave"

clean:
	rm -rf build
