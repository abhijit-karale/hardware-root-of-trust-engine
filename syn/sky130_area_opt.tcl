###############################################################################
# Company: Hardware Root-of-Trust (RoT) Silicon Lab
# Engineer: Abhijit Karale
# File: sky130_area_opt.tcl
# Description: Synthesis and Area Optimization Directives for SkyWater 130nm
###############################################################################

# Set high-effort optimization for area and timing
set_app_var compile_timing_high_effort true
set_app_var compile_area_high_effort_mode true

# Enable automatic clock gating to reduce dynamic switching power
set_clock_gating_style -positive_edge_logic {integrated:sky130_fd_sc_hd__cgat_1} \
                       -control_point before \
                       -control_signal scan_enable \
                       -minimum_bitwidth 4

# S-Box and Galois Field Multiplier Area Directives:
# Group AES S-Boxes and Keccak Chi mappings into balanced XOR/NAND structures
set_optimize_registers true
set_register_merging true

# Prevent boundary optimization on secure key registers to preserve zeroization safety
set_dont_touch [get_cells -hierarchical *key_words*]
set_dont_touch [get_cells -hierarchical *rk_reg*]

# Report timing and area breakdown
report_timing -delay_type max -max_paths 10 -significant_digits 3
report_area -hierarchy
report_power -analysis_effort medium
report_qor
