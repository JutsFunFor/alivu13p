set_false_path -to [get_ports {user_led[*] pcie_link_up}]
# Status synchronizers only. The AXI converter supplies its own FIFO CDC constraints.
set_false_path -to [get_pins -hier -regexp {.*(calib_sync_reg|ecc_sync_reg|ready_sync_reg|failed_sync_reg)\[0\]/D}]

# The memory and the link run off different oscillators -- the DDR4 reference on the
# board and the PCIe reference from the slot -- so their clock trees have no common
# ancestor and no fixed phase relationship. Vivado does not assume that: without this,
# every crossing lands in the **async_default** path group, where it is timed against a
# worst-case alignment nothing in the design has to satisfy. That reports as a real
# failure, and a large one -- WNS -2.479 ns, ~10 ns of total negative slack, all of it
# in the clock converter's FIFO.
#
# Declaring them asynchronous is not a way of hiding those paths. Every crossing between
# the two domains goes through something built for it: bulk data through the AXI clock
# converter's asynchronous FIFO, status bits through the two-stage synchronizers
# false-pathed above, and reset through asynchronous assertion with synchronized release
# in each domain.
#
# This needs the design's constraints processed after the memory controller's, since
# c1_sys_clk_p is a clock the IP creates. tcl/prj.tcl sets PROCESSING_ORDER LATE for
# exactly that reason; without it these names resolve to nothing and the constraint is
# silently dropped.
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks c1_sys_clk_p] \
    -group [get_clocks -include_generated_clocks pcie_refclk]
