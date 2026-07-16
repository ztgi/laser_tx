# Read-only structural audit for iteration-6 C-class output-word paths.
# Opens only the archived routed checkpoint and writes reports under reports/.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set dcp [file join $root reports ad9528_gt_rate_planner \
    timing_iteration6_parallel_index iteration6_parallel_index_routed.dcp]
set out [file join $root reports ad9528_gt_rate_planner \
    timing_iteration6_c_path_audit]
file mkdir $out

open_checkpoint $dcp

set txdata_d [get_pins -quiet -hier -regexp \
    {.*u_pattern_tx_engine/txdata_reg\[[0-9]+\]/D$}]
if {[llength $txdata_d] == 0} {
    error "No pattern_tx_engine txdata register endpoints found"
}

report_timing -delay_type max -to $txdata_d -max_paths 50 -nworst 1 \
    -path_type full_clock_expanded \
    -file [file join $out c_class_setup_top50.rpt]
report_timing -delay_type max -to $txdata_d -max_paths 50 -nworst 1 \
    -path_type full_clock_expanded -input_pins \
    -file [file join $out c_class_primitive_full_top50.rpt]

set c_paths [get_timing_paths -quiet -delay_type max -to $txdata_d \
    -max_paths 50 -nworst 1]
proc timing_path_property_or_na {path property_name} {
    if {[lsearch -exact [list_property $path] $property_name] >= 0} {
        return [get_property $property_name $path]
    }
    return "NA"
}
set fd [open [file join $out c_class_path_properties.tsv] w]
puts $fd "rank\tslack_ns\tdatapath_delay_ns\tlogic_delay_ns\troute_delay_ns\tlevels\tstartpoint\tendpoint"
set rank 0
foreach path $c_paths {
    incr rank
    puts $fd [join [list \
        $rank \
        [get_property SLACK $path] \
        [timing_path_property_or_na $path DATAPATH_DELAY] \
        [timing_path_property_or_na $path LOGIC_DELAY] \
        [timing_path_property_or_na $path ROUTE_DELAY] \
        [timing_path_property_or_na $path LOGIC_LEVELS] \
        [timing_path_property_or_na $path STARTPOINT_PIN] \
        [timing_path_property_or_na $path ENDPOINT_PIN]] "\t"]
}
close $fd

proc dump_net_group {out_file nets} {
    set fd [open $out_file w]
    puts $fd "net\tflat_pin_count\tdriver_pin\tdriver_cell\tdriver_ref\tdriver_loc\tload_pin\tload_cell\tload_ref\tload_loc\tis_ila_load"
    foreach net $nets {
        set pins [get_pins -quiet -of_objects $net]
        set drivers [filter $pins {DIRECTION == OUT}]
        set loads [filter $pins {DIRECTION == IN}]
        if {[llength $drivers] == 0} { set drivers [list ""] }
        foreach driver $drivers {
            set driver_cell ""
            set driver_ref ""
            set driver_loc ""
            if {$driver ne ""} {
                set dc [get_cells -quiet -of_objects $driver]
                set driver_cell $dc
                set driver_ref [get_property -quiet REF_NAME $dc]
                set driver_loc [get_property -quiet LOC $dc]
            }
            foreach load $loads {
                set lc [get_cells -quiet -of_objects $load]
                set load_name [get_property -quiet NAME $lc]
                set is_ila [expr {[string match "*ila*" [string tolower $load_name]] ? 1 : 0}]
                puts $fd [join [list \
                    [get_property NAME $net] \
                    [llength $pins] \
                    $driver $driver_cell $driver_ref $driver_loc \
                    $load $lc \
                    [get_property -quiet REF_NAME $lc] \
                    [get_property -quiet LOC $lc] \
                    $is_ila] "\t"]
            }
        }
    }
    close $fd
}

set p0_nets [get_nets -quiet -hier -regexp \
    {.*u_pattern_tx_engine/p_0_in\[[56]\]$}]
dump_net_group [file join $out p_0_in_5_6_driver_loads.tsv] $p0_nets

set len_nets [get_nets -quiet -hier -regexp \
    {.*u_pattern_tx_engine/len_active.*}]
set phase_nets [get_nets -quiet -hier -regexp \
    {.*u_pattern_tx_engine/phase_offset.*}]
set index_nets [get_nets -quiet -hier -regexp \
    {.*u_pattern_tx_engine/pattern_index.*}]

set fd [open [file join $out selected_net_fanout.tsv] w]
puts $fd "group\tnet\tflat_pin_count\tila_load_count"
foreach group [list len_active phase_offset pattern_index p_0_in] \
              nets [list $len_nets $phase_nets $index_nets $p0_nets] {
    foreach net $nets {
        set pins [get_pins -quiet -of_objects $net]
        set ila_count 0
        foreach pin [filter $pins {DIRECTION == IN}] {
            set cell_name [get_property -quiet NAME [get_cells -quiet -of_objects $pin]]
            if {[string match "*ila*" [string tolower $cell_name]]} {
                incr ila_count
            }
        }
        puts $fd [join [list $group [get_property NAME $net] \
            [llength $pins] $ila_count] "\t"]
    }
}
close $fd

report_high_fanout_nets -timing -load_types -max_nets 500 \
    -file [file join $out high_fanout_top500.rpt]
report_design_analysis -congestion \
    -file [file join $out congestion.rpt]

set fd [open [file join $out audit_summary.txt] w]
puts $fd "source_dcp=$dcp"
puts $fd "txdata_endpoints=[llength $txdata_d]"
puts $fd "c_paths=[llength $c_paths]"
puts $fd "p_0_in_5_6_nets=[llength $p0_nets]"
puts $fd "len_active_nets=[llength $len_nets]"
puts $fd "phase_offset_nets=[llength $phase_nets]"
puts $fd "pattern_index_nets=[llength $index_nets]"
puts $fd "txusrclk_period_ns=[get_property PERIOD [get_clocks GT_TXUSRCLK_RUNTIME_MAX]]"
puts $fd "txusrclk2_period_ns=[get_property PERIOD [get_clocks GT_TXUSRCLK2_RUNTIME_MAX]]"
close $fd

close_design
puts "ITERATION6_C_PATH_AUDIT_COMPLETE"
