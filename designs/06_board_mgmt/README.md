# 06 — board management: configuration flash and QSFP module I2C

Two board-level interfaces that no other design here touches, both reachable from the
host over PCIe with no JTAG cable attached:

- the **SPI configuration flash**, through `STARTUPE3` — the same pins the FPGA booted
  from, which is why the interface needs no pin constraints at all;
- each **QSFP28 cage's I2C bus**, which is how a module says what it is (SFF-8636).

Both answer questions this repository could not answer before: which flash part is
fitted, and whether the cage I2C pins are the pins `xdc/qsfp_sideband.xdc` claims.

The memory-mapped path carries the same 64 KiB BRAM at `0xC000_0000` as
`01_golden_pcie`, at the same address and geometry, so the existing DMA tests run
against this bitstream unchanged.

| Interface | Address | Purpose |
|---|---:|---|
| DMA | `0xC000_0000` | 64 KiB BRAM, 512-bit |
| AXI-Lite | `0x0001_0000` | configuration flash (AXI Quad SPI, via STARTUPE3) |
| AXI-Lite | `0x0003_0000` | GPIO: eight user LEDs, design identity |
| AXI-Lite | `0x0004_0000` | AXI debug bridge (XVC) |
| AXI-Lite | `0x0005_0000` | cage 0 I2C |
| AXI-Lite | `0x0006_0000` | cage 1 I2C |
| AXI-Lite | `0x0007_0000` | GPIO: QSFP sideband |

Identity at `0x0003_0008` reads `0x424D0101`. The low bit is End Of Startup from the SPI
controller's `STARTUPE3` rather than a constant, so the identity read also proves the
startup block is present and clocked. The host test refuses any other value.

## The flash size in `xdc/bitstream.xdc` is an assumption this design tests

That file sets `BITSTREAM.CONFIG.SPI_32BIT_ADDR YES`, with a comment saying the flash is
larger than 128 Mb and so cannot be reached with three address bytes. Nothing had ever
checked that. The JEDEC capacity byte read here is the check: capacity is log2 of the
size in bytes for essentially every vendor, so `0x18` is 16 MiB (128 Mb) and `0x19` is
32 MiB. A part at `0x18` or below does not need 32-bit addressing, and a boot image
built on that assumption would be reading from addresses the flash truncates.

## The sideband defaults matter

Sideband GPIO channel 1 resets to `0x05`: **both `ResetL` high**, both `LPMode` low. That
happens at configuration, with no host software involved, which is the whole point —
`ResetL` is active low, and a design that leaves these pins undeclared lets them fall to
`BITSTREAM.CONFIG.UNUSEDPIN`, a pulldown, and holds every module in permanent reset.
Passive copper DACs link anyway and hide it; anything with electronics in it never comes
up. See the end of `xdc/qsfp_sideband.xdc`.

| bit | channel 1 (out) | channel 2 (in) |
|---:|---|---|
| 0 | cage 0 `ResetL` | cage 0 `ModPrsL` (low = module seated) |
| 1 | cage 0 `LPMode` | cage 0 `IntL` |
| 2 | cage 1 `ResetL` | cage 1 `ModPrsL` |
| 3 | cage 1 `LPMode` | cage 1 `IntL` |
| 4–7 | cage LEDs: y0, y1, g0, g1 | — |

## Build

From the repository root:

```sh
bash designs/06_board_mgmt/compile.sh
```

Outputs land in `designs/06_board_mgmt/output_board_mgmt/`. The build writes utilization,
timing, DRC and CDC reports and refuses to export a bitstream if setup or hold timing
fails.

## Hardware test

```sh
vivado -mode batch -source tools/jtag_scan.tcl          # find the target string
host/pcie_bringup.sh detach
vivado -mode batch -source tools/program.tcl -tclargs \
    <target> designs/06_board_mgmt/output_board_mgmt/board_mgmt.bit
host/pcie_bringup.sh attach
```

Then:

```sh
python3 host/test_board_mgmt.py
python3 host/test_board_mgmt.py --leds     # also walks a bit across the eight LEDs
```

Everything the script does is read-only: a JEDEC ID read (`0x9F`) and a flash status
read (`0x05`), and EEPROM reads at I2C address `0x50`. It does not write to the flash or
to a module.

An empty cage is not a failure — it is the expected state for a board with one cable.
These are failures, and each one names a specific wiring fault:

- a flash ID of all `00` or all `FF` — the controller reached no device;
- a cage reporting a module present whose EEPROM will not answer — `ModPrsL` and the I2C
  bus disagree, so one of the two pin assignments is wrong;
- a cage reporting *empty* where something still acknowledges at `0x50` — the same
  disagreement, the other way round;
- an EEPROM that acknowledges and then returns all `00` or all `FF`.

## What this design does not do

No transceivers: `xdc/qsfp_gty.xdc` is deliberately not part of it, and the 8 lanes stay
undeclared. Link, eye and BER belong to `03_qsfp_ibert`. Nothing here writes flash
either — identifying the part is the prerequisite for a QSPI boot image, not the image
itself.
