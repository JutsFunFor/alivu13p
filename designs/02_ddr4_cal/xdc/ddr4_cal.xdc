# Design-specific constraints for the DDR4 calibration and BIST design.
#
# The pin assignments themselves are not here. Board pinout lives in xdc/ at the top of
# the repository -- ddr4_c[0-3].xdc, clocks.xdc, led.xdc, bitstream.xdc -- and this
# design's build script adds those files directly, so there is exactly one copy of each
# board fact. What belongs here is only what is true of this design and no other.

# The four memory channels and the board clock are four independent clock domains with no
# logic between them. Everything that does cross -- the start command out, the status
# flags back -- goes through a synchroniser in ddr4_cal_top.v, so the tool should not try
# to time those paths.
set_clock_groups -asynchronous \
    -group [get_clocks sysclk] \
    -group [get_clocks -include_generated_clocks -of_objects [get_ports c0_sys_clk_p]] \
    -group [get_clocks -include_generated_clocks -of_objects [get_ports c1_sys_clk_p]] \
    -group [get_clocks -include_generated_clocks -of_objects [get_ports c2_sys_clk_p]] \
    -group [get_clocks -include_generated_clocks -of_objects [get_ports c3_sys_clk_p]]
