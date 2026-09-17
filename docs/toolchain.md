# Toolchain

Target: **Vivado 2025.2**, part `xcvu13p-fhgb2104-2L-e`.

## Vivado discovery

The build system takes `vivado` from `PATH`:

```make
VIVADO ?= vivado
```

Override per invocation if you keep several installs:

```bash
make VIVADO=/tools/Xilinx/2025.2/Vivado/bin/vivado
```

Never hardcode an absolute Vivado path in a checked-in Makefile — it is the fastest way
to make a project unbuildable on every machine but one.

## IP versioning

Vivado's IP catalog changes between releases, and a design that pins exact VLNVs stops
building the moment it moves. Two changes matter for this part:

| IP | 2024.x | 2025.x | Consequence |
|---|---|---|---|
| `xilinx.com:ip:xdma` | 4.1 | **4.2** | a pinned `:4.1` fails to instantiate |
| `xilinx.com:ip:axi_interconnect` | 2.1 | **removed** | no version of it exists; `smartconnect:1.0` replaces it with a different clock/reset pin model |

Two patterns keep a design portable across releases. Use them.

**Resolve from the live catalog** rather than pinning, so the newest available version
is taken:

```tcl
set xdma_0 [ create_bd_cell -type ip -vlnv \
  [lindex [lsort -dictionary [get_ipdefs -quiet xilinx.com:ip:xdma:*]] end] xdma_0 ]
```

Wildcard it in any `list_check_ips` catalog check too — `get_ipdefs` takes a glob.

**Import and upgrade explicitly** when a design carries a checked-in `.xci`:

```tcl
import_ip -name $ipname $here/ip/$ipname.xci
upgrade_ip [get_ips $ipname]
generate_target all [get_ips $ipname]
```

This is what `designs/03_qsfp_ibert` does, and it is why that design survives IP version
changes without edits.

`smartconnect` is not a drop-in for `axi_interconnect`: it takes one `aclk`/`aresetn`
pair for the whole core instead of per-port `ACLK`/`ARESETN`/`S*_ACLK`/`M*_ACLK`. Any
design that needs it has to be wired for it from the start.

## Block designs belong in the project, not the source tree

Vivado can generate a block design as a *remote* BD, which writes the elaborated design
into a directory beside your sources. Two problems follow: tens of megabytes of
generated content sit in the working tree, and a stale copy aborts the next build with

```
ERROR: [BD::TCL 103-2030] The remote BD file path <...> already exists!
```

When the BD is fully described by a tcl script, that script is the source. Build it
inside the Vivado project instead:

```tcl
set run_remote_bd_flow 0
```

Output then lands under the project's output directory, outside the repository, and
rebuilds are clean.

## Always write debug probes

A bitstream containing ILA, VIO or IBERT cores is useless in Hardware Manager without
the matching `.ltx` — the tool cannot resolve the cores and the device appears to have
none. Make it part of the build, not a manual step:

```tcl
write_debug_probes -force -quiet ${outdir}/${top}.ltx
```

It is harmless when a design has no debug cores (Vivado reports "No debug cores were
found" and writes nothing). When programming over JTAG, set `PROBES.FILE` alongside
`PROGRAM.FILE` or the probes will not be associated even though the `.ltx` exists.

`.ltx` files are small and are committed with their design; bitstreams are not.

## Relative paths in `common/vivado.mk`

`vivado.mk` rewrites relative source paths by prepending `../`, because Vivado runs
inside the generated project subdirectory:

```make
XDC_FILES_REL = $(foreach p,$(XDC_FILES),$(if $(filter /% ./%,$p),$p,../$p))
```

So a path in a design's Makefile is resolved one level up from where it looks. If you
move a design to a different directory depth, account for that extra level or the
constraints silently fail to load — which surfaces much later as mysterious timing or
placement behaviour rather than an error.

## Host toolchain

The Xilinx XDMA driver is tracked as a submodule at `third_party/dma_ip_drivers`, pinned
to current upstream.

Older snapshots of that driver do not build on kernel 6.3+, because three kernel APIs
changed: `class_create()` lost its `THIS_MODULE` argument (6.4), `iov_iter.iov` became
`__iov` reached via `iter_iov()` (6.4), and `vma->vm_flags` became read-only, requiring
`vm_flags_set()` (6.3). Projects pinned to a 2023-era commit hit all three and need
patching.

Current upstream already carries those version guards, so **no patch is required**.
Verified on this host: builds clean on kernel 6.8.0-138, unpatched.

This is the argument for tracking upstream rather than pinning an old snapshot — the
problem disappears instead of needing to be carried.

The userspace tools that ship with the driver are kernel-version agnostic and build with
a stock `gcc`.

## The configuration watchdog will refuse your JTAG load

`BITSTREAM.CONFIG.TIMER_CFG` arms the configuration watchdog. It is usually described as
part of the fallback mechanism, and it is — but it is armed **whenever it is set**, not
only when `CONFIGFALLBACK` is enabled, and it counts during configuration itself.

At `0x01FFFFFF` the timer is roughly 0.67 s. A 36 MB bitstream takes many seconds to
shift in over a USB JTAG cable, so the timer expires partway through and aborts the load.
What you see is:

```
ERROR: [Labtools 27-3165] End of startup status: LOW
```

which reads like a corrupt bitstream or a bad board. The device disagrees, if you ask it:

```
REGISTER.BOOT_STATUS.SLR0.BIT[03]_0_WATCHDOG_TIMEOUT_ERROR = 1
REGISTER.CONFIG_STATUS.SLR0.BIT[29]_BAD_PACKET_ERROR       = 1
REGISTER.CONFIG_STATUS.SLR0.BIT[20:18]_CFG_STARTUP_STATE_MACHINE_PHASE = 000
```

A watchdog timeout, a rejected packet, and a startup state machine that never left phase
zero. Nothing ambiguous about it — the information is there, it is just not in the error
message.

So `TIMER_CFG` lives in `xdc/golden.xdc` rather than `xdc/bitstream.xdc`: only the image
flashed to QSPI wants it, and flash configuration at 51 MHz on a four-bit bus finishes
well inside the timer. Any design loaded over JTAG must not set it.

**When a device fails to configure, read its status registers before theorising.** They
name the failure directly, and the whole check is a dozen lines of Tcl against
`REGISTER.CONFIG_STATUS.*` and `REGISTER.BOOT_STATUS.*` on the `hw_device`.
