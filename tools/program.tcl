# Program a bitstream over JTAG, with its probes file.
#
#   vivado -nojournal -nolog -mode batch -source tools/program.tcl \
#          -tclargs <target> <bitstream.bit> [probes.ltx]
#
# The target is required, not defaulted. `[lindex [get_hw_targets] 0]` is the first cable
# that enumerated, which is only this board when exactly one is attached -- and
# programming the wrong device does not fail, it succeeds, on the wrong board. List them
# with tools/jtag_scan.tcl.
#
# The probes file is optional but almost always wanted: without it Hardware Manager can
# see that debug cores exist but cannot resolve their names, so a design with a VIO or an
# ILA looks like it has none.

if {$argc < 2} {
    puts "usage: -tclargs <jtag-target> <bitstream.bit> \[probes.ltx\]"
    puts "       list targets with tools/jtag_scan.tcl"
    exit 2
}
set target [lindex $argv 0]
set bitfile [file normalize [lindex $argv 1]]
set ltxfile [expr {$argc > 2 ? [file normalize [lindex $argv 2]] : ""}]

if {![file exists $bitfile]} { puts "no such bitstream: $bitfile"; exit 2 }

# Default to the .ltx sitting next to the bitstream, since that is where the build
# scripts here put it.
if {$ltxfile eq ""} {
    set guess [file rootname $bitfile].ltx
    if {[file exists $guess]} {
        set ltxfile $guess
        puts "using probes file found alongside the bitstream: $ltxfile"
    }
}
if {$ltxfile ne "" && ![file exists $ltxfile]} { puts "no such probes file: $ltxfile"; exit 2 }

open_hw_manager
connect_hw_server -quiet
if {[catch {open_hw_target $target} err]} {
    puts "cannot open target $target:\n  $err"
    exit 2
}

set dev [lindex [get_hw_devices -quiet] 0]
if {$dev eq ""} { puts "no device on $target"; exit 2 }
current_hw_device $dev
refresh_hw_device -quiet $dev

puts "device:    [get_property -quiet PART $dev]"
puts "bitstream: $bitfile"
set_property PROGRAM.FILE $bitfile $dev
if {$ltxfile ne ""} { set_property PROBES.FILE $ltxfile $dev }

program_hw_devices $dev
refresh_hw_device $dev

set done [get_property -quiet REGISTER.IR.BIT5_DONE $dev]
puts "DONE = $done"
if {$done ne "1"} {
    puts "The device did not assert DONE. The bitstream was rejected -- most often"
    puts "because it was built for a different part than the one on this cable."
    close_hw_target
    exit 1
}
puts "PROGRAMMED OK"
close_hw_target
