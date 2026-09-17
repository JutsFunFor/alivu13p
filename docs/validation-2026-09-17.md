# DDR4 and PCIe hardware validation — 2026-09-17

Board: ALIVU13P, `xcvu13p-fhgb2104-2L-e`. Vivado 2025.2, Linux
6.8.0-138-generic. These are two independently verified bitstreams:
`01_golden_pcie` and `02_ddr4_cal`; this does not establish DDR4 DMA over PCIe.

## PCIe after the warm reboot

The existing PCIe image survived the warm reboot. Linux enumerated `10ee:903f`
at `0000:1b:00.0` and allocated BAR0 at `0xb5c00000` (512 KiB), BAR1 at
`0xb5c80000` (64 KiB). The parent bridge `18:10.0` now has a 1 MiB memory
window. This resolves the previous unassigned-BAR blocker.

The endpoint advertises Gen3 x16 and negotiates **8 GT/s x8**. The parent
PEX 8747 port advertises x8 and negotiates x8; this host cannot qualify x16.
XDMA builds and loads, bus mastering and MSI are enabled.

Commands from the repository root:

```sh
bash host/pcie_bringup.sh load
python3 -m pytest host/tests -v -s
```

Result: **10 passed**, including 64 KiB random BRAM and UltraRAM roundtrips,
independent address windows, unaligned DMA, GPIO data readback, and a
host-triggered user interrupt. Single-transfer timings varied roughly from
1.2–2.0 GB/s; these small transfers are functional checks, not a sustained
bandwidth benchmark. LED register readback does not prove the physical LEDs.

The first run exposed an incorrect test assumption: both GPIO channels use
`C_ALL_OUTPUTS=1`. The generated AXI GPIO read mux ties direction-register
readback to all ones in this configuration. Test the implemented DATA register
with alternating values instead. The fixed output mode is described in
[AMD PG144](https://docs.amd.com/r/en-US/pg144-axi-gpio/All-Outputs).

PCIe error status was not entirely clear: `DevSta` contained `CorrErr+` and
`UnsupReq+`, and AER contained `AdvNonFatalErr+`. No fatal/nonfatal uncorrectable
status, lane error, bad TLP/DLLP or receiver-error bits were set at inspection.
These sticky flags were not cleared or attributed, so this is functional
validation, not an error-free endurance qualification.

## Fresh DDR4 test

Unloaded XDMA and removed only this endpoint from Linux before programming the
DDR4 image. Explicitly selected the JTAG target containing `xcvu13p`; another
attached target contained `xcku115`.

```sh
vivado -nojournal -nolog -mode batch -source tools/program.tcl \
  -tclargs <target> <ddr4_cal.bit>
vivado -nojournal -nolog -mode batch -source tools/check_ddr4_bist.tcl \
  -tclargs <target> <ddr4_cal.ltx>
vivado -nojournal -nolog -mode batch -source tools/check_ddr4_cal.tcl \
  -tclargs <target>
```

Observed:

```text
FRESH: calib=f done=0 pass=0 busy=0
errors_cap_1 = 0
errors_cap_2 = 0
errors_cap_3 = 0
errors_cap = 0
RESULT: calib=f done=f pass=f busy=0 ecc=0
```

All four MIGs independently report 15 PASS / 12 SKIP, stage NONE, no calibration
errors. Each BIST performs 8192 64-byte writes and reads: a dense 256 KiB walk
and sparse addresses across each 4 GiB channel. It does not test every byte
of the full 16 GiB or establish long-term retention.

Rerunning the checker without reprogramming correctly returns exit code 1
with `BIST is not fresh`. This prevents a saved pass latch being mistaken for
a new test. The checker also rejects missing probes, timeouts and ECC events.

## Supplied XDC audit

Audited the supplied sibling `vu13p/xdc/` against the checked-in package
database. Added the 1.2 V DDR4 DCI/differential standards to the validator;
previously it reported those standards as unsupported rather than checking
their bank voltage.

```sh
python3 xdc/tools/validate_pins.py ../vu13p/xdc ../vu13p/xdc/ddr4_72
python3 xdc/tools/validate_pins.py xdc/
python3 -m pytest xdc/tools/tests -q
```

The supplied 72-bit selection has 646 assignments and **two collisions**:
`BC12` is both main I2C SCL and upper-cage SDA; `BD8` is both main I2C SDA
and upper-cage SCL. Excluding `vu13p_iic.xdc`, the 72-bit selection passes
with 644 assignments, and the alternative 64-bit selection passes with 600.
The two DDR4 width variants must be validated separately.

Channel names differ from this repository's SLR-based numbering:

| Supplied channel | Repository channel / SLR | Matching assignments | Different data assignments |
|---|---|---:|---:|
| c0 | c3 / SLR3 | 37 | 80 |
| c1 | c2 / SLR2 | 77 | 40 |
| c2 | c0 / SLR0 | 82 | 35 |
| c3 | c1 / SLR1 | 30 | 87 |

Counts compare 117 assignments per channel after renaming `ddr4_clk_p` to
`sys_clk_p` and `dm_n` to `dm_dbi_n`. The supplied files additionally constrain
11 negative differential halves per channel; this repository lets MIG derive
them. All clock, reset, address and command assignments agree after channel
renaming. Differences are confined to DQ, DQS and DM ordering, using the same
physical pin sets. Package consistency alone cannot qualify a different
logical memory mapping.

Kept the repository's vendor-derived, hardware-proven DDR4 mapping and its
existing PCIe constraints in use. Importing the supplied files verbatim would
change data ordering and channel names and reintroduce the I2C collision.
The active repository set passes **534 assignments**, and the validator suite
passes **32 tests**. No FPGA RTL or active pin assignments changed in this update;
the previously timing-closed bitstreams were exercised on hardware.

## Artifacts and final state

Tested existing build artifacts (SHA-256):

```text
7f042e38a985d98b0dfe9627c726bb280a4b52bc6b127b692f2e55efb92a0aa8  golden_pcie.bit
6bcf9eaae364b61b6e09e722e6849a711aa408c3f2999a32819ffa51e4162ef0  ddr4_cal.bit
```

Supplied XDC checkout: `3d985d639adcaf6535e76e91a25b0bd1d208c16a`.
Restored the PCIe image, rescanned, reloaded XDMA and passed the 64 KiB smoke
roundtrip. QSPI was not written. The board remains configured for PCIe use;
DDR4 testing requires loading its separate image again.
