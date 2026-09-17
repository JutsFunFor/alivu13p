#!/usr/bin/env python3
"""Publish the built bitstreams as a GitHub release.

Bitstreams are build outputs. They do not belong in git -- they are tens of megabytes
each, they change on every rebuild, and nothing about them is reviewable. But a person
who wants to try this board should not have to install Vivado and wait an hour to find
out whether it enumerates, so they belong somewhere.

What this publishes is meant to be checkable rather than taken on faith:

  * every .bit carries its own header naming the top module, the exact part and the tool
    version -- read back here and put in the notes, so a file's claims come from the file
    rather than from prose someone typed;
  * the timing numbers come from that build's own report;
  * a bitstream older than the last commit touching its sources is refused, because it
    does not correspond to the tagged tree;
  * SHA256 for everything.

    tools/release.py --tag v0.2 --dry-run     # see exactly what would be published
    tools/release.py --tag v0.2
"""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bitstream_info import read_header      # noqa: E402

REPO = Path(__file__).resolve().parents[1]
PART = "xcvu13p-fhgb2104-2L-e"

# A bitstream depends on more than its own directory: the shared board constraints and,
# for some designs, a shared build script. Which ones is not a guess -- each design's own
# scripts name the files they pull in, so they are read out rather than assumed. Treating
# all of xdc/ as a dependency of every design would mark a QSFP constraint edit as
# invalidating the clock probe, which is false and would train people to pass
# --allow-stale by reflex.
# What a rebuild would actually read. A README edit does not change a bitstream, and
# treating it as if it did is how a staleness check gets ignored.
BUILD_INPUTS = {".v", ".sv", ".vh", ".vhd", ".xdc", ".tcl", ".xci", ".xdc", ".sh", ".mk"}

SHARED_REFERENCE = re.compile(r"(?:xdc|common)/[A-Za-z0-9_.\[\]-]+\.(?:xdc|tcl)")


def run(*args: str, check: bool = True) -> str:
    result = subprocess.run(args, cwd=REPO, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise SystemExit(f"{' '.join(args)} failed:\n{result.stderr.strip()}")
    return result.stdout.strip()


def newest_source(paths: list[str]) -> tuple[float, str]:
    """Modification time of the most recently edited source, and which file it was.

    Deliberately file mtimes rather than commit times. The usual order is build, look at
    the result, then commit -- so a perfectly good bitstream is always older than the
    commit that introduces it, and a commit-time comparison would call every release
    stale. What actually invalidates a bitstream is a source edited after it was built,
    which is the same rule make uses.
    """
    newest, culprit = 0.0, ""
    for path in paths:
        target = REPO / path
        candidates = [target] if target.is_file() else [
            f for f in target.rglob("*")
            if f.is_file()
            and not any(part.startswith("output_") for part in f.relative_to(target).parts)
            and f.suffix in BUILD_INPUTS
        ]
        for candidate in candidates:
            stamp = candidate.stat().st_mtime
            if stamp > newest:
                newest, culprit = stamp, str(candidate.relative_to(REPO))
    return newest, culprit


def dependencies(design_dir: Path) -> list[str]:
    """The design's own directory, plus the shared files its scripts actually name."""
    deps = {str(design_dir.relative_to(REPO))}
    for script in list(design_dir.rglob("*.tcl")) + list(design_dir.rglob("*.sh")):
        # Skip the build directory: Vivado copies scripts in there, and a stale copy
        # would report dependencies the design no longer has.
        if any(part.startswith("output_") for part in script.relative_to(design_dir).parts):
            continue
        text = script.read_text(errors="replace")
        for match in SHARED_REFERENCE.findall(text):
            if (REPO / match).exists():
                deps.add(match)
    # A design built through a shared script inherits that script's references too.
    for shared in [d for d in deps if d.startswith("common/")]:
        for match in SHARED_REFERENCE.findall((REPO / shared).read_text(errors="replace")):
            if (REPO / match).exists():
                deps.add(match)
    return sorted(deps)


def timing(design_dir: Path) -> tuple[str, str]:
    """WNS and WHS from the build's own report, not from anyone's memory."""
    # The shared build script writes one next to the bitstream; designs with their own
    # script leave Vivado's post-route report in the run directory instead.
    reports = (list(design_dir.glob("output_*/timing_summary.rpt"))
               or list(design_dir.glob("output_*/*/*.runs/impl_1/*_timing_summary_routed.rpt")))
    if not reports:
        return ("?", "?")
    text = reports[0].read_text(errors="replace")
    marker = text.find("Design Timing Summary")
    if marker < 0:
        return ("?", "?")
    for line in text[marker:].splitlines():
        numbers = re.findall(r"-?\d+\.\d+", line)
        if len(numbers) >= 5 and "WNS" not in line:
            return (numbers[0], numbers[2])
    return ("?", "?")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collect(allow_stale: bool) -> list[dict]:
    found = []
    for design_dir in sorted(REPO.glob("designs/*")):
        if not design_dir.is_dir():
            continue
        bits = sorted(design_dir.glob("output_*/*.bit"))
        # Only the copy the build script promoted, never the one still in the run
        # directory -- those two are identical today and will not be the day someone
        # reruns implementation without finishing.
        bits = [b for b in bits if b.parent.name.startswith("output_")]
        if not bits:
            continue
        bit = bits[0]
        header = read_header(bit)
        if header.get("part") != PART:
            raise SystemExit(f"{bit} is built for {header.get('part')}, not {PART}")
        deps = dependencies(design_dir)
        edited, culprit = newest_source(deps)
        stale = bit.stat().st_mtime < edited
        if stale and not allow_stale:
            when = datetime.fromtimestamp(edited).strftime("%Y-%m-%d %H:%M")
            raise SystemExit(
                f"{bit.relative_to(REPO)} is older than its sources: {culprit} was "
                f"edited at {when}, after the bitstream was built. Rebuild it, or pass "
                f"--allow-stale to publish a bitstream that does not match the tree.")
        entry = {
            "design": design_dir.name,
            "stale_because": culprit if stale else "",
            "bit": bit,
            "ltx": next(iter(sorted(design_dir.glob("output_*/*.ltx"))), None),
            "header": header,
            "wns": timing(design_dir)[0],
            "whs": timing(design_dir)[1],
            "stale": stale,
        }
        found.append(entry)
    return found


def notes(entries: list[dict], tag: str, commit: str) -> str:
    lines = [
        f"Bitstreams for `{commit}`, built with Vivado "
        f"{entries[0]['header'].get('design', '').split('Version=')[-1].split(';')[0]}"
        if entries else "",
        "",
        "Every file below reports its own identity: the table's top module, part and",
        "build time are read out of the `.bit` header, and the timing numbers come from",
        f"that build's report. Part is `{PART}` for all of them.",
        "",
        "| Design | Top module | Built | WNS (ns) | WHS (ns) | Size |",
        "|---|---|---|---:|---:|---:|",
    ]
    for entry in entries:
        header = entry["header"]
        top = header.get("design", "").split(";")[0]
        size = f"{entry['bit'].stat().st_size / 1e6:.1f} MB"
        mark = " ⚠" if entry["stale"] else ""
        lines.append(f"| `{entry['design']}`{mark} | `{top}` | {header.get('date')} "
                     f"{header.get('time')} | {entry['wns']} | {entry['whs']} | {size} |")
    stale = [e for e in entries if e["stale"]]
    if stale:
        lines += ["", "⚠ built before the last edit to one of its sources, so it does not "
                      "correspond exactly to this tag:", ""]
        lines += [f"- `{e['design']}` — `{e['stale_because']}` changed after the build"
                  for e in stale]
    lines += [
        "",
        "## Programming one",
        "",
        "```sh",
        "vivado -mode batch -source tools/jtag_scan.tcl        # find the target string",
        "vivado -mode batch -source tools/program.tcl -tclargs <target> <file>.bit",
        "```",
        "",
        "A `.ltx` beside a `.bit` is its debug-probe file; `program.tcl` picks it up",
        "automatically. Without it Hardware Manager can see that a design has debug cores",
        "but cannot name them, which looks like the cores were never built.",
        "",
        "Configuring over JTAG after the host has booted does not make the card appear on",
        "PCIe -- the bus is enumerated once, at boot. See `docs/pcie-bringup.md`.",
        "",
        "Verify what you downloaded:",
        "",
        "```sh",
        "sha256sum -c SHA256SUMS",
        "python3 tools/bitstream_info.py <file>.bit    # what the file says it is",
        "```",
    ]
    return "\n".join(line for line in lines if line is not None)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tag", required=True, help="release tag, e.g. v0.2")
    parser.add_argument("--title", help="release title; defaults to the tag")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the notes and the asset list, publish nothing")
    parser.add_argument("--allow-stale", action="store_true",
                        help="publish bitstreams older than their sources")
    parser.add_argument("--draft", action="store_true", help="create the release as a draft")
    args = parser.parse_args()

    if run("git", "status", "--porcelain", "--untracked-files=no"):
        print("warning: the working tree has uncommitted changes; the tag will not "
              "describe what these bitstreams were built from", file=sys.stderr)
    commit = run("git", "rev-parse", "--short", "HEAD")

    entries = collect(args.allow_stale)
    if not entries:
        raise SystemExit("no bitstreams found -- build a design first")

    staging = REPO / "output_release"
    staging.mkdir(exist_ok=True)
    assets, sums = [], []
    for entry in entries:
        for kind in ("bit", "ltx"):
            source = entry[kind]
            if source is None:
                continue
            target = staging / f"{entry['design']}.{kind}"
            target.write_bytes(source.read_bytes())
            assets.append(target)
            sums.append(f"{sha256(target)}  {target.name}")
    checksums = staging / "SHA256SUMS"
    checksums.write_text("\n".join(sums) + "\n")
    assets.append(checksums)

    body = notes(entries, args.tag, commit)
    notes_file = staging / "RELEASE_NOTES.md"
    notes_file.write_text(body + "\n")

    print(body)
    print("\nassets:")
    for asset in assets:
        print(f"  {asset.relative_to(REPO)}  ({asset.stat().st_size / 1e6:.1f} MB)")

    if args.dry_run:
        print("\n--dry-run: nothing published")
        return 0

    command = ["gh", "release", "create", args.tag,
               "--title", args.title or args.tag,
               "--notes-file", str(notes_file)]
    if args.draft:
        command.append("--draft")
    command += [str(a) for a in assets]
    print("\n" + " ".join(command[:6]) + f" ... ({len(assets)} assets)")
    subprocess.run(command, cwd=REPO, check=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
