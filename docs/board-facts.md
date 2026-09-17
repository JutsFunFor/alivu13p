# Measured board facts

The ALIVU13P ships with no documentation. Everything on this page was established by
querying the part in Vivado or by measuring the board. Nothing here is assumed, and
anything not yet established is listed as open rather than guessed.

## QSFP28 / GTY — established

Two cages, on different GTY banks. Quad and refclk assignment was confirmed by querying
`xcvu13p-fhgb2104-2L-e` directly and by measuring the clocks on the board.

| Cage | Bank | GT quad | Refclk | Pins | Measured |
|---|---|---|---|---|---|
| `up_qsfp` (far from PCIe fingers) | 233 | QUAD27 | `MGTREFCLK0_233` | D11 / D10 | 161.13 MHz ✔ |
| `dn_qsfp` (near PCIe fingers) | 229 | QUAD23 | `MGTREFCLK0_229` | Y11 / Y10 | 161.13 MHz ✔ |

**`MGTREFCLK1` is dead on both banks** — `B11`/`B10` and `V11`/`V10` have no oscillator
routed. Measured, not inferred. Do not select it; a design that does will build happily
and then never produce a link.

161.1328125 MHz is the standard 25G/100G Ethernet reference: ×160 gives 25.78125 Gbps,
×80 gives 12.890625 Gbps.

## System clock — established

100 MHz differential on `AY23` / `BA23`, bank 64, `DIFF_SSTL12`.

Bank 64 runs at 1.2 V, which has a consequence worth knowing: `DIFF_TERM` must be
`FALSE` on this input. `DIFF_TERM_ADV` is only legal for I/O standards with internal
differential termination such as LVDS, so setting it `TRUE` on a `DIFF_SSTL12` port
fails DRC `PORTPROP-6` before placement.

## The QSFP module-control trap — established by construction

If a design does not declare `resetl` / `lpmode` / `i2c` / `modprsl` / `intl` as ports,
those pins fall to `BITSTREAM.CONFIG.UNUSEDPIN`, which defaults to **`Pulldown`**.

`ResetL` is **active low**. A pulldown therefore holds the module in permanent reset.

Passive copper DACs do not care — they have no module logic to reset, so they link
anyway, which is exactly why this defect survives testing. Optical, AOC and retimed
modules never come up. Any design intended for real optics must drive `resetl` high and
`lpmode` low as genuine ports.

## Part identification — established

`xcvu13p-fhgb2104-2L-e`.

The `L` means `Vccint` may be either 0.72 V or 0.85 V. This board runs 0.85 V, readable
from SysMon, so `-2L-e` and `-2-e` behave identically in Vivado; `-2L-e` is the more
precise choice.

It matters for PCIe: at 0.72 V the `PCIE4` core clock is capped at 250 MHz, which is not
enough for Gen3 x16.

## DDR4 — established

Four independent channels, one per SLR, each 72 bits wide: `MT40A512M16JY-083E` for
[63:0] plus `MT40A1G8WE-083E` for the [71:64] ECC lane.

| Channel | SLR | Refclk | `reset_n` | `act_n` |
|---|---|---|---|---|
| c0 | SLR0 | AE31 | Y32 | Y31 |
| c1 | SLR1 | AW14 | AL15 | AR13 |
| c2 | SLR2 | J26 | B29 | A28 |
| c3 | SLR3 | G25 | B24 | A22 |

Full pin assignment is in `xdc/ddr4_c[0-3].xdc`, 117 pins per channel.

**All four channels calibrate on this board** (2026-09-17). Verified by loading the board
vendor's four-channel reference bitstream and reading the MIG calibration engines over
JTAG: every channel reports `CALIBRATION_FAIL.STATUS = FALSE`, failing stage `NONE`, and
"No errors detected during calibration", with 15 calibration stages passing and 12
skipped. The skipped stages are the DBI, VREF-training and multi-rank ones, which this
configuration does not use — a skip there is normal, not a partial result.

Reproduce it with:

```bash
vivado -nojournal -nolog -mode batch -source tools/check_ddr4_cal.tcl -tclargs <target>
```

No `.ltx` is needed. Every DDR4 MIG instantiates its own calibration engine regardless of
the IP's "Debug Signals" option, and Hardware Manager reads it over the debug hub — so
calibration is observable even in a design containing no ILA.

That result also validates the pin assignment itself: these exact pins drive four working
memory channels on this board.

## JTAG — check which board you are talking to

`get_hw_targets` can return several cables, and `[lindex [get_hw_targets] 0]` is only
right when exactly one is attached. On the machine this repository was developed on, the
first target is a completely different board (an `xcku115`); the ALIVU13P is the second.
Programming the wrong device does not fail — it succeeds, on the wrong board.

```bash
vivado -nojournal -nolog -mode batch -source tools/jtag_scan.tcl
```

lists every target with the devices behind it and their `DONE` status. Use the printed
target string explicitly in any programming or debug script.

## Open — not yet established

These are needed by designs not yet written. They are listed as open rather than
assumed, because an unverified pin assignment produces a design that builds cleanly and
then silently does not work.

| Signal group | Pins needed | How to establish |
|---|---|---|
| PCIe refclk | 1 diff pair | Constrained by the device: a x16 endpoint can only use the GTY quads wired to its block location, and the refclk must be one of that quad's `MGTREFCLK` pins. That narrows it to a few candidates; the link training is the pass/fail test |
| PCIe PERST | 1 | Probe, or infer from which candidate lets the endpoint come out of reset |
| PCIe link LED | 1 | Drive each candidate and look at the board |
| User LEDs | 8 | Drive each candidate and look at the board |
| QSPI | 4-6 | Config-bank pins are largely fixed by the device; confirm against the flash part |
| Main board I2C | 2 | Probe |
| QSFP sideband (ModPrsL, IntL) | 2 per cage | Read back with and without a module inserted — presence detect is self-checking |

### Method

The reliable technique for single-ended signals is to drive each candidate pin from the
FPGA in a known pattern and observe it externally, or to read it back and compare
against a known board state — inserting and removing a QSFP module, for instance, gives
a self-checking test for `ModPrsL`.

For differential and hard-block signals, start from what the device permits: querying the
part in Vivado for the quads and reference clocks reachable from a given hard-block
location usually reduces the search to a handful of options, and the interface either
comes up or it does not.
