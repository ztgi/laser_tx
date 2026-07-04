# Build an isolated static 1000 Mb/s GT TX Profile 1 bitstream.
#
# Run from the project root:
#   vivado -mode batch -source scripts/build_gt_profile1_1000m_static.tcl
#
# This script intentionally creates a copied Vivado project in a short local
# work directory and copies final artifacts back under reports/.
# It does not overwrite the verified Profile 0 XCI or Profile 0 source top.
# It also does not implement runtime rate switching, GTX DRP, or MMCM DRP.

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set project_file [file join $project_dir laser_tx.xpr]

set out_root [file join $project_dir reports gt_profile1_1000m_static]
set copied_project_dir [file join $project_dir _p1_1g_vivado]
set copied_project_name p1
set copied_project_file [file join $copied_project_dir ${copied_project_name}.xpr]
set report_dir [file join $out_root reports]
set artifact_dir [file join $out_root artifacts]

set profile1_top [file join $project_dir rtl laser_tx_board_top_profile1_1000m.v]
set profile1_gt [file join $project_dir laser_tx.srcs sources_1 new laser_gt_tx_profile1_1000m.v]
set profile1_usrclk [file join $project_dir laser_tx.srcs sources_1 new laser_gt_usrclk_profile1_1000m.v]
set profile1_xdc [file join $project_dir constraints laser_tx_gt_profile1_1000m.xdc]
set profile0_xdc [file join $project_dir constraints laser_tx_gt_profile0.xdc]
set impl_pre_tcl [file join $script_dir gt_profile1_1000m_impl_pre.tcl]

set profile0_xci [file join $project_dir laser_tx.srcs sources_1 ip gtwizard_0 gtwizard_0.xci]
set profile0_gen_gt [file join $project_dir laser_tx.gen sources_1 ip gtwizard_0 gtwizard_0_gt.v]
set profile0_gen_xml [file join $project_dir laser_tx.gen sources_1 ip gtwizard_0 gtwizard_0.xml]

set compare_script [file join $script_dir create_gtwizard_1000m_compare.tcl]
set profile1_xci [file join $project_dir reports gt_dynamic_rate_phase2_design_pkg gtwizard_1000m_compare copied_ip gtwizard_0.xci]
set profile1_prop_report [file join $project_dir reports gt_dynamic_rate_phase2_design_pkg gtwizard_1000m_compare gtwizard_1000m_selected_properties.txt]
set copied_project_xci [file join $copied_project_dir ${copied_project_name}.srcs sources_1 ip gtwizard_0 gtwizard_0.xci]
set copied_project_gt_gen_dir [file join $copied_project_dir ${copied_project_name}.gen sources_1 ip gtwizard_0]

proc build_fail {message} {
    puts stderr "ERROR: $message"
    return -code error $message
}

proc require_file {path description} {
    if {![file exists $path]} {
        build_fail "$description not found: $path"
    }
}

proc require_file_regex {path pattern description} {
    require_file $path $description
    set fh [open $path r]
    set text [read $fh]
    close $fh
    if {![regexp $pattern $text]} {
        build_fail "$description does not match required pattern '$pattern': $path"
    }
}

proc require_complete_run {run_name expected_status_glob} {
    set status [get_property STATUS [get_runs $run_name]]
    puts "INFO: $run_name status: $status"
    if {![string match $expected_status_glob $status]} {
        build_fail "$run_name did not complete successfully: $status"
    }
}

proc remove_file_if_present {path} {
    set files [get_files -quiet [file normalize $path]]
    if {[llength $files] > 0} {
        remove_files $files
    }
}

proc rewrite_xci_output_dir {xci_path output_dir} {
    set output_dir_norm [string map {\\ /} [file normalize $output_dir]]
    set fh [open $xci_path r]
    set text [read $fh]
    close $fh
    regsub {"gen_directory": "[^"]+"} $text "\"gen_directory\": \"$output_dir_norm\"" text
    if {[regexp {"OUTPUTDIR": \[ \{ "value": "[^"]+" \} \]} $text]} {
        regsub {"OUTPUTDIR": \[ \{ "value": "[^"]+" \} \]} $text "\"OUTPUTDIR\": \[ \{ \"value\": \"$output_dir_norm\" \} \]" text
    }
    set fh [open $xci_path w]
    puts -nonewline $fh $text
    close $fh
}

require_file $project_file "Source Vivado project"
require_file $profile1_top "Profile 1 top"
require_file $profile1_gt "Profile 1 GT wrapper"
require_file $profile1_usrclk "Profile 1 user clocking"
require_file $profile1_xdc "Profile 1 XDC"
require_file $impl_pre_tcl "Profile 1 implementation pre-hook"
require_file $compare_script "1000M comparison generator"

# Profile 0 guard before any work.
require_file_regex $profile0_gen_gt {\.TXOUT_DIV\s*\(\s*8\s*\)} "Profile 0 generated GT HDL"
require_file_regex $profile0_gen_xml {gt0_val_tx_line_rate} "Profile 0 generated GT XML"
require_file_regex $profile0_gen_xml {>0[.]5<} "Profile 0 generated GT XML"

file mkdir $out_root
file mkdir $report_dir
file mkdir $artifact_dir

# Ensure the isolated 1000M comparison XCI exists and is current.
source $compare_script
require_file $profile1_xci "Isolated 1000M comparison XCI"
require_file_regex $profile1_prop_report {gt0_val_tx_line_rate = 1\.0} "1000M selected property report"
require_file_regex $profile1_prop_report {gt0_val_cpll_txout_div = 4} "1000M selected property report"

if {[llength [get_projects -quiet]] > 0} {
    close_project
}
open_project $project_file

if {[file exists $copied_project_dir]} {
    file delete -force $copied_project_dir
}
file mkdir $copied_project_dir

save_project_as $copied_project_name $copied_project_dir -force
close_project

# Replace the copied project's local GT Wizard XCI before opening the copied
# project.  Merely adding another same-named gtwizard_0.xci is not sufficient:
# Vivado keeps using the copied Profile 0 IP.  Overwriting the copied local XCI
# makes the copied project explicitly static-1000M while the source Profile 0
# XCI remains untouched.
require_file $copied_project_xci "Copied project local GT Wizard XCI"
file copy -force $profile1_xci $copied_project_xci
rewrite_xci_output_dir $copied_project_xci $copied_project_gt_gen_dir
if {[file exists $copied_project_gt_gen_dir]} {
    file delete -force $copied_project_gt_gen_dir
}

open_project $copied_project_file

# Work only inside the copied project from this point.
remove_file_if_present $profile0_xdc
add_files -fileset constrs_1 -norecurse $profile1_xdc

add_files -fileset sources_1 -norecurse [list $profile1_top $profile1_gt $profile1_usrclk]
set_property top laser_tx_board_top_profile1_1000m [get_filesets sources_1]

# Create a dedicated static-1000M GT debug ILA in the copied project.
if {[llength [get_ips -quiet ila_gt_profile1_1000m]] == 0} {
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_gt_profile1_1000m
}
set ila_ip [get_ips ila_gt_profile1_1000m]
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {8} \
    CONFIG.C_DATA_DEPTH {2048} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {24} \
    CONFIG.C_PROBE6_WIDTH {64} \
    CONFIG.C_PROBE7_WIDTH {64}] $ila_ip
generate_target all $ila_ip

reset_target all [get_ips gtwizard_0]
generate_target all [get_ips gtwizard_0]

set system_bd [get_files -quiet -all -filter {NAME =~ */system.bd || NAME == system.bd}]
if {[llength $system_bd] != 1} {
    build_fail "Expected one system.bd in copied project for output product regeneration; got '$system_bd'."
}
puts "INFO: Regenerating copied project BD output products so module-reference debug RTL is included: $system_bd"
reset_target all $system_bd
generate_target all $system_bd
update_compile_order -fileset sources_1

if {[get_property top [get_filesets sources_1]] ne "laser_tx_board_top_profile1_1000m"} {
    build_fail "sources_1 top must be laser_tx_board_top_profile1_1000m."
}

foreach run_name {gtwizard_0_synth_1 ila_gt_profile1_1000m_synth_1} {
    if {[llength [get_runs -quiet $run_name]] == 1} {
        reset_run $run_name
        launch_runs $run_name -jobs 2
        wait_on_run $run_name
        require_complete_run $run_name "synth_design Complete!"
    } else {
        puts "WARNING: Optional IP run not found: $run_name"
    }
}

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
require_complete_run synth_1 "synth_design Complete!"

reset_run impl_1
set_property STEPS.OPT_DESIGN.TCL.PRE $impl_pre_tcl [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
require_complete_run impl_1 "write_bitstream Complete!"

open_run impl_1
report_clocks -file [file join $report_dir clocks.rpt]
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_clock_interaction -file [file join $report_dir clock_interaction.rpt]
report_cdc -file [file join $report_dir cdc.rpt]

set impl_dir [file join $copied_project_dir ${copied_project_name}.runs impl_1]
set bit_src [file join $impl_dir laser_tx_board_top_profile1_1000m.bit]
set ltx_src [file join $impl_dir laser_tx_board_top_profile1_1000m.ltx]
set debug_ltx_src [file join $impl_dir debug_nets.ltx]
require_file $bit_src "Profile 1 bitstream"
if {![file exists $ltx_src] && [file exists $debug_ltx_src]} {
    set ltx_src $debug_ltx_src
}
require_file $ltx_src "Profile 1 LTX"

file copy -force $bit_src [file join $artifact_dir laser_tx_board_top_profile1_1000m.bit]
file copy -force $ltx_src [file join $artifact_dir laser_tx_board_top_profile1_1000m.ltx]

# Profile 0 guard after build.
require_file_regex $profile0_gen_gt {\.TXOUT_DIV\s*\(\s*8\s*\)} "Profile 0 generated GT HDL after Profile 1 build"
require_file_regex $profile0_gen_xml {gt0_val_tx_line_rate} "Profile 0 generated GT XML after Profile 1 build"
require_file_regex $profile0_gen_xml {>0[.]5<} "Profile 0 generated GT XML after Profile 1 build"

puts "INFO: Static 1000M Profile 1 bitstream completed."
puts "INFO: BIT: [file join $artifact_dir laser_tx_board_top_profile1_1000m.bit]"
puts "INFO: LTX: [file join $artifact_dir laser_tx_board_top_profile1_1000m.ltx]"
puts "INFO: Reports: $report_dir"
close_project
