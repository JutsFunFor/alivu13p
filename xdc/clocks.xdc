# Board clocks.
#
# Two differential clocks arrive in bank 64. They are unrelated to the four per-channel
# DDR4 reference clocks, which live in the memory banks and are constrained in
# ddr4_c[0-3].xdc.
#
# Bank 64 runs at 1.2 V, which forces DIFF_SSTL12 and has one consequence worth knowing:
# DIFF_TERM must be FALSE. Internal differential termination exists only for standards
# that define it, such as LVDS, so setting DIFF_TERM_ADV TRUE on a DIFF_SSTL12 port fails
# DRC PORTPROP-6 before placement rather than at elaboration, where it would be obvious.

# 100 MHz -- the general-purpose board clock. Use this for anything that needs a clock
# before the memory controllers have come up, including the debug hub.
set_property PACKAGE_PIN AY23 [get_ports sysclk_p]
set_property PACKAGE_PIN BA23 [get_ports sysclk_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sysclk_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sysclk_n]
create_clock -period 10.000 -name sysclk [get_ports sysclk_p]

# 400 MHz. Present on the board and verified to exist as a package pair in bank 64, but
# no design here uses it yet and its frequency has not been measured -- 400 MHz is the
# label it carries, not a measurement. Measure it with designs/00_clk_probe before
# building anything that depends on the exact rate.
# set_property PACKAGE_PIN AY22 [get_ports clk400_p]
# set_property PACKAGE_PIN BA22 [get_ports clk400_n]
# set_property IOSTANDARD DIFF_SSTL12 [get_ports clk400_p]
# set_property IOSTANDARD DIFF_SSTL12 [get_ports clk400_n]
# create_clock -period 2.500 -name clk400 [get_ports clk400_p]
