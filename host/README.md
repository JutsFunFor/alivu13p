# Host software

Everything that runs on the machine the card is plugged into.

```
pcie_bringup.sh    enumerate, build and load the driver, smoke test
alivu13p/          Python package: register access, DMA, interrupts, address maps
tests/             pytest suite, one file per interface
```

## Quick start

```bash
./pcie_bringup.sh all
python3 -m pytest tests/ -v -s
```

`-s` because the DMA tests print throughput, and a number you cannot see is not evidence.

## Dependencies

`pytest`, and nothing else. The `alivu13p` package itself has no dependencies at all:
these run on a machine that has just had a kernel module inserted, often over ssh, and
requiring a virtualenv first is a poor trade for a few hundred lines of file I/O.

## What the driver gives you

| Device | What it is | How the package uses it |
|---|---|---|
| `/dev/xdma0_user` | the AXI-Lite BAR | `AxiLite` mmaps it; a register access is a memory access |
| `/dev/xdma0_h2c_0` | host to card | `Dma.write` — the file offset is the AXI address |
| `/dev/xdma0_c2h_0` | card to host | `Dma.read` |
| `/dev/xdma0_events_0` | user interrupt | `Event.wait` polls it with a timeout |

Transfers use `pread`/`pwrite` so the offset never lives in the object's state, which
means concurrent transfers on one handle cannot interfere.

## Addresses are per-design

Two designs on the same card will happily put GPIO at different offsets, and getting it
wrong is silent: a read from an unmapped address returns zeroes or ones rather than
failing, so a wrong base address presents as broken hardware.

So the maps live in `alivu13p/memmap.py` as data rather than as literals scattered through
the tests. Each mirrors the crossbar parameters in its design's `tcl/prj.tcl` — check the
two together if a window ever moves.
