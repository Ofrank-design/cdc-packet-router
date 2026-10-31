# Architecture

## Domains

| | Write domain | Read domain |
|---|---|---|
| Clock | `wr_clk`, nominal 50 MHz | `rd_clk`, nominal 200 MHz |
| Owns | write pointer, `full`, ingress state, malformed counter | read pointer, `empty`, egress |
| Reset | `reset_sync` on `wr_clk` | `reset_sync` on `rd_clk` |

The 4:1 ratio is nominal. The design assumes the clocks are unrelated and the
testbenches run ratios like 13000:4999 ps and 10000:10013 ps to make sure it
doesn't quietly lean on the ratio.

## Every crossing

| Signal | From → to | Width | Kind | Mechanism |
|---|---|---|---|---|
| read pointer (Gray) | rd → wr | ADDR_W+1 | counter | `cdc_gray_sync` |
| write pointer (Gray) | wr → rd | ADDR_W+1 | counter | `cdc_gray_sync` |
| packet words | wr → rd | 36 | data | FIFO memory; the read side only looks at a slot after the write pointer has passed it |
| `src_enable` → `link_up` | wr → rd | 1 | level | `cdc_bit_sync` |
| `rst_n` | external → both | 1 | async reset | `reset_sync` per domain |

`rx_malformed` and `wr_full` are write-domain outputs; `rd_empty` is read-domain.
None of them is sampled by the other domain inside the router. If a consumer
needs `rx_malformed` in the read domain it must cross it (Gray or handshake),
not copy bits.

## Why the FIFO memory needs no synchronizer

The writer fills slot N, *then* advances its Gray pointer. The reader only
sees the new pointer a couple of read clocks later, and only then treats slot N
as readable. By that time the data has been stable for longer than a clock
period. The mirror argument covers the writer reusing a slot: it waits until
the stale read pointer says the slot is free.

Staleness is always safe-side: `full` can linger after space opens and `empty`
can linger after data lands. Throughput suffers a little; correctness doesn't.

## Packet word

```
[35] sop  [34] eop  [33:32] dest  [31:0] payload
```

Ingress stamps the packet's destination on every beat, so egress is stateless
and metadata can't separate from payload.

## FIFO sizing

The default top-level depth is 16 words (`FIFO_ADDR_W = 4`); the benches use 8
to force constant wrap. Size it from your real burst length and the longest
stall you accept on an output port. 50 Mword/s in versus 200 Mword/s out is a
best case; a blocked port stalls the whole queue (head-of-line blocking), by
design here, because there is one FIFO.

## Known behaviours to be aware of

- One FIFO means one blocked port blocks all ports.
- A truncated packet (a new sop before the previous eop) is counted and still
  forwarded. Policy for what a consumer should do with it is up to you.
- The FIFO read is combinational off the memory, so it infers distributed RAM.
  For block RAM, register the read data and budget one extra cycle.
