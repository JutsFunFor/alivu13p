#!/usr/bin/env python3
"""Give an enumerated-but-BARless FPGA endpoint memory without rebooting.

`/sys/bus/pci/rescan` only places new BARs into bridge windows that already
exist; it never grows a window that has a claimed device inside it. When the
FPGA sits behind a switch whose firmware-sized window is used up by another
device (seen here: a PLX PEX 8747 shared with the Wi-Fi card), rescans leave
BAR0/BAR1 unassigned forever and XDMA fails with "Failed to detect XDMA config BAR".

This removes the whole subtree below the FPGA's root port and rescans that root
port's secondary bus through `/sys/class/pci_bus/<bus>/rescan`, which takes the
kernel's bridge-resize path (pci_rescan_bus_bridge_resize): windows are sized
from scratch and may be regrown from free host-bridge aperture.

Afterwards it parks any bridge BAR that the kernel left *unassigned* but whose
config register still decodes an address inside the root port window. Linux
does not clear such a register, and the stale decode can shadow the FPGA's BAR
(the switch then answers reads meant for the FPGA, e.g. returning its own ID).

Every other device in the subtree disappears for the duration (Wi-Fi, NICs,
NVMe...). If that is your network link, run detached, as root:

    sudo setsid host/pcie_realloc.py --yes > realloc.log 2>&1 < /dev/null &

    host/pcie_realloc.py --dry-run       # show topology and plan, change nothing
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

SYS = "/sys/bus/pci/devices"
BDF = re.compile(r"^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$")


def read(path, default=None):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def write(path, value):
    with open(path, "w") as f:
        f.write(value)


def bars(bdf):
    """[(start, end, flags)] for BAR0..5 from sysfs."""
    lines = (read(f"{SYS}/{bdf}/resource", "") or "").splitlines()[:6]
    return [tuple(int(x, 16) for x in line.split()) for line in lines]


def bars_assigned(bdf):
    present = [(s, e) for s, e, f in bars(bdf) if f]
    return bool(present) and all(s != 0 for s, _ in present)


def find_endpoint(vendor="0x10ee"):
    found = [os.path.basename(p) for p in glob.glob(f"{SYS}/*") if read(f"{p}/vendor") == vendor
             and read(f"{p}/class", "").startswith("0x") and not read(f"{p}/class").startswith("0x0604")]
    if len(found) != 1:
        sys.exit(f"expected exactly one {vendor} endpoint, found {found or 'none'}; pass --bdf")
    return found[0]


def path_to(bdf):
    """BDFs from the root port down to the endpoint."""
    parts = [p for p in os.path.realpath(f"{SYS}/{bdf}").split("/") if BDF.match(p)]
    if len(parts) < 2:
        sys.exit(f"{bdf} is not below a root port; nothing to resize")
    return parts


def subtree(bdf):
    """All devices at or below bdf, with driver and network interfaces.
    Walks only real BDF-named child directories; sysfs symlinks loop."""
    out, stack = [], [os.path.realpath(f"{SYS}/{bdf}")]
    while stack:
        p = stack.pop()
        driver = os.path.basename(os.path.realpath(f"{p}/driver")) if os.path.islink(f"{p}/driver") else None
        nets = sorted(os.listdir(f"{p}/net")) if os.path.isdir(f"{p}/net") else []
        out.append({"bdf": os.path.basename(p), "driver": driver, "net": nets})
        stack += [f"{p}/{c}" for c in sorted(os.listdir(p), reverse=True)
                  if BDF.match(c) and not os.path.islink(f"{p}/{c}")]
    return out


def config_bar(bdf, index):
    raw = open(f"{SYS}/{bdf}/config", "rb").read(0x10 + 4 * (index + 1))
    return int.from_bytes(raw[0x10 + 4 * index:0x14 + 4 * index], "little")


def window(bdf):
    """Non-prefetchable memory window of a bridge from config space, or None."""
    raw = open(f"{SYS}/{bdf}/config", "rb").read(0x24)
    base, limit = int.from_bytes(raw[0x20:0x22], "little"), int.from_bytes(raw[0x22:0x24], "little")
    start, end = (base & 0xfff0) << 16, ((limit & 0xfff0) << 16) | 0xfffff
    return (start, end) if start <= end else None


def iomem():
    entries = []
    for line in read("/proc/iomem", "").splitlines():
        depth = (len(line) - len(line.lstrip())) // 2
        span, _, name = line.strip().partition(" : ")
        lo, hi = (int(x, 16) for x in span.split("-"))
        entries.append((depth, lo, hi, name))
    return entries


def park_address(root_port, size):
    """Lowest size-aligned 32-bit address in the root bus aperture that holds the
    root port, outside every claimed range below it (so nothing forwards to it)."""
    rw = window(root_port)
    entries = iomem()
    bus = "PCI Bus " + root_port[:7]
    for depth, lo, hi, name in entries:
        if name == bus and hi < 1 << 32 and lo <= rw[0] <= hi:
            used = [(l, h) for d, l, h, _ in entries if d > depth and lo <= l <= hi]
            addr = (lo + size - 1) // size * size
            while addr + size - 1 <= hi:
                if not any(l <= addr + size - 1 and addr <= h for l, h in used):
                    return addr
                addr += size
    sys.exit("no free parking address in the root bus aperture")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bdf", help="FPGA endpoint, e.g. 0000:1b:00.0 (default: the only 10ee endpoint)")
    ap.add_argument("--yes", action="store_true", help="accept that other devices in the subtree drop out")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true", help="run even if BARs already look assigned")
    args = ap.parse_args()

    fpga = args.bdf or find_endpoint()
    chain = path_to(fpga)
    root_port, top = chain[0], chain[1]
    secondary = read(f"{SYS}/{root_port}/subordinate_bus_number") and \
        f"{root_port[:4]}:{int(open(f'{SYS}/{root_port}/config', 'rb').read(0x1a)[0x19]):02x}"
    others = [d for d in subtree(top) if d["bdf"] != fpga and d["driver"] and d["driver"] != "pcieport"]
    plan = {"fpga": fpga, "root_port": root_port, "remove": top, "rescan_bus": secondary,
            "bars_assigned": bars_assigned(fpga), "affected": others}
    print(json.dumps(plan, indent=2), flush=True)
    if args.dry_run:
        return
    if os.geteuid():
        sys.exit("run as root")
    if plan["bars_assigned"] and not args.force:
        print("BARs already assigned; nothing to do")
        return
    fpga_driver = next((d["driver"] for d in subtree(fpga) if d["bdf"] == fpga), None)
    if fpga_driver not in (None, "serial"):
        sys.exit(f"{fpga} is bound to {fpga_driver}; unload it first (rmmod xdma)")
    if others and not args.yes:
        sys.exit("other devices above would disappear during the rescan; re-run with --yes")

    write(f"{SYS}/{top}/remove", "1")
    time.sleep(2)
    write(f"/sys/class/pci_bus/{secondary}/rescan", "1")   # bridge-resize path
    time.sleep(5)
    if not os.path.exists(f"{SYS}/{fpga}") or not bars_assigned(fpga):
        print("bridge resize incomplete; global rescan", flush=True)
        write("/sys/bus/pci/rescan", "1")
        time.sleep(5)

    parked = []
    rw = window(root_port)
    for bdf in chain[1:-1]:
        for i, (start, end, flags) in enumerate(bars(bdf)[:2]):
            reg = config_bar(bdf, i)
            decoded = reg & ~0xf
            if flags == 0 and start == 0 and decoded and rw and rw[0] <= decoded <= rw[1]:
                size = 1 << max(20, (end - start).bit_length())   # 1 MiB-aligned covers small BARs
                addr = park_address(root_port, size)
                cfg = os.open(f"{SYS}/{bdf}/config", os.O_WRONLY)
                os.pwrite(cfg, (addr | (reg & 0xf)).to_bytes(4, "little"), 0x10 + 4 * i)
                os.close(cfg)
                parked.append({"bdf": bdf, "bar": i, "from": hex(decoded), "to": hex(addr)})
    nets = [n for d in others for n in d["net"]]
    if nets and shutil.which("nmcli"):
        for n in nets:
            subprocess.run(["nmcli", "device", "connect", n], check=False)
    result = {"bars_assigned": bars_assigned(fpga), "bars": [hex(s) for s, _, f in bars(fpga) if f],
              "parked": parked, "reconnected": nets}
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["bars_assigned"] else 1)


if __name__ == "__main__":
    main()
