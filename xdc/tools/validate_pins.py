#!/usr/bin/env python3
"""Check every pin assignment in xdc/ against what the device actually is.

A pin constraint is a claim about how the board is wired. A wrong claim does not fail
the build -- it produces a bitstream that implements cleanly, meets timing, and then does
not work, with nothing in any report pointing at the cause. The only cheap defence is to
check each claim mechanically against the device database and against the other claims.

Run xdc/tools/dump_package_pins.tcl first to produce package_pins.csv, then:

    python3 xdc/tools/validate_pins.py xdc/

Checks performed
----------------
exists           The package pin is a real pin on this part.
role             An I/O port lands on a general-purpose pin; a transceiver port lands on
                 a transceiver pin. Catches a pin name that is valid but in the wrong
                 world entirely.
collision        No package pin is claimed by two different ports. This is the failure
                 that bit the board file this repository replaces, where the main I2C
                 bus and a QSFP cage's I2C bus were assigned the same two pins -- with
                 SDA and SCL swapped between them, so even the roles disagreed.
vcco             All ports in one bank request I/O standards that need the same VCCO.
                 A bank has one supply; two standards needing different voltages cannot
                 both be right, and the board can only be wired for one of them.
diffpair         Where a port pair names itself differential and both halves are
                 constrained by hand, the two pins really are the two halves of one
                 package pair. Hand-written N-side assignments drift from the P side.
gtlane           A transceiver lane's RX and TX pins resolve to the same channel site.
                 RX and TX are separate package pins, so a whole pinout being internally
                 consistent this way is strong evidence it was transcribed correctly.

Exit status is 0 only if nothing failed.
"""

from __future__ import annotations

import csv
import re
import sys
from collections import defaultdict
from pathlib import Path

# I/O standard -> VCCO in millivolts. Only the standards this board uses; an unknown
# standard is reported rather than assumed, because silently skipping it would defeat
# the purpose of the check.
VCCO_MV = {
    "LVCMOS12": 1200,
    "DIFF_SSTL12": 1200,
    "SSTL12": 1200,
    "POD12": 1200,
    "SSTL12_DCI": 1200,
    "POD12_DCI": 1200,
    "DIFF_POD12": 1200,
    "DIFF_POD12_DCI": 1200,
    "DIFF_SSTL12_DCI": 1200,
    "LVCMOS18": 1800,
    "DIFF_SSTL18_I": 1800,
    "LVDS": 1800,
}

# set_property PACKAGE_PIN <pin> [get_ports <port>]
PORT = r"(?P<port>\{[^\}]*\}|[^\s\]]+)"

RE_PACKAGE_PIN = re.compile(
    r"^\s*set_property\s+PACKAGE_PIN\s+(?P<pin>\w+)\s+"
    r"\[\s*get_ports\s+" + PORT + r"\s*\]"
)
# set_property -dict {LOC <pin> IOSTANDARD <std> ...} [get_ports <port>]
RE_DICT_LOC = re.compile(
    r"^\s*set_property\s+-dict\s+\{(?P<dict>[^\}]*)\}\s*"
    r"\[\s*get_ports\s+" + PORT + r"\s*\]"
)
# set_property IOSTANDARD <std> [get_ports <port>]
RE_IOSTANDARD = re.compile(
    r"^\s*set_property\s+IOSTANDARD\s+(?P<std>\w+)\s+"
    r"\[\s*get_ports\s+" + PORT + r"\s*\]"
)

# MGTYRXP3_227 / MGTREFCLK0N_233 -> the transceiver pin naming the device uses.
RE_GT_FUNC = re.compile(r"^MGT[YH](?P<dir>RX|TX)(?P<pol>[PN])(?P<lane>\d)_(?P<quad>\d+)$")
# foo_p / foo_n[3] / ddr4_dqs_t[8] -> a port naming itself one half of a pair.
RE_PORT_POL = re.compile(r"^(?P<base>.+)_(?P<pol>[pPnNtTcC])(?:\[(?P<idx>\d+)\])?$")
# IO_L12P_T1U_N10_GC_64 -> differential pair 12, positive half, bank 64.
RE_IO_PAIR = re.compile(r"^IO_L(?P<pair>\d+)(?P<pol>[PN])_")


class Device:
    """The package pin database dumped from Vivado."""

    def __init__(self, csv_path: Path):
        self.pins: dict[str, dict[str, str]] = {}
        with csv_path.open() as fh:
            for row in csv.DictReader(fh):
                self.pins[row["pin"]] = row

    def bank(self, pin: str) -> str:
        return self.pins[pin]["bank"]

    def func(self, pin: str) -> str:
        return self.pins[pin]["pin_func"]

    def site(self, pin: str) -> str:
        return self.pins[pin]["site"]

    def is_gt(self, pin: str) -> bool:
        return self.func(pin).startswith("MGT")

    def is_gpio(self, pin: str) -> bool:
        return self.pins[pin]["is_general_purpose"] == "1"


class Assignment:
    __slots__ = ("port", "pin", "iostandard", "source")

    def __init__(self, port: str, pin: str, source: str):
        self.port = port
        self.pin = pin
        self.iostandard: str | None = None
        self.source = source


def _port(m: re.Match) -> str:
    """Port name as written, with the optional Tcl braces removed."""
    return m.group("port").strip("{}").strip()


def parse(paths: list[Path]) -> list[Assignment]:
    """Collect pin assignments from a set of XDC files.

    Commented lines are skipped deliberately: this repository comments out constraints
    that are correct but inapplicable to the current configuration -- the DDR4 data-mask
    pins under ECC, the PCIe lane table the hard block places on its own -- and a
    validator that read them would report conflicts that do not exist in any build.
    """
    by_port: dict[str, Assignment] = {}
    order: list[Assignment] = []

    for path in sorted(paths):
        for lineno, raw in enumerate(path.read_text().splitlines(), 1):
            line = raw.split("#", 1)[0]
            if not line.strip():
                continue
            where = f"{path.name}:{lineno}"

            m = RE_PACKAGE_PIN.match(line)
            if m:
                port, pin = _port(m), m.group("pin")
                a = by_port.setdefault(port, Assignment(port, pin, where))
                if a.pin != pin:
                    a.source += f" (also {where})"
                order.append(a) if a not in order else None
                continue

            m = RE_DICT_LOC.match(line)
            if m:
                fields = m.group("dict").split()
                d = {fields[i]: fields[i + 1] for i in range(0, len(fields) - 1, 2)}
                if "LOC" not in d:
                    continue
                port = _port(m)
                a = by_port.setdefault(port, Assignment(port, d["LOC"], where))
                if "IOSTANDARD" in d:
                    a.iostandard = d["IOSTANDARD"]
                if a not in order:
                    order.append(a)
                continue

            m = RE_IOSTANDARD.match(line)
            if m:
                port = _port(m)
                # An IOSTANDARD applied to a wildcard covers every port already seen
                # whose name matches, which is how vectors are usually constrained.
                if "*" in port:
                    prefix = port.split("*", 1)[0]
                    for name, a in by_port.items():
                        if name.startswith(prefix):
                            a.iostandard = m.group("std")
                elif port in by_port:
                    by_port[port].iostandard = m.group("std")

    return order


def validate(assignments: list[Assignment], dev: Device) -> list[str]:
    failures: list[str] = []

    def fail(msg: str) -> None:
        failures.append(msg)

    # --- exists, role
    live = []
    for a in assignments:
        if a.pin not in dev.pins:
            fail(f"{a.source}: {a.port} -> {a.pin}: no such package pin on this part")
            continue
        live.append(a)
        gt_port = dev.is_gt(a.pin)
        if not gt_port and not dev.is_gpio(a.pin):
            fail(
                f"{a.source}: {a.port} -> {a.pin}: not a general-purpose I/O pin "
                f"(function {dev.func(a.pin)})"
            )

    # --- collision
    by_pin: dict[str, list[Assignment]] = defaultdict(list)
    for a in live:
        by_pin[a.pin].append(a)
    for pin, users in sorted(by_pin.items()):
        names = {u.port for u in users}
        if len(names) > 1:
            detail = ", ".join(f"{u.port} ({u.source})" for u in users)
            fail(f"pin {pin} is claimed by {len(names)} different ports: {detail}")

    # --- vcco
    by_bank: dict[str, dict[int, list[Assignment]]] = defaultdict(lambda: defaultdict(list))
    for a in live:
        if a.iostandard is None or dev.is_gt(a.pin):
            continue
        mv = VCCO_MV.get(a.iostandard)
        if mv is None:
            fail(
                f"{a.source}: {a.port}: I/O standard {a.iostandard} is not in this "
                f"script's VCCO table -- add it rather than leaving it unchecked"
            )
            continue
        by_bank[dev.bank(a.pin)][mv].append(a)
    for bank, levels in sorted(by_bank.items()):
        if len(levels) > 1:
            detail = "; ".join(
                f"{mv/1000:.1f}V needed by " + ", ".join(sorted({a.port for a in v}))
                for mv, v in sorted(levels.items())
            )
            fail(f"bank {bank} would need more than one VCCO: {detail}")

    # --- diffpair
    # Keyed off the port names, not the package: single-ended signals routinely occupy
    # both halves of a package pair -- every DDR4 data and address pin does -- so two
    # ports sharing a pair proves nothing. What is worth checking is the case where the
    # design itself declares a differential pair and both halves are constrained by
    # hand, because then the N-side assignment is a second source of truth that can
    # drift from the P side.
    halves: dict[tuple[str, str], dict[str, Assignment]] = defaultdict(dict)
    for a in live:
        m = RE_PORT_POL.match(a.port)
        if m:
            halves[(m.group("base"), m.group("idx") or "")][m.group("pol").lower()] = a
    for (base, idx), members in sorted(halves.items()):
        pos = members.get("p") or members.get("t")
        neg = members.get("n") or members.get("c")
        if pos is None or neg is None:
            continue
        fp, fn = dev.func(pos.pin), dev.func(neg.pin)
        mp, mn = RE_IO_PAIR.match(fp), RE_IO_PAIR.match(fn)
        gp, gn = RE_GT_FUNC.match(fp), RE_GT_FUNC.match(fn)
        label = f"{base}{('[' + idx + ']') if idx else ''}"
        if mp and mn:
            ok = (
                dev.bank(pos.pin) == dev.bank(neg.pin)
                and mp.group("pair") == mn.group("pair")
                and mp.group("pol") == "P"
                and mn.group("pol") == "N"
            )
        elif gp and gn:
            ok = (
                dev.site(pos.pin) == dev.site(neg.pin)
                and gp.group("pol") == "P"
                and gn.group("pol") == "N"
            )
        else:
            ok = True  # dedicated or unrecognised function; nothing to compare
        if not ok:
            fail(
                f"{label}: {pos.pin} ({fp}) and {neg.pin} ({fn}) are constrained as a "
                f"differential pair but are not the two halves of one package pair"
            )

    # --- gtlane
    gt_lane: dict[tuple[str, str, str], dict[str, Assignment]] = defaultdict(dict)
    for a in live:
        m = RE_GT_FUNC.match(dev.func(a.pin))
        if m and m.group("dir") in ("RX", "TX"):
            # Group by the port's logical lane: strip direction and polarity from the
            # port name so rx and tx of the same lane land in one bucket.
            base = re.sub(r"(rx|tx)", "", a.port, count=1)
            gt_lane[(m.group("quad"), base, m.group("pol"))][m.group("dir")] = a
    for (quad, base, pol), dirs in sorted(gt_lane.items()):
        if len(dirs) != 2:
            continue
        rx, tx = dirs["RX"], dirs["TX"]
        if dev.site(rx.pin) != dev.site(tx.pin):
            fail(
                f"quad {quad} {base}: RX {rx.port} ({rx.pin}, {dev.site(rx.pin)}) and "
                f"TX {tx.port} ({tx.pin}, {dev.site(tx.pin)}) are on different channels"
            )

    return failures


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print(f"usage: {sys.argv[0]} <xdc-dir-or-files>...", file=sys.stderr)
        return 2

    here = Path(__file__).resolve().parent
    csv_path = here / "package_pins.csv"
    if not csv_path.is_file():
        print(
            f"missing {csv_path}\nrun: vivado -nojournal -nolog -mode batch "
            f"-source xdc/tools/dump_package_pins.tcl",
            file=sys.stderr,
        )
        return 2
    dev = Device(csv_path)

    paths: list[Path] = []
    for arg in sys.argv[1:]:
        p = Path(arg)
        paths.extend(sorted(p.glob("*.xdc")) if p.is_dir() else [p])
    if not paths:
        print("no .xdc files found", file=sys.stderr)
        return 2

    assignments = parse(paths)
    failures = validate(assignments, dev)

    banks = sorted({dev.bank(a.pin) for a in assignments if a.pin in dev.pins})
    print(f"{len(assignments)} pin assignments in {len(paths)} files, banks: {', '.join(banks)}")

    if failures:
        print(f"\n{len(failures)} problem(s):")
        for f in failures:
            print(f"  FAIL  {f}")
        return 1

    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
