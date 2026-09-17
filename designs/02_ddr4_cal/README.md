# 02 — DDR4 calibration and memory test

Brings up all four DDR4 channels and proves each one stores data, with no PCIe and no
host software involved. If this design passes and a later design with memory fails, the
memory is not the problem.

## Build and run

```bash
./compile.sh                       # -> ./output_ddr4_cal_<date>/
```

```bash
# find the right cable first -- see below for why this is not optional
vivado -nojournal -nolog -mode batch -source ../../tools/jtag_scan.tcl

vivado -nojournal -nolog -mode batch -source ../../tools/program.tcl \
       -tclargs <target> output_ddr4_cal_<date>/ddr4_cal.bit

# calibration only -- works on any design containing a MIG, no .ltx needed
vivado -nojournal -nolog -mode batch -source ../../tools/check_ddr4_cal.tcl \
       -tclargs <target>
```

`program.tcl` picks up the `.ltx` sitting beside the bitstream on its own; without it
Hardware Manager can see that a VIO exists but cannot resolve its probes, so the design
looks like it has none.

The target is never defaulted anywhere in this repository. On a machine with more than
one cable attached, programming target 0 does not fail — it succeeds, on the wrong
board.

## Two kinds of evidence

The design reports calibration and a data test separately, because they fail
differently and one does not imply the other.

**Calibration** means the controller trained its timing against the DRAM. Every DDR4 MIG
carries its own calibration engine regardless of whether debug signals are enabled, and
Hardware Manager reads it over the debug hub — which is why `check_ddr4_cal.tcl` works on
a design with no ILA in it.

**The BIST** writes a pattern over the AXI port and reads it back. This is the part
calibration cannot tell you: a channel with a swapped address line trains perfectly and
then aliases, storing data at the wrong place and returning the wrong word. The pattern
is derived from the address rather than being a constant, so a read that lands in the
wrong place fails instead of passing by luck.

The test walks memory two ways in one pass:

| Half of the index range | Covers | Catches |
|---|---|---|
| dense, 64 B apart from 0x8000 | 256 KB contiguous | neighbouring-column interference, byte-lane faults |
| sparse, 1 MB apart from 0 | the full 4 GB | stuck or swapped high address lines |

Either walk alone has a blind spot the other covers. The two ranges are deliberately
disjoint — the dense walk starts at 0x8000 so it sits between the first two sparse
points, because if both started at zero the sparse pass would overwrite the dense pass's
first word and report a failure on a perfectly good channel.

## Reading the result

Without a computer: the LEDs. Low nibble is per-channel calibration, high nibble is
per-channel BIST pass. All eight lit means all four channels work.

In Hardware Manager, the VIO carries the same two nibbles plus the detail: per-channel
error count, the first failing address, a busy flag, and a latched ECC interrupt. Set `probe_out0` to 1 to start the test; it runs on every channel that has finished
calibrating. It is a level rather than a pulse, so set it back to 0 before starting
again — a channel that is already done ignores a start that never went low.

The ECC interrupt is latched deliberately. It arrives as a pulse a few clocks wide, and
a VIO samples only when refreshed, so without a latch the most interesting failure the
memory can produce would leave no trace.

## Memory configuration

72 bits wide with ECC, which is how the board is populated — eight x16 devices for data
plus one more for check bits. Enabling ECC forces the data mask off (`NO_DM_NO_DBI`): the
controller cannot mask part of a write and maintain check bits over it.

That setting changes what the controller *drives*, not the port list. `c*_ddr4_dm_dbi_n`
still exists as a 9-bit inout and those pins are routed on this board, so the top level
declares them and `xdc/ddr4_c*.xdc` constrains them.

The rest of the configuration — part number, latencies, clock period, address mapping —
is in `tcl/prj.tcl` and is copied from a reference design known to calibrate on this
board. Memory settings are exactly the kind of parameter that yields a design which
builds cleanly and then never trains, so they are worth taking from something that
demonstrably worked.

## Clock domains

Five, and none of them are related: the 100 MHz board clock that runs the VIO, plus one
`ui_clk` per channel from that channel's own PLL. Everything crossing between them goes
through a synchroniser — the start command out, the status flags back. The wide values
are handled with a flag handshake instead of a synchroniser, since `error_count` and
`first_bad_addr` stop changing once `done` rises; a VIO sampling an unsynchronised
counter can return a number that never existed, which on an error count is the kind of
wrong that gets believed.
