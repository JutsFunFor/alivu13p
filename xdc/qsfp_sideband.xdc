# QSFP28 module sideband: I2C, presence and control for both cages, plus the cage LEDs.
#
# This is ordinary fabric I/O in bank 68 and bank 64, entirely separate from the
# transceivers in qsfp_gty.xdc. A management design that only reads module EEPROMs needs
# this file alone; a design that drives the lanes needs both.
#
# Cage 0 is the one nearer the PCIe fingers, cage 1 the one further away.

# ------------------------------------------------------------- cage 0, bank 68
set_property PACKAGE_PIN BF12 [get_ports qsfp0_i2c_scl]
set_property PACKAGE_PIN BD9  [get_ports qsfp0_i2c_sda]
set_property PACKAGE_PIN BB11 [get_ports qsfp0_modprsl]
set_property PACKAGE_PIN BC11 [get_ports qsfp0_intl]
set_property PACKAGE_PIN BB10 [get_ports qsfp0_resetl]
set_property PACKAGE_PIN BB7  [get_ports qsfp0_lpmode]

# ------------------------------------------------------------- cage 1, bank 68
set_property PACKAGE_PIN BD8  [get_ports qsfp1_i2c_scl]
set_property PACKAGE_PIN BC12 [get_ports qsfp1_i2c_sda]
set_property PACKAGE_PIN BC7  [get_ports qsfp1_modprsl]
set_property PACKAGE_PIN BC8  [get_ports qsfp1_intl]
set_property PACKAGE_PIN BA7  [get_ports qsfp1_resetl]
set_property PACKAGE_PIN BB9  [get_ports qsfp1_lpmode]

# ------------------------------------------------------------- module control I/O
# Bank 68 is 1.2 V. PULLUP on the open-drain and active-low lines so the board sits in a
# sane state during configuration, before the fabric drives anything.
set_property IOSTANDARD LVCMOS12 [get_ports {qsfp0_i2c_scl qsfp0_i2c_sda qsfp0_modprsl qsfp0_intl qsfp0_resetl qsfp0_lpmode}]
set_property IOSTANDARD LVCMOS12 [get_ports {qsfp1_i2c_scl qsfp1_i2c_sda qsfp1_modprsl qsfp1_intl qsfp1_resetl qsfp1_lpmode}]
set_property PULLUP true [get_ports {qsfp0_i2c_scl qsfp0_i2c_sda qsfp0_resetl}]
set_property PULLUP true [get_ports {qsfp1_i2c_scl qsfp1_i2c_sda qsfp1_resetl}]
set_property SLEW SLOW [get_ports {qsfp0_i2c_scl qsfp0_i2c_sda qsfp1_i2c_scl qsfp1_i2c_sda}]

# Drive strength is not optional here. Bank 68 is a High Performance bank, and an HP bank
# at LVCMOS12 supports 2, 4, 6 or 8 mA -- not the 12 mA a port defaults to. Leaving it at
# the default fails DRC BIVB-1 before placement, naming these four ports. Only the
# bidirectional pins are affected, because only they carry an output buffer whose drive
# the tool resolves from the port.
#
# 8 mA is the most an HP bank will give at this voltage, and I2C only ever pulls low
# against the board's pull-ups, so this sets how fast the falling edge is and nothing
# else. SLOW slew above keeps that edge inside the I2C specification.
set_property DRIVE 8 [get_ports {qsfp0_i2c_scl qsfp0_i2c_sda qsfp1_i2c_scl qsfp1_i2c_sda}]

# Sideband is software-paced and asynchronous to every clock in the design.
set_false_path -to   [get_ports {qsfp0_i2c_* qsfp0_resetl qsfp0_lpmode qsfp1_i2c_* qsfp1_resetl qsfp1_lpmode}]
set_false_path -from [get_ports {qsfp0_i2c_* qsfp0_modprsl qsfp0_intl qsfp1_i2c_* qsfp1_modprsl qsfp1_intl}]

# ------------------------------------------------------------------- cage LEDs
# Two per cage, bank 64. What they mean is entirely up to the design driving them --
# they are not wired to any link status in hardware.
set_property PACKAGE_PIN BD21 [get_ports {qsfp_led_y[0]}]
set_property PACKAGE_PIN BE21 [get_ports {qsfp_led_y[1]}]
set_property PACKAGE_PIN BE22 [get_ports {qsfp_led_g[0]}]
set_property PACKAGE_PIN BF22 [get_ports {qsfp_led_g[1]}]
set_property IOSTANDARD LVCMOS12 [get_ports {qsfp_led_y[*] qsfp_led_g[*]}]
set_false_path -to [get_ports {qsfp_led_y[*] qsfp_led_g[*]}]

# ============================================================================ the trap
# ResetL is active low, and an undeclared pin falls to BITSTREAM.CONFIG.UNUSEDPIN, which
# defaults to Pulldown. A design that does not declare these ports therefore holds both
# modules in permanent reset.
#
# It survives testing because passive copper DACs have no module logic to reset and link
# anyway. Optical, AOC and retimed modules never come up. Drive resetl high and lpmode
# low as real ports in any design that will see a module with electronics in it.
#
# A `set_property` whose `get_ports` matches nothing is a critical warning rather than an
# error, so a design that declares only some of these ports still builds -- with a dozen
# warnings nobody reads and the rest of the pins silently falling into that trap. Use
# this file whole.
