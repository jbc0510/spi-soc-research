# Round-6 sim-only BD: VIP master (CPU stand-in) + real axi_cdma +
# real axi_quad_spi + VIP slave-mem (DDR stand-in), one SmartConnect.
# Question under test: does CDMA KeyHole Write hold AWADDR at the DTR?
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
set_property -dict [list CONFIG.C_FIFO_DEPTH {256} \
  CONFIG.C_NUM_SS_BITS {1}] [get_bd_cells axi_quad_spi_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smartconnect_0
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {3} \
  CONFIG.NUM_CLKS {1}] [get_bd_cells smartconnect_0]

connect_bd_intf_net [get_bd_intf_pins axi_vip_0/M_AXI] \
  [get_bd_intf_pins smartconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_cdma_0/M_AXI] \
  [get_bd_intf_pins smartconnect_0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M00_AXI] \
  [get_bd_intf_pins axi_quad_spi_0/AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M01_AXI] \
  [get_bd_intf_pins axi_cdma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M02_AXI] \
  [get_bd_intf_pins axi_vip_1/S_AXI]

connect_bd_net [get_bd_ports aclk] \
  [get_bd_pins axi_vip_0/aclk] [get_bd_pins axi_vip_1/aclk] \
  [get_bd_pins axi_cdma_0/s_axi_lite_aclk] \
  [get_bd_pins axi_cdma_0/m_axi_aclk] \
  [get_bd_pins axi_quad_spi_0/s_axi_aclk] \
  [get_bd_pins axi_quad_spi_0/ext_spi_clk] \
  [get_bd_pins smartconnect_0/aclk]
connect_bd_net [get_bd_ports aresetn] \
  [get_bd_pins axi_vip_0/aresetn] [get_bd_pins axi_vip_1/aresetn] \
  [get_bd_pins axi_cdma_0/s_axi_lite_aresetn] \
  [get_bd_pins axi_quad_spi_0/s_axi_aresetn] \
  [get_bd_pins smartconnect_0/aresetn]

assign_bd_address -offset 0xA0000000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces axi_vip_0/Master_AXI] \
  [get_bd_addr_segs axi_quad_spi_0/AXI_LITE/Reg] -force
assign_bd_address -offset 0xA0010000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces axi_vip_0/Master_AXI] \
  [get_bd_addr_segs axi_cdma_0/S_AXI_LITE/Reg] -force
assign_bd_address -offset 0x00000000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces axi_vip_0/Master_AXI] \
  [get_bd_addr_segs axi_vip_1/S_AXI/Reg] -force
assign_bd_address -offset 0xA0000000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces axi_cdma_0/Data] \
  [get_bd_addr_segs axi_quad_spi_0/AXI_LITE/Reg] -force
assign_bd_address -offset 0x00000000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces axi_cdma_0/Data] \
  [get_bd_addr_segs axi_vip_1/S_AXI/Reg] -force
catch { exclude_bd_addr_seg -target_address_space \
  [get_bd_addr_spaces axi_cdma_0/Data] \
  [get_bd_addr_segs axi_cdma_0/S_AXI_LITE/Reg] }

validate_bd_design
save_bd_design
puts "R6_SIMBD: sim_keyhole BD validated"
