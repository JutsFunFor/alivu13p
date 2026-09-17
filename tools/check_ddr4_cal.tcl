# Report DDR4 calibration status for every MIG in the design currently loaded on the FPGA.
#
#   vivado -nojournal -nolog -mode batch -source tools/check_ddr4_cal.tcl -tclargs <target>
#
# <target> is a JTAG target string from tools/jtag_scan.tcl. It is required rather than
# defaulted: picking target 0 programs or probes whichever cable enumerated first, which
# is not necessarily this board.
#
# No .ltx is needed. Every DDR4 MIG instantiates its own calibration engine regardless of
# the "Debug Signals" IP option, and Hardware Manager reads it over the debug hub -- which
# is why calibration can be checked on a design that contains no ILA at all.
#
# Exit status is 0 only if at least one MIG is present and all of them calibrated.

if {$argc < 1} {
    puts "usage: -tclargs <jtag-target>   (list them with tools/jtag_scan.tcl)"
    exit 2
}
set target [lindex $argv 0]

open_hw_manager
connect_hw_server -quiet
if {[catch {open_hw_target $target} err]} {
    puts "cannot open target $target:\n  $err"
    exit 2
}

set dev [lindex [get_hw_devices -quiet] 0]
if {$dev eq ""} { puts "no device on $target"; exit 2 }
current_hw_device $dev

# Calibration runs at configuration time and takes a moment; refreshing too early
# reports "Calibration is still in-progress" on a design that is in fact fine.
after 3000
refresh_hw_device -quiet $dev

set migs [lsort [get_hw_migs -quiet]]
if {[llength $migs] == 0} {
    puts "No MIG cores found. Either the loaded design has no DDR4 controller, or the"
    puts "device is not programmed -- check DONE with tools/program.tcl."
    close_hw_target
    exit 1
}

puts "\n=== DDR4 calibration: [llength $migs] MIG core(s) on [get_property -quiet PART $dev] ==="
set bad 0
foreach m $migs {
    set name [lindex [split $m /] end]
    set failed [get_property -quiet CALIBRATION_FAIL.STATUS $m]
    set stage  [get_property -quiet CALIBRATION_FAIL.STAGE $m]
    set msg    [get_property -quiet CAL_ERROR_MSG $m]

    # Stage counts. SKIP is normal and not a defect: stages for DBI, VREF training and
    # multi-rank adjustment are skipped when the configuration does not use them.
    set npass 0; set nskip 0; set nother 0
    foreach p [list_property $m] {
        if {![string match "CAL_STATUS.RANK0.*" $p]} { continue }
        switch -- [get_property -quiet $p $m] {
            PASS    { incr npass }
            SKIP    { incr nskip }
            default { incr nother }
        }
    }

    if {$failed eq "FALSE" && $nother == 0} {
        set verdict "OK"
    } else {
        set verdict "FAILED"
        incr bad
    }
    puts [format "  %-8s %-7s pass=%2d skip=%2d other=%d  stage=%-6s  %s" \
        $name $verdict $npass $nskip $nother $stage $msg]

    # On failure, name the stages that did not pass -- that is the part that tells you
    # whether to suspect the pinout, the clock, or signal integrity.
    if {$verdict eq "FAILED"} {
        foreach p [lsort [list_property $m]] {
            if {![string match "CAL_STATUS.RANK0.*" $p]} { continue }
            set v [get_property -quiet $p $m]
            if {$v ne "PASS" && $v ne "SKIP"} {
                puts [format "      %-52s %s" [string range $p 16 end] $v]
            }
        }
    }
}
close_hw_target

if {$bad} {
    puts "\n$bad of [llength $migs] channel(s) failed calibration.\n"
    exit 1
}
puts "\nAll [llength $migs] channel(s) calibrated.\n"
