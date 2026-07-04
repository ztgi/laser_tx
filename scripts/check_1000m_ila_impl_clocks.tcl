# 1000M Profile1 implemented-design ILA clock connectivity check.
# This script does not change the implemented design.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize [file join $script_dir ".."]]
set project    [file normalize [file join $repo_dir "reports" "gt_profile1_1000m_static" "vivado_project" "laser_tx_profile1_1000m.xpr"]]
set out_dir    [file normalize [file join $repo_dir "reports" "gt_profile1_1000m_static" "ila_debug_check"]]
file mkdir $out_dir
set rpt_path   [file normalize [file join $out_dir "check_1000m_ila_impl_clocks.rpt"]]

set fh [open $rpt_path "w"]
proc rpt {msg} {
    global fh
    puts $msg
    puts $fh $msg
    flush $fh
}

proc one_or_none {objects} {
    if {[llength $objects] == 0} { return "<none>" }
    return [lindex $objects 0]
}

proc safe_prop {obj prop} {
    if {$obj eq "<none>"} { return "<none>" }
    if {[catch {set value [get_property $prop $obj]} err]} {
        return "<property $prop unavailable: $err>"
    }
    if {$value eq ""} { return "<empty>" }
    return $value
}

proc clock_info_for_pin {pin} {
    set clocks [get_clocks -quiet -of_objects $pin]
    if {[llength $clocks] == 0} {
        set net [one_or_none [get_nets -quiet -of_objects $pin]]
        if {$net ne "<none>"} {
            set clocks [get_clocks -quiet -of_objects $net]
        }
    }
    if {[llength $clocks] == 0} {
        return "<no_clock>"
    }
    set items {}
    foreach clk $clocks {
        lappend items "[get_property NAME $clk] period=[get_property PERIOD $clk]ns"
    }
    return [join $items "; "]
}

proc report_ila_clock {cell_name friendly_name expected_domain risk_note} {
    set cell [get_cells -quiet $cell_name]
    if {[llength $cell] == 0} {
        set cell [get_cells -hier -quiet $cell_name]
    }
    if {[llength $cell] == 0} {
        rpt "| $friendly_name | $cell_name | <not found> | <not found> | $expected_domain | not found |"
        return
    }
    set cell [lindex $cell 0]
    set clk_pin [one_or_none [get_pins -quiet "$cell/clk"]]
    if {$clk_pin eq "<none>"} {
        set clk_pin [one_or_none [get_pins -quiet "$cell/inst/clk"]]
    }
    set net [one_or_none [get_nets -quiet -of_objects $clk_pin]]
    set driver [one_or_none [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]]
    set clk_info [clock_info_for_pin $clk_pin]
    rpt "| $friendly_name | $cell | net=$net; driver=$driver | $clk_info | $expected_domain | $risk_note |"
}

if {![file exists $project]} {
    rpt "ERROR: project not found: $project"
    close $fh
    exit 1
}

open_project $project
open_run impl_1

rpt "# 1000M Profile1 implemented-design ILA clock connectivity"
rpt ""
rpt "Project: $project"
rpt "Report:  $rpt_path"
rpt ""
rpt "## Clock summary"
foreach name {clk_fpga_0 clkout0_txusrclk2 clkout1_txusrclk} {
    set clk [get_clocks -quiet $name]
    if {[llength $clk]} {
        rpt "- $name: period=[get_property PERIOD $clk] ns"
    } else {
        rpt "- $name: <not found>"
    }
}
set txout_clk [get_clocks -quiet *TXOUTCLK]
foreach clk $txout_clk {
    rpt "- [get_property NAME $clk]: period=[get_property PERIOD $clk] ns"
}
rpt ""
rpt "## ILA clock table"
rpt "| ILA | CELL_NAME | clk source | clock frequency | expected domain | risk |"
rpt "| --- | --- | --- | --- | --- | --- |"
report_ila_clock "u_system_wrapper/system_i/ila_laser_axi_cfg" "ila_laser_axi_cfg" "axi_clk / PS FCLK" "low: PS FCLK should be free-running after PS init"
report_ila_clock "u_system_wrapper/system_i/ila_laser_tx" "ila_laser_tx" "txusrclk2" "high: depends on GT TXOUTCLK and TX MMCM lock"
report_ila_clock "u_laser_gt_tx_profile1_1000m/u_ila_gt_profile1_1000m" "ila_gt_profile1_1000m" "txusrclk2" "high: depends on GT TXOUTCLK and TX MMCM lock"

rpt ""
rpt "## dbg_hub clock evidence"
set dbg_pins [get_pins -hier -quiet -filter {NAME =~ dbg_hub*/*clk || NAME =~ dbg_hub*/*/clk}]
set dbg_count 0
foreach p $dbg_pins {
    incr dbg_count
    if {$dbg_count > 40} {
        rpt "- ... truncated after 40 dbg_hub clock-like pins ..."
        break
    }
    set net [one_or_none [get_nets -quiet -of_objects $p]]
    rpt "- $p: net=$net; clocks=[clock_info_for_pin $p]"
}
set dbg_cells [get_cells -hier -quiet -filter {NAME =~ dbg_hub*}]
rpt "dbg_hub cells: [llength $dbg_cells]"

close $fh
puts "Wrote $rpt_path"
close_project
exit
