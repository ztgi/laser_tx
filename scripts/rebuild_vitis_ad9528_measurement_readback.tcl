# Update the existing Vitis platform from the software-readback XSA, then
# clean-build the bringup application.
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set workspace [file join $project_dir vitis_bringup]
set xsa_file [file join $project_dir reports ad9528_out0_software_readback laser_tx_board_top_ad9528_measure.xsa]

if {![file exists $xsa_file]} {
    error "XSA not found: $xsa_file"
}
setws $workspace
platform active laser_tx_system_top
platform config -updatehw $xsa_file
platform generate
app clean -name bringup
app build -name bringup
puts "INFO: Updated laser_tx_system_top and built bringup from $xsa_file"
