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
| ⚠️ | Works, with a limitation worth knowing about |
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
| PCIe link trains | ✅ | `designs/01_golden_pcie` | **enumerates on this host** as `10ee:903f`, `LnkSta: Speed 8GT/s (ok)` (2026-09-17). BAR sizes as configured: 512 KB register window, 64 KB XDMA config. WNS +0.165 ns, 0 critical warnings |
| PCIe link width | ⚠️ | `designs/01_golden_pcie` | trains at **x8, not x16** — but the limit is the slot, not the card. The upstream PEX 8747 port is itself `LnkCap: Width x8` and reports `x8 (ok)`; the kernel names it explicitly: "limited by 8.0 GT/s PCIe x8 link at 0000:18:10.0". The endpoint advertises x16 |
| PCIe BAR assignment | ❌ | `designs/01_golden_pcie` | **blocked on a host reboot.** The card enumerates but gets no memory regions: the firmware sized the bridge window at boot with nothing behind that port, so there is no space to assign. `dmesg`: "bridge window [mem size 0x00100000]: can't assign; no space". Nothing can be tested from the host until this is resolved |
| PCIe reference clock | ✅ | `designs/00_clk_probe` | `AK11`/`AK10` (bank 226 MGTREFCLK1) measured at 100.0016 MHz; `AV11`/`AV10` carries the same oscillator (2026-09-17) |
| PCIe PERST | ✅ | `xdc/pcie.xdc` | `AR26` is the device's own `PERSTN0` pin — named by the silicon, not chosen from general-purpose pins. I/O standard still asserted rather than measured; enumeration is its test |
| PCIe lane mapping | ✅ | `designs/01_golden_pcie` | confirmed twice over: the pin table is internally consistent (every lane's RX and TX on one channel, no gaps), and with the lane pins left **unconstrained** the tool independently placed the endpoint on exactly those channels — `X1Y16..X1Y31` at `PCIE40E4_X0Y1` |
| PCIe link LED (`BD20`) | ⚙️ | `designs/01_golden_pcie` | driven from `user_lnk_up`; not yet observed lit |
| Reference-clock probe | ✅ | `designs/00_clk_probe` | 12 candidates measured at once; 4 known-state controls all read as predicted. WNS +7.109 ns, 0 critical warnings |
| BRAM over DMA | ⚙️ | `designs/01_golden_pcie` | 64 KB at `0xC000_0000`; host test written, not yet run |
| URAM over DMA | ⚙️ | `designs/01_golden_pcie` | 64 KB at `0xC001_0000`. Synthesis reports **8 URAM** primitives, so it is genuinely UltraRAM rather than block RAM silently substituted |
| DDR4 channels 0-3 calibrate | ✅ | vendor reference bitstream | all 4 MIGs: `CALIBRATION_FAIL.STATUS=FALSE`, stage `NONE`, 15 stages PASS / 12 SKIP, "No errors detected during calibration" (2026-09-17) |
| DDR4 via our own MIG design | ✅ | `designs/02_ddr4_cal` | **all 4 channels calibrate and pass a memory test on this board** (2026-09-17). 15 stages PASS / 12 SKIP per channel, stage `NONE`, no errors. BIST: 8192 writes + 8192 reads per channel, 0 errors, no ECC events. WNS +0.049 ns, WHS +0.010 ns, 0 critical warnings |
| DDR4 read/write data path | ✅ | `designs/02_ddr4_cal` | dense walk (256 KB contiguous) plus sparse walk (1 MB stride across the full 4 GB), address-derived pattern. All four channels `pass=1`, `errors=0`. Verified from a freshly programmed device, so the result is not a stale latch |
| DDR4 pinout, 4 channels | ✅ | `xdc/ddr4_c[0-3].xdc` | 468 pins, now 117 per channel including the data mask. The identical assignment calibrates all 4 channels on this board (2026-09-17) |
| DDR4 channel-to-SLR mapping | ✅ | `designs/02_ddr4_cal` | each channel's I/O **and** all ~49,700 of its controller cells land in the matching SLR, no spillover. `cN` really does mean SLR*n* |
| DDR4 calibration readout | ✅ | Hardware Manager | `get_hw_migs` reports all 4 cores and per-stage status over JTAG, with no `.ltx` required |
| AXI-Lite GPIO / user LEDs | ⚙️ | `designs/01_golden_pcie` | 8 LEDs on bank 64, validated against the device and consistent with that bank's 1.2 V; walked from the host by `host/tests/test_registers.py`, not yet watched |
| User interrupts | ⚙️ | `designs/01_golden_pcie` | host raises its own via GPIO channel 2 and waits on `/dev/xdma0_events_0`; test written, not yet run |
| XVC (JTAG over PCIe) | ⚙️ | `designs/01_golden_pcie` | debug bridge at `0x0004_0000`, which is already the driver's default `xvc_bar_offset` |
| QSPI flash | ❓ | — | needs no pin constraints — the config bank is fixed and `axi_quad_spi` reaches it through `STARTUPE3`. The flash part is still unidentified |
| XDMA driver build on kernel 6.8 | ✅ | `third_party/dma_ip_drivers` | builds clean **unpatched** on 6.8.0-138 (2026-09-17). Current upstream already carries the 6.3/6.4 guards; no patch needed |
| Main board I2C | ❓ | — | genuinely unknown. The assignment in circulation points at cage 1's I2C pins with SCL/SDA swapped; see [docs/board-facts.md](docs/board-facts.md) |
| Board pin assignments | ✅ | `xdc/` | 534 assignments checked against the device package database — existence, role, collisions, bank voltage, differential pairing, transceiver lane consistency. Runs in CI |
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

That work is now largely done, and the method is recorded rather than just the answers.
`xdc/tools/dump_package_pins.tcl` exports what the device says about every package pin,
and `xdc/tools/validate_pins.py` checks every assignment against it — which is what
turned the remaining question marks into either facts or explicit unknowns.

What is left is the last category: single-ended signals whose pins are assigned and
device-validated but have never been *watched*. The eight user LEDs and the PCIe link LED
are assigned, in the right bank, at the right voltage — and nobody has yet seen one light
up. `designs/01_golden_pcie` walks a bit across them from the host, which is the test;
it needs a person looking at the card.

The genuinely unknown one is the main board I2C bus. See
[docs/board-facts.md](docs/board-facts.md) for why the assignment in circulation cannot
be right.

## Build status under Vivado 2025.2

| Design | Builds | Notes |
|---|---|---|
| `designs/00_clk_probe` | ✅ | WNS +7.109 ns, WHS +0.002 ns, zero critical warnings |
| `designs/01_golden_pcie` | ✅ | WNS +0.165 ns, WHS +0.010 ns, 0 critical warnings. No block design — every IP is created from the live catalog in `tcl/prj.tcl` |
| `designs/02_ddr4_cal` | ✅ | WNS +0.049 ns, WHS +0.010 ns, 0 critical warnings. Setup margin is thin at 49 ps — worth watching if anything is added |
| `designs/03_qsfp_ibert` | ✅ | `import_ip` + explicit `upgrade_ip`, so it survives IP version changes; writes its own `.ltx` |

## Toolchain notes

`xilinx.com:ip:axi_interconnect` was **removed** from the Vivado 2025.x IP catalog; its
replacement `smartconnect:1.0` has a different clock/reset pin model. `xdma` moved from
4.1 to 4.2. Designs here resolve IP versions from the live catalog rather than pinning
them — see [docs/toolchain.md](docs/toolchain.md).
