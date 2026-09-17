# Eight user LEDs, bank 64.
#
# Bank 64 is the 1.2 V bank shared with the board clocks, so LVCMOS12 is the only
# consistent choice -- a bank has one VCCO and the clocks already fix it.

set_property PACKAGE_PIN BA20 [get_ports {user_led[0]}]
set_property PACKAGE_PIN BB20 [get_ports {user_led[1]}]
set_property PACKAGE_PIN BB21 [get_ports {user_led[2]}]
set_property PACKAGE_PIN BC21 [get_ports {user_led[3]}]
set_property PACKAGE_PIN BB22 [get_ports {user_led[4]}]
set_property PACKAGE_PIN BC22 [get_ports {user_led[5]}]
set_property PACKAGE_PIN BA24 [get_ports {user_led[6]}]
set_property PACKAGE_PIN BB24 [get_ports {user_led[7]}]
set_property IOSTANDARD LVCMOS12 [get_ports {user_led[*]}]

# LEDs are not a timed interface.
set_false_path -to [get_ports {user_led[*]}]
