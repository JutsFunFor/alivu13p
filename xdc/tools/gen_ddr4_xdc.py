#!/usr/bin/env python3
"""Generate the repository's DDR4 constraints from the board vendor's reference project.

Source
------
The ALIVU13P ships with a Vivado reference project (``XCVU13P_DDR4.zip``) containing a
MicroBlaze plus four independent DDR4 MIG channels, built by the board vendor. Its
constraint files ``DDR4_SLR0.xdc`` .. ``DDR4_SLR3.xdc`` carry the package pin assignment
for each channel, and are explicitly labelled by SLR -- which is the authoritative answer
to which memory channel sits on which super logic region.

This script reads those files and re-emits them in this repository's conventions. It is
kept in-tree so the derivation is reproducible and auditable rather than being a one-off
copy: point it at an extracted copy of the vendor archive and it regenerates the
constraints byte for byte.

What it changes
---------------
* Port naming: the vendor's ``ddr4_rtl_<n>_*`` / ``diff_clock_rtl_<n>_clk_p`` becomes the
  Xilinx MIG external interface naming ``c<n>_ddr4_*`` / ``c<n>_sys_clk_p``, so a
  generated MIG connects to these constraints without a rename layer.
* Channel numbering is pinned to the SLR: ``c0`` is SLR0, ``c1`` is SLR1, and so on.
  Physical placement is what matters when floorplanning four controllers across a
  four-die part, so the name should carry it.
* One file per channel, each with a header recording provenance and the SLR.

What it deliberately does not change
------------------------------------
* Pin assignments are facts about how the board is wired; they are reproduced exactly.
* No ``IOSTANDARD`` is emitted. The vendor files set none either: the DDR4 MIG generates
  the I/O standards for its own interface (POD12/SSTL12 and their DCI variants), and a
  hand-written duplicate here would be a second source of truth that silently drifts.
* Only the P/T half of each differential pair is constrained, as in the source. Vivado
  derives the N/C pin of a package pin pair automatically, and constraining both is a
  common way to introduce a contradiction.

Memory configuration
--------------------
The board is populated for 72-bit channels: ``MT40A512M16JY-083E`` for bits [63:0] plus
``MT40A1G8WE-083E`` for the [71:64] ECC lane, per the vendor file headers. The MIG must
therefore be configured 72 bits wide with ECC enabled to match these constraints.

A 64-bit no-ECC configuration is a strict subset: drop ``dq[71:64]``, ``dm_dbi_n[8]`` and
``dqs_t[8]``/``dqs_c[8]``, and leave those package pins unconstrained.

Usage
-----
    ./gen_ddr4_xdc.py --vendor-dir /path/to/XCVU13P_DDR4_1B_Test --out-dir ../
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Vendor signal suffix -> (MIG signal suffix, is_vector)
#
# The vendor emits scalars for act_n/reset_n and single-bit vectors for the rest of the
# command/address group; the MIG external interface uses the same shape, so the mapping
# is a rename rather than a reshape. dm_n becomes dm_dbi_n, which is what the MIG calls
# the pin when data mask is enabled without data bus inversion.
SIGNAL_MAP = {
    "act_n": "act_n",
    "adr": "adr",
    "ba": "ba",
    "bg": "bg",
    "ck_t": "ck_t",
    "cke": "cke",
    "cs_n": "cs_n",
    "dm_n": "dm_dbi_n",
    "dq": "dq",
    "dqs_t": "dqs_t",
    "odt": "odt",
    "reset_n": "reset_n",
}

# Emission order. Grouped the way a person reads a memory interface: clock and reset
# first, then command/address, then the data group, rather than the source file's order.
EMIT_ORDER = [
    ("Reference clock", ["sys_clk_p"]),
    ("Reset and command", ["reset_n", "act_n"]),
    ("Address and bank", ["adr", "ba", "bg"]),
    ("Control", ["cke", "cs_n", "odt", "ck_t"]),
    ("Data", ["dq", "dqs_t", "dm_dbi_n"]),
]

# Nothing is emitted commented out any more. An earlier version of this script withheld
# the data-mask pins, reasoning that enabling ECC forces NO_DM_NO_DBI and therefore
# leaves the controller with no data-mask ports. Only the first half is true: the MIG
# still presents c<n>_ddr4_dm_dbi_n as a 9-bit inout whatever the data-mask setting --
# NO_DM_NO_DBI changes what the controller drives on those pins, not whether the port
# exists. Checked against the instantiation template of a MIG customised exactly as this
# board needs. The pins are routed, the port is there, so they are constrained.
OPTIONAL_SIGNALS = []

PIN_RE = re.compile(
    r"^\s*set_property\s+PACKAGE_PIN\s+(?P<pin>\S+)\s+"
    r"\[get_ports\s+\{?(?P<port>[A-Za-z0-9_]+?)(?:\[(?P<idx>\d+)\])?\}?\s*\]",
)

HEADER = """\
# DDR4 channel {ch} -- SLR{slr}
#
# Package pin assignment for one of the four independent DDR4 channels on the ALIVU13P.
# Derived from the board vendor's reference project (DDR4_SLR{slr}.xdc) by
# xdc/tools/gen_ddr4_xdc.py -- do not hand-edit; regenerate instead.
#
# Memory: MT40A512M16JY-083E [63:0] + MT40A1G8WE-083E [71:64] (ECC lane).
# Configure the MIG 72 bits wide with ECC enabled to match.
#
# No IOSTANDARD is set here on purpose: the DDR4 MIG generates the I/O standards for its
# own interface. Only the P/T half of each differential pair is constrained; Vivado
# derives the N/C pin of the package pair.
"""


def parse_vendor_file(path: Path, channel: int) -> dict[tuple[str, int | None], str]:
    """Return {(mig_signal, index_or_None): package_pin} for one vendor channel file."""
    pins: dict[tuple[str, int | None], str] = {}
    prefix_ddr4 = f"ddr4_rtl_{channel}_"
    prefix_clk = f"diff_clock_rtl_{channel}_"

    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = PIN_RE.match(line)
        if not m:
            if "PACKAGE_PIN" in line:
                raise SystemExit(f"{path}:{lineno}: unparsed PACKAGE_PIN line:\n  {line}")
            continue

        port, pin = m.group("port"), m.group("pin")
        idx = int(m.group("idx")) if m.group("idx") is not None else None

        if port.startswith(prefix_clk):
            suffix = port[len(prefix_clk):]
            if suffix != "clk_p":
                raise SystemExit(f"{path}:{lineno}: unexpected clock port {port!r}")
            key = ("sys_clk_p", None)
        elif port.startswith(prefix_ddr4):
            suffix = port[len(prefix_ddr4):]
            if suffix not in SIGNAL_MAP:
                raise SystemExit(f"{path}:{lineno}: unmapped signal {suffix!r} in {port!r}")
            key = (SIGNAL_MAP[suffix], idx)
        else:
            raise SystemExit(
                f"{path}:{lineno}: port {port!r} is not channel {channel} "
                f"(expected prefix {prefix_ddr4!r} or {prefix_clk!r})"
            )

        if key in pins:
            raise SystemExit(f"{path}:{lineno}: duplicate constraint for {key}")
        pins[key] = pin

    return pins


def emit(channel: int, slr: int, pins: dict[tuple[str, int | None], str]) -> str:
    out = [HEADER.format(ch=channel, slr=slr)]
    emitted: set[tuple[str, int | None]] = set()

    for section, signals in EMIT_ORDER:
        rows: list[tuple[str, str]] = []
        for sig in signals:
            keys = sorted(
                (k for k in pins if k[0] == sig),
                key=lambda k: (k[1] is not None, k[1] if k[1] is not None else -1),
            )
            for key in keys:
                name = sig if key[1] is None else f"{sig}[{key[1]}]"
                port = name if key[0] == "sys_clk_p" else f"c{channel}_ddr4_{name}"
                if key[0] == "sys_clk_p":
                    port = f"c{channel}_sys_clk_p"
                rows.append((port, pins[key]))
                emitted.add(key)

        if not rows:
            continue
        out.append(f"\n# {section}")
        for port, pin in rows:
            braced = "{" + port + "}" if "[" in port else port
            out.append(f"set_property PACKAGE_PIN {pin:<6} [get_ports {braced}]")

    missing = set(pins) - emitted
    if missing:
        raise SystemExit(f"channel {channel}: signals parsed but never emitted: {sorted(missing)}")

    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument(
        "--vendor-dir",
        required=True,
        type=Path,
        help="extracted XCVU13P_DDR4_1B_Test directory from the vendor archive",
    )
    ap.add_argument("--out-dir", required=True, type=Path, help="where to write ddr4_c*.xdc")
    args = ap.parse_args()

    src = args.vendor_dir / "XCVU13P_DDR4_1B_Test.srcs" / "constrs_1" / "new"
    if not src.is_dir():
        # Tolerate being handed the constraints directory directly.
        src = args.vendor_dir
    args.out_dir.mkdir(parents=True, exist_ok=True)

    total = 0
    for slr in range(4):
        vendor_file = src / f"DDR4_SLR{slr}.xdc"
        if not vendor_file.is_file():
            raise SystemExit(f"missing {vendor_file}")
        # The vendor names the file by SLR and the ports by channel index; on this board
        # they coincide, which is the property that lets cN mean SLRn. Verify rather than
        # assume -- a mismatch would silently mis-place four memory controllers.
        pins = parse_vendor_file(vendor_file, channel=slr)
        if len(pins) != 117:
            raise SystemExit(
                f"{vendor_file}: expected 117 constrained pins, parsed {len(pins)}"
            )
        (args.out_dir / f"ddr4_c{slr}.xdc").write_text(emit(slr, slr, pins))
        total += len(pins)
        print(f"ddr4_c{slr}.xdc  <- DDR4_SLR{slr}.xdc  ({len(pins)} pins)")

    print(f"{total} pins across 4 channels")
    return 0


if __name__ == "__main__":
    sys.exit(main())
