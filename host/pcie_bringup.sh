#!/bin/bash
# ALIVU13P PCIe bring-up / smoke test.
#
#   ./pcie_bringup.sh rescan   - try to enumerate the FPGA without rebooting
#   ./pcie_bringup.sh load     - build + insert the xdma driver, chown the nodes
#   ./pcie_bringup.sh test     - BAR (reg_rw) + DMA (BRAM loopback) smoke test
#   ./pcie_bringup.sh all      - rescan, load, test
#
# The FPGA must already be configured (JTAG or QSPI) before the host will see it.
# A device that was not configured when the host booted usually needs a WARM
# reboot to enumerate; `rescan` is the free thing to try first.
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
XDMA=${XDMA_SRC:-$REPO/third_party/dma_ip_drivers/XDMA/linux-kernel}
# Addresses for designs/01_golden_pcie. They are the crossbar parameters in that
# design's tcl/prj.tcl, and the same numbers appear in host/alivu13p/memmap.py --
# check all three together if a window ever moves.
#   DMA       BRAM          0xC000_0000  64K
#   DMA       URAM          0xC001_0000  64K
#   register  GPIO / LEDs   0x0003_0000
#   register  debug bridge  0x0004_0000  -> XVC, the driver's default xvc_bar_offset
GPIO_OFF=0x30000
BRAM_SIZE=$((64*1024))

find_dev() { lspci -d 10ee: -nn 2>/dev/null; }

do_rescan() {
    echo "== before =="; find_dev || echo "  (no Xilinx device)"
    echo "== rescanning PCI bus =="
    echo 1 | sudo tee /sys/bus/pci/rescan >/dev/null
    sleep 2
    echo "== after =="
    if find_dev | grep -q .; then
        find_dev
        echo "OK: device enumerated."
    else
        echo "No Xilinx device found."
        echo "The FPGA must be configured BEFORE the host enumerates PCIe."
        echo "Program the bitstream, then warm-reboot (reboot, not power off):"
        echo "    sudo reboot"
    fi
}

do_load() {
    [ -d "$XDMA" ] || { echo "missing $XDMA - run: git submodule update --init --recursive"; exit 1; }
    echo "== building driver for $(uname -r) =="
    make -C "$XDMA/xdma" -j"$(nproc)" || exit 1
    make -C "$XDMA/tools"    >/dev/null || exit 1
    echo "== loading =="
    sudo rmmod xdma 2>/dev/null
    sudo insmod "$XDMA/xdma/xdma.ko" interrupt_mode=1 || exit 1
    sleep 1
    sudo chown "$USER" /dev/xdma* 2>/dev/null
    ls /dev/xdma* 2>/dev/null || { echo "FAIL: no /dev/xdma* nodes - is the FPGA enumerated?"; exit 1; }
}

do_test() {
    [ -e /dev/xdma0_user ] || { echo "FAIL: /dev/xdma0_user missing - run 'load' first"; exit 1; }
    echo
    echo "== link status =="
    lspci -d 10ee: -vv 2>/dev/null | grep -E 'LnkCap:|LnkSta:' || sudo lspci -d 10ee: -vv | grep -E 'LnkCap:|LnkSta:'
    echo
    echo "== BAR access: blink the LEDs via AXI GPIO @ $GPIO_OFF =="
    # GPIO data register is at offset 0x0 of the AXI GPIO; write a walking pattern.
    for v in 0x000000ff 0x00000000 0x000000aa 0x00000055 0x00000000; do
        "$XDMA/tools/reg_rw" /dev/xdma0_user $GPIO_OFF w $v >/dev/null && echo "  wrote LED = $v"
        sleep 0.3
    done
    echo
    echo "== DMA loopback through the 64K BRAM @ 0xC0000000 =="
    tmp=$(mktemp -d)
    head -c $BRAM_SIZE /dev/urandom > "$tmp/tx.bin"
    "$XDMA/tools/dma_to_device"   -d /dev/xdma0_h2c_0 -f "$tmp/tx.bin" -s $BRAM_SIZE -a 0xC0000000 || exit 1
    "$XDMA/tools/dma_from_device" -d /dev/xdma0_c2h_0 -f "$tmp/rx.bin" -s $BRAM_SIZE -a 0xC0000000 || exit 1
    if cmp -s "$tmp/tx.bin" "$tmp/rx.bin"; then
        echo "PASS: $BRAM_SIZE bytes written and read back identical."
    else
        echo "FAIL: readback mismatch"; cmp "$tmp/tx.bin" "$tmp/rx.bin" | head
    fi
    rm -rf "$tmp"
}

case "${1:-all}" in
    rescan) do_rescan ;;
    load)   do_load ;;
    test)   do_test ;;
    all)    do_rescan; do_load; do_test ;;
    *) sed -n '2,12p' "$0"; exit 1 ;;
esac
