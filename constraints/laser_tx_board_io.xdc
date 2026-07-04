# ============================================================
# laser_tx board-level sync outputs
# Reserved PL GPIO, Bank 10, VCCO = 3.3 V
# Board connector J9: GPIO1 through GPIO4
# ============================================================

set_property PACKAGE_PIN AG17 [get_ports eom_out_0]
set_property IOSTANDARD LVCMOS33 [get_ports eom_out_0]

set_property PACKAGE_PIN AB12 [get_ports soa_gate_out_0]
set_property IOSTANDARD LVCMOS33 [get_ports soa_gate_out_0]

set_property PACKAGE_PIN AC14 [get_ports acq_trig_out_0]
set_property IOSTANDARD LVCMOS33 [get_ports acq_trig_out_0]

set_property PACKAGE_PIN AD16 [get_ports acq_gate_out_0]
set_property IOSTANDARD LVCMOS33 [get_ports acq_gate_out_0]

# Output delays intentionally omitted until the external receiver clock and
# setup/hold requirements are known.
