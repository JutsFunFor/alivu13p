# 04 — PCIe DMA to ECC DDR4

XDMA Gen3 x16 connects to **channel 1 / SLR1**, a 4 GiB, 72-bit DDR4 interface
with 64 data bits and ECC. This channel shares the PCIe hard block's SLR.
The DDR4 controller uses the same memory parameters and board pinout as the
four-channel calibration design.

The 512-bit memory path is XDMA → address decoder → asynchronous AXI clock
converter → MIG. The decoder exposes `[0, 0xFFFFFFFF]`; the converter crosses
from the 250 MHz PCIe AXI clock to the approximately 300 MHz MIG UI clock.
AXI IDs, bursts, byte strobes and responses are carried through the converter.

| Interface | Address | Purpose |
|---|---:|---|
| DMA | `0x00000000`–`0xFFFFFFFF` | 4 GiB DDR4 channel 1 |
| AXI-Lite | `0x30000` | Eight LED output bits |
| AXI-Lite | `0x30008` | Identity and status |
| AXI-Lite | `0x40000` | AXI debug bridge |

Status bits `[31:8]` are `0xD40101`, bit 0 is synchronized calibration complete,
bit 1 is a latched ECC interrupt, bit 2 confirms ECC setup completed, and
bit 3 reports an ECC setup AXI error. A ready, error-free value is
`0xD4010105`. A local AXI-Lite sequencer explicitly enables ECC checking and
both interrupt classes; MIG interrupt enable resets to zero. The host test refuses any other design identity. An ECC event
requires reprogramming or a board reset to clear; host DMA reset alone does
not erase that evidence.

Both transport reset outputs assert asynchronously on PCIe AXI reset or MIG
UI reset and release through four local clock stages. MIG system reset uses
PERST. Do not reset either interface in the middle of live DMA.

## Build

From the repository root:

```sh
bash designs/04_pcie_ddr4/compile.sh
```

Outputs are under `designs/04_pcie_ddr4/output_pcie_ddr4/`. The build saves
utilization, timing, DRC and CDC reports and refuses to export a bitstream
when setup or hold timing fails.

## Hardware test

Swapping the bitstream underneath a live PCIe endpoint is the part that
bites. The host must let go of the device *before* it stops existing:

```sh
vivado -mode batch -source tools/jtag_scan.tcl          # find the target string
host/pcie_bringup.sh detach                             # rmmod xdma, remove the endpoint
vivado -mode batch -source tools/program.tcl -tclargs \
    <target> designs/04_pcie_ddr4/output_pcie_ddr4/pcie_ddr4.bit
host/pcie_bringup.sh attach                             # rescan, build and insert the driver
```

The JTAG target is never defaulted, and for a reason: programming the wrong
device does not fail, it succeeds on the wrong board.

**Do not use the golden design's smoke test:** its addresses describe BRAM
and URAM, whereas this design contains DRAM.

```sh
python3 host/test_pcie_ddr4.py          # sparse, partial-write and 64 MiB checks
python3 host/test_pcie_ddr4.py --full   # write and verify every byte of 4 GiB
```

The test destroys memory contents. It writes all blocks before reading them
back, using independent deterministic pseudorandom data per block, so high
address aliasing cannot pass by reading each block immediately after writing.
Partial-write checks compare surrounding bytes as well as the requested
fragment. The script checks calibration and ECC status before and after DMA.

Channels 0, 2 and 3 are not instantiated. The debug bridge is present, but
its presence alone is not verification of XVC operation. QSFP ports and QSPI
boot are outside this design.
