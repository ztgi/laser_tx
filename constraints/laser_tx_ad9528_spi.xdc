# ============================================================
# PS SPI1 EMIO for the ADRV9009 / AD9528 shared SPI bus
# Bank 11, VCCO = 2.5 V
#
# Schematic sheet 16 maps SS0 to AJ23 and SS1 to AK23.
# Schematic sheet 20 maps SS0 to ADRV9009 and SS1 to AD9528.
# The AD9528 software selects slave 1 (AD9528_SPI_SLAVE = 1U).
# ============================================================

# SPI SCLK
set_property PACKAGE_PIN AJ24 [get_ports SPI_1_0_sck_io]
set_property IOSTANDARD LVCMOS25 [get_ports SPI_1_0_sck_io]

# SPI MOSI / DIN / SDIO
set_property PACKAGE_PIN AH23 [get_ports SPI_1_0_io0_io]
set_property IOSTANDARD LVCMOS25 [get_ports SPI_1_0_io0_io]

# SPI MISO / DOUT / SDO
set_property PACKAGE_PIN AH24 [get_ports SPI_1_0_io1_io]
set_property IOSTANDARD LVCMOS25 [get_ports SPI_1_0_io1_io]

# ADRV9009 chip select (SS0)
set_property PACKAGE_PIN AJ23 [get_ports SPI_1_0_ss_io]
set_property IOSTANDARD LVCMOS25 [get_ports SPI_1_0_ss_io]

# AD9528 chip select (SS1)
set_property PACKAGE_PIN AK23 [get_ports SPI_1_0_ss1_o]
set_property IOSTANDARD LVCMOS25 [get_ports SPI_1_0_ss1_o]

# PS7 internally provides SS2, but the board top-level wrapper intentionally
# does not export it. Only the two chip selects present on the schematic are
# physical top-level ports.
