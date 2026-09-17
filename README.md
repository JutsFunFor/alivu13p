# alivu13p

Board support for the **ALIVU13P** — a low-cost ex-datacenter accelerator card built
around the AMD/Xilinx Virtex UltraScale+ **XCVU13P** (`xcvu13p-fhgb2104-2L-e`).

The card is cheap and widely available second-hand, and undocumented. This repository
brings it up on a current toolchain and keeps an honest record of which interfaces have
actually been proven to work, with the evidence attached.

**Start at [STATUS.md](STATUS.md).** Every interface, its state, what was observed, and
when. Nothing is marked verified because it compiled.

## What the board has

| | |
|---|---|
| FPGA | XCVU13P, 4 SLRs, `fhgb2104` package, speed grade `-2L-e` |
| Host interface | PCIe Gen3 x16 edge connector |
| Memory | 4 independent DDR4 channels, 16 GB total |
| Network | 2× QSFP28 cages (GTY bank 233 and bank 229) |
| Config | QSPI flash, JTAG header |
| Indicators | 8 user LEDs, 2 bicolour cage LEDs, a PCIe link LED |

## Layout

```
designs/     FPGA designs, one directory per interface under test
common/      shared build system
xdc/         board constraints, established by measurement
host/        host-side software: driver patches, bring-up and test tooling
docs/        toolchain notes, PCIe bring-up, measured board facts
third_party/ external dependencies (submodules)
```

## Requirements

- **Vivado 2025.2.** The build system takes `vivado` from `PATH` — override with
  `make VIVADO=/path/to/vivado`.
- **Linux host** for the PCIe work. The Xilinx XDMA driver needs
  `host/patches/xdma-kernel-6.8.patch` on kernel 6.3 and newer.

## Designs

| Design | What it proves |
|---|---|
| `designs/03_qsfp_ibert` | QSFP28 physical path — per-lane link, eye scan and BER across both cages, in Hardware Manager |

More are in progress; see [STATUS.md](STATUS.md) for what is built and what is still
being established.

## The PCIe gotcha that catches everyone

The host walks the PCIe bus once, at boot. A card configured over JTAG *afterwards* does
not exist as far as Linux is concerned — nothing is wrong with your design. Either
rescan, or warm-reboot (**not** a power cycle, which wipes the FPGA), or flash the image
to QSPI so the card configures at power-on. See
[docs/pcie-bringup.md](docs/pcie-bringup.md).

## Licence

Apache-2.0 — see [LICENSE](LICENSE). External components keep their own licences and
their headers are left intact; see [THIRD-PARTY.md](THIRD-PARTY.md).
