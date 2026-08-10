create_project -in_memory -part xczu9eg-ffvb1156-2-e
source hardware/spi_bm_bd_2025p1.tcl
source hardware/add_cdma_r6_v2.tcl
puts "WPROBE: === interface DATA_WIDTH / USER widths ==="
foreach ip {zynq_ultra_ps_e_0/M_AXI_HPM0_FPD zynq_ultra_ps_e_0/S_AXI_HP0_FPD \
            axi_cdma_0/M_AXI axi_cdma_0/S_AXI_LITE axi_quad_spi_0/AXI_FULL \
            axi_ic_0/S00_AXI axi_ic_0/S01_AXI axi_ic_0/M00_AXI \
            axi_ic_0/M01_AXI axi_ic_0/M02_AXI} {
  if {[catch {set o [get_bd_intf_pins $ip]} e]} { puts "WPROBE: $ip MISSING"; continue }
  set dw "?" ; set aw "?"
  catch { set dw [get_property CONFIG.DATA_WIDTH $o] }
  catch { set aw [get_property CONFIG.AWUSER_WIDTH $o] }
  puts [format "WPROBE:   %-40s DATA=%-5s AWUSER=%s" $ip $dw $aw]
}
puts "WPROBE: === PS width params ==="
foreach p {PSU__MAXIGP0__DATA_WIDTH PSU__MAXIGP1__DATA_WIDTH \
           PSU__SAXIGP2__DATA_WIDTH} {
  if {![catch {set v [get_property CONFIG.$p [get_bd_cells zynq_ultra_ps_e_0]]}]} {
    puts "WPROBE:   $p = $v"
  } else { puts "WPROBE:   $p NOT A PARAM" }
}
puts "WPROBE: === inserted couplers ==="
foreach c [get_bd_cells -hierarchical -quiet -filter {NAME =~ "auto_*"}] {
  puts "WPROBE:   $c"
}
puts "WPROBE: === M00_ISSUANCE legal values ==="
catch { puts "WPROBE:   [list_property_value CONFIG.M00_ISSUANCE \
  [get_bd_cells axi_ic_0]]" }
puts "WPROBE: DONE"
