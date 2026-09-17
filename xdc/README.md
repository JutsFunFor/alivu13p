# Board constraints

One copy of each board fact. Designs add these files directly rather than keeping their
own copies, so a pin fix happens in one place.

| File | Covers |
|---|---|
| `clocks.xdc` | 100 MHz board clock; the 400 MHz pair, commented out until measured |
| `pcie.xdc` | PCIe reference clock, PERST, link LED — plus the lane table, as reference |
| `led.xdc` | eight user LEDs |
| `qsfp.xdc` | both QSFP28 cages: lanes, reference clocks, module control, cage LEDs |
| `ddr4_c0.xdc` … `ddr4_c3.xdc` | four DDR4 channels, 117 pins each, one per SLR |
| `bitstream.xdc` | configuration settings shared by every design |
| `golden.xdc` | fallback settings — only for an image flashed at address 0 |

## Why these are checked rather than trusted

A pin constraint is a claim about how a board is wired, and a wrong claim does not fail
the build. It produces a bitstream that implements cleanly, meets timing, and then does
not work, with nothing in any report pointing at the cause. This board ships with no
documentation, so every claim here came from either measuring the board or querying the
device — and both can be transcribed wrongly.

```bash
# once, to export what the device says about every package pin
vivado -nojournal -nolog -mode batch -source xdc/tools/dump_package_pins.tcl

# then, any time
python3 xdc/tools/validate_pins.py xdc/
```

What it checks:

**exists** — the pin is real on this part. **role** — an I/O port is on a general-purpose
pin and a transceiver port is on a transceiver pin. **collision** — no package pin is
claimed by two different ports. **vcco** — every port in a bank asks for an I/O standard
needing the same supply voltage, since a bank has only one. **diffpair** — where a design
declares a differential pair and constrains both halves by hand, the two pins really are
the two halves of one package pair. **gtlane** — a transceiver lane's RX and TX pins
resolve to the same channel.

The collision check exists because of a real defect: a board file in circulation assigns
the main I2C bus and a QSFP cage's I2C bus to the same two pins, with SCL and SDA swapped
between the two uses. That is invisible until both are used at once.

The gtlane check is the one that earns its keep on a board with no documentation. RX and
TX are separate package pins, so a whole 16-lane pinout being internally consistent —
every lane's two pins landing on the same channel, with no gaps in the sequence — is
strong evidence it was transcribed correctly, and it costs nothing to verify.

## Generated files

`ddr4_c[0-3].xdc` are generated, not hand-written. Regenerate rather than editing:

```bash
python3 xdc/tools/gen_ddr4_xdc.py --vendor-dir <extracted reference project> --out-dir xdc/
```

The generator is kept in-tree so the derivation is auditable instead of being a paste
that nobody can re-check.

## Conventions

No `IOSTANDARD` on the DDR4 interface — the memory controller generates those for its own
pins, and a hand-written duplicate is a second source of truth that drifts.

For differential pairs, only the P or T half is constrained where the tool can derive the
other. Constraining both is a common way to introduce a contradiction. Where both are
written out — the board clock, the QSFP and PCIe lanes — the validator checks they are a
genuine package pair.

QSFP cages are numbered by position: **cage 0 is nearer the PCIe fingers**, cage 1 is
further away. Positional rather than silkscreen-based, because it is the property you can
check by looking at the card.
