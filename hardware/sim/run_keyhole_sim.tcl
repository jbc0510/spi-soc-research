set REPO $::env(HOME)/spi-soc-research
file delete -force /tmp/r6_keyhole_sim
create_project r6sim /tmp/r6_keyhole_sim -part xczu9eg-ffvb1156-2-e -force
source $REPO/hardware/sim/sim_keyhole_bd.tcl
make_wrapper -files [get_files */sim_keyhole.bd] -top
add_files -norecurse [glob /tmp/r6_keyhole_sim/r6sim.gen/sources_1/bd/sim_keyhole/hdl/sim_keyhole_wrapper.v]
add_files -fileset sim_1 -norecurse $REPO/hardware/sim/tb_keyhole.sv
set_property top tb_keyhole [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
catch { run all }
puts "R6_SIMRUN: launch complete"
