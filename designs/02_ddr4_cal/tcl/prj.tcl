# Build the four-channel DDR4 calibration and BIST design.
#
#   vivado -mode batch -source tcl/prj.tcl -tclargs <outdir> [jobs]
#
# One DDR4 MIG configuration is generated and instantiated four times. The parameters
# below are not a guess: they are the configuration of a reference design that is known
# to calibrate all four channels on this board, read back out of its IP customisation.
# Memory settings are the kind of thing that produces a design which builds perfectly and
# then fails to train, so they are worth copying from something that demonstrably worked
# rather than deriving from a datasheet.

set here   [file normalize [file dirname [info script]]/..]
set repo   [file normalize $here/../..]
set outdir [lindex $argv 0]
set jobs   [expr {[llength $argv] > 1 ? [lindex $argv 1] : 8}]
if {$outdir eq ""} { puts "usage: -tclargs <outdir> \[jobs\]"; exit 2 }

set part     xcvu13p-fhgb2104-2L-e
set top      ddr4_cal_top
set prj_name ddr4_cal

file mkdir $outdir
create_project -force $prj_name $outdir/$prj_name -part $part

add_files -fileset sources_1 [glob $here/rtl/*.v]

# Board pinout from the shared set, plus this design's own timing constraints. The
# shared files are read, never copied: a board-level pin fix belongs in one place.
add_files -fileset constrs_1 [list \
    $repo/xdc/ddr4_c0.xdc \
    $repo/xdc/ddr4_c1.xdc \
    $repo/xdc/ddr4_c2.xdc \
    $repo/xdc/ddr4_c3.xdc \
    $repo/xdc/clocks.xdc \
    $repo/xdc/led.xdc \
    $repo/xdc/bitstream.xdc \
    $here/xdc/ddr4_cal.xdc \
]
set_property top $top [current_fileset]

# ---------------------------------------------------------------------- memory IP
# 72 bits wide with ECC, matching how the board is populated: eight x16 devices for the
# data plus one more for the check bits.
#
# Enabling ECC forces the data mask off (NO_DM_NO_DBI) -- the controller cannot mask
# writes and maintain check bits at the same time. Note that this changes what the
# controller drives, not the port list: c0_ddr4_dm_dbi_n still exists as a 9-bit inout
# and its pins are still routed on this board, so the top level declares it and
# xdc/ddr4_c*.xdc constrains it.
create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_0
set_property -dict [list \
    CONFIG.C0.DDR4_MemoryPart           {MT40A512M16HA-083E} \
    CONFIG.C0.DDR4_MemoryType           {Components} \
    CONFIG.C0.DDR4_MemoryVoltage        {1.2V} \
    CONFIG.C0.DDR4_DataWidth            {72} \
    CONFIG.C0.DDR4_Ecc                  {true} \
    CONFIG.C0.DDR4_DataMask             {NO_DM_NO_DBI} \
    CONFIG.C0.DDR4_CasLatency           {16} \
    CONFIG.C0.DDR4_CasWriteLatency      {12} \
    CONFIG.C0.DDR4_InputClockPeriod     {2499} \
    CONFIG.C0.DDR4_TimePeriod           {833} \
    CONFIG.C0.DDR4_PhyClockRatio        {4:1} \
    CONFIG.C0.DDR4_AxiSelection         {true} \
    CONFIG.C0.DDR4_AxiDataWidth         {512} \
    CONFIG.C0.DDR4_AxiAddressWidth      {32} \
    CONFIG.C0.DDR4_AxiIDWidth           {1} \
    CONFIG.C0.DDR4_AxiArbitrationScheme {RD_PRI_REG} \
    CONFIG.C0.DDR4_Mem_Add_Map          {ROW_COLUMN_BANK} \
    CONFIG.C0.DDR4_BurstLength          {8} \
    CONFIG.C0.DDR4_Ordering             {Normal} \
    CONFIG.C0.DDR4_Slot                 {Single} \
    CONFIG.C0.DDR4_Clamshell            {false} \
    CONFIG.C0.StackHeight               {1} \
    CONFIG.System_Clock                 {Differential} \
    CONFIG.Debug_Signal                 {Disable} \
] [get_ips ddr4_0]
generate_target all [get_ips ddr4_0]

# Debug_Signal is Disable above, and that does not cost visibility. Every DDR4 MIG
# instantiates its own calibration engine whatever that option says, and Hardware Manager
# reads it over the debug hub -- which is why tools/check_ddr4_cal.tcl works against a
# design with no ILA in it at all. The option only controls extra probe ports.

# ---------------------------------------------------------------------- readout IP
# Four channels x (calib, done, pass, busy, ecc) as nibbles, plus per-channel error
# count and first failing address, plus one output to start the test.
create_ip -name vio -vendor xilinx.com -library ip -module_name vio_ddr4
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN         {13} \
    CONFIG.C_NUM_PROBE_OUT        {1}  \
    CONFIG.C_EN_PROBE_IN_ACTIVITY {1}  \
    CONFIG.C_PROBE_IN0_WIDTH      {4}  \
    CONFIG.C_PROBE_IN1_WIDTH      {4}  \
    CONFIG.C_PROBE_IN2_WIDTH      {4}  \
    CONFIG.C_PROBE_IN3_WIDTH      {4}  \
    CONFIG.C_PROBE_IN4_WIDTH      {32} \
    CONFIG.C_PROBE_IN5_WIDTH      {32} \
    CONFIG.C_PROBE_IN6_WIDTH      {32} \
    CONFIG.C_PROBE_IN7_WIDTH      {32} \
    CONFIG.C_PROBE_IN8_WIDTH      {32} \
    CONFIG.C_PROBE_IN9_WIDTH      {32} \
    CONFIG.C_PROBE_IN10_WIDTH     {32} \
    CONFIG.C_PROBE_IN11_WIDTH     {32} \
    CONFIG.C_PROBE_IN12_WIDTH     {4}  \
    CONFIG.C_PROBE_OUT0_WIDTH     {1}  \
    CONFIG.C_PROBE_OUT0_INIT_VAL  {0x0} \
] [get_ips vio_ddr4]
generate_target all [get_ips vio_ddr4]

# ------------------------------------------------------------------------ build
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "SYNTHESIS FAILED"
    exit 1
}

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    puts "IMPLEMENTATION FAILED"
    exit 1
}

open_run impl_1
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "TIMING: WNS=$wns WHS=$whs"

# Report where each controller landed. Four controllers on a four-die part should end up
# one per SLR, matching the channel numbering; anything else means the tool packed two
# into one die, which is worth knowing before chasing a timing failure.
#
# Ask the placed sites rather than the hierarchical cell -- get_slrs on a hierarchical
# cell returns nothing, because the cell has no site of its own.
foreach n {0 1 2 3} {
    set slrs {}
    foreach c [get_cells -quiet -hier -filter "NAME =~ *u_ddr4_c${n}*"] {
        set site [get_sites -quiet -of_objects $c]
        if {$site eq ""} { continue }
        set s [get_slrs -quiet -of_objects $site]
        if {$s ne ""} { lappend slrs [get_property NAME $s] }
    }
    puts "PLACEMENT: channel c${n} -> [lsort -unique $slrs]"
}

write_debug_probes -force $outdir/${prj_name}.ltx
file copy -force [get_property DIRECTORY [get_runs impl_1]]/${top}.bit $outdir/${prj_name}.bit

puts "DDR4 CAL BUILD OK"
puts "  bitstream: $outdir/${prj_name}.bit"
puts "  probes:    $outdir/${prj_name}.ltx"
