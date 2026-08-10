create_project -in_memory -part xczu9eg-ffvb1156-2-e
create_bd_design probe_ids
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 ps]
puts "IDPROBE: === enabling all HP/HPC slave ports ==="
foreach p {PSU__USE__S_AXI_GP0 PSU__USE__S_AXI_GP1 PSU__USE__S_AXI_GP2 \
           PSU__USE__S_AXI_GP3 PSU__USE__S_AXI_GP4 PSU__USE__S_AXI_GP5 \
           PSU__USE__S_AXI_GP6} {
  catch { set_property CONFIG.$p {1} $ps }
}
puts "IDPROBE: === slave port ID_WIDTH / DATA_WIDTH ==="
foreach i [get_bd_intf_pins -of_objects $ps -quiet] {
  if {[regexp {S_AXI_(HP|HPC|LPD|ACP)} $i]} {
    set idw "?" ; set dw "?"
    catch { set idw [get_property CONFIG.ID_WIDTH $i] }
    catch { set dw  [get_property CONFIG.DATA_WIDTH $i] }
    puts [format "IDPROBE:   %-44s ID=%-4s DATA=%s" $i $idw $dw]
  }
}
puts "IDPROBE: === axi_bram_ctrl ID width settable? ==="
set b [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl bram]
foreach p [list_property $b] {
  if {[regexp -nocase {ID_WIDTH|PROTOCOL|DATA_WIDTH} $p]} {
    puts [format "IDPROBE:   %-40s = %s" $p [get_property $p $b]]
  }
}
puts "IDPROBE: DONE"
