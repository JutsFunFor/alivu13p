set here [file normalize [file dirname [info script]]/..]
set prj_name pcie_stream
set mode stream
if {[llength $argv] < 1} { puts "usage: -tclargs <outdir> \[jobs\]"; exit 2 }
if {[catch {source $here/../../common/pcie_test_build.tcl} message]} {
    puts stderr "BUILD FAILED: $message"
    puts stderr $::errorInfo
    exit 1
}
exit 0
