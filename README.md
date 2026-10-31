# cdc-packet-router

A packet router that moves 36-bit words between two unrelated clock domains
(nominally 50 MHz in, 200 MHz out) through a Gray-pointer asynchronous FIFO,
then fans them out to four output ports. Written in VHDL-2008, simulated with
GHDL, no vendor primitives.

```
 wr_clk (50 MHz)                      │                    rd_clk (200 MHz)
                                      │
 src_* ──► packet_ingress ──► async_fifo ──► packet_egress ──► out_*[0..3]
           stamps dest        Gray ptrs      picks port by
           counts strays      both ways      the head word
                                      │
 src_enable ───────────► cdc_bit_sync ┼──────────────────────► link_up
 rst_n ──► reset_sync (wr)            │      reset_sync (rd) ◄── rst_n
```

## Run it

You need GHDL with VHDL-2008 (`sudo apt install ghdl` on Ubuntu 24.04 is enough).

```sh
make test          # 37 scenarios: clock ratios, phases, seeds, traffic pressure
make mutate        # breaks the RTL 8 ways; the benches must catch every one
make synth-check   # elaborates as synthesizable hardware, no latches
make wave TB=async_fifo_tb   # dump a waveform for GTKWave
```

## Layout

```
rtl/cdc/        cdc_bit_sync, cdc_gray_sync, reset_sync
rtl/fifo/       async_fifo
rtl/router/     packet_ingress, packet_egress, packet_router (top)
rtl/packages/   router_types_pkg (the word format)
tb/             self-checking benches
scripts/        regression, mutation check, compile order
constraints/    XDC template for the two clocks and the pointer crossings
docs/           architecture, reset strategy, verification
```

## Interface in one paragraph

Source side is valid/ready on `wr_clk`. A packet starts with `src_sop` (which
carries `src_dest`), ends with `src_eop`, and can be 1 to any number of beats.
`src_ready` drops while the FIFO is full, while `src_enable` is low, and during
reset. Output side is one valid/ready pair per port on `rd_clk`; `out_valid` is
one-hot or idle and never depends on `out_ready`. Words come out in the order
they went in. A non-sop word outside a packet is dropped and counted in
`rx_malformed`.

## What is verified, and what is not

Verified in simulation: data integrity, order, no overwrite, no underflow,
correct full/empty behaviour across wide clock ratios and phase offsets, port
selection, backpressure, stray-word handling, and that each test fails when the
RTL is deliberately broken. See `docs/verification.md`.

Not done, and needed before this goes on a board: a vendor CDC report, timing
closure on your actual device, validating the XDC template, a reset-in-the-
middle-of-traffic test, and hardware stress. Simulation cannot show metastability.

## License

MIT, Copyright (c) 2026 Frank Oduro <frankoduro1912@gmail.com>.
