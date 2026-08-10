# Round-6 v2 delta: AXI CDMA (keyhole) -> AXI Quad SPI in ENHANCED mode,
# via AXI Interconnect (NOT SmartConnect: SC blocks FIXED bursts, UG1037).
# Supersedes add_cdma_r6.tcl (kept in git as the falsified topology).
# Source AFTER hardware/spi_bm_bd_2025p1.tcl in the same session.
#
# Names verified by hardware/probe_qspi_enhanced.tcl on 2025.1 / xczu9eg:
#   enhanced mode intf = AXI_FULL (AXI_LITE disappears)
#   clk/rst pins       = s_axi4_aclk / s_axi4_aresetn
#   addr segment       = aximm/MEM0  (memory seg, not Reg)
#   C_S_AXI4_ID_WIDTH  = 4 (enabled only in enhanced mode)

# set-and-verify: set_property emits only a CRITICAL WARNING on read-only
# params, so catch{} reports false success. Always read back and compare.
proc setv {obj param want} {
  catch { set_property $param $want $obj }
  set got "<unreadable>"
  catch { set got [get_property $param $obj] }
  if {$got ne $want} {
    puts "R6V2:   FAILED $param -> wanted $want, got $got"
    return 0
  }
  puts "R6V2:   OK $param = $got"
  return 1
}

puts "R6V2: === STEP 1 — tear down SmartConnect and QSPI AXI nets ==="
# QSPI's AXI_LITE intf + s_axi_aclk/aresetn pins VANISH on mode change,
# so every net touching them must go first or set_property will error.
foreach n {smartconnect_0_M00_AXI} {
  catch { delete_bd_objs [get_bd_intf_nets $n] }
}
catch { delete_bd_objs [get_bd_intf_nets -of_objects \
          [get_bd_intf_pins axi_quad_spi_0/AXI_LITE]] }
foreach p {axi_quad_spi_0/s_axi_aclk axi_quad_spi_0/s_axi_aresetn} {
  catch { disconnect_bd_net -net [get_bd_nets -of_objects [get_bd_pins $p]] \
            [get_bd_pins $p] }
}
# Now the SmartConnect itself (removes its remaining intf/clk nets).
catch { delete_bd_objs [get_bd_intf_nets -of_objects \
          [get_bd_cells smartconnect_0]] }
catch { delete_bd_objs [get_bd_cells smartconnect_0] }
puts "R6V2: smartconnect_0 removed; cells now: [get_bd_cells]"

puts "R6V2: === STEP 2 — QSPI to ENHANCED mode (AXI4 slave) ==="
set_property -dict [list \
  CONFIG.C_TYPE_OF_AXI4_INTERFACE {1} \
  CONFIG.C_XIP_MODE {0} \
  CONFIG.C_SPI_MODE {0} \
  CONFIG.C_FIFO_DEPTH {256} \
  CONFIG.C_SCK_RATIO {16} \
  CONFIG.C_NUM_SS_BITS {1}] [get_bd_cells axi_quad_spi_0]
# Fail loudly if the tool coerced anything (comparability depends on these).
foreach {p want} {CONFIG.C_TYPE_OF_AXI4_INTERFACE 1 CONFIG.C_XIP_MODE 0 \
                  CONFIG.C_SPI_MODE 0 CONFIG.C_FIFO_DEPTH 256 \
                  CONFIG.C_SCK_RATIO 16} {
  set got [get_property $p [get_bd_cells axi_quad_spi_0]]
  if {$got ne $want} { error "R6V2 ABORT: $p = $got, expected $want" }
  puts "R6V2:   OK $p = $got"
}
puts "R6V2: QSPI intf now: [get_bd_intf_pins -of_objects \
  [get_bd_cells axi_quad_spi_0]]"

puts "R6V2: === STEP 3 — PS ports 32-bit to avoid ALL width couplers ==="
set_property CONFIG.PSU__USE__S_AXI_GP2 {1} [get_bd_cells zynq_ultra_ps_e_0]
# CRITICAL: M_AXI_HPM0_FPD defaults to 128-bit (probe 2026-08-10). The xbar
# sizes to the widest SI, so a 128-bit PS master forces auto_us on the CDMA
# SI and auto_ds into the QSPI MI. PG059: upsizing PACKS data when the addr
# channel permits -> packing a FIXED burst destroys held-address semantics.
# Narrowing the PS master to 32 removes every width converter. Costs PS->PL
# control bandwidth only (register writes), which is irrelevant here.
set_property CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
  [get_bd_cells zynq_ultra_ps_e_0]
set_property CONFIG.PSU__SAXIGP2__DATA_WIDTH {32} \
  [get_bd_cells zynq_ultra_ps_e_0]
foreach {ip want} {zynq_ultra_ps_e_0/M_AXI_HPM0_FPD 32 \
                   zynq_ultra_ps_e_0/S_AXI_HP0_FPD 32} {
  set got [get_property CONFIG.DATA_WIDTH [get_bd_intf_pins $ip]]
  if {$got ne $want} { error "R6V2 ABORT: $ip DATA_WIDTH=$got, want $want" }
  puts "R6V2:   OK $ip DATA_WIDTH = $got"
}

puts "R6V2: === STEP 4 — CDMA: simple mode, 32-bit, max burst 16 ==="
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_cdma axi_cdma_0
set_property -dict [list CONFIG.C_INCLUDE_SG {0} \
  CONFIG.C_M_AXI_MAX_BURST_LEN {16} \
  CONFIG.C_M_AXI_DATA_WIDTH {32}] [get_bd_cells axi_cdma_0]

puts "R6V2: === STEP 4b — QSPI ID width 0 (single-thread reg slave) ==="
# C_S_AXI4_ID_WIDTH becomes ENABLED in enhanced mode (was disabled in legacy;
# that was the BD 41-721 warning). Default 4 makes the xbar compute
# ID_WIDTH=17, which overflows S_AXI_HP0_FPD's 6-bit limit (BD 41-237 ERROR).
# PG153: only one read or one write outstanding at a time on the AXI4 intf ->
# the QSPI has no use for thread IDs. Pin it to 0.
catch { set_property CONFIG.C_S_AXI4_ID_WIDTH {0} \
          [get_bd_cells axi_quad_spi_0] }
puts "R6V2:   C_S_AXI4_ID_WIDTH = [get_property CONFIG.C_S_AXI4_ID_WIDTH \
  [get_bd_cells axi_quad_spi_0]]"

puts "R6V2: === STEP 5 — AXI Interconnect (FIXED-tolerant) 2 SI / 3 MI ==="
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_ic_0
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {3}] \
  [get_bd_cells axi_ic_0]
# Constrain xbar ID growth: PG059 prefixes a master ID per SI slot, so
# ID_WIDTH = ceil_log2(NUM_SI) + max(THREAD_ID_WIDTH). With 2 SI that is
# 1 + max_thread. S_AXI_HP0_FPD accepts 6 -> keep thread widths small.
foreach {p v} {CONFIG.S00_THREAD_ID_WIDTH 0 CONFIG.S01_THREAD_ID_WIDTH 0 \
               CONFIG.M00_ISSUANCE 1 CONFIG.STRATEGY 0} {
  if {[catch { set_property $p $v [get_bd_cells axi_ic_0] } e]} {
    puts "R6V2:   NOTE could not set $p: $e"
  } else {
    puts "R6V2:   set $p = $v"
  }
}
# Discovery: we do not yet know the param name for per-MI issuing limit
# (PG153: QSPI accepts only ONE write outstanding). Dump candidates.
puts "R6V2: --- interconnect issuing/acceptance candidate params ---"
foreach p [list_property [get_bd_cells axi_ic_0]] {
  if {[regexp -nocase {ISSUING|ACCEPTANCE|M00_} $p]} {
    puts [format "R6V2:   %-42s = %s" $p \
      [get_property $p [get_bd_cells axi_ic_0]]]
  }
}

puts "R6V2: === STEP 5b — narrow xbar S00 thread ID (post-wire) ==="
# M_AXI_HPM0_FPD advertises ID=16 (fixed silicon; PS has no ID knob, only
# PSU__MAXIGP0__DATA_WIDTH -- probed 2026-08-10). The xbar inherits that as
# S00_THREAD_ID_WIDTH=16, then PG059 adds ceil_log2(NUM_SI)=1 -> ID_WIDTH=17.
# S_AXI_HP0_FPD accepts 6 -> BD 41-237 ERROR. PG059: the xbar samples only
# the ID bits defined by THREAD_ID_WIDTH per SI slot, so narrowing discards
# unused upper bits. The APU only writes control registers here; it does not
# need 2^16 outstanding thread IDs.
# NOTE: writing into the interconnect hierarchy is NOT the documented flow.
# IP integrator may recompute this on validate. Verified below either way.
proc r6v2_narrow_xbar {} {
  set xb [get_bd_cells -quiet axi_ic_0/xbar]
  if {$xb eq ""} { puts "R6V2:   xbar not present yet"; return 0 }
  catch { set_property CONFIG.S00_THREAD_ID_WIDTH {1} $xb }
  catch { set_property CONFIG.S00_SINGLE_THREAD {1} $xb }
  set t "?" ; set w "?"
  catch { set t [get_property CONFIG.S00_THREAD_ID_WIDTH $xb] }
  catch { set w [get_property CONFIG.ID_WIDTH $xb] }
  puts "R6V2:   xbar S00_THREAD_ID_WIDTH = $t ; ID_WIDTH = $w"
  return [expr {$w ne "?" && $w <= 6}]
}

puts "R6V2: === STEP 6 — interface wiring ==="
connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] \
  [get_bd_intf_pins axi_ic_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_cdma_0/M_AXI] \
  [get_bd_intf_pins axi_ic_0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M00_AXI] \
  [get_bd_intf_pins axi_quad_spi_0/AXI_FULL]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M01_AXI] \
  [get_bd_intf_pins axi_cdma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M02_AXI] \
  [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]

r6v2_narrow_xbar

puts "R6V2: === STEP 7 — clocks and resets ==="
set clk [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]
set rst [get_bd_pins proc_sys_reset_0/peripheral_aresetn]
set icrst [get_bd_pins proc_sys_reset_0/interconnect_aresetn]
connect_bd_net $clk [get_bd_pins axi_cdma_0/s_axi_lite_aclk] \
  [get_bd_pins axi_cdma_0/m_axi_aclk] \
  [get_bd_pins axi_quad_spi_0/s_axi4_aclk] \
  [get_bd_pins axi_quad_spi_0/ext_spi_clk] \
  [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk] \
  [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] \
  [get_bd_pins axi_ic_0/ACLK] \
  [get_bd_pins axi_ic_0/S00_ACLK] [get_bd_pins axi_ic_0/S01_ACLK] \
  [get_bd_pins axi_ic_0/M00_ACLK] [get_bd_pins axi_ic_0/M01_ACLK] \
  [get_bd_pins axi_ic_0/M02_ACLK]
connect_bd_net $rst [get_bd_pins axi_cdma_0/s_axi_lite_aresetn] \
  [get_bd_pins axi_quad_spi_0/s_axi4_aresetn] \
  [get_bd_pins axi_ic_0/S00_ARESETN] [get_bd_pins axi_ic_0/S01_ARESETN] \
  [get_bd_pins axi_ic_0/M00_ARESETN] [get_bd_pins axi_ic_0/M01_ARESETN] \
  [get_bd_pins axi_ic_0/M02_ARESETN]
connect_bd_net $icrst [get_bd_pins axi_ic_0/ARESETN]

puts "R6V2: === STEP 8 — address map (QSPI seg is aximm/MEM0 now) ==="
# PS must still reach QSPI control regs — enhanced mode has ONE port.
assign_bd_address -offset 0xA0000000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
  [get_bd_addr_segs axi_quad_spi_0/aximm/MEM0] -force
assign_bd_address -offset 0xA0010000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
  [get_bd_addr_segs axi_cdma_0/S_AXI_LITE/Reg] -force
assign_bd_address -offset 0xA0000000 -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces axi_cdma_0/Data] \
  [get_bd_addr_segs axi_quad_spi_0/aximm/MEM0] -force
assign_bd_address -offset 0x00000000 -range 0x80000000 \
  -target_address_space [get_bd_addr_spaces axi_cdma_0/Data] \
  [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/HP0_DDR_LOW] -force
foreach seg {HP0_DDR_LOW HP0_DDR_HIGH HP0_QSPI HP0_PCIE_LOW \
             HP0_PCIE_HIGH1 HP0_PCIE_HIGH2 HP0_LPS_OCM} {
  catch { exclude_bd_addr_seg \
    -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
    [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/$seg] }
}
catch { exclude_bd_addr_seg \
  -target_address_space [get_bd_addr_spaces axi_cdma_0/Data] \
  [get_bd_addr_segs axi_cdma_0/S_AXI_LITE/Reg] }

puts "R6V2: === pre-validate re-narrow (IPI may have recomputed) ==="
r6v2_narrow_xbar

validate_bd_design

puts "R6V2: === GATE — no width converters allowed in the FIXED path ==="
set bad {}
foreach c [get_bd_cells -hierarchical -quiet -filter {NAME =~ "auto_*"}] {
  puts "R6V2:   coupler present: $c"
  if {[regexp {auto_(us|ds)$} $c]} { lappend bad $c }
}
if {[llength $bad]} {
  error "R6V2 ABORT: width converters present: $bad -- FIXED burst would be\
 packed/repacked (PG059). Fix port widths before proceeding."
}
puts "R6V2:   GATE PASS — no auto_us/auto_ds (auto_pc on m01 is expected:\
 AXI4->Lite for CDMA regs, not in the FIXED path)"

save_bd_design
puts "R6V2: delta applied and validated"
