# 00 — Reference-clock probe

Answers "which of these pins actually has an oscillator behind it?" on a board with no
documentation, for twelve candidate GT reference clocks at once.

It exists because the alternative is guessing. A design built on a reference clock that
isn't connected synthesises cleanly, implements cleanly, meets timing, and then never
links — with nothing in any report pointing at the cause.

## Build and run

```bash
./compile.sh                       # -> ./output_clk_probe_<date>/
```

Program the bitstream **with its `.ltx`** and read the VIO in Hardware Manager. Find the
right JTAG target first — see `tools/jtag_scan.tcl`, because picking target 0 on a
machine with several cables will happily program a different board.

Each probe reports a 32-bit count. The gate is one second of the 100 MHz board clock, so
**the count is the frequency in Hz**.

## How it works

Each candidate gets an `IBUFDS_GTE4`, whose `ODIV2` output reaches fabric through a
`BUFG_GT` — the only legal route for a GT reference clock. A free-running counter in that
domain is sampled from the board-clock domain at a fixed cadence, and the difference
between consecutive samples is the frequency.

The counter is Gray-coded before crossing domains. A multi-bit binary counter sampled
asynchronously can be caught mid-increment and yield a value that was never real; a Gray
code changes one bit per step, so a torn sample is always either the old value or the new
one. This matters more than usual here, because a probed clock may not exist at all and
nothing in the reference domain may wait on it.

## Controls, and why they are the important part

Four of the twelve probes are not unknowns. Two are reference clocks already known to
carry 161.13 MHz, and two are known dead:

| Index | Pin | Expected |
|---|---|---|
| 8 | Y11 / Y10 (bank 229) | ~161.13 MHz |
| 9 | V11 / V10 (bank 229) | dead |
| 10 | D11 / D10 (bank 233) | ~161.13 MHz |
| 11 | B11 / B10 (bank 233) | dead |

If those four do not read as expected, the measurement is broken and none of the other
eight readings mean anything. A probe without controls cannot tell "this pin is dead"
apart from "my counter never ran".

## Results on this board (2026-09-17)

| Index | Pin | Bank / refclk | Measured |
|---|---|---|---|
| 0 | AW9 | 224 MGTREFCLK0 | — |
| **1** | **AV11** | **224 MGTREFCLK1** | **100.0016 MHz** |
| 2 | AT11 | 225 MGTREFCLK0 | — |
| 3 | AP11 | 225 MGTREFCLK1 | 2.03 MHz (noise) |
| 4 | AM11 | 226 MGTREFCLK0 | — |
| **5** | **AK11** | **226 MGTREFCLK1** | **100.0016 MHz** |
| 6 | AH11 | 227 MGTREFCLK0 | 99.846 MHz |
| 7 | AF11 | 227 MGTREFCLK1 | 294.9 MHz (noise) |
| 8 | Y11 | 229 MGTREFCLK0 | 161.132 MHz ✔ control |
| 9 | V11 | 229 MGTREFCLK1 | — ✔ control |
| 10 | D11 | 233 MGTREFCLK0 | 161.135 MHz ✔ control |
| 11 | B11 | 233 MGTREFCLK1 | — ✔ control |

All four controls read as predicted, so the rest is trustworthy.

`AK11` and `AV11` carry the 100 MHz PCIe reference clock, with counts identical to the
cycle — one oscillator fanned out to two quads, which is how a x16 endpoint gets a
reference into every quad it spans.

**Do not read 2.03 MHz or 294.9 MHz as clocks.** An unconnected differential GT input
floats, its buffer output oscillates, and a counter faithfully counts the result. Those
mean "nothing connected".

## Adding candidates

Extend the `refclk_p`/`refclk_n` vectors in `rtl/clk_probe_top.v`, add pins to
`xdc/clk_probe.xdc` and a probe to the VIO in `tcl/prj.tcl`, keeping `N_PROBES` in step.
Keep at least one known-live and one known-dead control in the set.
