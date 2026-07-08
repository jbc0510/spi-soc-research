# =============================================================================
# setup_quartus.tcl — Quartus Pro project setup for BASE v2.0 FPGA emulation
# Target: Terasic DE25-Standard, Intel Agilex 5 (A5ED013BB32AE4S)
# Usage:  quartus_sh -t setup_quartus.tcl
# =============================================================================

package require ::quartus::project

set project_name "base_v2_de25"

if {[project_exists $project_name]} {
    project_open $project_name
} else {
    project_new $project_name
}

# -----------------------------------------------------------------------------
# Device Assignment
# -----------------------------------------------------------------------------
set_global_assignment -name FAMILY "Agilex 5"
set_global_assignment -name DEVICE A5ED013BB32AE4S
set_global_assignment -name TOP_LEVEL_ENTITY top_de25

# -----------------------------------------------------------------------------
# RTL Source Files
# IMPORTANT: Use secure_boot_core/ versions (NOT root copies).
#            Do NOT include anything from archive_v1/.
# -----------------------------------------------------------------------------
set_global_assignment -name SYSTEMVERILOG_FILE top_de25.sv
set_global_assignment -name SYSTEMVERILOG_FILE ../verilog/rtl/control_plane/secure_boot_control_plane.sv
set_global_assignment -name SYSTEMVERILOG_FILE ../verilog/rtl/secure_boot_core/secure_boot_system_wrapper.sv
set_global_assignment -name SYSTEMVERILOG_FILE ../verilog/rtl/secure_boot_core/secure_boot_fsm.sv
set_global_assignment -name SYSTEMVERILOG_FILE ../verilog/rtl/secure_boot_core/group_fsm.sv
set_global_assignment -name VERILOG_FILE       ../verilog/rtl/defines.v

# -----------------------------------------------------------------------------
# Search Paths (for `include resolution)
# -----------------------------------------------------------------------------
set_global_assignment -name SEARCH_PATH ../verilog/rtl
set_global_assignment -name SEARCH_PATH ../verilog/rtl/control_plane
set_global_assignment -name SEARCH_PATH ../verilog/rtl/secure_boot_core

# -----------------------------------------------------------------------------
# Timing Constraints
# -----------------------------------------------------------------------------
set_global_assignment -name SDC_FILE base_v2_de25.sdc

# -----------------------------------------------------------------------------
# Pin Assignments — PLACEHOLDER
# ⚠️  UPDATE FROM DE25-Standard user manual or import Terasic .qsf template
#     before compiling. These are NOT real pin numbers.
# -----------------------------------------------------------------------------
set_location_assignment PIN_AA24 -to CLOCK_50
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to CLOCK_50

set_location_assignment PIN_AB28 -to KEY_RESET_N
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to KEY_RESET_N

# KEY[3:0], SW[9:0], LEDR[9:0], HEX0-HEX5 — all need real pins
# Import Terasic's .qsf template to fill these in

foreach port {KEY[0] KEY[1] KEY[2] KEY[3]} {
    set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to $port
}
foreach i {0 1 2 3 4 5 6 7 8 9} {
    set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to SW[$i]
    set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to LEDR[$i]
}
foreach h {0 1 2 3 4 5} {
    foreach s {0 1 2 3 4 5 6} {
        set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to HEX${h}[$s]
    }
}

# -----------------------------------------------------------------------------
# Compilation Settings
# -----------------------------------------------------------------------------
set_global_assignment -name OPTIMIZATION_MODE "HIGH PERFORMANCE EFFORT"
set_global_assignment -name ALLOW_REGISTER_RETIMING ON
set_global_assignment -name VERILOG_INPUT_VERSION SYSTEMVERILOG_2012

project_close
