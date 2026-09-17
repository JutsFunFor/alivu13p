# 03 — QSFP28 IBERT (GTY link / eye / BER)

IBERT design for the two onboard QSFP28 cages. It is **visible in Vivado Hardware
Manager**, giving per-lane link status, eye scans and BER counters — which is what you
want when asking *"does the QSFP physical path actually work?"* rather than *"does my
protocol logic work?"*.

## Build

```bash
./compile.sh                  # -> ./output_ibert_<date>/
./compile.sh ./out 16         # explicit outdir + jobs
```

Then program `output_*/ibert_qsfp.runs/impl_1/*.bit` and open Hardware Manager. The
IBERT core appears automatically under the device (it talks over the debug hub, clocked
by the 100 MHz sysclk). Right-click → *Create Links*, then use the **Links** and
**Eye Scan** tabs.

The build writes an `.ltx` explicitly (`tcl/prj.tcl`). Without it Hardware Manager
cannot resolve the debug cores and the device looks empty.

## Board mapping

GT quad and refclk assignment, confirmed by querying `xcvu13p-fhgb2104-2L-e` directly
and by measuring the reference clocks on the board:

| Cage | Bank | IBERT quad | Refclk source | Pins | Measured |
|---|---|---|---|---|---|
| `up_qsfp` (far from PCIe fingers) | 233 | QUAD27 | `MGTREFCLK0_233` | D11 / D10 | 161.13 MHz ✔ |
| `dn_qsfp` (near PCIe fingers)     | 229 | QUAD23 | `MGTREFCLK0_229` | Y11 / Y10 | 161.13 MHz ✔ |

**`MGTREFCLK1` has no clock on either bank** (B11/B10 and V11/V10) — measured dead, no
oscillator routed. Do not select it.

System clock: 100 MHz differential on AY23 / BA23, bank 64.

## Line rate: 12.890625 Gbps × 8 lanes

`161.1328125 MHz × 80-bit datawidth`, QPLL0, all 8 lanes (both full quads).

**25.78125 Gbps is not usable here.** The IBERT UltraScale GTY IP refuses more than one
lane at that rate:

```
Number of Lanes selected for Custom_1_/_25.78125_Gbps protocol should not exceed 1
```

So full-rate 25G validation of every lane is not possible through IBERT. 12.89 Gbps
still exercises every lane, both cages, the connectors and the cable, which makes it a
good physical-path test.

## QSFP module control pins — important

The design drives, in `src/example_ibert_ultrascale_gty_0.v`:

```verilog
assign qsfp_resetn = 2'b11;   // ResetL is ACTIVE LOW  - release the modules
assign qsfp_lpmode = 2'b00;   // LPMode is ACTIVE HIGH - disable low-power mode
```

This matters more than it looks. If a design does not declare these as ports, the pins
fall to `BITSTREAM.CONFIG.UNUSEDPIN`, which defaults to `Pulldown` — and since **ResetL
is active low**, a pulldown holds the module in permanent reset.

Passive copper DACs do not care; they have no module logic to reset and link anyway.
Optical, AOC and retimed modules never come up. Any design intended to work with real
optics must drive these pins.

## DIFF_TERM on the system clock

`IBUFGDS` is instantiated with `DIFF_TERM("FALSE")`. The vendor example export used
`TRUE`, which sets `DIFF_TERM_ADV` on the port — only legal for I/O standards with
internal differential termination such as LVDS. The 100 MHz clock here is `DIFF_SSTL12`
in 1.2 V bank 64, so `TRUE` fails DRC `PORTPROP-6` before placement.

## What this design does not tell you

- It proves the **physical** path: serialiser, connector, cable, equalisation. It says
  nothing about Ethernet framing, MAC behaviour or protocol logic.
- With a cage-to-cage DAC loopback it exercises both cages at once, but a link failure
  does not by itself say which cage or which end is at fault — swap the cable ends to
  isolate.
