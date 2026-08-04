# Export Vivado block-diagram renders: original BD + CDMA-modified BD
set REPO $::env(HOME)/spi-soc-research
set OUT  $REPO/hardware/docs
file delete -force /tmp/r6_bd_export
create_project r6exp /tmp/r6_bd_export -part xczu9eg-ffvb1156-2-e -force

# --- 1. Original design ---
source $REPO/hardware/spi_bm_bd_2025p1.tcl
regenerate_bd_layout
write_bd_layout -force -format pdf -orientation landscape $OUT/bd_spi_benchmark_original.pdf
write_bd_layout -force -format svg $OUT/bd_spi_benchmark_original.svg
puts "BD_EXPORT: original done"

# --- 2. Apply CDMA delta, re-export ---
source $REPO/hardware/add_cdma_r6.tcl
regenerate_bd_layout
write_bd_layout -force -format pdf -orientation landscape $OUT/bd_spi_benchmark_cdma_r6.pdf
write_bd_layout -force -format svg $OUT/bd_spi_benchmark_cdma_r6.svg
puts "BD_EXPORT: cdma variant done"
puts "BD_EXPORT: COMPLETE"
exit
