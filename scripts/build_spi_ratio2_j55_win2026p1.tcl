# Reproducible ZCU102 AXI Quad SPI ratio-2/J55 build for Vivado 2026.1.
# Historical repository bitstreams are never overwritten.
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set REPO       [file normalize [file join $SCRIPT_DIR ..]]
set BD_TCL     [file join $REPO hardware spi_bm_bd_2025p1.tcl]
set XDC        [file join $REPO hardware zcu102_spi_benchmark.xdc]

set PART       xczu9eg-ffvb1156-2-e
set BD_NAME    spi_benchmark
set TOP_NAME   ${BD_NAME}_wrapper
set JOBS       8
set RATIO      2
set EXPECT_PL0_MHZ 100.0
set EXPECT_SCK_MHZ 50.0

set WORK_ROOT [file normalize [file join $::env(USERPROFILE) spi_ratio2_j55_build_20260928]]
set PROJ_DIR  [file join $WORK_ROOT project]
set OUT_DIR   [file join $WORK_ROOT output]
set RAW_BIT   [file join $OUT_DIR spi_ratio2_j55_wrapper.bit]
set XSA_OUT   [file join $OUT_DIR spi_ratio2_j55_wrapper.xsa]
set BIN_BASE  [file join $OUT_DIR spi_ratio2_j55_wrapper.bit.bin]

foreach f [list $BD_TCL $XDC] {
    if {![file isfile $f]} { return -code error "required input not found: $f" }
}
file delete -force $WORK_ROOT
file mkdir $PROJ_DIR
file mkdir $OUT_DIR
create_project spi_ratio2_j55 $PROJ_DIR -part $PART -force
if {[get_property PART [current_project]] ne $PART} {
    return -code error "project part mismatch"
}

source $BD_TCL
set spi [get_bd_cells axi_quad_spi_0]
set ps  [get_bd_cells zynq_ultra_ps_e_0]
if {[llength $spi] != 1 || [llength $ps] != 1} {
    return -code error "expected SPI/PS cells were not created"
}

set_property CONFIG.C_SCK_RATIO $RATIO $spi
set ratio_readback [get_property CONFIG.C_SCK_RATIO $spi]
set pl0_mhz [get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ $ps]
if {$ratio_readback != $RATIO} {
    return -code error "C_SCK_RATIO readback mismatch: $ratio_readback"
}
if {[expr {abs(double($pl0_mhz) - $EXPECT_PL0_MHZ)}] > 0.01} {
    return -code error "PL0 design target mismatch: $pl0_mhz MHz"
}

validate_bd_design
save_bd_design
make_wrapper -files [get_files -quiet */${BD_NAME}.bd] -top
set wrapper [file join $PROJ_DIR spi_ratio2_j55.gen sources_1 bd $BD_NAME hdl ${TOP_NAME}.v]
if {![file isfile $wrapper]} { return -code error "wrapper missing: $wrapper" }
add_files -norecurse $wrapper
set_property top $TOP_NAME [current_fileset]
add_files -fileset constrs_1 -norecurse $XDC
update_compile_order -fileset sources_1

launch_runs impl_1 -to_step write_bitstream -jobs $JOBS
wait_on_run impl_1
set impl_status   [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
if {$impl_progress ne "100%"} {
    return -code error "implementation failed: $impl_status / $impl_progress"
}

set impl_bit [file join $PROJ_DIR spi_ratio2_j55.runs impl_1 ${TOP_NAME}.bit]
if {![file isfile $impl_bit]} { return -code error "bitstream missing: $impl_bit" }
file copy -force $impl_bit $RAW_BIT

open_run impl_1
report_utilization -file [file join $OUT_DIR utilization_impl.txt]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose     -max_paths 10 -file [file join $OUT_DIR timing_summary_impl.txt]
report_io -file [file join $OUT_DIR io_impl.txt]
report_route_status -file [file join $OUT_DIR route_status_impl.txt]
write_debug_probes -force [file join $OUT_DIR spi_ratio2_j55_wrapper.ltx]

write_hw_platform -force -fixed -include_bit $XSA_OUT
write_cfgmem -force -format BIN -interface SMAPx32 -disablebitswap     -loadbit "up 0x0 $RAW_BIT" $BIN_BASE
set bins [glob -nocomplain ${BIN_BASE}*]
if {[llength $bins] == 0} { return -code error "cfgmem BIN was not produced" }
set prov [open [file join $OUT_DIR build_provenance.txt] w]
puts $prov "VIVADO_VERSION=[version -short]"
puts $prov "PART=$PART"
puts $prov "BD_TCL=$BD_TCL"
puts $prov "XDC=$XDC"
puts $prov "C_SCK_RATIO=$ratio_readback"
puts $prov "PL0_DESIGN_TARGET_MHZ=$pl0_mhz"
puts $prov "EXPECTED_SCK_MHZ=$EXPECT_SCK_MHZ"
puts $prov "IMPL_STATUS=$impl_status"
puts $prov "IMPL_PROGRESS=$impl_progress"
puts $prov "RAW_BIT=$RAW_BIT"
puts $prov "XSA=$XSA_OUT"
puts $prov "CFGMEM=$bins"
puts $prov "LTX=[file join $OUT_DIR spi_ratio2_j55_wrapper.ltx]"
puts $prov "ROUTE_STATUS=[file join $OUT_DIR route_status_impl.txt]"
puts $prov "FINAL_WNS_NS=[get_property SLACK [lindex [get_timing_paths -setup -max_paths 1] 0]]"
puts $prov "J55_MOSI_D12=[get_property PACKAGE_PIN [get_ports SPI_0_io0_io]]"
puts $prov "J55_MISO_E10=[get_property PACKAGE_PIN [get_ports SPI_0_io1_io]]"
puts $prov "J55_SCK_F11=[get_property PACKAGE_PIN [get_ports SPI_0_sck_io]]"
puts $prov "J55_SS0_D11=[get_property PACKAGE_PIN [get_ports {SPI_0_ss_io[0]}]]"
if {![catch {exec git -C $REPO rev-parse HEAD} git_head]} {
    puts $prov "GIT_HEAD=$git_head"
}
if {![catch {exec git -C $REPO status --short} git_status]} {
    puts $prov "GIT_STATUS_BEGIN"
    puts $prov $git_status
    puts $prov "GIT_STATUS_END"
}
close $prov
puts "BUILD_COMPLETE=$OUT_DIR"
