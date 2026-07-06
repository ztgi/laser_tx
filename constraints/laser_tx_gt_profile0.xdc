# Single-optical-port GTX TX: Profile 0
# Board reference: XC7Z100 / ADRV9009 V3.0, identical lane/refclk mapping to
# D:/FPGA_Learn/project_gtx.  This profile is fixed at 0.5 Gb/s with a 64-bit
# TX user interface and uses the local 125 MHz MGTREFCLK0 in bank 111.

set_property PACKAGE_PIN AB2 [get_ports gtx_txp_out]
set_property PACKAGE_PIN AB1 [get_ports gtx_txn_out]

set_property PACKAGE_PIN U8 [get_ports gt_refclk125_p]
set_property PACKAGE_PIN U7 [get_ports gt_refclk125_n]
create_clock -period 8.000 -name MGT_REFCLK_125M [get_ports gt_refclk125_p]

# The package pins place the GTX channel in bank 111.  The validated runtime
# profiles still select the CPLL path, but the wrapper also instantiates the
# quad COMMON block so the QPLL clock/lock/reset path is real and available for
# the next architecture stage.  Keep both locations explicit; direct
# out-of-context IP insertion does not always carry the GT placement into the
# top-level implementation.  The TX differential pins AB2/AB1 correspond to the
# validated single optical GTX lane in bank 111.
set_property LOC GTXE2_CHANNEL_X0Y8 [get_cells -hier -filter {REF_NAME == GTXE2_CHANNEL && NAME =~ *u_laser_gt_tx_profile0*}]
set_property LOC GTXE2_COMMON_X0Y2 [get_cells -hier -filter {REF_NAME == GTXE2_COMMON && NAME =~ *u_gtxe2_common_qpll*}]

# GT Wizard IP constrains the primitive TXOUTCLK to 64 ns.  The local Profile 0
# user-clock MMCM follows the Wizard example design:
#   TXOUTCLK  = 15.625 MHz, 64 ns
#   TXUSRCLK  = 15.625 MHz, 64 ns
#   TXUSRCLK2 =  7.8125 MHz, 128 ns
# The MMCM generated clocks are inferred from the MMCME2_ADV instance.  The
# implementation pre-hook verifies these periods and applies the AXI<->GT
# asynchronous clock group after link_design, when the IP/DCP/MMCM clock objects
# exist.  Do not constrain laser_tx_core.txusrclk2 as 15.625 MHz.
