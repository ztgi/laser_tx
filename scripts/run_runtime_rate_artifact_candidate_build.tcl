# Clean, gated artifact build for the Iteration-7 runtime-rate RTL baseline.
# Generated reports and binary artifacts stay below reports/ and are not Git inputs.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set out [file join $root reports ad9528_gt_rate_planner artifact_build]
set artifact_dir [file join $out artifacts]
file mkdir $out
file mkdir $artifact_dir

proc require_complete {run_name} {
    set run [get_runs -quiet $run_name]
    if {![llength $run]} { error "required run does not exist: $run_name" }
    set status [get_property STATUS $run]
    if {![string match "*Complete*" $status]} {
        error "$run_name is not complete: $status"
    }
}

proc sha256_file {path} {
    set escaped [string map {' ''} [file normalize $path]]
    return [string trim [exec powershell.exe -NoProfile -Command \
        "(Get-FileHash -LiteralPath '$escaped' -Algorithm SHA256).Hash"]]
}

proc report_contains_zero {path check_name} {
    set fp [open $path r]
    set text [read $fp]
    close $fp
    return [regexp "checking ${check_name} \\(0\\)" $text]
}

open_project [file join $root laser_tx.xpr]
set_property top laser_tx_board_top [get_filesets sources_1]

# Preserve the timing-clean source policy: XCI supplies parameter provenance,
# while tracked wrapper sources expose the runtime reference-clock controls.
set wizard_xci [get_files -quiet */gtwizard_0.xci]
if {![llength $wizard_xci]} { error "gtwizard_0.xci not found" }
set_property IS_ENABLED false $wizard_xci
set wrapper_root [file join $root laser_tx.srcs sources_1 imports sources_1 ip gtwizard_0]
set wrapper_sources [concat \
    [glob -nocomplain [file join $wrapper_root *.v]] \
    [glob -nocomplain [file join $wrapper_root gtwizard_0 example_design *.v]]]
foreach source $wrapper_sources {
    if {![llength [get_files -quiet $source]]} {
        add_files -fileset sources_1 -norecurse $source
    }
}

set bd_file [get_files -quiet */system.bd]
if {![llength $bd_file]} { error "system.bd not found" }
# A clean composite regeneration is the supported freshness mechanism for IPI
# children which Vivado does not expose as independent synth runs.
set bd_regeneration_start [clock seconds]
reset_target all $bd_file
generate_target all $bd_file
# Child IPI cores must be managed through their parent block design.  Calling
# create_ip_run on an individual child XCI is rejected by Vivado 2022.2.
create_ip_run $bd_file
update_compile_order -fileset sources_1

# Every child checkpoint loaded by the managed implementation flow must have a
# current managed OOC run.  Disabling IP cache for this build makes freshness
# independent of a previous workstation cache entry.
set required_ips {
    system_processing_system7_0_0
    system_axi_bram_ctrl_0_0
    system_blk_mem_gen_0_0
    system_axi_gpio_0_0
    system_axi_smc_0
    system_rst_ps7_0_50M_0
    system_ila_laser_axi_cfg_0
    system_ila_laser_tx_0
    system_axi_gpio_gt_status_0
    system_axi_gpio_ad9528_measure_0
    system_axi_gpio_dynamic_mailbox_0
    system_axi_bram_dyn_desc_0
    system_blk_mem_dyn_desc_0
    system_laser_tx_core_0_0
}
set ooc_runs {}
foreach ip_name $required_ips {
    set ip [get_ips -quiet $ip_name]
    if {![llength $ip]} { error "required managed IP not found: $ip_name" }
    set run_name ${ip_name}_synth_1
    if {[llength [get_runs -quiet $run_name]]} {
        catch {config_ip_cache -disable_for_ip $ip}
        lappend ooc_runs $run_name
    }
}

foreach run_name $ooc_runs { reset_run $run_name }
launch_runs $ooc_runs -jobs 4
foreach run_name $ooc_runs {
    wait_on_run $run_name
    require_complete $run_name
}

# For IPs with independent managed runs, require the generated composite DCP and
# run DCP to be byte-identical.  Other IPI children are clean-generated only by
# their parent BD; require their DCP to have been written by this invocation.
set hash_fp [open [file join $out ooc_dcp_freshness.tsv] w]
puts $hash_fp "ip\tprovenance\trun_dcp\tgenerated_dcp\trun_sha256\tgenerated_sha256\tmatch\tgenerated_mtime"
foreach ip_name $required_ips {
    set run_name ${ip_name}_synth_1
    set run_dcp ""
    set candidates [get_files -quiet -all */${ip_name}.dcp]
    set generated_dcp ""
    foreach candidate $candidates {
        set norm [string map {\\ /} [file normalize $candidate]]
        if {[string first "/laser_tx.gen/" $norm] >= 0} {
            set generated_dcp [file normalize $candidate]
            break
        }
    }
    if {$generated_dcp eq "" || ![file exists $generated_dcp]} {
        error "missing OOC freshness input for $ip_name: run=$run_dcp generated=$generated_dcp"
    }
    set generated_hash [sha256_file $generated_dcp]
    set generated_mtime [file mtime $generated_dcp]
    if {[llength [get_runs -quiet $run_name]]} {
        set run_dir [file normalize [get_property DIRECTORY [get_runs $run_name]]]
        set run_dcp [file join $run_dir ${ip_name}.dcp]
        if {![file exists $run_dcp]} { error "managed OOC DCP missing: $run_dcp" }
        set run_hash [sha256_file $run_dcp]
        set match [expr {[string equal -nocase $run_hash $generated_hash] ? 1 : 0}]
        set provenance MANAGED_OOC_RUN_AND_BD_EXPORT
        if {!$match} { error "stale generated OOC checkpoint detected for $ip_name" }
    } else {
        set run_hash NA
        set match [expr {$generated_mtime >= $bd_regeneration_start ? 1 : 0}]
        set provenance CLEAN_PARENT_BD_GENERATION
        if {!$match} { error "child DCP was not regenerated in this build: $generated_dcp" }
    }
    puts $hash_fp [join [list $ip_name $provenance $run_dcp $generated_dcp $run_hash $generated_hash $match $generated_mtime] "\t"]
}
close $hash_fp

# The module-reference OOC checkpoint must contain the exact Iteration-7 RTL.
set core_run system_laser_tx_core_0_0_synth_1
open_run $core_run
set signature_patterns [dict create \
    pattern_index_reg *pattern_index_reg* \
    pattern_mode_63_active *pattern_mode_63_active* \
    pattern_cursor_reg *pattern_cursor_reg* \
    len_active_reg *len_active_reg* \
    next_phase_pattern_base_q *next_phase_pattern_base_q* \
    cross_next_valid_count_q *cross_next_valid_count_q* \
    current_pattern_q *current_pattern_q* \
    rotated_pattern_reg *rotated_pattern_reg*]
set signature_fp [open [file join $out ooc_rtl_signature.txt] w]
dict for {name pattern} $signature_patterns {
    set count [llength [get_cells -quiet -hier $pattern]]
    set signature($name) $count
    puts $signature_fp "$name=$count"
}
close $signature_fp
close_design
if {$signature(pattern_index_reg) == 0 ||
    $signature(pattern_mode_63_active) == 0 ||
    $signature(pattern_cursor_reg) != 0 ||
    $signature(len_active_reg) != 0 ||
    $signature(next_phase_pattern_base_q) != 0 ||
    $signature(cross_next_valid_count_q) != 0 ||
    $signature(current_pattern_q) != 0 ||
    $signature(rotated_pattern_reg) != 0} {
    error "Iteration-7 OOC RTL signature mismatch"
}

reset_run impl_1
reset_run synth_1
set impl_run [get_runs impl_1]
set_property strategy Performance_Explore $impl_run
set_property STEPS.OPT_DESIGN.TCL.PRE \
    [file join $root scripts gt_profile0_impl_pre.tcl] $impl_run
launch_runs synth_1 -jobs 4
wait_on_run synth_1
require_complete synth_1
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
require_complete impl_1
open_run impl_1

set txusrclk [get_clocks -quiet GT_TXUSRCLK_RUNTIME_MAX]
set txusrclk2 [get_clocks -quiet GT_TXUSRCLK2_RUNTIME_MAX]
if {![llength $txusrclk] || ![llength $txusrclk2]} {
    error "runtime maximum user-clock constraints are missing"
}
set txusrclk_period [get_property PERIOD $txusrclk]
set txusrclk2_period [get_property PERIOD $txusrclk2]
if {abs($txusrclk_period - 3.103) > 0.001 || abs($txusrclk2_period - 6.206) > 0.001} {
    error "runtime clock mismatch: TXUSRCLK=$txusrclk_period TXUSRCLK2=$txusrclk2_period"
}

report_timing_summary -delay_type min_max -max_paths 100 -report_unconstrained \
    -file [file join $out timing_summary.rpt]
report_timing -delay_type max -max_paths 50 -path_type full_clock_expanded \
    -file [file join $out setup_top50.rpt]
report_timing -delay_type min -max_paths 50 -path_type full_clock_expanded \
    -file [file join $out hold_top50.rpt]
report_clock_interaction -delay_type min_max -file [file join $out clock_interaction.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_route_status -file [file join $out route_status.rpt]
report_drc -file [file join $out drc.rpt]
report_utilization -hierarchical -file [file join $out utilization.rpt]
report_debug_core -full_path -file [file join $out debug_cores.rpt]
write_checkpoint -force [file join $out routed.dcp]

set setup_paths [get_timing_paths -quiet -delay_type max -max_paths 100000 -slack_lesser_than 0]
set hold_paths [get_timing_paths -quiet -delay_type min -max_paths 100000 -slack_lesser_than 0]
set worst_setup [get_timing_paths -quiet -delay_type max -max_paths 1]
set worst_hold [get_timing_paths -quiet -delay_type min -max_paths 1]
set wns [expr {[llength $worst_setup] ? [get_property SLACK $worst_setup] : -999.0}]
set whs [expr {[llength $worst_hold] ? [get_property SLACK $worst_hold] : -999.0}]
set tns 0.0
foreach path $setup_paths { set tns [expr {$tns + [get_property SLACK $path]}] }
set ths 0.0
foreach path $hold_paths { set ths [expr {$ths + [get_property SLACK $path]}] }
set drc_errors [llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]
set unrouted [llength [get_nets -quiet -hier -filter {ROUTE_STATUS == UNROUTED}]]
set check_report [file join $out check_timing.rpt]
set no_clock_ok [report_contains_zero $check_report no_clock]
set multiple_clock_ok [report_contains_zero $check_report multiple_clock]
set unconstrained_ok [report_contains_zero $check_report unconstrained_internal_endpoints]

set metrics_fp [open [file join $out artifact_build_metrics.txt] w]
puts $metrics_fp "txusrclk_period_ns=$txusrclk_period"
puts $metrics_fp "txusrclk2_period_ns=$txusrclk2_period"
puts $metrics_fp "wns_ns=$wns"
puts $metrics_fp "tns_ns=$tns"
puts $metrics_fp "setup_failing_endpoints=[llength $setup_paths]"
puts $metrics_fp "whs_ns=$whs"
puts $metrics_fp "ths_ns=$ths"
puts $metrics_fp "hold_failing_endpoints=[llength $hold_paths]"
puts $metrics_fp "drc_errors=$drc_errors"
puts $metrics_fp "unrouted_nets=$unrouted"
puts $metrics_fp "no_clock_zero=$no_clock_ok"
puts $metrics_fp "multiple_clock_zero=$multiple_clock_ok"
puts $metrics_fp "unconstrained_internal_endpoints_zero=$unconstrained_ok"
close $metrics_fp

if {$wns < 0.0 || $tns < 0.0 || $whs < 0.0 || $ths < 0.0 ||
    [llength $setup_paths] != 0 || [llength $hold_paths] != 0 ||
    $drc_errors != 0 || $unrouted != 0 || !$no_clock_ok ||
    !$multiple_clock_ok || !$unconstrained_ok} {
    error "artifact timing/route/DRC gate failed; bit/LTX/XSA were not generated"
}

close_design
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
require_complete impl_1
open_run impl_1

set impl_dir [file normalize [get_property DIRECTORY [get_runs impl_1]]]
set run_bit [file join $impl_dir laser_tx_board_top.bit]
if {![file exists $run_bit]} { error "bitstream was not generated: $run_bit" }
set bit_path [file join $artifact_dir laser_tx_board_top.bit]
set ltx_path [file join $artifact_dir laser_tx_board_top.ltx]
set xsa_path [file join $artifact_dir laser_tx_board_top_runtime_rate_switch.xsa]
file copy -force $run_bit $bit_path
write_debug_probes -force $ltx_path
write_hw_platform -fixed -include_bit -force -file $xsa_path
report_timing_summary -delay_type min_max -max_paths 100 -report_unconstrained \
    -file [file join $out final_timing_summary.rpt]

set final_fp [open [file join $out hardware_artifact_paths.txt] w]
puts $final_fp "bit=$bit_path"
puts $final_fp "ltx=$ltx_path"
puts $final_fp "xsa=$xsa_path"
puts $final_fp "routed_dcp=[file join $out routed.dcp]"
close $final_fp
puts "RUNTIME_RATE_ARTIFACT_BUILD=PASS"
puts "BIT=$bit_path"
puts "LTX=$ltx_path"
puts "XSA=$xsa_path"
close_project
