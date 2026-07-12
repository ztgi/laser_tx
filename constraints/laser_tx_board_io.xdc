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

# ============================================================
# AD9528 OUT0 measurement-only MGT reference clock, Bank 110
# FPGA_REF0_CLK_P/N from the board schematic. IBUFDS_GTE2.ODIV2
# is used only by a debug frequency counter; it is not a Bank 111 GT source.
# ============================================================
set_property PACKAGE_PIN AA8 [get_ports ad9528_ref0_clk_p]
set_property PACKAGE_PIN AA7 [get_ports ad9528_ref0_clk_n]
create_clock -name ad9528_out0_clk -period 8.138020833 [get_ports ad9528_ref0_clk_p]
