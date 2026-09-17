# Reference-clock probe pin assignment.
#
# Twelve MGTREFCLK candidates plus the 100 MHz board clock. Only the P pin of each
# differential pair is constrained; Vivado derives the N pin of a package pair.
#
# Indices 0-7 are the reference clocks reachable by a PCIe x16 endpoint at
# PCIE40E4_X0Y1, which occupies four adjacent GTY quads in SLR1 -- banks 224-227.
# Indices 8-11 are known-state controls that validate the measurement.

# ---------------------------------------------------------------- board clock
set_property PACKAGE_PIN AY23  [get_ports sysclk_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sysclk_p]
create_clock -period 10.000 -name sysclk [get_ports sysclk_p]

# ------------------------------------------------- PCIe candidates, banks 224-227
# bank 224
set_property PACKAGE_PIN AW9   [get_ports {refclk_p[0]}]
set_property PACKAGE_PIN AV11  [get_ports {refclk_p[1]}]
# bank 225
set_property PACKAGE_PIN AT11  [get_ports {refclk_p[2]}]
set_property PACKAGE_PIN AP11  [get_ports {refclk_p[3]}]
# bank 226
set_property PACKAGE_PIN AM11  [get_ports {refclk_p[4]}]
set_property PACKAGE_PIN AK11  [get_ports {refclk_p[5]}]
# bank 227
set_property PACKAGE_PIN AH11  [get_ports {refclk_p[6]}]
set_property PACKAGE_PIN AF11  [get_ports {refclk_p[7]}]

# ------------------------------------------------------ controls, banks 229 / 233
# Known live at 161.13 MHz (dn cage) and known dead.
set_property PACKAGE_PIN Y11   [get_ports {refclk_p[8]}]
set_property PACKAGE_PIN V11   [get_ports {refclk_p[9]}]
# Known live at 161.13 MHz (up cage) and known dead.
set_property PACKAGE_PIN D11   [get_ports {refclk_p[10]}]
set_property PACKAGE_PIN B11   [get_ports {refclk_p[11]}]

# ------------------------------------------------------- QSFP module control pins
# Index 0 is the dn cage, 1 is the up cage. Driven so no module is held in reset.
set_property PACKAGE_PIN BB10  [get_ports {qsfp_resetn[0]}]
set_property PACKAGE_PIN BB7   [get_ports {qsfp_lpmode[0]}]
set_property PACKAGE_PIN BA7   [get_ports {qsfp_resetn[1]}]
set_property PACKAGE_PIN BB9   [get_ports {qsfp_lpmode[1]}]
set_property IOSTANDARD LVCMOS12 [get_ports {qsfp_resetn[*]}]
set_property IOSTANDARD LVCMOS12 [get_ports {qsfp_lpmode[*]}]

# ------------------------------------------------------------------------ timing
# Each probed clock is asynchronous to sysclk and to every other probe, and a candidate
# with no oscillator has no clock at all. The counter crosses domains through a
# Gray-coded two-flop synchroniser, so these paths are false by construction.
set_clock_groups -asynchronous -group [get_clocks sysclk]

# Unused pins default to a pulldown, which is the correct inactive state for everything
# on this board that is not driven here.
set_property BITSTREAM.CONFIG.UNUSEDPIN Pulldown [current_design]
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
