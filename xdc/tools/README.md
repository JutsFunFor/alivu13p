# Constraint tools

## `dump_package_pins.tcl`

Exports what the device says about every package pin — bank, pin function, whether it is
general-purpose, and the site behind it — into `package_pins.csv`. Needs Vivado, and only
needs running again if the part changes.

```bash
vivado -nojournal -nolog -mode batch -source xdc/tools/dump_package_pins.tcl
```

`package_pins.csv` is committed so that `validate_pins.py` runs anywhere, including in
CI, without a Vivado installation.

## `validate_pins.py`

Checks every pin assignment in `xdc/` against that database and against the other
assignments. See [../README.md](../README.md) for what each check catches and why.

```bash
python3 xdc/tools/validate_pins.py xdc/
```

Exit status is 0 only if nothing failed. No dependencies beyond the standard library.

## `gen_ddr4_xdc.py`

Generates `xdc/ddr4_c[0-3].xdc` from a reference project's constraint files, so the
derivation stays reproducible instead of being an unverifiable paste.

```bash
python3 xdc/tools/gen_ddr4_xdc.py --vendor-dir <extracted project> --out-dir xdc/
```

It validates as it goes — 117 pins per channel, no duplicates, no signal parsed but not
emitted — and fails rather than writing a partial file.

## `tests/`

Self-tests for the validator. Each case is a constraint file with one deliberate defect,
and asserts the checker rejects it; one case asserts it accepts a correct file, so the
suite cannot be satisfied by a checker that fails everything.

```bash
python3 -m pytest xdc/tools/tests/ -v
```

These run in CI before the real check, because a validator that has only ever passed is
not evidence that it works — it might be matching nothing at all.
