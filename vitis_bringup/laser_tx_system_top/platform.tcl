# 
# Usage: To re-create this platform project launch xsct with below options.
# xsct D:\FPGA_Learn\laser_tx\vitis_bringup\laser_tx_system_top\platform.tcl
# 
# OR launch xsct and run below command.
# source D:\FPGA_Learn\laser_tx\vitis_bringup\laser_tx_system_top\platform.tcl
# 
# To create the platform in a different location, modify the -out option of "platform create" command.
# -out option specifies the output directory of the platform project.

platform create -name {laser_tx_system_top}\
-hw {D:\FPGA_Learn\project_gtx\laser_tx_system_top.xsa}\
-out {D:/FPGA_Learn/laser_tx/vitis_bringup}

platform write
domain create -name {standalone_ps7_cortexa9_0} -display-name {standalone_ps7_cortexa9_0} -os {standalone} -proc {ps7_cortexa9_0} -runtime {cpp} -arch {32-bit} -support-app {empty_application}
platform generate -domains 
platform active {laser_tx_system_top}
domain active {zynq_fsbl}
domain active {standalone_ps7_cortexa9_0}
platform generate -quick
platform generate
platform clean
platform active {laser_tx_system_top}
bsp reload
catch {bsp regenerate}
bsp reload
platform config -updatehw {D:/FPGA_Learn/laser_tx/laser_tx_board_top_gt_profile0.xsa}
platform config -updatehw {D:/FPGA_Learn/laser_tx/laser_tx_board_top_gt_profile0.xsa}
bsp reload
catch {bsp regenerate}
domain active {zynq_fsbl}
bsp reload
catch {bsp regenerate}
platform clean
platform clean
platform generate
platform clean
platform generate
platform clean
platform generate
domain active {standalone_ps7_cortexa9_0}
bsp config stdin "ps7_uart_1"
bsp config zynqmp_fsbl_bsp "false"
bsp write
bsp setlib -name lwip211 -ver 1.8
bsp removelib -name lwip211
bsp setlib -name lwip211 -ver 1.8
bsp removelib -name lwip211
bsp setlib -name lwip211 -ver 1.8
bsp config dhcp_does_arp_check "false"
bsp config phy_link_speed "CONFIG_LINKSPEED100"
bsp write
bsp reload
catch {bsp regenerate}
catch {bsp regenerate}
platform clean
platform generate
platform clean
platform generate
platform clean
platform generate
platform generate
platform active {laser_tx_system_top}
platform active {laser_tx_system_top}
bsp reload
bsp write
catch {bsp regenerate}
platform clean
platform generate
platform clean
platform generate
platform clean
platform generate
catch {bsp regenerate}
catch {bsp regenerate}
catch {bsp regenerate}
catch {bsp regenerate}
bsp write
platform generate
platform generate
platform active {laser_tx_system_top}
bsp reload
bsp reload
platform config -updatehw {D:/FPGA_Learn/laser_tx/laser_tx_board_top.xsa}
domain active {zynq_fsbl}
bsp reload
catch {bsp regenerate}
domain active {standalone_ps7_cortexa9_0}
bsp reload
catch {bsp regenerate}
bsp reload
platform clean
platform generate
platform clean
platform generate
platform clean
platform generate
platform clean
platform clean
platform generate
platform generate
