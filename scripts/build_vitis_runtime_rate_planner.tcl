# Managed clean build for the existing bringup application.  This script does
# not update hardware, regenerate the platform, or add manual object files.
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
if {[info exists ::env(LASER_VITIS_WORKSPACE)]} {
    set workspace [file normalize $::env(LASER_VITIS_WORKSPACE)]
} else {
    set workspace [file join $project_dir vitis_bringup]
}

setws $workspace
app clean -name bringup
app build -name bringup
puts "INFO: managed clean build completed for bringup"
