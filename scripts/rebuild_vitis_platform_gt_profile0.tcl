# Build a fresh standalone platform/BSP from the GT Profile 0 XSA.
# Usage:
#   D:/Vitis/2022.2/bin/xsct.bat scripts/rebuild_vitis_platform_gt_profile0.tcl
# It creates a new platform name/path and never overwrites the legacy platform.

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set xsa_file [file join $project_dir laser_tx_board_top_gt_profile0.xsa]
set vitis_out [file join $project_dir vitis_bringup]
set platform_name laser_tx_gt_profile0_platform

if {![file exists $xsa_file]} {
    error "GT Profile 0 XSA not found: $xsa_file"
}
if {[file exists [file join $vitis_out $platform_name]]} {
    error "Refusing to overwrite existing platform: [file join $vitis_out $platform_name]"
}

platform create -name $platform_name -hw $xsa_file -out $vitis_out
domain create -name standalone_ps7_cortexa9_0 -display-name standalone_ps7_cortexa9_0 \
    -os standalone -proc ps7_cortexa9_0 -runtime cpp -arch 32-bit \
    -support-app empty_application
platform write
platform generate
platform active $platform_name
domain active standalone_ps7_cortexa9_0
platform generate -quick
puts "INFO: Fresh GT Profile 0 platform generated from $xsa_file"
