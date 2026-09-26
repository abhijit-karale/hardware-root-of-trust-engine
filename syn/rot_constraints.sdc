###############################################################################
# Company: Hardware Root-of-Trust (RoT) Silicon Lab
# Engineer: Abhijit Karale
# File: rot_constraints.sdc
# Target Node: SkyWater 130nm (sky130_fd_sc_hd)
# Target Clock Frequency: 200 MHz (Clock Period = 5.000 ns)
###############################################################################

# 1. Primary Clock Definition (200 MHz)
create_clock -name pclk -period 5.000 -waveform {0.000 2.500} [get_ports pclk]

# 2. Clock Uncertainty (Jitter + Skew margin: 200 ps)
set_clock_uncertainty -setup 0.200 [get_clocks pclk]
set_clock_uncertainty -hold  0.100 [get_clocks pclk]

# 3. Clock Transition (Slew rate: 150 ps)
set_clock_transition 0.150 [get_clocks pclk]

# 4. Input Delays (Assuming 20% of cycle for external SoC bus budget = 1.000 ns)
set_input_delay -clock pclk -max 1.000 [get_ports {paddr[*] psel penable pwrite pwdata[*] pstrb[*]}]
set_input_delay -clock pclk -min 0.200 [get_ports {paddr[*] psel penable pwrite pwdata[*] pstrb[*]}]

# 5. Output Delays (Assuming 20% of cycle for external SoC bus budget = 1.000 ns)
set_output_delay -clock pclk -max 1.000 [get_ports {pready prdata[*] pslverr rot_irq_out}]
set_output_delay -clock pclk -min 0.200 [get_ports {pready prdata[*] pslverr rot_irq_out}]

# 6. Physical Security Pin Constraints
# rot_zeroize_pin is an asynchronous emergency line: false path for setup, but max delay bounded
set_false_path -from [get_ports presetn]
set_false_path -from [get_ports rot_zeroize_pin]
set_false_path -to   [get_ports rot_alarm_out]

# 7. Driving Cell and Output Load Models (SkyWater 130nm Standard Cells)
# sky130_fd_sc_hd__buf_2 as default driver
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 [all_inputs -no_clocks]
# 15 fF standard output capacitive load
set_load -pin_load 0.015 [all_outputs]

# 8. Maximum Transition and Capacitance Constraints
set_max_transition 0.350 [current_design]
set_max_fanout 16 [current_design]
set_max_capacitance 0.050 [all_inputs -no_clocks]

###############################################################################
# End of SDC Timing Constraints
###############################################################################
