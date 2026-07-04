# TEMPLATE ONLY: replace every <PIN> and verify the I/O voltage against the
# board schematic before enabling these constraints. Never guess package pins.

# set_property PACKAGE_PIN <PIN> [get_ports eom_out_0]
# set_property IOSTANDARD LVCMOS18 [get_ports eom_out_0]

# set_property PACKAGE_PIN <PIN> [get_ports soa_gate_out_0]
# set_property IOSTANDARD LVCMOS18 [get_ports soa_gate_out_0]

# set_property PACKAGE_PIN <PIN> [get_ports acq_trig_out_0]
# set_property IOSTANDARD LVCMOS18 [get_ports acq_trig_out_0]

# set_property PACKAGE_PIN <PIN> [get_ports acq_gate_out_0]
# set_property IOSTANDARD LVCMOS18 [get_ports acq_gate_out_0]

# Add set_output_delay constraints only after the external receiver clock and
# its setup/hold requirements are known from the real board-level interface.
