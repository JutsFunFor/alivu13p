# Run the four-channel BIST in a freshly programmed designs/02_ddr4_cal.
# Usage: vivado -nojournal -nolog -mode batch -source tools/check_ddr4_bist.tcl \
#        -tclargs <target> <ddr4_cal.ltx>
# Refuse a stale done latch; reprogram before each qualification run.
if {$argc != 2} { puts "usage: -tclargs <target> <ddr4_cal.ltx>"; exit 2 }
proc probe {name} {
    global vio
    set ps [get_hw_probes -quiet -of_objects $vio -filter "NAME == $name"]
    if {[llength $ps] != 1} { error "Missing or ambiguous probe: $name" }
    return [lindex $ps 0]
}
proc value {name} {
    set raw [get_property INPUT_VALUE [probe $name]]
    if {![regexp {^[0-9a-fA-F]+$} $raw]} { error "Invalid $name value: $raw" }
    scan $raw %x result
    return $result
}
proc start {v} {
    global vio
    set_property OUTPUT_VALUE $v [probe vio_start]
    commit_hw_vio $vio
}

proc main {} {
    global argv vio
    set ltx [file normalize [lindex $argv 1]]
    if {![file isfile $ltx]} { error "Missing probes file: $ltx" }
    open_hw_manager
    connect_hw_server -quiet
    open_hw_target [lindex $argv 0]
    set devs [get_hw_devices -quiet -filter {PART == xcvu13p}]
    if {[llength $devs] != 1} { error "Expected exactly one xcvu13p on selected target" }
    set dev [lindex $devs 0]
    current_hw_device $dev
    set_property PROBES.FILE $ltx $dev
    refresh_hw_device $dev
    set vios [get_hw_vios -quiet -of_objects $dev]
    if {[llength $vios] != 1} { error "Expected one DDR4 VIO" }
    set vio [lindex $vios 0]


    start 0
    set deadline [expr {[clock milliseconds] + 30000}]
    while {1} {
        refresh_hw_vio $vio
        if {[value calib_sync] == 15} { break }
        if {[clock milliseconds] > $deadline} { error "Calibration timeout" }
        after 100
    }
    if {[value done_sync] != 0 || [value pass_sync] != 0 || [value busy_sync] != 0} {
        error "BIST is not fresh; program the DDR4 bitstream before running this check"
    }
    puts "FRESH: calib=f done=0 pass=0 busy=0"
    start 1
    set deadline [expr {[clock milliseconds] + 30000}]
    while {1} {
        refresh_hw_vio $vio
        if {[value done_sync] == 15} { break }
        if {[clock milliseconds] > $deadline} { start 0; error "BIST timeout" }
        after 100
    }
    # Give the captured multi-bit counters another VIO refresh after done.
    refresh_hw_vio $vio
    set bad [expr {[value calib_sync] != 15 || [value pass_sync] != 15 ||
                   [value busy_sync] != 0 || [value ecc_sync] != 0}]
    foreach name {errors_cap_1 errors_cap_2 errors_cap_3 errors_cap} {
        set n [value $name]
        puts "$name = $n"
        if {$n != 0} { set bad 1 }
    }
    puts [format "RESULT: calib=%x done=%x pass=%x busy=%x ecc=%x" \
        [value calib_sync] [value done_sync] [value pass_sync] [value busy_sync] [value ecc_sync]]
    start 0
    close_hw_target
    if {$bad} { error "DDR4 BIST failed" }
    puts "PASS: all four channels completed fresh memory tests with zero errors"

}
if {[catch {main} message]} {
    puts stderr "FAIL: $message"
    catch {close_hw_target}
    exit 1
}
exit 0
