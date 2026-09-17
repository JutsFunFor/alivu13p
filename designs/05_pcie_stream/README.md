# 05 — PCIe AXI-Stream packet loopback

One XDMA H2C stream feeds a 1024-beat, 512-bit AXI-Stream FIFO; its output
feeds the C2H stream. The FIFO stores **64 KiB of payload** plus TKEEP and
TLAST. It uses normal streaming mode, so packets larger than its capacity
flow through without requiring the whole packet to fit.

All datapath logic runs on XDMA's 250 MHz AXI clock. READY propagates
backpressure when the FIFO fills; packet boundaries and byte-valid masks
are retained. No DDR4 or external loopback cable is needed.

| AXI-Lite address | Purpose |
|---:|---|
| `0x30000` | Eight LED output bits |
| `0x30008` | Read-only identity `0x53540101` |
| `0x40000` | AXI debug bridge |

This is a streaming endpoint: character-device offsets are not memory
addresses. Do not run the golden design's memory-mapped DMA tests on it.

## Build and program

```sh
bash designs/05_pcie_stream/compile.sh
```

Outputs are under `designs/05_pcie_stream/output_pcie_stream/`. The host has
to let go of the endpoint before it is reprogrammed out from under it:

```sh
vivado -mode batch -source tools/jtag_scan.tcl          # find the target string
host/pcie_bringup.sh detach
vivado -mode batch -source tools/program.tcl -tclargs \
    <target> designs/05_pcie_stream/output_pcie_stream/pcie_stream.bit
host/pcie_bringup.sh attach
```

## Test

```sh
# The timeout bounds a stuck DMA system call in a failing design.
timeout 180s python3 host/test_pcie_stream.py
```

The test requires identity `0x53540101` before touching DMA. Page-aligned
mmap buffers satisfy DMA alignment requirements. C2H uses the driver's
`O_TRUNC` flag to enable end-of-packet flush: a read larger than a packet
must return exactly that packet's length. This verifies TLAST separately
from checking payload bytes. Odd packet sizes exercise TKEEP.

A writer thread starts H2C before C2H is submitted. Delayed reads and
packets larger than 64 KiB exercise FIFO backpressure. Every write and read
must transfer the expected byte count, and every payload must match.
The driver also has its own DMA timeouts.

The suite includes fixed boundary lengths and 50 deterministic random
lengths. The debug bridge is included but XVC, QSPI boot and QSFP links are
not qualified by this loopback test.

Protocol reference: [AMD PG195 C2H stream signals](https://docs.amd.com/r/en-US/pg195-pcie-dma/C2H-Channel-0-3-AXI4-Stream-Interface-Signals).
