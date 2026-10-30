# Contributing

Small project, small rules.

## Branches

`main` is always green. Work happens on short-lived branches:

- `feat/<thing>` new behaviour
- `fix/<thing>` bug fixes
- `test/<thing>` testbench-only changes
- `docs/<thing>` documentation

Open a pull request into `main`. CI runs the full regression, the mutation
check and the synthesizability check; all three must pass before merging.
Squash or rebase, keep history linear.

## Commits

Conventional-style prefixes, imperative mood:

```
feat(fifo): add almost-full flag
fix(ingress): count truncated packets once
test(router): sweep read phase
docs: explain reset release order
```

## Before you push

```sh
git config core.hooksPath .githooks   # once per clone: runs make test on push
make test
make mutate
make synth-check
```

## Touching a clock-domain crossing

Any change that adds, moves or removes a crossing must:

1. be listed in `docs/architecture.md` with its mechanism,
2. keep or extend a testbench that stresses it across clock phases,
3. add a mutation to `scripts/mutation_check.sh` if it introduces a new
   safety rule (for example, a new flag comparison),
4. update `constraints/router_template.xdc`.

A passing simulation does not prove a crossing is safe. It proves the protocol.
