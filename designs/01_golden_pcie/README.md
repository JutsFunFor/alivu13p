# 01 — PCIe bring-up (XDMA x16 Gen3)

The design that answers "does PCIe work", and nothing else. No memory controllers, no
transceivers besides the PCIe ones. If the host cannot see this, the problem is PCIe.

## Build and run

```bash
./compile.sh                       # -> ./output_golden_pcie_<date>/

vivado -nojournal -nolog -mode batch -source ../../tools/jtag_scan.tcl
vivado -nojournal -nolog -mode batch -source ../../tools/program.tcl \
       -tclargs <target> output_golden_pcie_<date>/golden_pcie.bit
```

Then, on the host — see the enumeration note below first, because a card programmed over
JTAG is not visible to a host that has already booted:

```bash
../../host/pcie_bringup.sh all     # rescan, build and load the driver, smoke test
cd ../../host && python3 -m pytest tests/ -v -s
```

## What the host gets

| Window | Address | Size | What it is |
|---|---|---|---|
| DMA | `0xC000_0000` | 64 KB | block RAM |
| DMA | `0xC001_0000` | 64 KB | UltraRAM |
| register | `0x0003_0000` | — | GPIO: eight LEDs, plus an interrupt trigger |
| register | `0x0004_0000` | — | debug bridge (XVC) |

Two DMA targets rather than one because BRAM and URAM are different silicon with
different timing, and a test that only exercises BRAM says nothing about whether URAM
works. They are deliberately identical in size and shape, so the host runs one test
against both and any difference in the result is a property of the memory rather than of
how it was wired.

`0x0004_0000` is not an arbitrary choice: it is where the Xilinx XDMA driver's
`xvc_bar_offset` looks by default, so `xvc_pcie` works against this design with no
rebuild and no driver parameter.

## The enumeration trap

The host walks the PCIe bus once, at boot. A card configured over JTAG afterwards does
not exist as far as Linux is concerned, and nothing about the design is wrong. In order
of cost:

1. `echo 1 | sudo tee /sys/bus/pci/rescan` — free, works often enough to try first.
2. **Warm** reboot. Reliable. It must not be a power cycle: that wipes the FPGA.
3. Flash to QSPI so the card configures at power-on and is present on every cold boot.
   This is the real end state and what a golden image is for.

Before reaching for any of them, look at the green LED at the bracket. It is driven
straight from the endpoint's link status, so it separates "the link never trained" from
"the link trained but Linux has not enumerated it" — two failures that look identical
from a shell.

Presence detect is not a substitute: on at least one test machine a populated slot
reports `PresDet-`, so `lspci -vv` cannot tell you whether the card is seated. Use the
LED, or `LnkSta`.

## There is no `.ltx`, and that is correct

The build reports "No debug cores were found". This design contains no ILA and no VIO, so
there are no probes to describe. The debug bridge is a *bridge*: it carries whatever cores
exist in the design being debugged through it, which is what makes it useful for reading
another design's ILAs over PCIe rather than over a cable.

## Device ID

The XDMA IP derives its PCI device ID from the link configuration, and x16 Gen3 gives
**0x903F** — not 0x9038, which is the x8 Gen3 value. This matters because the driver
binds on the ID and silently ignores anything not in its table, which looks exactly like
the card being absent. 0x903F is in the table shipped with the Xilinx XDMA driver, so no
patching is needed. The build prints the ID it configured.

## Interrupts

GPIO channel 2 is a single bit wired to the endpoint's user interrupt request. The host
raises its own interrupt and then confirms it arrived, which tests the whole path with no
other hardware involved. `usr_irq_req` is a level rather than a pulse, so the sequence is
write 1, wait for the event, write 0.

## No block design

Every IP is created and configured in `tcl/prj.tcl`. A block design records the tool
version that produced it and refuses to open under another, and pins the version of every
IP inside it. Both have to be fought on each upgrade, and `axi_interconnect` being
withdrawn from the catalog is the kind of change that turns a pinned block design into a
rewrite. Asking the catalog for what it currently has avoids the whole category.

## Lane pins are not constrained

Choosing the hard block location and the link width determines which transceiver channels
carry the lanes, and the IP emits those constraints itself. A second set in `xdc/` would
have to agree with the first forever, and when they disagree the tool obeys the
constraints and the link fails. The expected placement is tabulated at the end of
`xdc/pcie.xdc`; the build prints what was actually used so the two can be compared.

## Before this becomes the flashed golden image

`bitstream.xdc` pulls unclaimed pins down, and this design does not declare the QSFP
module-control pins. ResetL is active low, so both cages sit in reset while this bitstream
is loaded. Harmless here — this design never touches the transceivers — but a power-on
image that holds modules in reset is not what anyone wants from a fallback. Declare and
drive those pins before promoting it, and add `xdc/golden.xdc`.

QSPI is not in this design yet either. It needs the flash part identified first, and
flashing is worth doing only once the PCIe path above is solid.
