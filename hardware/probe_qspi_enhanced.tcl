# Probe: what does axi_quad_spi:3.2 look like in ENHANCED mode?
# Scratch project, no synth. Prints intf pins, pins, and legal params.
create_project -in_memory -part xczu9eg-ffvb1156-2-e
create_bd_design probe_qspi
set q [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_quad_spi:3.2 qspi]

puts "=== BEFORE (legacy defaults) ==="
puts "INTF: [get_bd_intf_pins -of_objects $q]"
puts "PINS: [get_bd_pins -of_objects $q]"

# List every CONFIG param whose name hints at mode/axi4/xip
puts "=== CANDIDATE PARAMS ==="
foreach p [list_property $q] {
  if {[regexp -nocase {CONFIG\..*(AXI4|XIP|PERF|MODE|RATIO|FIFO)} $p]} {
    puts [format "%-46s = %s" $p [get_property $p $q]]
  }
}

puts "=== APPLYING ENHANCED MODE ==="
if {[catch {
  set_property -dict [list \
    CONFIG.C_TYPE_OF_AXI4_INTERFACE {1} \
    CONFIG.C_XIP_MODE {0} \
    CONFIG.C_SPI_MODE {0} \
    CONFIG.C_FIFO_DEPTH {256} \
    CONFIG.C_SCK_RATIO {16} \
    CONFIG.C_NUM_SS_BITS {1}] $q
} emsg]} { puts "SET FAILED: $emsg" }

puts "=== AFTER ==="
puts "INTF: [get_bd_intf_pins -of_objects $q]"
puts "PINS: [get_bd_pins -of_objects $q]"
foreach p {CONFIG.C_TYPE_OF_AXI4_INTERFACE CONFIG.C_XIP_MODE \
           CONFIG.C_SPI_MODE CONFIG.C_FIFO_DEPTH CONFIG.C_SCK_RATIO} {
  if {![catch {set v [get_property $p $q]}]} {
    puts [format "%-40s = %s" $p $v]
  }
}
puts "=== ADDR SEGS ==="
foreach s [get_bd_addr_segs -of_objects $q] { puts "  $s" }
puts "PROBE_DONE"
