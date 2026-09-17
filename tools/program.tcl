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

# DONE is reported per SLR on this part -- it has four dies, and a single-die property
# name such as REGISTER.IR.BIT5_DONE simply returns nothing here, which reads as failure
# even on a device that configured perfectly. Ask every SLR and require all of them.
proc slr_done {dev} {
    set seen 0
    foreach p [list_property $dev] {
        # Braced, not quoted: inside a quoted string Tcl collapses \[14\] to [14], which
        # string match then reads as a character class matching "1" or "4" -- so the
        # pattern silently matches nothing and every device looks unprogrammed.
        if {![string match {REGISTER.CONFIG_STATUS.SLR*.BIT\[14\]_DONE_PIN} $p]} { continue }
        incr seen
        if {[get_property -quiet $p $dev] ne "1"} { return [list 0 $seen] }
    }
    return [list [expr {$seen > 0}] $seen]
}

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

lassign [slr_done $dev] ok nslr
puts "DONE = $ok (checked $nslr SLR(s))"
if {!$ok} {
    puts ""
    puts "The device did not assert DONE. Read its status registers rather than guessing:"
    puts "  REGISTER.BOOT_STATUS.SLR*   -- WATCHDOG_TIMEOUT_ERROR means the configuration"
    puts "                                 watchdog fired. BITSTREAM.CONFIG.TIMER_CFG arms"
    puts "                                 it whenever it is set, and it expires long"
    puts "                                 before a large bitstream loads over JTAG."
    puts "  REGISTER.CONFIG_STATUS.SLR* -- BAD_PACKET_ERROR, and the startup state machine"
    puts "                                 phase, which stays at 000 if startup never ran."
    puts "Other causes: a bitstream built for a different part, or a bank without power."
    close_hw_target
    exit 1
}
puts "PROGRAMMED OK"
close_hw_target
