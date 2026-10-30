## What changed

<!-- One or two sentences. Why, not just what. -->

## Clock domains touched

- [ ] none
- [ ] wr_clk side
- [ ] rd_clk side
- [ ] a crossing (synchronizer, pointer, reset)

## Checks

- [ ] `make test` passes
- [ ] `make mutate` passes (add a mutation if you added a new safety rule)
- [ ] `make synth-check` passes
- [ ] New CDC paths are listed in `docs/architecture.md`
- [ ] Constraints updated if a crossing was added or moved
