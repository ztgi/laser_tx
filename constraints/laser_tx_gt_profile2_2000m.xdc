# Single-optical-port GTX TX: static Profile 2 2000M validation.
# Same board lane/refclk mapping as fixed Profile 0.
# This XDC is intended for the isolated 2000M project copy only.

set_property PACKAGE_PIN AB2 [get_ports gtx_txp_out]
set_property PACKAGE_PIN AB1 [get_ports gtx_txn_out]

set_property PACKAGE_PIN U8 [get_ports gt_refclk125_p]
set_property PACKAGE_PIN U7 [get_ports gt_refclk125_n]
create_clock -period 8.000 -name MGT_REFCLK_125M [get_ports gt_refclk125_p]

# Static 2000M TX user clocking from GT Wizard example design:
#   TXOUTCLK  = 62.5  MHz, 16 ns
#   TXUSRCLK  = 62.5  MHz, 16 ns
#   TXUSRCLK2 = 31.25 MHz, 32 ns
# The implementation pre-hook verifies these generated clock periods after
# link_design has created GT/MMCM clock objects.

