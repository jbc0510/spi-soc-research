# Reproducible Task 2b CDMA -> AXI Quad SPI simulation.
# Run from this repository with Vivado 2025.1:
#   vivado -mode batch -source hardware/sim/run_task2b_cdma_loopback.tcl
# The unique /tmp run directory preserves earlier simulations.
set REPO [file normalize [file join [file dirname [info script]] ../..]]
set RUNROOT [file join /tmp "msu2_task2b_cdma_[pid]"]
file mkdir $RUNROOT
create_project r6sim [file join $RUNROOT r6sim] -part xczu9eg-ffvb1156-2-e -force
source [file join $REPO hardware sim sim_keyhole_bd.tcl]
make_wrapper -files [get_files */sim_keyhole.bd] -top
add_files -norecurse [glob [file join $RUNROOT r6sim r6sim.gen sources_1 bd sim_keyhole hdl sim_keyhole_wrapper.v]]
add_files -fileset sim_1 -norecurse [file join $REPO hardware sim tb_keyhole.sv]
set_property top tb_keyhole [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property xsim.simulate.runtime 1000000ns [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
puts "TASK2B_CDMA_SIM: complete; run directory=$RUNROOT"
exit
