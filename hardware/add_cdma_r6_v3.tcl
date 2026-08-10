# Round-6 v3: CDMA keyhole -> AXI Quad SPI (enhanced mode), payload sourced
# from PL BRAM instead of DDR. Supersedes add_cdma_r6_v2.tcl.
#
# WHY BRAM: v2 failed with BD 41-237 ID_WIDTH 17 vs 6. Chain (all probed
# 2026-08-10): PS M_AXI_HPM0_FPD advertises ID=16 as fixed silicon (no param);
# xbar inherits S00_THREAD_ID_WIDTH=16; PG059 adds ceil_log2(NUM_SI)=1 -> 17;
# every PS slave port (HP0-3, HPC0-1, LPD) caps at ID=6. QSPI
# C_S_AXI4_ID_WIDTH read-only at 4; axi_ic wrapper THREAD_ID_WIDTH read-only;
# axi_ic_0/xbar does not exist until validate_bd_design runs, so it cannot be
# overridden. => No parameter fix exists. HP0 is the ONLY slave that rejects
# ID=17 (AXI_FULL accepted 17; auto_pc narrows 17->0). Remove HP0.
#
# TRADEOFF (must appear in the paper): the DMA source is PL block RAM, not
# system DDR. This still answers SOW 2.b (PIO vs DMA transfer mechanism, CPU
# offload, FIXED-burst FIFO service) but does NOT characterize DMA from
# system memory. Document as a stated limitation.

proc setv {obj param want} {
  catch { set_property $param $want $obj }
  set got "<unreadable>"
  catch { set got [get_property $param $obj] }
  if {$got ne $want} {
    puts "R6V3:   FAILED $param -> wanted $want, got $got" ; return 0
  }
  puts "R6V3:   OK $param = $got" ; return 1
}

puts "R6V3: === STEP 1 — tear down SmartConnect + QSPI legacy AXI nets ==="
catch { delete_bd_objs [get_bd_intf_nets smartconnect_0_M00_AXI] }
catch { delete_bd_objs [get_bd_intf_nets -of_objects \
          [get_bd_intf_pins axi_quad_spi_0/AXI_LITE]] }
foreach p {axi_quad_spi_0/s_axi_aclk axi_quad_spi_0/s_axi_aresetn} {
  catch { disconnect_bd_net -net [get_bd_nets -of_objects [get_bd_pins $p]] \
            [get_bd_pins $p] }
}
catch { delete_bd_objs [get_bd_intf_nets -of_objects \
          [get_bd_cells smartconnect_0]] }
catch { delete_bd_objs [get_bd_cells smartconnect_0] }
puts "R6V3: cells now: [get_bd_cells]"

puts "R6V3: === STEP 2 — QSPI enhanced mode (single AXI4 slave port) ==="
set_property -dict [list CONFIG.C_TYPE_OF_AXI4_INTERFACE {1} \
  CONFIG.C_XIP_MODE {0} CONFIG.C_SPI_MODE {0} CONFIG.C_FIFO_DEPTH {256} \
  CONFIG.C_SCK_RATIO {16} CONFIG.C_NUM_SS_BITS {1}] \
  [get_bd_cells axi_quad_spi_0]
foreach {p want} {CONFIG.C_TYPE_OF_AXI4_INTERFACE 1 CONFIG.C_XIP_MODE 0 \
                  CONFIG.C_SPI_MODE 0 CONFIG.C_FIFO_DEPTH 256 \
                  CONFIG.C_SCK_RATIO 16} {
  set got [get_property $p [get_bd_cells axi_quad_spi_0]]
  if {$got ne $want} { error "R6V3 ABORT: $p = $got, want $want" }
  puts "R6V3:   OK $p = $got"
}
puts "R6V3: QSPI intf: [get_bd_intf_pins -of_objects \
  [get_bd_cells axi_quad_spi_0]]"

puts "R6V3: === STEP 3 — PS master 32-bit; HP0 deliberately NOT enabled ==="
setv [get_bd_cells zynq_ultra_ps_e_0] CONFIG.PSU__MAXIGP0__DATA_WIDTH 32

puts "R6V3: === STEP 4 — CDMA: simple mode, 32-bit, max burst 16 ==="
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_cdma axi_cdma_0
set_property -dict [list CONFIG.C_INCLUDE_SG {0} \
  CONFIG.C_M_AXI_MAX_BURST_LEN {16} \
  CONFIG.C_M_AXI_DATA_WIDTH {32}] [get_bd_cells axi_cdma_0]

puts "R6V3: === STEP 5 — BRAM as DMA source (64 KB, 32-bit) ==="
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl bram_ctrl_0
puts "R6V3: --- axi_bram_ctrl candidate params ---"
foreach p [list_property [get_bd_cells bram_ctrl_0]] {
  if {[regexp -nocase {DATA_WIDTH|ID_WIDTH|SINGLE_PORT|ECC|PROTOCOL|MEM_DEPTH} $p]} {
    puts [format "R6V3:   %-40s = %s" $p \
      [get_property $p [get_bd_cells bram_ctrl_0]]]
  }
}
setv [get_bd_cells bram_ctrl_0] CONFIG.DATA_WIDTH 32
setv [get_bd_cells bram_ctrl_0] CONFIG.SINGLE_PORT_BRAM 1
catch { setv [get_bd_cells bram_ctrl_0] CONFIG.ECC_TYPE 0 }

# Let IPI create and configure the block memory from the controller's own
# settings. Manual blk_mem_gen param names were unverified and were being set
# inside a bare catch{} -- same false-success trap as the read-only params.
if {[catch { apply_bd_automation -rule xilinx.com:bd_rule:bram_cntlr \
      -config {BRAM "New Blk_Mem_Gen" } \
      [get_bd_intf_pins bram_ctrl_0/BRAM_PORTA] } e]} {
  puts "R6V3:   bram automation failed: $e"
} else {
  puts "R6V3:   bram automation OK; cells: [get_bd_cells]"
}

puts "R6V3: === STEP 6 — AXI Interconnect: 2 SI / 3 MI, NO HP0 ==="
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_ic_0
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {3}] \
  [get_bd_cells axi_ic_0]
setv [get_bd_cells axi_ic_0] CONFIG.M00_ISSUANCE 1

connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] \
  [get_bd_intf_pins axi_ic_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_cdma_0/M_AXI] \
  [get_bd_intf_pins axi_ic_0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M00_AXI] \
  [get_bd_intf_pins axi_quad_spi_0/AXI_FULL]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M01_AXI] \
  [get_bd_intf_pins axi_cdma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M02_AXI] \
  [get_bd_intf_pins bram_ctrl_0/S_AXI]

puts "R6V3: === STEP 7 — clocks and resets ==="
set clk [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]
set rst [get_bd_pins proc_sys_reset_0/peripheral_aresetn]
connect_bd_net $clk [get_bd_pins axi_cdma_0/s_axi_lite_aclk] \
  [get_bd_pins axi_cdma_0/m_axi_aclk] \
  [get_bd_pins axi_quad_spi_0/s_axi4_aclk] \
  [get_bd_pins axi_quad_spi_0/ext_spi_clk] \
  [get_bd_pins bram_ctrl_0/s_axi_aclk] \
  [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] \
  [get_bd_pins axi_ic_0/ACLK] \
  [get_bd_pins axi_ic_0/S00_ACLK] [get_bd_pins axi_ic_0/S01_ACLK] \
  [get_bd_pins axi_ic_0/M00_ACLK] [get_bd_pins axi_ic_0/M01_ACLK] \
  [get_bd_pins axi_ic_0/M02_ACLK]
connect_bd_net $rst [get_bd_pins axi_cdma_0/s_axi_lite_aresetn] \
  [get_bd_pins axi_quad_spi_0/s_axi4_aresetn] \
  [get_bd_pins bram_ctrl_0/s_axi_aresetn] \
  [get_bd_pins axi_ic_0/S00_ARESETN] [get_bd_pins axi_ic_0/S01_ARESETN] \
  [get_bd_pins axi_ic_0/M00_ARESETN] [get_bd_pins axi_ic_0/M01_ARESETN] \
  [get_bd_pins axi_ic_0/M02_ARESETN]
connect_bd_net [get_bd_pins proc_sys_reset_0/interconnect_aresetn] \
  [get_bd_pins axi_ic_0/ARESETN]

puts "R6V3: === STEP 8 — address map (BRAM at 0xA0020000, 64 KB) ==="
foreach {space seg off rng} {
  zynq_ultra_ps_e_0/Data axi_quad_spi_0/aximm/MEM0    0xA0000000 0x00010000
  zynq_ultra_ps_e_0/Data axi_cdma_0/S_AXI_LITE/Reg    0xA0010000 0x00010000
  zynq_ultra_ps_e_0/Data bram_ctrl_0/S_AXI/Mem0       0xA0020000 0x00010000
  axi_cdma_0/Data        axi_quad_spi_0/aximm/MEM0    0xA0000000 0x00010000
  axi_cdma_0/Data        bram_ctrl_0/S_AXI/Mem0       0xA0020000 0x00010000
} {
  if {[catch { assign_bd_address -offset $off -range $rng \
      -target_address_space [get_bd_addr_spaces $space] \
      [get_bd_addr_segs $seg] -force } e]} {
    puts "R6V3:   ADDR FAIL $space <- $seg : $e"
  } else { puts "R6V3:   addr OK $space <- $seg @ $off" }
}
catch { exclude_bd_addr_seg \
  -target_address_space [get_bd_addr_spaces axi_cdma_0/Data] \
  [get_bd_addr_segs axi_cdma_0/S_AXI_LITE/Reg] }

validate_bd_design

puts "R6V3: === GATE — no width converters in the FIXED path ==="
set bad {}
foreach c [get_bd_cells -hierarchical -quiet -filter {NAME =~ "auto_*"}] {
  puts "R6V3:   coupler: $c"
  if {[regexp {auto_(us|ds)$} $c]} { lappend bad $c }
}
if {[llength $bad]} { error "R6V3 ABORT: width converters present: $bad" }
puts "R6V3:   GATE PASS"
save_bd_design
puts "R6V3: v3 delta applied and validated"
