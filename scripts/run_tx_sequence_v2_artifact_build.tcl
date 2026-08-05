# Clean, gated artifact build for the protocol-incompatible TX sequence V2.
# Generated reports and binary artifacts stay below reports/ and are not Git inputs.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set out [file join $root reports tx_sequence_v2_artifact_build]
set artifact_dir [file join $out artifacts]
set resume_after_synth [expr {$argc > 0 && [lindex $argv 0] eq "resume_after_synth"}]
set resume_after_ooc [expr {$argc > 0 && ([lindex $argv 0] eq "resume_after_ooc" || $resume_after_synth)}]
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
    set output [exec certutil.exe -hashfile [file nativename [file normalize $path]] SHA256]
    if {![regexp -nocase {([0-9a-f]{64})} $output -> hash]} {
        error "unable to parse SHA-256 for $path: $output"
    }
    return [string toupper $hash]
}

proc report_contains_zero {path check_name} {
    set fp [open $path r]
    set text [read $fp]
    close $fp
    return [regexp "checking ${check_name} \\(0\\)" $text]
}

open_project [file join $root laser_tx.xpr]
set_property top laser_tx_board_top [get_filesets sources_1]
# Keep automatic source management for BD/module-reference IP.  The
# top-synthesis pre-hook loads only the generated lower GT children owned by
# the XCI composite; no standalone generated HDL registration is added.
set_property source_mgmt_mode All [current_project]

# The checked-in XCI is the sole GT Wizard source.  Generated HDL is recreated
# under laser_tx.gen and no imported/reference-project GT source is accepted.
set wizard_xci [get_files -quiet */gtwizard_0.xci]
if {![llength $wizard_xci]} { error "gtwizard_0.xci not found" }
set generated_gt [file join $root laser_tx.gen sources_1 ip gtwizard_0 gtwizard_0.v]
set effective_gt [file join $root laser_tx.srcs sources_1 imports sources_1 ip gtwizard_0 gtwizard_0.v]
set generated_gt_lower [file join $root laser_tx.gen sources_1 ip gtwizard_0 gtwizard_0_gt.v]
set effective_gt_lower [file join $root laser_tx.srcs sources_1 imports sources_1 ip gtwizard_0 gtwizard_0_gt.v]
if {[file exists $generated_gt] && [file exists $effective_gt]} {
    set generated_text [read [open $generated_gt r]]
    set effective_text [read [open $effective_gt r]]
    if {[string first "gt0_gtnorthrefclk0_in" $effective_text] >= 0 &&
        [string first "gt0_gtnorthrefclk0_in" $generated_text] < 0} {
        error "GT XCI/generated HDL mismatch: effective source exposes gt0_gtnorthrefclk0_in but local XCI output does not; refusing to select an unverified source"
    }
}
# laser_gt_tx_profile0 is bound through gtwizard_0_adapter directly to the
# XCI-generated lower primitive wrapper (gtwizard_0_GT), not to the Wizard
# example top.  CPLLREFCLKSEL is therefore checked at that actual binding
# boundary; the example top may legitimately omit this optional port.
if {[file exists $generated_gt_lower] && [file exists $effective_gt_lower]} {
    set generated_lower_text [read [open $generated_gt_lower r]]
    set effective_lower_text [read [open $effective_gt_lower r]]
    if {[string first "cpllrefclksel_in" $effective_lower_text] >= 0 &&
        [string first "cpllrefclksel_in" $generated_lower_text] < 0} {
        error "GT XCI/generated HDL mismatch: lower primitive wrapper lost runtime CPLLREFCLKSEL"
    }
    if {[string first "gtnorthrefclk0_in" $effective_lower_text] >= 0 &&
        [string first "gtnorthrefclk0_in" $generated_lower_text] < 0} {
        error "GT XCI/generated HDL mismatch: lower primitive wrapper lost GTNORTHREFCLK0"
    }
}
# gtwizard_0_multi_gt.v is an XCI-managed example wrapper and is not on the
# production adapter path.  Its fixed example-design CPLL selection must not
# be used as an equivalence check for the adapter's direct gtwizard_0_GT port.
set_property IS_ENABLED true $wizard_xci
set wrapper_root [file join $root laser_tx.srcs sources_1 imports sources_1 ip gtwizard_0]
set wrapper_sources [concat \
    [glob -nocomplain [file join $wrapper_root *.v]] \
    [glob -nocomplain [file join $wrapper_root gtwizard_0 example_design *.v]]]
foreach source $wrapper_sources {
    set imported [get_files -quiet $source]
    if {[llength $imported]} {
        remove_files $imported
    }
}
generate_target all $wizard_xci

set bd_file [get_files -quiet */system.bd]
if {![llength $bd_file]} { error "system.bd not found" }
# A clean composite regeneration is the supported freshness mechanism for IPI
# children which Vivado does not expose as independent synth runs.
set bd_regeneration_start 0
if {!$resume_after_ooc} {
    set bd_regeneration_start [clock seconds]
    reset_target all $bd_file
    generate_target all $bd_file
}
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
    if {$ip_name eq "system_blk_mem_dyn_desc_0"} {
        # BD validation can re-propagate the legacy 2K default.  The
        # architectural descriptor window is 1K x 32 (4 KiB), so override the
        # managed child IP immediately before its OOC run is launched.
        set_property CONFIG.Write_Depth_A {1024} $ip
        if {[get_property CONFIG.Write_Depth_A $ip] ne "1024"} {
            error "descriptor RAM depth did not resolve to 1024 before OOC"
        }
    }
    set run_name ${ip_name}_synth_1
    if {[llength [get_runs -quiet $run_name]]} {
        catch {config_ip_cache -disable_for_ip $ip}
        lappend ooc_runs $run_name
    }
}

if {!$resume_after_ooc} {
    foreach run_name $ooc_runs { reset_run $run_name }
    launch_runs $ooc_runs -jobs 4
    foreach run_name $ooc_runs {
        wait_on_run $run_name
        require_complete $run_name
    }
} else {
    foreach run_name $ooc_runs { require_complete $run_name }
}

# For IPs with independent managed runs, require the generated composite DCP and
# run DCP to be byte-identical.  Other IPI children are clean-generated only by
# their parent BD; require their DCP to have been written by this invocation.
set hash_fp [open [file join $out ooc_dcp_freshness.tsv] w]
puts $hash_fp "ip\tprovenance\trun_dcp\tgenerated_dcp\trun_sha256\tgenerated_sha256\tmatch\tgenerated_mtime"
foreach ip_name $required_ips {
    set run_name ${ip_name}_synth_1
    # Vivado 2022.2 treats a module-reference IP as a BD-owned source after
    # Refresh Module Reference; it cannot have an independent create_ip_run.
    # Its generated XML/source is therefore freshness-checked through the
    # parent BD, while regular vendor IPs continue to require a managed DCP.
    if {$ip_name eq "system_laser_tx_core_0_0" &&
        ![llength [get_runs -quiet $run_name]]} {
        set module_xml [file join $root laser_tx.gen sources_1 bd system ip \
            system_laser_tx_core_0_0 system_laser_tx_core_0_0.xml]
        if {![file exists $module_xml] ||
            (!$resume_after_ooc && [file mtime $module_xml] < $bd_regeneration_start)} {
            error "module-reference output was not freshly generated: $module_xml"
        }
        puts $hash_fp [join [list $ip_name CLEAN_PARENT_BD_MODULE_REFERENCE "" \
            $module_xml NA NA 1 [file mtime $module_xml]] "\t"]
        continue
    }
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

# The module-reference OOC checkpoint must contain TX sequence V2 and none of
# the removed V1 scheduler state.
set core_run system_laser_tx_core_0_0_synth_1
set signature_patterns [dict create \
    append_metadata_stage *append_meta_valid_q* \
    append_next_plan_stage *next_append_plan_valid_q* \
    append_current_plan_stage *current_append_plan_valid_q* \
    pattern_mode_63_active *pattern_mode_63_active* \
    repeat_index_state *repeat_index_state* \
    phase_scheduler_state *phase_offset_reg* \
    eom_window *u_tx_eom_window_generator* \
    insert_after *insert_after* \
    tail_delay *tail_delay* \
    pattern_cursor *pattern_cursor* \
    legacy_len_active *u_pattern_tx_engine/len_active_reg*]
set signature_fp [open [file join $out ooc_rtl_signature.txt] w]
if {[llength [get_runs -quiet $core_run]]} {
    open_run $core_run
    dict for {name pattern} $signature_patterns {
        set count [llength [get_cells -quiet -hier $pattern]]
        set signature($name) $count
        puts $signature_fp "$name=$count"
    }
} else {
    # Module-reference output is owned by the BD after Refresh.  Preserve the
    # same signature gate using the checked-in RTL text when no independent
    # OOC run exists in Vivado's project metadata.
    set rtl_text ""
    foreach source_file [glob -nocomplain [file join $root laser_tx.srcs sources_1 new laser_tx_core *.v]] {
        set source_fp [open $source_file r]
        append rtl_text [read $source_fp]
        close $source_fp
    }
    dict for {name pattern} $signature_patterns {
        set literal [string trim $pattern *]
        set count [expr {[string first $literal $rtl_text] >= 0 ? 1 : 0}]
        set signature($name) $count
        puts $signature_fp "$name=$count (source_signature)"
    }
}
close $signature_fp
close_design
if {$signature(append_metadata_stage) == 0 ||
    $signature(append_next_plan_stage) == 0 ||
    $signature(append_current_plan_stage) == 0 ||
    $signature(pattern_mode_63_active) == 0 ||
    $signature(repeat_index_state) == 0 ||
    $signature(phase_scheduler_state) == 0 ||
    $signature(eom_window) == 0 ||
    $signature(insert_after) != 0 ||
    $signature(tail_delay) != 0 ||
    $signature(pattern_cursor) != 0 ||
    $signature(legacy_len_active) != 0} {
    error "TX sequence V2 OOC RTL signature mismatch"
}
reset_run impl_1
set synth_run [get_runs synth_1]
# The adapter instantiates gtwizard_0_GT (the XCI-generated lower wrapper),
# not the Wizard example top.  Load that parent-owned child set during the
# top synthesis run without adding duplicate project source entries.
set_property STEPS.SYNTH_DESIGN.TCL.PRE \
    [file join $root scripts gtwizard_0_synth_pre.tcl] $synth_run
# A release-candidate reproducibility build must not consume the prior top-level
# automatic incremental checkpoint recorded in the project.
set_property AUTO_INCREMENTAL_CHECKPOINT 0 $synth_run
set_property INCREMENTAL_CHECKPOINT "" $synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.INCREMENTAL_MODE off $synth_run
set impl_run [get_runs impl_1]
set_property strategy Performance_ExplorePostRoutePhysOpt $impl_run
set_property STEPS.OPT_DESIGN.TCL.PRE \
    [file join $root scripts gt_profile0_impl_pre.tcl] $impl_run
if {!$resume_after_synth} {
    reset_run synth_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    require_complete synth_1
} else {
    require_complete synth_1
}
# Keep the release-candidate QoR flow aligned with the timing-clean validation
# run.  This strategy performs the post-route physical-optimization step after
# routing and before the timing/DRC artifact gate below.
launch_runs impl_1 -to_step {phys_opt_design (Post-Route)} -jobs 4
wait_on_run impl_1
require_complete impl_1
open_run impl_1

set txusrclk [get_clocks -quiet GT_TXUSRCLK_RUNTIME_MAX]
set txusrclk2 [get_clocks -quiet GT_TXUSRCLK2_RUNTIME_MAX]
set eom_clk [get_clocks -quiet GT_EOM_CLK_RUNTIME_MAX]
if {![llength $txusrclk] || ![llength $txusrclk2] || ![llength $eom_clk]} {
    error "runtime maximum TX/EOM clock constraints are missing"
}
set txusrclk_period [get_property PERIOD $txusrclk]
set txusrclk2_period [get_property PERIOD $txusrclk2]
set eom_clk_period [get_property PERIOD $eom_clk]
if {abs($txusrclk_period - 3.103) > 0.001 ||
    abs($txusrclk2_period - 6.206) > 0.001 ||
    abs($eom_clk_period - 6.206) > 0.001} {
    error "runtime clock mismatch: TXUSRCLK=$txusrclk_period TXUSRCLK2=$txusrclk2_period EOM=$eom_clk_period"
}

report_timing_summary -delay_type min_max -max_paths 100 -report_unconstrained \
    -file [file join $out timing_summary.rpt]
report_timing -delay_type max -max_paths 50 -path_type full_clock_expanded \
    -file [file join $out setup_top50.rpt]
report_timing -delay_type min -max_paths 50 -path_type full_clock_expanded \
    -file [file join $out hold_top50.rpt]
report_clocks -file [file join $out clocks.rpt]
report_clock_interaction -delay_type min_max -file [file join $out clock_interaction.rpt]
report_cdc -details -file [file join $out cdc.rpt]
report_methodology -file [file join $out methodology.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_route_status -file [file join $out route_status.rpt]
report_drc -file [file join $out drc.rpt]
report_io -file [file join $out io.rpt]
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
puts $metrics_fp "eom_clk_period_ns=$eom_clk_period"
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
set xsa_path [file join $artifact_dir laser_tx_board_top_tx_sequence_v2.xsa]
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
puts "TX_SEQUENCE_V2_ARTIFACT_BUILD=PASS"
puts "BIT=$bit_path"
puts "LTX=$ltx_path"
puts "XSA=$xsa_path"
close_project
