# =============================================================================
# base_v2_de25.sdc — Timing Constraints for BASE v2.0 on DE25-Standard
# =============================================================================

# 50 MHz board oscillator
create_clock -name clk_50 -period 20.000 [get_ports CLOCK_50]

# Input delays — relaxed for pushbutton/switch inputs (async, but constrain for tools)
set_input_delay  -clock clk_50 -max 10.0 [get_ports {SW[*]}]
set_input_delay  -clock clk_50 -min  0.0 [get_ports {SW[*]}]
set_input_delay  -clock clk_50 -max 10.0 [get_ports {KEY[*]}]
set_input_delay  -clock clk_50 -min  0.0 [get_ports {KEY[*]}]
set_input_delay  -clock clk_50 -max 10.0 [get_ports KEY_RESET_N]
set_input_delay  -clock clk_50 -min  0.0 [get_ports KEY_RESET_N]

# Output delays — LEDs and 7-seg are async but constrain loosely
set_output_delay -clock clk_50 -max 5.0 [get_ports {LEDR[*]}]
set_output_delay -clock clk_50 -max 5.0 [get_ports {HEX0[*]}]
set_output_delay -clock clk_50 -max 5.0 [get_ports {HEX1[*]}]
set_output_delay -clock clk_50 -max 5.0 [get_ports {HEX2[*]}]
set_output_delay -clock clk_50 -max 5.0 [get_ports {HEX3[*]}]
set_output_delay -clock clk_50 -max 5.0 [get_ports {HEX4[*]}]
set_output_delay -clock clk_50 -max 5.0 [get_ports {HEX5[*]}]

# False paths on async resets
set_false_path -from [get_ports KEY_RESET_N]

# Cut paths on switch inputs (they are metastability-prone async inputs)
# If you add synchronizers, constrain those instead
set_false_path -from [get_ports {SW[*]}]
set_false_path -from [get_ports {KEY[*]}]
