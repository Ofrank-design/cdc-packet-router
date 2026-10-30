#!/bin/sh
# Compile everything and run the full regression. Exits non-zero on the
# first scenario that fails. Needs GHDL (mcode, llvm or gcc backend) with
# VHDL-2008 support.
#
# Usage: scripts/run_sims.sh [workdir]
set -eu
cd "$(dirname "$0")/.."

GHDL=${GHDL:-ghdl}
W=${1:-build}
STD=08
mkdir -p "$W"

echo "== analyze"
# shellcheck disable=SC2046
$GHDL -a --std=$STD --workdir="$W" $(cat scripts/filelist.txt)

pass=0
run() {
    top=$1; shift
    if $GHDL --elab-run --std=$STD --workdir="$W" "$top" "$@" > "$W/last.log" 2>&1; then
        pass=$((pass + 1))
        printf 'PASS  %-18s %s\n' "$top" "$*"
    else
        printf 'FAIL  %-18s %s\n' "$top" "$*"
        tail -n 15 "$W/last.log"
        exit 1
    fi
}

echo "== synchronizers"
run cdc_bit_sync_tb
run reset_sync_tb

echo "== async FIFO"
# nominal: 50 MHz write, 200 MHz read, odd start phases, reader often starved
run async_fifo_tb -gEXPECT_EMPTY=true
# reversed: 200 MHz write into a 50 MHz reader, FIFO must fill
run async_fifo_tb -gWR_PERIOD_PS=5000 -gRD_PERIOD_PS=20000 -gWR_PCT=90 -gRD_PCT=90 -gEXPECT_FULL=true
# nominal clocks but a slow consumer: sustained full
run async_fifo_tb -gWR_PCT=100 -gRD_PCT=10 -gEXPECT_FULL=true
# starved reader
run async_fifo_tb -gWR_PCT=100 -gRD_PCT=100 -gEXPECT_EMPTY=true
# awkward ratio, phase slowly sliding against each other
run async_fifo_tb -gWR_PERIOD_PS=13000 -gRD_PERIOD_PS=4999 -gWR_PHASE_PS=0 -gRD_PHASE_PS=0 -gWR_PCT=60 -gRD_PCT=60
# same frequency, different phase
run async_fifo_tb -gWR_PERIOD_PS=10000 -gRD_PERIOD_PS=10000 -gWR_PHASE_PS=0 -gRD_PHASE_PS=3333 -gWR_PCT=100 -gRD_PCT=100
# near-equal frequencies: edges drift past each other continuously
run async_fifo_tb -gWR_PERIOD_PS=10000 -gRD_PERIOD_PS=10013 -gWR_PCT=100 -gRD_PCT=100 -gNUM_WORDS=8000
# write phase sweep across one 50 MHz period
for ph in 0 2500 5000 7500 10000 12500 15000 17500; do
    run async_fifo_tb -gWR_PHASE_PS=$ph -gRD_PHASE_PS=0 -gNUM_WORDS=1500
done
# different random traffic
for s in 2 3 4 5 6; do
    run async_fifo_tb -gSEED=$s -gNUM_WORDS=2500
done

echo "== packet router"
run packet_router_tb
run packet_router_tb -gSRC_PCT=100 -gOUT_PCT=30 -gEXPECT_FULL=true
run packet_router_tb -gSRC_PCT=30 -gOUT_PCT=100
run packet_router_tb -gSRC_PCT=100 -gOUT_PCT=100
run packet_router_tb -gWR_PERIOD_PS=5000 -gRD_PERIOD_PS=20000 -gSRC_PCT=80 -gOUT_PCT=80 -gEXPECT_FULL=true
run packet_router_tb -gWR_PERIOD_PS=13000 -gRD_PERIOD_PS=4999 -gWR_PHASE_PS=0 -gRD_PHASE_PS=0
for ph in 0 4000 8000 12000 16000; do
    run packet_router_tb -gWR_PHASE_PS=$ph -gRD_PHASE_PS=0 -gNUM_PKTS=200
done
for s in 11 12 13 14; do
    run packet_router_tb -gSEED=$s -gNUM_PKTS=300
done

echo
echo "all $pass scenarios passed"
