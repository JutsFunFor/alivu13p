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

### The controller configuration that calibrates

Taken from the reference design that was verified above, so this is a known-good set
rather than a plausible one:

| Parameter | Value |
|---|---|
| Memory part | `MT40A512M16HA-083E`, components, 1.2 V |
| Data width | 72, **ECC enabled** |
| Data mask | `NO_DM_NO_DBI` |
| CAS latency / CAS write latency | 16 / 12 |
| Input clock period | 2499 ps (≈400 MHz on `c*_sys_clk_p`) |
| PHY clock ratio | 4:1 |
| AXI data / address / ID width | 512 / 32 / 1 |
| Address mapping | `ROW_COLUMN_BANK` |
| ODT / output impedance | RZQ/6 / RZQ/7 |
| Burst | length 8, sequential, `RD_PRI_REG` arbitration |

Note the interaction between the last two rows: **enabling ECC forces `NO_DM_NO_DBI`**,
because the controller cannot mask part of a write and maintain check bits over it.

That changes what the controller *drives*, not the port list. `c*_ddr4_dm_dbi_n` is still
present as a 9-bit inout whatever the data-mask setting says — checked against the
instantiation template of a MIG customised exactly this way. Those pins are routed on
this board, so `xdc/ddr4_c[0-3].xdc` constrains all 117 per channel, data mask included.

The reference clock is per channel and runs at ~400 MHz, which is distinct from the
100 MHz board clock on AY23.

Reproduce the calibration check with:

```bash
vivado -nojournal -nolog -mode batch -source tools/check_ddr4_cal.tcl -tclargs <target>
```

No `.ltx` is needed. Every DDR4 MIG instantiates its own calibration engine regardless of
the IP's "Debug Signals" option, and Hardware Manager reads it over the debug hub — so
calibration is observable even in a design containing no ILA.

That result also validates the pin assignment itself: these exact pins drive four working
memory channels on this board.

## PCIe — measured and cross-checked

Measured with `designs/00_clk_probe`, which counts twelve candidate reference clocks at
once against the 100 MHz board clock (2026-09-17).

| Pin (P/N) | Bank / refclk | Measured | Reading |
|---|---|---|---|
| AW9 / AW8 | 224 MGTREFCLK0 | 0 | no clock |
| **AV11 / AV10** | **224 MGTREFCLK1** | **100.0016 MHz** | **live** |
| AT11 / AT10 | 225 MGTREFCLK0 | 0 | no clock |
| AP11 / AP10 | 225 MGTREFCLK1 | 2.03 MHz | noise, see below |
| AM11 / AM10 | 226 MGTREFCLK0 | 0 | no clock |
| **AK11 / AK10** | **226 MGTREFCLK1** | **100.0016 MHz** | **live** |
| AH11 / AH10 | 227 MGTREFCLK0 | 99.846 MHz | live, different source |
| AF11 / AF10 | 227 MGTREFCLK1 | 294.9 MHz | noise, see below |

**`AK11`/`AK10` and `AV11`/`AV10` carry the 100 MHz PCIe reference clock.** Their counts
are identical to the cycle, so this is one oscillator fanned out to two quads rather than
two independent sources — which is how a x16 endpoint gets a reference into every quad it
spans.

`AH11` reads 99.846 MHz, 0.15% low, so it is a genuinely different source rather than the
same clock. Worth identifying before relying on it.

Two candidates report implausible values: 2.03 MHz and 294.9 MHz. An unconnected
differential GT input is not held anywhere, so its buffer output drifts and oscillates,
and a frequency counter dutifully counts the result. Read those as "nothing connected",
not as a clock. It is the reason this design carries controls.

### PERST, and the one pin the device names for you

`AR26` is not a guess among general-purpose pins: the device's own pin function for it is
`IO_T3U_N12_PERSTN0_65` — the silicon calls it PERST. (`AN27` is `PERSTN1`, doubling as
`I2C_SDA`.) A pin the part names for the job is much stronger evidence than a plausible
general-purpose pin would be.

The I/O standard is the weak link. Bank 65's VCCO cannot be read out of the part, and
PERST is the only signal placed in that bank here, so there is no second port to
cross-check against — `LVCMOS12` is asserted by analogy with bank 64 next door. If it is
wrong the endpoint never leaves reset and never enumerates, which makes host enumeration
itself the test of this line.

### Lane mapping — from the device, not the board

The PCIE40E4 hard block is wired to a fixed set of transceiver channels, so the block
location plus the link width determine the lane placement completely. For `X0Y1` at x16
the result is banks 227, 226, 225, 224 and channels `GTYE4_CHANNEL_X1Y31` down to
`X1Y16`, lane *n* on channel `X1Y(31-n)`.

Two properties make that mapping trustworthy without probing anything. Every lane's RX
and TX pins resolve to the *same* channel site, which is a sixteen-way consistency check
that a mis-transcribed list would fail; and the sixteen channels run monotonically with
no gap, where an error would show a discontinuity. Both are checked mechanically by
`xdc/tools/validate_pins.py`.

The full table is at the end of `xdc/pcie.xdc`, deliberately commented out. Constraining
the lanes as well as the block location creates a second source of truth that has to
agree with the first forever, and when they disagree the tool obeys the constraints and
the link fails.

### Device ID

The XDMA IP derives its PCI device ID from the link configuration. x16 Gen3 gives
**`0x903F`**; `0x9038` is the x8 Gen3 value. The distinction matters because the host
driver binds on the ID and silently ignores anything outside its table — which presents
exactly like the card being absent. `0x903f` is in the table shipped with the Xilinx
XDMA driver (`XDMA/linux-kernel/xdma/xdma_mod.c`), so nothing needs patching.

### Trusting the measurement

Four of the twelve probes are controls, not unknowns: two reference clocks already known
to carry 161.13 MHz and two known to be dead. All four read exactly as expected
(161.132 / 161.135 MHz and zero), which is what makes the other eight readings credible.
A probe design without controls cannot distinguish "this pin is dead" from "my counter is
broken".

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

| Signal group | Pins | State | How to settle it |
|---|---|---|---|
| User LEDs | 8, bank 64 | assigned, not yet observed | `designs/01_golden_pcie` walks a bit across them — watch the card |
| PCIe link LED | `BD20` | assigned, not yet observed | driven from `user_lnk_up`; lights when the link trains |
| QSFP ModPrsL / IntL | 2 per cage, bank 68 | assigned, not yet observed | read back with and without a module inserted — presence detect is self-checking |
| Main board I2C | 2 | **unknown** | see below |
| QSPI | — | not needed as pins | the config bank is fixed by the device and `axi_quad_spi` reaches it through `STARTUPE3`; what is still unknown is the flash part |

### Main board I2C is genuinely unknown

Worth stating plainly, because a plausible-looking answer is in circulation. A board
constraint file found in the wild assigns `main_iic` to `BD8`/`BC12` — which are the
bank-68 pins belonging to **cage 1's module I2C**, with SCL and SDA swapped relative to
that use as well. Its own author left a note saying the binding was wrong and that the
optical interface's I2C was being borrowed as a stopgap.

Two independent readings agree that `BD8`/`BC12` belong to the cage: each cage has a
complete, non-overlapping six-signal sideband group in bank 68, and cage 1's group is
only complete if those two pins are its I2C. So this repository assigns them to the cage
and leaves the main bus unassigned rather than carrying a known-wrong constraint that
would collide the moment both were used.

`xdc/tools/validate_pins.py` checks for exactly this class of mistake — one package pin
claimed by two different ports — across every file in `xdc/`.

### Method

The reliable technique for single-ended signals is to drive each candidate pin from the
FPGA in a known pattern and observe it externally, or to read it back and compare
against a known board state — inserting and removing a QSFP module, for instance, gives
a self-checking test for `ModPrsL`.

For differential and hard-block signals, start from what the device permits: querying the
part in Vivado for the quads and reference clocks reachable from a given hard-block
location usually reduces the search to a handful of options, and the interface either
comes up or it does not.
