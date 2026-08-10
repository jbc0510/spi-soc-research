# Build base BD then apply the round-6 v2 delta, in one session.
create_project -in_memory -part xczu9eg-ffvb1156-2-e
source hardware/spi_bm_bd_2025p1.tcl
puts "R6V2RUN: base BD sourced; cells = [get_bd_cells]"
puts "R6V2RUN: reset pins = [get_bd_pins -of_objects \
  [get_bd_cells proc_sys_reset_0]]"
source hardware/add_cdma_r6_v2.tcl
puts "R6V2RUN: post-delta cells = [get_bd_cells]"
puts "R6V2RUN: QSPI intf = [get_bd_intf_pins -of_objects \
  [get_bd_cells axi_quad_spi_0]]"
puts "R6V2RUN: DONE"
