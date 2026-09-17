# Dump the package pin database for the ALIVU13P part.
#
# Every pin assignment in xdc/ is a claim about how the board is wired, and a wrong claim
# produces a design that builds cleanly and then does not work. This script exports what
# the *device* says about each package pin -- which bank it belongs to, what the silicon
# can drive there, whether it is a gigabit transceiver pin and which lane of which quad --
# so that xdc/tools/validate_pins.py can check every claim against it mechanically.
#
#   vivado -nojournal -nolog -mode batch -source xdc/tools/dump_package_pins.tcl
#
# Writes xdc/tools/package_pins.csv next to this script.
#
# Bank grouping is derived from the per-pin BANK column rather than dumped separately:
# get_iobanks returns nothing against a part with no design loaded, so a second file
# would just be an empty header.

set part      "xcvu13p-fhgb2104-2L-e"
set here      [file dirname [file normalize [info script]]]

link_design -part $part

set fh [open [file join $here package_pins.csv] w]
puts $fh "pin,bank,pin_func,is_general_purpose,site"
foreach p [get_package_pins] {
    set bank [get_property BANK          $p]
    set func [get_property PIN_FUNC      $p]
    set gp   [get_property IS_GENERAL_PURPOSE $p]
    # Not every package pin has a site behind it (power, ground, no-connect).
    set site ""
    catch { set site [get_sites -quiet -of_objects $p] }
    puts $fh "[get_property NAME $p],$bank,$func,$gp,$site"
}
close $fh

puts "wrote package_pins.csv ([llength [get_package_pins]] pins)"
