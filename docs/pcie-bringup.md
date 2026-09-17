# PCIe bring-up

The most common "my design is broken" report on a card like this is not a broken design.
It is PCIe enumeration.

## Why the card is invisible

Linux walks the PCIe bus **once, at boot**. A card configured over JTAG *after* the host
has booted was not present during that walk, so it does not exist as far as the kernel
is concerned: `lspci -d 10ee:` returns nothing and there is no `/dev/xdma*`.

Nothing is wrong. The link has simply never been trained.

Options, cheapest first:

1. **Rescan** — free, sometimes works:
   ```bash
   echo 1 | sudo tee /sys/bus/pci/rescan
   ```
2. **Warm reboot** — reliable:
   ```bash
   sudo reboot
   ```
   It must be *warm*. A power cycle wipes the FPGA and puts you back at the start.
3. **Flash to QSPI** so the FPGA configures at power-on and the device is present on
   every cold boot. This is the real end state for a deployed card.

## Reading the link

```bash
lspci -d 10ee: -nn                                  # is it there at all
sudo lspci -d 10ee: -vv | grep -E 'LnkCap:|LnkSta:' # what did it negotiate
```

Expect `LnkSta: Speed 8GT/s, Width x16` for a Gen3 x16 design. A width lower than
`LnkCap` means lanes failed to train; a speed lower than capability usually means signal
integrity or a refclk problem.

**Presence-detect can lie.** On hosts with a PCIe switch (a PLX PEX 8747, for example)
downstream ports may report `PresDet-` even with a working card behind them, so
`lspci -vv` cannot reliably tell you whether the board is seated. Use the negotiated
`LnkSta` width, or a link LED driven from the PCIe core itself, which depends on nothing
above the hardware.

## Driver

The Xilinx XDMA driver is a submodule at `third_party/dma_ip_drivers`, tracking current
upstream, which builds unpatched on kernel 6.3+ — see [toolchain.md](toolchain.md).

```bash
cd host
./pcie_bringup.sh rescan   # enumerate without rebooting
./pcie_bringup.sh load     # build + insmod + chown /dev/xdma*
./pcie_bringup.sh test     # AXI-Lite register access, then a DMA loopback
./pcie_bringup.sh all
```

Point it at a driver tree with `XDMA_SRC=/path/to/dma_ip_drivers/XDMA/linux-kernel` if
it is not the submodule in `third_party/`.

The driver binds on Xilinx vendor ID `0x10ee` and its ID table already covers the XDMA
Gen3 x16 default device ID `0x9038`, so no ID patching is needed for a stock
configuration.

## Address maps are per-design

There is no such thing as "the" BAR layout for a board. Each design's AXI-Lite map comes
from its own address editor, and two designs on the same card will happily put GPIO at
different offsets. Always take the map from the design you actually loaded — a register
write to the wrong offset is silent, not an error.

Each design in `designs/` documents its own map in its README.

## Debug over PCIe

A design that includes a debug bridge configured for AXI-to-BSCAN exposes the on-chip
debug fabric through the XDMA driver as `/dev/xdma0_xvc`:

```bash
xvc_pcie -s TCP::10200 -d /dev/xdma0_xvc
```

Connect Vivado Hardware Manager to `localhost:10200` as a virtual cable, and ILA, VIO
and Memory IP calibration status all work **over PCIe** with no JTAG cable attached.
Worth wiring into any design that has to be debugged in a machine you cannot easily
reach.

The XDMA driver's `xvc_bar_offset` parameter must match where the debug bridge sits in
the AXI-Lite map; its default is `0x40000`.
