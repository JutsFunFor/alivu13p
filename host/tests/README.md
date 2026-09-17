# Host tests

```bash
cd host
python3 -m pytest tests/ -v -s          # -s so throughput numbers are printed
```

Everything skips rather than fails when `/dev/xdma0_user` is absent. A missing card is
not a test failure — it means the suite was run somewhere it cannot say anything, and
failing there trains people to ignore red results.

Requires `pytest` and nothing else. The package under `alivu13p/` has no dependencies at
all, on purpose: these run on a machine that has just had a driver inserted, often over
ssh, and needing a virtualenv first is a poor trade for a few hundred lines of file I/O.

| File | Covers | Fails when |
|---|---|---|
| `test_registers.py` | AXI-Lite BAR | the register window is unreachable or a bit is stuck |
| `test_dma.py` | both DMA windows | data is corrupted, windows overlap, or unaligned transfers break |
| `test_interrupt.py` | user interrupt | the interrupt never arrives |

`test_dma.py` runs every case against BRAM and URAM identically. The two windows are the
same size and shape in the design precisely so this is possible — a difference in the
result is then a property of the memory rather than of the test.

The one to read carefully is `test_windows_are_independent`. An address decode that is
one bit too narrow maps both memories onto the same place, and every single-window test
still passes; only writing one and checking the other catches it.
