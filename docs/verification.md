# Verification

Run `make test`, `make mutate`, `make synth-check`.

## What each bench checks

- `cdc_bit_sync_tb`: levels across ten destination-clock phases arrive with
  one-to-two-period latency. Short (1 ns) pulses against a 5 ns clock are
  sometimes missed, and the bench insists some are (2 of 10 in the current
  run) so the documented limitation is actually being exercised. Reset clears
  at once and release takes two edges.
- `reset_sync_tb`: assert immediate, release only on a clock edge, ten phases.
- `async_fifo_tb`: numbered words through an 8-deep FIFO with independent
  clocks, phases and random stalls; `wr_en`/`rd_en` are held high when the FIFO
  can't take them. Scoreboard compares every accepted read with its expected
  sequence number (catches loss, duplication, reordering). Occupancy is checked
  never to exceed depth. Coverage assertions make sure full and empty really
  happened in the scenarios built to cause them.
- `packet_router_tb`: random packets of 1 to 6 beats to four ports, random
  per-port backpressure, `src_enable` dropping mid-stream, junk on `src_dest`
  for non-sop beats, and a stray word that must be dropped and counted.

## Scenarios

37 in `scripts/run_sims.sh`: nominal 50/200 MHz, reversed, equal frequency with
phase offset, 13000:4999 ps, 10000:10013 ps (edges drift continuously), a
write-phase sweep, five FIFO seeds, a router phase sweep and four router seeds.

## Mutation check

`scripts/mutation_check.sh` breaks the RTL in eight small ways (full flag with
the wrap bit un-inverted, empty comparing the wrong pointer, writes accepted
while full, reads while empty, dest not stamped, egress popping without ready,
strays forwarded, ready ignoring full) and requires the regression to fail
each time. All eight are caught.

## What simulation cannot tell you

RTL simulation has no metastability. These need real tools and a real device:

1. A vendor CDC report (for example Vivado `report_cdc`) with no unwaived criticals.
2. Timing closure with the constraints in `constraints/`, which are a template
   and have not been run through a vendor tool.
3. Confirmation that the synthesizer keeps the synchronizer pairs (the
   `ASYNC_REG` attribute is Xilinx-specific; other vendors differ) and keeps
   each pair's flops adjacent.
4. Hardware stress: sustained traffic, long runs, output stalls.

## Gaps in the current benches

- Reset during traffic (see `reset_strategy.md`).
- One clock stopped and restarted.
- Malformed cases beyond a stray word: a truncated packet is counted but not
  scoreboarded.
- Only the 36-bit word and four ports; other widths are generic only in the FIFO.

## Synthesizability

`make synth-check` runs GHDL's synthesis front end over the RTL: it elaborates
cleanly and infers no latches. That is a sanity check, not a substitute for a
vendor synthesis report.
