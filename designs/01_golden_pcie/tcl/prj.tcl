# Build the PCIe bring-up design.
#
#   vivado -mode batch -source tcl/prj.tcl -tclargs <outdir> [jobs]
#
# Every IP is created and configured here rather than imported from a block design. A
# block design records the tool version that made it and refuses to open under another,
# and pins the version of every IP inside it; both have to be fought on each upgrade.
# This file asks the catalog for whatever it currently has.

set here   [file normalize [file dirname [info script]]/..]
set repo   [file normalize $here/../..]
set outdir [lindex $argv 0]
set jobs   [expr {[llength $argv] > 1 ? [lindex $argv 1] : 8}]
if {$outdir eq ""} { puts "usage: -tclargs <outdir> \[jobs\]"; exit 2 }

set part     xcvu13p-fhgb2104-2L-e
set top      golden_pcie_top
set prj_name golden_pcie

file mkdir $outdir
create_project -force $prj_name $outdir/$prj_name -part $part

add_files -fileset sources_1 [glob $here/rtl/*.v]
add_files -fileset constrs_1 [list \
    $repo/xdc/pcie.xdc \
    $repo/xdc/led.xdc \
    $repo/xdc/bitstream.xdc \
    $here/xdc/golden_pcie.xdc \
]
set_property top $top [current_fileset]

# ------------------------------------------------------------------------ XDMA
# x16 Gen3 at PCIE40E4_X0Y1, the only block on this part whose quads reach the edge
# connector.
#
# The lane pins are deliberately left unconstrained. The hard block location plus the
# link width determine which transceiver channels are used, and the IP emits those
# constraints itself; a second set in xdc/ would have to agree with the first forever.
# The expected result is tabulated at the end of xdc/pcie.xdc -- check the implemented
# design against it rather than forcing it.
create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_0
set_property -dict [list \
    CONFIG.mode_selection             {Advanced} \
    CONFIG.pcie_blk_locn              {X0Y1} \
    CONFIG.pl_link_cap_max_link_width {X16} \
    CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
    CONFIG.axisten_freq               {250} \
    CONFIG.axi_data_width             {512_bit} \
    CONFIG.axi_addr_width             {64} \
    CONFIG.xdma_axi_intf_mm           {AXI_Memory_Mapped} \
    CONFIG.axilite_master_en          {true} \
    CONFIG.axilite_master_scale       {Kilobytes} \
    CONFIG.axilite_master_size        {512} \
    CONFIG.xdma_num_usr_irq           {1} \
    CONFIG.xdma_rnum_chnl             {1} \
    CONFIG.xdma_wnum_chnl             {1} \
    CONFIG.sys_reset_polarity         {ACTIVE_LOW} \
    CONFIG.ref_clk_freq               {100_MHz} \
] [get_ips xdma_0]

# The IP derives the PCI device ID from the link configuration; x16 Gen3 gives 0x903F.
# Worth printing, because the host driver binds on this and will simply ignore a device
# whose ID is not in its table -- a failure that looks exactly like the card being
# absent. 0x903F is in the table shipped with the Xilinx XDMA driver.
puts "PCI DEVICE ID: 0x[get_property CONFIG.pf0_device_id [get_ips xdma_0]] (vendor 0x[get_property CONFIG.vendor_id [get_ips xdma_0]])"

# ------------------------------------------------------- memory-mapped crossbar
# One master, two slaves: BRAM then URAM, 64 KB each.
create_ip -name axi_crossbar -vendor xilinx.com -library ip -module_name axi_xbar_mm
set_property -dict [list \
    CONFIG.NUM_SI {1} CONFIG.NUM_MI {2} \
    CONFIG.PROTOCOL {AXI4} CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} \
    CONFIG.ID_WIDTH {4} \
    CONFIG.M00_A00_BASE_ADDR {0x00000000c0000000} CONFIG.M00_A00_ADDR_WIDTH {16} \
    CONFIG.M01_A00_BASE_ADDR {0x00000000c0010000} CONFIG.M01_A00_ADDR_WIDTH {16} \
] [get_ips axi_xbar_mm]

# ----------------------------------------------------------- register crossbar
create_ip -name axi_crossbar -vendor xilinx.com -library ip -module_name axi_xbar_lite
set_property -dict [list \
    CONFIG.NUM_SI {1} CONFIG.NUM_MI {2} \
    CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {32} CONFIG.DATA_WIDTH {32} \
    CONFIG.M00_A00_BASE_ADDR {0x0000000000030000} CONFIG.M00_A00_ADDR_WIDTH {16} \
    CONFIG.M01_A00_BASE_ADDR {0x0000000000040000} CONFIG.M01_A00_ADDR_WIDTH {16} \
] [get_ips axi_xbar_lite]

# ------------------------------------------------------------------ DMA targets
# One controller definition used twice. SINGLE_PORT_BRAM means only port A exists, which
# is all a DMA target needs and halves the wiring.
# ID_WIDTH is not optional here, and its default of 0 is a trap. With no ID ports the
# controller cannot echo a transaction ID back, so the crossbar's BID and RID inputs are
# left with nothing driving them -- which synthesises with only a warning and then fails
# in opt_design, where a LUT inside the crossbar's register slice is found to have an
# input that no longer connects to anything. It must match the crossbar's ID_WIDTH.
create_ip -name axi_bram_ctrl -vendor xilinx.com -library ip -module_name axi_bram_ctrl_0
set_property -dict [list \
    CONFIG.DATA_WIDTH {512} CONFIG.SUPPORTS_NARROW_BURST {0} \
    CONFIG.SINGLE_PORT_BRAM {1} CONFIG.ECC_TYPE {0} CONFIG.MEM_DEPTH {1024} \
    CONFIG.ID_WIDTH {4} \
] [get_ips axi_bram_ctrl_0]

# Same geometry, different silicon. Keeping them identical is the point: the host runs
# one test against both, so any difference in the result is a property of the memory
# rather than of how it was wired up.
#
# The output register is off in both, giving a read latency of one cycle, which is what
# axi_bram_ctrl assumes. Leaving it on would return the previous word on every read --
# a fault that looks like data corruption rather than a latency mismatch.
foreach {name prim} {blk_mem_bram BRAM blk_mem_uram URAM} {
    create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name $name
    set_property -dict [list \
        CONFIG.Interface_Type {Native} CONFIG.Memory_Type {Single_Port_RAM} \
        CONFIG.Use_Byte_Write_Enable {true} CONFIG.Byte_Size {8} \
        CONFIG.Write_Width_A {512} CONFIG.Write_Depth_A {1024} CONFIG.Read_Width_A {512} \
        CONFIG.Enable_A {Use_ENA_Pin} \
        CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
        CONFIG.PRIM_type_to_Implement $prim \
    ] [get_ips $name]
}

# ------------------------------------------------------------ GPIO: LEDs and IRQ
# Channel 1 is the eight LEDs. Channel 2 is one bit driving the endpoint's user
# interrupt request, so the host can raise an interrupt and confirm it arrived without
# any other hardware being involved.
create_ip -name axi_gpio -vendor xilinx.com -library ip -module_name axi_gpio_led
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH  {8} CONFIG.C_ALL_OUTPUTS   {1} \
    CONFIG.C_IS_DUAL     {1} \
    CONFIG.C_GPIO2_WIDTH {1} CONFIG.C_ALL_OUTPUTS_2 {1} \
] [get_ips axi_gpio_led]

# -------------------------------------------------------------- XVC over PCIe
# C_DEBUG_MODE 2 is the AXI-to-JTAG bridge: the host opens /dev/xdma0_user, xvc_pcie
# serves it as a virtual cable, and Hardware Manager connects with no cable attached.
create_ip -name debug_bridge -vendor xilinx.com -library ip -module_name debug_bridge_xvc
set_property -dict [list CONFIG.C_DEBUG_MODE {2}] [get_ips debug_bridge_xvc]

# Synthesise the IP in context with the rest of the design rather than out of context.
#
# An out-of-context run constrains the IP with a placeholder clock taken from the IP's own
# default -- 100 ns for the crossbars here, against an actual 4 ns. The IP is then built
# with almost no effort spent on timing and afterwards asked to run sixty times faster.
# Vivado says so, as a warning among hundreds. On a 512-bit datapath at 250 MHz that is
# not a risk worth taking to save rebuild time.
#
# Only the IP created above, and one at a time: the debug bridge contains a block design
# whose own IP is locked, and asking to change a read-only property there aborts the
# whole script.
foreach name {xdma_0 axi_xbar_mm axi_xbar_lite axi_bram_ctrl_0
              blk_mem_bram blk_mem_uram axi_gpio_led debug_bridge_xvc} {
    set ip [get_ips -quiet $name]
    if {$ip eq ""} { continue }
    set f [get_files -quiet [get_property IP_FILE $ip]]
    if {$f eq ""} { continue }
    if {[catch {set_property generate_synth_checkpoint false $f} msg]} {
        puts "NOTE: $name stays out-of-context ($msg)"
    }
}

foreach ip [get_ips] { generate_target all [get_ips $ip] }

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

# Where the endpoint actually landed, and on which transceivers. This is the check
# against the table at the end of xdc/pcie.xdc: the lane pins are not constrained, so
# this is the only confirmation that the tool chose the quads that reach the connector.
foreach site [get_sites -quiet -filter {SITE_TYPE =~ PCIE*} -of_objects [get_cells -quiet -hier -filter {REF_NAME =~ PCIE40E4*}]] {
    puts "PCIE BLOCK: $site"
}
set gtch [lsort [get_sites -quiet -of_objects [get_cells -quiet -hier -filter {REF_NAME =~ GTYE4_CHANNEL*}]]]
puts "GT CHANNELS: [llength $gtch] -> $gtch"

# This design has no ILA or VIO of its own, so there are no probes to write and Vivado
# says "No debug cores were found". That is the expected result, not a failure: the debug
# bridge is a bridge, not a probed core. It carries whatever cores exist in the design
# being debugged *through* it, and this one has none.
#
# The call stays so that adding an ILA later produces its .ltx without anyone having to
# remember to re-add it.
if {[llength [get_debug_cores -quiet]]} {
    write_debug_probes -force $outdir/${prj_name}.ltx
    puts "  probes:    $outdir/${prj_name}.ltx"
}

file copy -force [get_property DIRECTORY [get_runs impl_1]]/${top}.bit $outdir/${prj_name}.bit

puts "GOLDEN PCIE BUILD OK"
puts "  bitstream: $outdir/${prj_name}.bit"
