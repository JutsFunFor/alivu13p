# ALIVU13P interface status

What works on this board, what has been observed, and how to reproduce it.

**Rules for this table.** A row is ✅ only when it was observed on real hardware and the
evidence says how. "It builds" is not verification — that is ⚙️. Anything not yet
established in this repository is ❌ or ❓, even if it is widely assumed to be true.
Anything untestable with the hardware on hand is 🚫, which is a limitation, not a
failure.

| | Meaning |
|---|---|
| ✅ | Verified on hardware, evidence recorded |
| ⚙️ | Builds clean, not yet hardware-verified |
| ❓ | Not yet established here — must be determined before it can be relied on |
| 🚫 | Not testable with available hardware |
| ❌ | Not started |

Toolchain: **Vivado 2025.2**, part `xcvu13p-fhgb2104-2L-e`, host kernel 6.8.0-138.

Test hardware on hand: one Xilinx Platform Cable USB II, one passive QSFP28 DAC cable.

## Interfaces

| Interface | State | Design | Evidence |
|---|---|---|---|
| QSFP28 GTY refclk map (both cages) | ✅ | `designs/03_qsfp_ibert` | 161.13 MHz measured on `MGTREFCLK0` of banks 233 and 229 |
| `MGTREFCLK1`, both banks | ✅ | `designs/03_qsfp_ibert` | measured dead — no oscillator routed. Do not select |
| QSFP28 8-lane link @ 12.89 Gbps | ⚙️ | `designs/03_qsfp_ibert` | builds and writes `.ltx`; eye/BER not yet run on hardware |
| QSFP module control (ResetL/LPMode) | ⚙️ | `designs/03_qsfp_ibert` | driven as real ports — ResetL high, LPMode low |
| Optical / AOC modules | 🚫 | — | only a passive DAC is available. DACs link regardless of ResetL, so the module-control path cannot be proven here |
| System clock 100 MHz (AY23/BA23) | ✅ | `designs/03_qsfp_ibert` | drives the IBERT debug hub; design builds and meets timing |
| PCIe Gen3 x16 (XDMA) | ❌ | — | design not yet written |
| PCIe reference clock | ✅ | `designs/00_clk_probe` | `AK11`/`AK10` (bank 226 MGTREFCLK1) measured at 100.0016 MHz; `AV11`/`AV10` carries the same oscillator (2026-09-17) |
| PCIe PERST / link LED pins | ❓ | — | must be probed on hardware |
| Reference-clock probe | ✅ | `designs/00_clk_probe` | 12 candidates measured at once; 4 known-state controls all read as predicted. WNS +7.109 ns, 0 critical warnings |
| BRAM over DMA | ❌ | — | — |
| URAM over DMA | ❌ | — | — |
| DDR4 channels 0-3 calibrate | ✅ | vendor reference bitstream | all 4 MIGs: `CALIBRATION_FAIL.STATUS=FALSE`, stage `NONE`, 15 stages PASS / 12 SKIP, "No errors detected during calibration" (2026-09-17) |
| DDR4 via our own MIG design | ❌ | — | design not yet written |
| DDR4 pinout, 4 channels | ✅ | `xdc/ddr4_c[0-3].xdc` | 468 pins; the identical assignment calibrates all 4 channels on this board (2026-09-17). Not yet exercised from our own design |
| DDR4 calibration readout | ✅ | Hardware Manager | `get_hw_migs` reports all 4 cores and per-stage status over JTAG, with no `.ltx` required |
| AXI-Lite GPIO / user LEDs | ❓ | — | LED pin assignments not established here |
| QSPI flash | ❓ | — | — |
| XDMA driver build on kernel 6.8 | ✅ | `third_party/dma_ip_drivers` | builds clean **unpatched** on 6.8.0-138 (2026-09-17). Current upstream already carries the 6.3/6.4 guards; no patch needed |
| Main board I2C | ❓ | — | — |
| 100G NIC | ❌ | — | separate repository, not yet started |

## What is established, and how

### PCIe hard blocks — from the device

Four `PCIE40E4` sites, one per SLR: `X0Y0`=SLR0, `X0Y1`=SLR1, `X0Y2`=SLR2, `X0Y3`=SLR3.
A x16 endpoint consumes four adjacent GTY quads in its own SLR, so the choice of hard
block fixes which quads and therefore which reference clocks are reachable — 8 candidate
pin pairs per block. For `X0Y1` those are banks 224-227:

| Bank | MGTREFCLK0 (P/N) | MGTREFCLK1 (P/N) |
|---|---|---|
| 224 | AW9 / AW8 | AV11 / AV10 |
| 225 | AT11 / AT10 | AP11 / AP10 |
| 226 | AM11 / AM10 | **AK11 / AK10** |
| 227 | AH11 / AH10 | AF11 / AF10 |

Which of the eight the board actually wires is a measurement, not a choice — see below.

### DDR4 — from the board vendor's reference project

| Channel | SLR | Refclk | `reset_n` | `act_n` |
|---|---|---|---|---|
| c0 | SLR0 | AE31 | Y32 | Y31 |
| c1 | SLR1 | AW14 | AL15 | AR13 |
| c2 | SLR2 | J26 | B29 | A28 |
| c3 | SLR3 | G25 | B24 | A22 |

All four are 72-bit: `MT40A512M16JY-083E` for [63:0] plus `MT40A1G8WE-083E` for the
[71:64] ECC lane. Channel numbering is pinned to the SLR, since physical placement is
what matters when floorplanning four controllers across a four-die part.

### QSFP / GTY — measured

The GTY side is settled because the IBERT design both queries the part and runs against
the real clocks:

| Cage | Bank | GT quad | Refclk | Pins |
|---|---|---|---|---|
| `up_qsfp` (far from PCIe fingers) | 233 | QUAD27 | `MGTREFCLK0_233` | D11 / D10 |
| `dn_qsfp` (near PCIe fingers) | 229 | QUAD23 | `MGTREFCLK0_229` | Y11 / Y10 |

System clock: 100 MHz differential, AY23 / BA23, bank 64, `DIFF_SSTL12`.

## What still has to be established

This board ships with no pinout documentation, so every signal below has to be pinned
down before the design that uses it can be trusted. Two methods:

1. **Constrained by the device.** Some assignments are not free choices — a PCIe x16
   endpoint at a given block location can only use the GTY quads wired to it, and the
   refclk must be one of that quad's `MGTREFCLK` pins. Querying the part narrows the
   candidates to a handful, and the link either trains or it does not.
2. **Probed on the board.** For single-ended control signals (PERST, LEDs, I2C, module
   status) the reliable method is to drive each candidate pin from the FPGA and observe
   it, or to read it back — the same technique that established the GTY clock map.

Order of work: PCIe first (refclk, PERST, link LED — a handful of pins, and the link
training is its own pass/fail signal), then the user LEDs and QSPI, then DDR4, which is
by far the largest pin count and the one worth automating.

## Build status under Vivado 2025.2

| Design | Builds | Notes |
|---|---|---|
| `designs/03_qsfp_ibert` | ✅ | `import_ip` + explicit `upgrade_ip`, so it survives IP version changes; writes its own `.ltx` |

## Toolchain notes

`xilinx.com:ip:axi_interconnect` was **removed** from the Vivado 2025.x IP catalog; its
replacement `smartconnect:1.0` has a different clock/reset pin model. `xdma` moved from
4.1 to 4.2. Designs here resolve IP versions from the live catalog rather than pinning
them — see [docs/toolchain.md](docs/toolchain.md).
