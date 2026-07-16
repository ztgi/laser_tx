# Create a clean Vitis 2022.2 platform/BSP from the timing-clean runtime-rate XSA.
# The generated workspace is intentionally placed under reports/ and is not a
# tracked source tree.

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set artifact_root [file join $project_dir reports ad9528_gt_rate_planner artifact_build]
# Keep the generated workspace path short.  Vitis 2022.2 BSP make rules on
# Windows fail to copy core standalone headers when nested below the much
# deeper artifact directory.
set workspace [file join $project_dir reports runtime_rate_vitis]
set xsa_file [file join $artifact_root artifacts laser_tx_board_top_runtime_rate_switch.xsa]
set platform_name runtime_rate_artifact_platform
set domain_name standalone_ps7_cortexa9_0

if {![file exists $xsa_file]} {
    error "Timing-clean XSA not found: $xsa_file"
}

if {[file exists $workspace]} {
    error "Refusing to overwrite Vitis workspace: $workspace"
}

file mkdir $workspace
setws $workspace

platform create -name $platform_name -hw $xsa_file -out $workspace
domain create -name $domain_name -display-name $domain_name \
    -os standalone -proc ps7_cortexa9_0 -runtime cpp -arch 32-bit \
    -support-app empty_application
platform write
platform active $platform_name
domain active $domain_name

# Generate the base standalone BSP first.  Vitis 2022.2 otherwise starts the
# lwIP build before the standalone headers (including xpseudo_asm.h) have been
# copied into the domain include directory.
platform generate
platform active $platform_name
domain active $domain_name

bsp config stdin "ps7_uart_1"
bsp setlib -name lwip211 -ver 1.8
bsp config dhcp_does_arp_check "false"
bsp config phy_link_speed "CONFIG_LINKSPEED100"
bsp write
catch {bsp regenerate}
platform generate

puts "RUNTIME_RATE_VITIS_PLATFORM=PASS"
puts "workspace=$workspace"
puts "platform=$platform_name"
puts "domain=$domain_name"
puts "xsa=$xsa_file"
