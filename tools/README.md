# JTAG tools

Vivado batch scripts for talking to the board over a cable. All of them take the JTAG
target as an explicit argument.

```bash
vivado -nojournal -nolog -mode batch -source tools/<script>.tcl -tclargs <args>
```

| Script | Arguments | What it does |
|---|---|---|
| `jtag_scan.tcl` | — | lists every cable, the devices behind it, and their DONE status |
| `program.tcl` | `<target> <file.bit> [file.ltx]` | programs a device and checks DONE |
| `check_ddr4_bist.tcl` | `<target> <ddr4_cal.ltx>` | starts a fresh four-channel memory test; rejects stale results and returns nonzero on failure |
| `check_ddr4_cal.tcl` | `<target>` | per-channel DDR4 calibration status |
| `bitstream_info.py` | `<file.bit> ...` | what a bitstream says about itself: top module, exact part, build time, tool version |
| `release.py` | `--tag <tag> [--dry-run]` | publish the built bitstreams as a GitHub release |

## Why the target is never defaulted

`[lindex [get_hw_targets] 0]` is the first cable that enumerated, which is this board
only when exactly one is attached. On the machine this repository was developed on the
first target is a different board entirely.

Programming the wrong device does not fail. It succeeds, on the wrong board, and then the
design you meant to test appears not to work. Run `jtag_scan.tcl` first and pass the
target string you get back.

## Probes

`program.tcl` picks up a `.ltx` sitting beside the bitstream automatically, which is where
the build scripts here put it. Without one, Hardware Manager can see that debug cores
exist but cannot resolve their names, so a design with a VIO or an ILA looks like it has
none — a confusing failure that looks like the cores were never built.

## Calibration without a probes file

`check_ddr4_cal.tcl` needs no `.ltx`, and works on any design containing a DDR4
controller — including one with no debug cores at all. Every MIG instantiates its own
calibration engine regardless of the IP's "Debug Signals" option, and Hardware Manager
reads it over the debug hub.

It waits before reading, deliberately: calibration runs at configuration time and takes a
moment, so refreshing immediately reports "still in progress" on a design that is fine.

## Publishing bitstreams

Bitstreams are build outputs: tens of megabytes, different on every rebuild, and nothing
about them is reviewable. They do not belong in git. But someone who wants to try this
board should not have to install Vivado and wait an hour to find out whether it
enumerates, so `release.py` ships them as GitHub release assets instead.

```sh
python3 tools/release.py --tag v0.2 --dry-run    # exactly what would be published
python3 tools/release.py --tag v0.2 --draft      # a draft, visible only to you
python3 tools/release.py --tag v0.2
```

It refuses to publish a bitstream older than a file it was built from -- an edit to a
shared constraint invalidates every design that reads it, and shipping the old binary
under a new tag is how a release comes to describe something that was never built.
`--allow-stale` overrides that and marks the affected designs in the notes rather than
quietly omitting the fact.

Which shared files a design depends on is read out of its own build scripts, not assumed.
A QSFP constraint edit does not invalidate the clock probe, and a check that claimed
otherwise would be ignored within a week.

The notes table is filled in from the artifacts themselves: top module, part and build
time come from each `.bit` header, and the timing numbers from that build's own report.
