create_project -in_memory -part xczu9eg-ffvb1156-2-e
source hardware/spi_bm_bd_2025p1.tcl
catch { source hardware/add_cdma_r6_v2.tcl } emsg
puts "IDW2: delta ended: $emsg"

puts "IDW2: === per-interface ID_WIDTH on every master/slave ==="
foreach i [get_bd_intf_pins -hierarchical -quiet] {
  set idw "-" ; set awu "-"
  catch { set idw [get_property CONFIG.ID_WIDTH $i] }
  catch { set awu [get_property CONFIG.AWUSER_WIDTH $i] }
  if {$idw ne "-" || $awu ne "-"} {
    puts [format "IDW2:   %-52s ID=%-5s AWUSER=%s" $i $idw $awu]
  }
}
puts "IDW2: === xbar params ==="
foreach c [get_bd_cells -hierarchical -quiet -filter {NAME =~ "*xbar*"}] {
  foreach pr [list_property $c] {
    if {[regexp -nocase {ID_WIDTH|THREAD|NUM_S|NUM_M} $pr]} {
      puts [format "IDW2:   %s %-34s = %s" $c $pr [get_property $pr $c]]
    }
  }
}
puts "IDW2: DONE"
