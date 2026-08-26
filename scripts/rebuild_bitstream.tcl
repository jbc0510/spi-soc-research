#=============================================================================
# rebuild_bitstream.tcl  —  ZCU102 SPI Benchmark, one-shot bitstream rebuild
#
# PURPOSE
#   Regenerate spi_benchmark_wrapper.bit.bin from the migrated 2025.1 block
#   design, with no manual steps. Run this the moment Vivado synthesis access
#   for xczu9eg is provisioned on stile.
#
# PREREQ
#   - Vivado 2025.1 environment sourced (this machine's install root):
#       source /home/opentitan/Documents/AMD/Vivado_2025.1_Enterprise/2025.1/Vivado/settings64.sh
#   - Valid synthesis license for xczu9eg reachable (XILINXD_LICENSE_FILE set).
#   - Patched block-design TCL committed at:
#       ~/spi-soc-research/hardware/spi_bm_bd_2025p1.tcl
#   - Constraints committed at:
#       ~/spi-soc-research/hardware/zcu102_spi_benchmark.xdc
#
# RUN
#   vivado -mode tcl -source rebuild_bitstream.tcl
#   (or, from inside vivado -mode tcl:  source rebuild_bitstream.tcl )
#
# OUTPUT
#   /tmp/spi_rebuild_out/spi_benchmark_wrapper.bit       (raw bitstream)
#   /tmp/spi_rebuild_out/spi_benchmark_wrapper.bit.bin   (SD-loadable image)
#=============================================================================

# ---- user-adjustable settings ------------------------------------------------
set REPO       $::env(HOME)/spi-soc-research
set BD_TCL     $REPO/hardware/spi_bm_bd_2025p1.tcl
set XDC        $REPO/hardware/zcu102_spi_benchmark.xdc
set PART       xczu9eg-ffvb1156-2-e
set PROJ_DIR   /tmp/spi_rebuild_proj
set OUT_DIR    /tmp/spi_rebuild_out
set BD_NAME    spi_benchmark
set JOBS       8
# ------------------------------------------------------------------------------

puts "=============================================="
puts " ZCU102 SPI bitstream rebuild"
puts " part:    $PART"
puts " bd tcl:  $BD_TCL"
puts " xdc:     $XDC"
puts "=============================================="

# Sanity: required files exist before we burn time
foreach f [list $BD_TCL $XDC] {
    if { ![file exists $f] } {
        puts "ERROR: required file not found: $f"
        return -code error "missing input file"
    }
}

# Clean any prior run so this is repeatable
file delete -force $PROJ_DIR
file mkdir $OUT_DIR

# 1. Project ------------------------------------------------------------------
create_project spi_rebuild $PROJ_DIR -part $PART -force

# 2. Block design (migrated 2025.1 TCL: PS bumped to 3.5, version guard cleared)
source $BD_TCL

# 3. HDL wrapper, set as top --------------------------------------------------
set bd_file [get_files $PROJ_DIR/spi_rebuild.srcs/sources_1/bd/$BD_NAME/$BD_NAME.bd]
make_wrapper -files $bd_file -top
add_files -norecurse $PROJ_DIR/spi_rebuild.gen/sources_1/bd/$BD_NAME/hdl/${BD_NAME}_wrapper.v
set_property top ${BD_NAME}_wrapper [current_fileset]

# 4. Constraints --------------------------------------------------------------
add_files -fileset constrs_1 -norecurse $XDC
update_compile_order -fileset sources_1

# 5. Synthesis + implementation + bitstream -----------------------------------
launch_runs impl_1 -to_step write_bitstream -jobs $JOBS
wait_on_run impl_1

set st [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $st"
if { [get_property PROGRESS [get_runs impl_1]] != "100%" } {
    puts "ERROR: implementation did not complete. Check the run log:"
    puts "  $PROJ_DIR/spi_rebuild.runs/impl_1/runme.log"
    return -code error "impl incomplete"
}

# 6. Collect the .bit ---------------------------------------------------------
set bitfile $PROJ_DIR/spi_rebuild.runs/impl_1/${BD_NAME}_wrapper.bit
if { ![file exists $bitfile] } {
    puts "ERROR: expected bitstream not found at $bitfile"
    return -code error "no bit produced"
}
file copy -force $bitfile $OUT_DIR/spi_benchmark_wrapper.bit
puts "Copied raw bitstream -> $OUT_DIR/spi_benchmark_wrapper.bit"

# 7. Convert .bit -> .bit.bin (raw load image for FPGA-manager / DT overlay) ---
#    NOTE: verify this matches how the ORIGINAL spi_benchmark_wrapper.bit.bin
#    (26 MB) was produced. write_cfgmem with -interface SMAPx32 -disablebitswap
#    yields the raw config image PetaLinux fpga_manager expects. If your
#    original used bootgen instead, see deploy_and_test notes for the bootgen path.
write_cfgmem -force -format BIN -interface SMAPx32 -disablebitswap \
    -loadbit "up 0x0 $OUT_DIR/spi_benchmark_wrapper.bit" \
    $OUT_DIR/spi_benchmark_wrapper.bit.bin

# write_cfgmem appends suffixes for multi-file outputs; normalize the name
set produced [glob -nocomplain $OUT_DIR/spi_benchmark_wrapper.bit.bin*]
puts "cfgmem produced: $produced"

puts "=============================================="
puts " DONE. Outputs in $OUT_DIR :"
foreach f [glob -nocomplain $OUT_DIR/*] { puts "   $f" }
puts "=============================================="
puts " Next: copy spi_benchmark_wrapper.bit.bin to the SD card boot"
puts " partition (overwriting the stale one), then run the board-side"
puts " deploy_and_test steps."
