# Round-6 sim-only BD: VIP master (CPU stand-in) + real axi_cdma +
# real axi_quad_spi (ENHANCED mode) + VIP slave-mem (source stand-in),
# one axi_interconnect (SmartConnect blocks FIXED unconditionally, UG1037).
# SIM/SILICON DELTAS: source is VIP slave-mem at 0x0, not BRAM at 0xA0020000
#   (source addr irrelevant to the destination-hold question under test);
#   VIP master is AXI4LITE, so S00 gets an auto_pc the real BD lacks -- S00 is
#   the control leg, NOT the CDMA FIXED leg (S01), so it cannot mask the DUT.
# Question under test: does CDMA KeyHole Write hold AWADDR at the DTR?
proc setv {cell param val} {
  set_property $param $val $cell
  set got [get_property $param $cell]
  if {$got ne $val} { error "SETV FAIL $param want=$val got=$got" }
  puts "R6_SIMBD: setv $param = $got"
}
create_bd_design sim_keyhole
create_bd_port -dir I -type clk -freq_hz 100000000 aclk
create_bd_port -dir I -type rst aresetn

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vip axi_vip_0
set_property -dict [list CONFIG.INTERFACE_MODE {MASTER} \
  CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {32} \
  CONFIG.DATA_WIDTH {32}] [get_bd_cells axi_vip_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vip axi_vip_1
set_property -dict [list CONFIG.INTERFACE_MODE {SLAVE} \
  CONFIG.PROTOCOL {AXI4} CONFIG.ADDR_WIDTH {32} \
  CONFIG.DATA_WIDTH {32}] [get_bd_cells axi_vip_1]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_cdma axi_cdma_0
set_property -dict [list CONFIG.C_INCLUDE_SG {0} \
  CONFIG.C_M_AXI_MAX_BURST_LEN {16} \
  CONFIG.C_M_AXI_DATA_WIDTH {32}] [get_bd_cells axi_cdma_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_quad_spi axi_quad_spi_0
foreach {prm val} {CONFIG.C_TYPE_OF_AXI4_INTERFACE 1 CONFIG.C_XIP_MODE 0 \
                   CONFIG.C_SPI_MODE 0 CONFIG.C_FIFO_DEPTH 256 \
                   CONFIG.C_SCK_RATIO 16 CONFIG.C_NUM_SS_BITS 1} {
  setv [get_bd_cells axi_quad_spi_0] $prm $val
}

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_ic_0
setv [get_bd_cells axi_ic_0] CONFIG.NUM_SI 2
setv [get_bd_cells axi_ic_0] CONFIG.NUM_MI 3
setv [get_bd_cells axi_ic_0] CONFIG.M00_ISSUANCE 1

connect_bd_intf_net [get_bd_intf_pins axi_vip_0/M_AXI] \
  [get_bd_intf_pins axi_ic_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_cdma_0/M_AXI] \
  [get_bd_intf_pins axi_ic_0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M00_AXI] \
  [get_bd_intf_pins axi_quad_spi_0/AXI_FULL]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M01_AXI] \
  [get_bd_intf_pins axi_cdma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M02_AXI] \
  [get_bd_intf_pins axi_vip_1/S_AXI]

connect_bd_net [get_bd_ports aclk] \
  [get_bd_pins axi_vip_0/aclk] [get_bd_pins axi_vip_1/aclk] \
  [get_bd_pins axi_cdma_0/s_axi_lite_aclk] \
  [get_bd_pins axi_cdma_0/m_axi_aclk] \
  [get_bd_pins axi_quad_spi_0/s_axi4_aclk] \
  [get_bd_pins axi_quad_spi_0/ext_spi_clk] \
  [get_bd_pins axi_ic_0/ACLK] \
  [get_bd_pins axi_ic_0/S00_ACLK] [get_bd_pins axi_ic_0/S01_ACLK] \
  [get_bd_pins axi_ic_0/M00_ACLK] [get_bd_pins axi_ic_0/M01_ACLK] \
  [get_bd_pins axi_ic_0/M02_ACLK]
connect_bd_net [get_bd_ports aresetn] \
  [get_bd_pins axi_vip_0/aresetn] [get_bd_pins axi_vip_1/aresetn] \
  [get_bd_pins axi_cdma_0/s_axi_lite_aresetn] \
  [get_bd_pins axi_quad_spi_0/s_axi4_aresetn] \
  [get_bd_pins axi_ic_0/ARESETN] \
  [get_bd_pins axi_ic_0/S00_ARESETN] [get_bd_pins axi_ic_0/S01_ARESETN] \
  [get_bd_pins axi_ic_0/M00_ARESETN] [get_bd_pins axi_ic_0/M01_ARESETN] \
  [get_bd_pins axi_ic_0/M02_ARESETN]

assign_bd_address -offset 0xA0000000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces axi_vip_0/Master_AXI] \
  [get_bd_addr_segs axi_quad_spi_0/aximm/MEM0] -force
assign_bd_address -offset 0xA0010000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces axi_vip_0/Master_AXI] \
  [get_bd_addr_segs axi_cdma_0/S_AXI_LITE/Reg] -force
assign_bd_address -offset 0x00000000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces axi_vip_0/Master_AXI] \
  [get_bd_addr_segs axi_vip_1/S_AXI/Reg] -force
assign_bd_address -offset 0xA0000000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces axi_cdma_0/Data] \
  [get_bd_addr_segs axi_quad_spi_0/aximm/MEM0] -force
assign_bd_address -offset 0x00000000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces axi_cdma_0/Data] \
  [get_bd_addr_segs axi_vip_1/S_AXI/Reg] -force
catch { exclude_bd_addr_seg -target_address_space \
  [get_bd_addr_spaces axi_cdma_0/Data] \
  [get_bd_addr_segs axi_cdma_0/S_AXI_LITE/Reg] }

validate_bd_design
save_bd_design
puts "R6_SIMBD: sim_keyhole BD validated"
