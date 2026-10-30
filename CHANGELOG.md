# Changelog

## 0.1.0

- Two-flop bit synchronizer, Gray-pointer synchronizer, reset synchronizer
- Gray-pointer asynchronous FIFO (first-word-fall-through)
- Packet router: ingress with destination stamping and malformed-word
  accounting, stateless egress to four ports
- Self-checking benches with a 37-scenario regression, 8-mutation check and
  GHDL synthesizability check, wired into GitHub Actions
