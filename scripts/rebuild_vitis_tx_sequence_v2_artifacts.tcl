# Update the original Vitis 2022.2 platform from the TX Sequence V2 XSA and
# perform a managed clean build of the existing bringup application.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set workspace [file join $root vitis_bringup]
set xsa_file [file join $root reports tx_sequence_v2_artifact_build artifacts \
    laser_tx_board_top_tx_sequence_v2.xsa]
set platform_name laser_tx_system_top
set domain_name standalone_ps7_cortexa9_0
set app_name bringup
set app_debug_dir [file join $workspace $app_name Debug]
set bsp_lib_dir [file join $workspace $platform_name export $platform_name sw \
    $platform_name $domain_name bsplib lib]
set elf_file [file join $app_debug_dir ${app_name}.elf]

if {![file exists $xsa_file]} {
    error "TX Sequence V2 XSA is missing: $xsa_file"
}
if {![file isdirectory $workspace]} {
    error "Original Vitis workspace is missing: $workspace"
}

setws $workspace
platform active $platform_name
platform config -updatehw $xsa_file
platform write
platform active $platform_name
domain active $domain_name
platform generate

# Preserve the existing application and its managed source inventory.  A real
# clean build verifies that no manually supplied object is required.
app clean -name $app_name
app build -name $app_name

# Vitis 2022.2 can return success after only regenerating the managed makefile
# in an older workspace.  Execute that generated makefile explicitly and pass
# the freshly generated BSP library directory to the linker.  USER_OBJS and
# the managed source/object inventory remain unchanged.
if {![file isdirectory $app_debug_dir]} {
    error "Managed application Debug directory is missing: $app_debug_dir"
}
if {![file exists [file join $bsp_lib_dir libxil.a]] ||
    ![file exists [file join $bsp_lib_dir liblwip4.a]]} {
    error "Generated BSP libraries are missing: $bsp_lib_dir"
}
set managed_libs "-L[file normalize $bsp_lib_dir] -Wl,--start-group,-lxil,-lgcc,-lc,--end-group -Wl,--start-group,-lxil,-llwip4,-lgcc,-lc,--end-group"
set old_dir [pwd]
cd $app_debug_dir
if {[catch {exec make clean 2>@1} clean_output]} {
    cd $old_dir
    error "Managed application clean failed:\n$clean_output"
}
if {[catch {exec make all "LIBS=$managed_libs" 2>@1} build_output]} {
    cd $old_dir
    error "Managed application build failed:\n$build_output"
}
cd $old_dir
if {![file exists $elf_file]} {
    error "Managed application reported success but ELF is missing: $elf_file"
}

puts "TX_SEQUENCE_V2_VITIS_BUILD=PASS"
puts "workspace=$workspace"
puts "platform=$platform_name"
puts "domain=$domain_name"
puts "application=$app_name"
puts "xsa=$xsa_file"
puts "elf=$elf_file"
