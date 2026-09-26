#=============================================================================
# build_spi_common_hw.tcl
#
# Reconciled ZCU102 SPI benchmark hardware build.
#
# PURPOSE
#   Produce one traceable hardware handoff from the current repository sources:
#
#       spi_bm_bd_2025p1.tcl + zcu102_spi_benchmark.xdc
#             -> implementation
#             -> raw .bit
#             -> XSA containing that same implemented bitstream
#             -> .bit.bin derived from that raw .bit
#
# This script intentionally does NOT overwrite any historical repository
# bitstream, XSA, SD-card image, or other evidence artifact.
#
# Vivado: 2025.1
# Device: xczu9eg-ffvb1156-2-e
# Board:  xilinx.com:zcu102:part0:3.4
#=============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set REPO       [file normalize [file join $SCRIPT_DIR ..]]

set BD_TCL     [file join $REPO hardware spi_bm_bd_2025p1.tcl]
set XDC        [file join $REPO hardware zcu102_spi_benchmark.xdc]

set PART       xczu9eg-ffvb1156-2-e
set BOARD_PART xilinx.com:zcu102:part0:3.4
set BD_NAME    spi_benchmark
set TOP_NAME   ${BD_NAME}_wrapper
set JOBS       8

# Generated implementation products deliberately live outside the repository.
set WORK_ROOT  /tmp/spi_common_hw
set PROJ_DIR   [file join $WORK_ROOT project]
set OUT_DIR    [file join $WORK_ROOT output]

set RAW_BIT    [file join $OUT_DIR spi_common_wrapper.bit]
set XSA_OUT    [file join $OUT_DIR spi_common_wrapper.xsa]
set BIN_BASE   [file join $OUT_DIR spi_common_wrapper.bit.bin]

puts "================================================================"
puts " ZCU102 SPI common-controller hardware reconciliation build"
puts " repo:       $REPO"
puts " part:       $PART"
puts " board part: $BOARD_PART"
puts " BD source:  $BD_TCL"
puts " XDC:        $XDC"
puts " work root:  $WORK_ROOT"
puts "================================================================"

# -----------------------------------------------------------------------------
# Input guards
# -----------------------------------------------------------------------------
foreach f [list $BD_TCL $XDC] {
    if {![file isfile $f]} {
        return -code error "required input not found: $f"
    }
}

set bp [get_board_parts -quiet $BOARD_PART]
if {[llength $bp] != 1} {
    return -code error "required board part unavailable: $BOARD_PART"
}

# -----------------------------------------------------------------------------
# Isolated clean build area
# -----------------------------------------------------------------------------
file delete -force $WORK_ROOT
file mkdir $PROJ_DIR
file mkdir $OUT_DIR

# -----------------------------------------------------------------------------
# Project + explicit board identity
# -----------------------------------------------------------------------------
create_project spi_common_hw $PROJ_DIR -part $PART -force
set_property BOARD_PART $BOARD_PART [current_project]

puts "PROJECT_PART=[get_property PART [current_project]]"
puts "PROJECT_BOARD_PART=[get_property BOARD_PART [current_project]]"

if {[get_property PART [current_project]] ne $PART} {
    return -code error "project part mismatch"
}
if {[get_property BOARD_PART [current_project]] ne $BOARD_PART} {
    return -code error "project board-part mismatch"
}

# -----------------------------------------------------------------------------
# Block design from repository source
# -----------------------------------------------------------------------------
source $BD_TCL

set bd_files [get_files -quiet */${BD_NAME}.bd]
if {[llength $bd_files] != 1} {
    return -code error "expected exactly one ${BD_NAME}.bd, found [llength $bd_files]"
}
set bd_file [lindex $bd_files 0]

validate_bd_design
save_bd_design

# -----------------------------------------------------------------------------
# Wrapper + constraints
# -----------------------------------------------------------------------------
make_wrapper -files $bd_file -top

set wrapper_candidates [get_files -quiet */${TOP_NAME}.v]
if {[llength $wrapper_candidates] == 0} {
    set generated_wrapper \
        [file join $PROJ_DIR spi_common_hw.gen sources_1 bd $BD_NAME hdl ${TOP_NAME}.v]
    if {![file exists $generated_wrapper]} {
        return -code error "generated wrapper not found: $generated_wrapper"
    }
    add_files -norecurse $generated_wrapper
}

set_property top $TOP_NAME [current_fileset]

add_files -fileset constrs_1 -norecurse $XDC
update_compile_order -fileset sources_1

# -----------------------------------------------------------------------------
# Synthesis + implementation + raw bitstream
# -----------------------------------------------------------------------------
launch_runs impl_1 -to_step write_bitstream -jobs $JOBS
wait_on_run impl_1

set impl_status   [get_property STATUS   [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]

puts "IMPL_STATUS=$impl_status"
puts "IMPL_PROGRESS=$impl_progress"

if {$impl_progress ne "100%"} {
    return -code error "implementation did not reach 100%"
}

set impl_bit \
    [file join $PROJ_DIR spi_common_hw.runs impl_1 ${TOP_NAME}.bit]

if {![file isfile $impl_bit]} {
    return -code error "implementation bitstream missing: $impl_bit"
}

file copy -force $impl_bit $RAW_BIT

# -----------------------------------------------------------------------------
# Open the exact implemented run and capture implementation evidence.
# -----------------------------------------------------------------------------
open_run impl_1

report_utilization \
    -file [file join $OUT_DIR utilization_impl.txt]

report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 10 \
    -input_pins \
    -file [file join $OUT_DIR timing_summary_impl.txt]

# -----------------------------------------------------------------------------
# XSA exported from this exact implemented design, including its bitstream.
# -----------------------------------------------------------------------------
write_hw_platform -force -fixed -include_bit $XSA_OUT

if {![file isfile $XSA_OUT]} {
    return -code error "XSA was not produced: $XSA_OUT"
}

# -----------------------------------------------------------------------------
# Linux FPGA-manager load image derived from the exact copied raw .bit.
#
# This preserves the historical conversion method for comparison, but creates
# a new artifact under /tmp only. No claim of byte equivalence to historical
# bit.bin is implied.
# -----------------------------------------------------------------------------
write_cfgmem \
    -force \
    -format BIN \
    -interface SMAPx32 \
    -disablebitswap \
    -loadbit "up 0x0 $RAW_BIT" \
    $BIN_BASE

set bins [glob -nocomplain ${BIN_BASE}*]
if {[llength $bins] == 0} {
    return -code error "write_cfgmem produced no output"
}

# -----------------------------------------------------------------------------
# Provenance text
# -----------------------------------------------------------------------------
set prov [open [file join $OUT_DIR build_provenance.txt] w]

puts $prov "REPO=$REPO"
puts $prov "PART=$PART"
puts $prov "BOARD_PART=$BOARD_PART"
puts $prov "BD_TCL=$BD_TCL"
puts $prov "XDC=$XDC"
puts $prov "RAW_BIT=$RAW_BIT"
puts $prov "XSA=$XSA_OUT"
puts $prov "IMPL_STATUS=$impl_status"
puts $prov "IMPL_PROGRESS=$impl_progress"
puts $prov "VIVADO_VERSION=[version -short]"

if {![catch {exec git -C $REPO rev-parse HEAD} git_head]} {
    puts $prov "GIT_HEAD=$git_head"
}
if {![catch {exec git -C $REPO status --short} git_status]} {
    puts $prov "GIT_STATUS_BEGIN"
    puts $prov $git_status
    puts $prov "GIT_STATUS_END"
}

foreach f [list $BD_TCL $XDC $RAW_BIT $XSA_OUT] {
    if {![catch {exec sha256sum $f} h]} {
        puts $prov "SHA256=$h"
    }
}

foreach f $bins {
    if {![catch {exec sha256sum $f} h]} {
        puts $prov "SHA256=$h"
    }
}

close $prov

puts "================================================================"
puts " BUILD COMPLETE"
puts " Raw bit:       $RAW_BIT"
puts " XSA:           $XSA_OUT"
puts " cfgmem output: $bins"
puts " Timing:        [file join $OUT_DIR timing_summary_impl.txt]"
puts " Utilization:   [file join $OUT_DIR utilization_impl.txt]"
puts " Provenance:    [file join $OUT_DIR build_provenance.txt]"
puts ""
puts " NOTE:"
puts "   These are NEW reconciliation artifacts under /tmp."
puts "   Historical repository artifacts were not overwritten."
puts "   Physical SPI SCK remains unmeasured until board/instrument validation."
puts "================================================================"
