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

The driver binds on Xilinx vendor ID `0x10ee` plus a device ID, and the XDMA IP derives
that ID from the link configuration. **Gen3 x16 gives `0x903F`**; `0x9038` is the Gen3 x8
value, so quoting it for a x16 design is a common and confusing mistake — the driver
silently ignores a device outside its table, which looks exactly like the card being
absent rather than like a mismatch.

Both IDs are in the table shipped with the driver, so no patching is needed either way.
`designs/01_golden_pcie` prints the ID it configured during the build; compare it with
what `lspci -d 10ee: -nn` reports.

## Rescan can succeed and still leave the card useless

There are two separate enumeration failures, and they look nothing alike once you know
what to read.

The first is the familiar one: the card is simply absent from `lspci`. The host walked
the bus at boot, the FPGA was not configured yet, and nothing has looked since.

The second is worse because it looks like success. `/sys/bus/pci/rescan` finds the device,
`lspci -d 10ee:` lists it with the right ID, the link trains — and the driver still cannot
do anything, because the device has no memory regions:

```
$ cat /sys/bus/pci/devices/0000:1b:00.0/resource
0x0000000000000000 0x0000000000000000 0x0000000000000000
...
```

All zeroes. `dmesg` says why:

```
pcieport 0000:18:10.0: bridge window [mem size 0x00100000]: can't assign; no space
pci 0000:1b:00.0: BAR 0 [mem size 0x00080000]: failed to assign
pci 0000:1b:00.0: BAR 1 [mem size 0x00010000]: failed to assign
```

The firmware sized the bridge windows at boot, when nothing was behind that port, so
there is no address space to hand the BARs now. Rescanning cannot create it. This is why
the warm reboot is described here as the reliable option rather than the inconvenient
one: at power-on self-test the device is already there and gets a window sized for it.

`pci=realloc=on` on the kernel command line tells Linux to re-do the firmware's
allocation, which can also fix it — but it needs a reboot too, so it is only worth
reaching for if reboots alone do not help.

**Check `resource` or `dmesg`, not just `lspci`.** A device with no BARs is listed exactly
like a working one.

## Address maps are per-design

There is no such thing as "the" BAR layout for a board. Two designs on the same card will
happily put GPIO at different offsets. Always take the map from the design you actually
loaded — a register write to the wrong offset is silent, not an error, and a read from an
unmapped address returns zeroes or ones rather than failing, so a wrong base address
presents as broken hardware instead of a wrong constant.

For that reason the maps live in `host/alivu13p/memmap.py` as data rather than being
spread through the test code as literals. Each one mirrors the crossbar parameters in its
design's `tcl/prj.tcl`; check the two together if a window ever moves.

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
