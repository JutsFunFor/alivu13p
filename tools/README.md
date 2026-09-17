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
