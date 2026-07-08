#==============================================================================
# ZCU102 SPI Benchmark XDC Constraints
# Bank 28 = 1.8V on ZCU102 — ALL PL I/O must use LVCMOS18
# J55 = single PMOD connector (not dual like ZCU104)
# Reference: ZCU102 Schematic (UG1182), Bank 28 pins
#==============================================================================

#------------------------------------------------------------------------------
# AXI Quad SPI → J55 PMOD (Bank 28, LVCMOS18)
# J55 pin assignments per ZCU102 schematic:
#   Pin 1 = D12 (IO_L4P_T0L_N6_AD15P_28)
#   Pin 2 = E10 (IO_L6P_T0U_N10_AD6P_28)
#   Pin 3 = F10 (IO_L6N_T0U_N11_AD6N_28)
#   Pin 4 = F11 (IO_L7P_T1L_N0_QBC_AD13P_28)
#   Pin 7 = D11 (IO_L4N_T0L_N7_AD15N_28)
#   Pin 8 = E12 (IO_L5P_T0U_N8_AD14P_28)
#------------------------------------------------------------------------------

# SPI_0 SCK  → J55 pin 4
set_property PACKAGE_PIN F11 [get_ports SPI_0_sck_io]
set_property IOSTANDARD LVCMOS18 [get_ports SPI_0_sck_io]

# SPI_0 MOSI (io0) → J55 pin 1
set_property PACKAGE_PIN D12 [get_ports SPI_0_io0_io]
set_property IOSTANDARD LVCMOS18 [get_ports SPI_0_io0_io]

# SPI_0 MISO (io1) → J55 pin 2
set_property PACKAGE_PIN E10 [get_ports SPI_0_io1_io]
set_property IOSTANDARD LVCMOS18 [get_ports SPI_0_io1_io]

# SPI_0 SS   → J55 pin 7
set_property PACKAGE_PIN D11 [get_ports {SPI_0_ss_io[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {SPI_0_ss_io[0]}]

#------------------------------------------------------------------------------
# EMIO SPI1 → J55 remaining pins (probe points, LVCMOS18)
#------------------------------------------------------------------------------

# EMIO SPI1 SCLK → J55 pin 3
set_property PACKAGE_PIN F10 [get_ports {emio_spi1_sclk_o[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {emio_spi1_sclk_o[0]}]

# EMIO SPI1 MOSI → J55 pin 8
set_property PACKAGE_PIN E12 [get_ports {emio_spi1_mosi_o[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {emio_spi1_mosi_o[0]}]

# EMIO SPI1 MISO → tie to GND via pull-down for loopback test
set_property PACKAGE_PIN E13 [get_ports {emio_spi1_mosi_i[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {emio_spi1_mosi_i[0]}]
set_property PULLTYPE PULLDOWN [get_ports {emio_spi1_mosi_i[0]}]

set_property PACKAGE_PIN F13 [get_ports {emio_spi1_miso_i[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {emio_spi1_miso_i[0]}]
set_property PULLTYPE PULLDOWN [get_ports {emio_spi1_miso_i[0]}]

# EMIO SPI1 SS
set_property PACKAGE_PIN C13 [get_ports {emio_spi1_ss_o[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {emio_spi1_ss_o[0]}]

# Output enables (tri-state controls — no physical pin needed but must exist)
set_property PACKAGE_PIN B13 [get_ports {emio_spi1_sclk_o_en[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {emio_spi1_sclk_o_en[0]}]

set_property PACKAGE_PIN A13 [get_ports {emio_spi1_mosi_o_en[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {emio_spi1_mosi_o_en[0]}]

set_property PACKAGE_PIN B14 [get_ports {emio_spi1_ss_o_en[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {emio_spi1_ss_o_en[0]}]

#------------------------------------------------------------------------------
# Timing
#------------------------------------------------------------------------------
# 100 MHz PL clock from PS
# pl_clk0 is auto-derived from PS — no manual constraint needed
# create_clock handled by PS IP internally

# SPI I/O are asynchronous outputs — false path
set_false_path -to [get_ports {SPI_0_sck_io SPI_0_io0_io SPI_0_ss_io SPI_0_io1_io}]
set_false_path -from [get_ports SPI_0_io1_io]
set_false_path -to [get_ports {emio_spi1_sclk_o emio_spi1_mosi_o emio_spi1_ss_o}]
set_false_path -from [get_ports {emio_spi1_mosi_i emio_spi1_miso_i emio_spi1_sclk_i}]

# EMIO SPI1 SCLK input — was missing from original XDC
set_property PACKAGE_PIN G13 [get_ports {emio_spi1_sclk_i[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {emio_spi1_sclk_i[0]}]
set_property PULLTYPE PULLDOWN [get_ports {emio_spi1_sclk_i[0]}]




create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 16384 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list spi_benchmark_i/zynq_ultra_ps_e_0_pl_clk0]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 1 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list spi_benchmark_i/SPI_0_io0_o]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets u_ila_0_zynq_ultra_ps_e_0_pl_clk0]
