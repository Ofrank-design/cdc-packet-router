#!/bin/sh
# A green testbench only means something if it goes red when the design is
# wrong. This script breaks the RTL on purpose, one small change at a time,
# and insists that the regression notices every time.
#
# Usage: scripts/mutation_check.sh
set -eu
cd "$(dirname "$0")/.."
GHDL=${GHDL:-ghdl}

caught=0
total=0

mutate() {
    desc=$1; file=$2; old=$3; new=$4; top=$5; shift 5
    total=$((total + 1))
    m=build/mut
    rm -rf "$m"; mkdir -p "$m/work"
    python3 - "$file" "$old" "$new" "$m" <<'PY'
import sys, pathlib, shutil
file, old, new, m = sys.argv[1:5]
files = pathlib.Path("scripts/filelist.txt").read_text().split()
for f in files:
    src = pathlib.Path(f).read_text()
    if f == file:
        if old not in src:
            sys.exit("mutation pattern not found in " + f)
        src = src.replace(old, new, 1)
    out = pathlib.Path(m) / f
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(src)
PY
    # shellcheck disable=SC2046
    $GHDL -a --std=08 --workdir="$m/work" $(sed "s#^#$m/#" scripts/filelist.txt) >/dev/null 2>&1
    if $GHDL --elab-run --std=08 --workdir="$m/work" "$top" "$@" >"$m/log" 2>&1; then
        printf 'MISSED  %s\n' "$desc"
    else
        printf 'caught  %s\n' "$desc"
        caught=$((caught + 1))
    fi
}

mutate "full flag stops inverting the wrap bit" \
    rtl/fifo/async_fifo.vhd \
    "(not rgray_in_wclk(PTR_W - 1) &" "(rgray_in_wclk(PTR_W - 1) &" \
    async_fifo_tb -gWR_PCT=100 -gRD_PCT=10

mutate "empty flag compares the old read pointer" \
    rtl/fifo/async_fifo.vhd \
    "'1' when rgray_next = wgray_in_rclk" "'1' when rgray = wgray_in_rclk" \
    async_fifo_tb

mutate "FIFO accepts writes while full" \
    rtl/fifo/async_fifo.vhd \
    "wr_fire    <= wr_en and not full_i;" "wr_fire    <= wr_en;" \
    async_fifo_tb -gWR_PCT=100 -gRD_PCT=10

mutate "FIFO accepts reads while empty" \
    rtl/fifo/async_fifo.vhd \
    "rd_fire    <= rd_en and not empty_i;" "rd_fire    <= rd_en;" \
    async_fifo_tb -gWR_PCT=100 -gRD_PCT=100

mutate "ingress forgets to stamp dest on later beats" \
    rtl/router/packet_ingress.vhd \
    "eff_dest  <= src_dest when src_sop = '1' else dest_q;" "eff_dest  <= src_dest;" \
    packet_router_tb

mutate "egress pops without waiting for out_ready" \
    rtl/router/packet_egress.vhd \
    "fifo_rd_en <= out_ready(to_integer(unsigned(dest_i)));" "fifo_rd_en <= '1';" \
    packet_router_tb -gOUT_PCT=30

mutate "ingress forwards stray words" \
    rtl/router/packet_ingress.vhd \
    "wr_en_i   <= accept and not stray;" "wr_en_i   <= accept;" \
    packet_router_tb

mutate "ready ignores FIFO full" \
    rtl/router/packet_ingress.vhd \
    "ready_i   <= rst_n and src_enable and not fifo_full;" "ready_i   <= rst_n and src_enable;" \
    packet_router_tb -gSRC_PCT=100 -gOUT_PCT=30

echo
echo "$caught of $total mutations caught"
[ "$caught" -eq "$total" ]
