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
| PCIe refclk / PERST / link LED pins | ❓ | — | must be established on hardware — see below |
| BRAM over DMA | ❌ | — | — |
| URAM over DMA | ❌ | — | — |
| DDR4 channels 0-3 (16 GB) | ❌ | — | design not yet written |
| DDR4 pinout | ❓ | — | not established here. 4 channels × ~120 pins must be determined before a MIG can be built |
| DDR4 calibration status | ❌ | — | — |
| AXI-Lite GPIO / user LEDs | ❓ | — | LED pin assignments not established here |
| QSPI flash | ❓ | — | — |
| XDMA driver build on kernel 6.8 | ✅ | `third_party/dma_ip_drivers` | builds clean **unpatched** on 6.8.0-138 (2026-09-17). Current upstream already carries the 6.3/6.4 guards; no patch needed |
| Main board I2C | ❓ | — | — |
| 100G NIC | ❌ | — | separate repository, not yet started |

## What is established, and how

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
