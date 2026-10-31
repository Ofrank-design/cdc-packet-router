# Reset strategy

One external active-low `rst_n`, treated as asynchronous. Inside, each clock
domain gets its own copy through `reset_sync`:

- **Assert:** immediate, no clock needed. Pointers, flags and synchronizers
  clear at once.
- **Release:** two clock edges after `rst_n` rises, on that domain's own
  clock. The two domains therefore leave reset at slightly different times.
  That is fine: the side that leaves reset first sees the other side's
  synchronized pointer still at zero, which is exactly its reset value.

Reset values: write/read pointers 0, `full` 0, `empty` 1, synchronizers 0.
`empty` is 1 and `rd_data` is zero while empty, so no stale word can look valid.
`src_ready` is low until the write domain is out of reset.

## The rule that matters

Assert reset to both domains together. If you reset only one side while the
other keeps running, the pointers disagree and the FIFO will lie about its
contents. Resetting from one external net, as the top level does, satisfies this.

## Not covered

Reset in the middle of traffic is not exercised by the testbenches: the FIFO
returns to its reset state (checked when idle), but the scoreboard has no
model of "words that were deliberately discarded." Add that before relying on
mid-stream reset in a product.
