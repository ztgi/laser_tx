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

# ============================================================
# J9 oscilloscope-only debug outputs
# Reserved PL GPIO, Bank 10, VCCO = 3.3 V
# J9 pin 10 is adjacent DGND for the scope ground reference.
# ============================================================

# J9 GPIO6 / pin 6 - stretched rate request pulse
set_property PACKAGE_PIN AE17 [get_ports dbg_scope_rate_req]
set_property IOSTANDARD LVCMOS33 [get_ports dbg_scope_rate_req]

# J9 GPIO7 / pin 7 - synchronized TX MMCM locked
set_property PACKAGE_PIN AH16 [get_ports dbg_scope_tx_mmcm_locked]
set_property IOSTANDARD LVCMOS33 [get_ports dbg_scope_tx_mmcm_locked]

# J9 GPIO8 / pin 8 - final GT ready
set_property PACKAGE_PIN AA14 [get_ports dbg_scope_gt_ready]
set_property IOSTANDARD LVCMOS33 [get_ports dbg_scope_gt_ready]

# J9 GPIO9 / pin 9 - TXUSRCLK2 divided by 16
set_property PACKAGE_PIN AD15 [get_ports dbg_scope_txusrclk2_div16]
set_property IOSTANDARD LVCMOS33 [get_ports dbg_scope_txusrclk2_div16]

set_property DRIVE 4 [get_ports {
    dbg_scope_rate_req
    dbg_scope_tx_mmcm_locked
    dbg_scope_gt_ready
    dbg_scope_txusrclk2_div16
}]

set_property SLEW SLOW [get_ports {
    dbg_scope_rate_req
    dbg_scope_tx_mmcm_locked
    dbg_scope_gt_ready
    dbg_scope_txusrclk2_div16
}]

# Output delays intentionally omitted until the external receiver clock and
# setup/hold requirements are known.
