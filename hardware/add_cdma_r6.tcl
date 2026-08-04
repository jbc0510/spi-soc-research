# Round-6 delta: add AXI CDMA (keyhole-capable) to spi_benchmark BD.
# Source AFTER hardware/spi_bm_bd_2025p1.tcl in the same session.
# Keyhole is a RUNTIME bit (CDMACR[4]/[5]) set by the benchmark app;
# here we only guarantee MaxBurst<=16 per PG034 keyhole constraint.

# 1. PS: enable S_AXI_HP0_FPD (SAXIGP2) for CDMA->DDR
set_property CONFIG.PSU__USE__S_AXI_GP2 {1} [get_bd_cells zynq_ultra_ps_e_0]

# 2. CDMA: simple mode, 32-bit master, max burst 16
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_cdma axi_cdma_0
set_property -dict [list CONFIG.C_INCLUDE_SG {0} \
  CONFIG.C_M_AXI_MAX_BURST_LEN {16} \
  CONFIG.C_M_AXI_DATA_WIDTH {32}] [get_bd_cells axi_cdma_0]

# 3. SmartConnect: 2 slaves in, 3 masters out
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {3}] \
  [get_bd_cells smartconnect_0]

# 4. Interface wiring
connect_bd_intf_net [get_bd_intf_pins axi_cdma_0/M_AXI] \
  [get_bd_intf_pins smartconnect_0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M01_AXI] \
  [get_bd_intf_pins axi_cdma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M02_AXI] \
  [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]

# 5. Clock/reset: join the existing pl_clk0 + peripheral reset nets
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
  [get_bd_pins axi_cdma_0/s_axi_lite_aclk] \
  [get_bd_pins axi_cdma_0/m_axi_aclk] \
  [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
  [get_bd_pins axi_cdma_0/s_axi_lite_aresetn]

# 6. Address map: assign the three real paths
assign_bd_address -offset 0xA0010000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
  [get_bd_addr_segs axi_cdma_0/S_AXI_LITE/Reg] -force
assign_bd_address -offset 0xA0000000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces axi_cdma_0/Data] \
  [get_bd_addr_segs axi_quad_spi_0/AXI_LITE/Reg] -force
assign_bd_address -offset 0x00000000 -range 0x80000000 \
  -target_address_space [get_bd_addr_spaces axi_cdma_0/Data] \
  [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/HP0_DDR_LOW] -force

# 7. Exclude the fan-out artifacts SmartConnect exposes:
#    PS looping into its own DDR via HP0, and CDMA seeing its own regs.
foreach seg {HP0_DDR_LOW HP0_DDR_HIGH HP0_QSPI HP0_PCIE_LOW \
             HP0_PCIE_HIGH1 HP0_PCIE_HIGH2 HP0_LPS_OCM} {
  catch { exclude_bd_addr_seg \
    -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
    [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/$seg] }
}
catch { exclude_bd_addr_seg \
  -target_address_space [get_bd_addr_spaces axi_cdma_0/Data] \
  [get_bd_addr_segs axi_cdma_0/S_AXI_LITE/Reg] }

validate_bd_design
save_bd_design
puts "R6_CDMA: delta applied and validated"
