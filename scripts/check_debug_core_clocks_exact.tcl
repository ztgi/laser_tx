open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
open_run impl_1

set out D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/debug_core_clock_exact_check.rpt
set fh [open $out w]
proc rpt {msg} {
    global fh
    puts $msg
    puts $fh $msg
}

rpt "=== Vivado report_debug_core limitation ==="
rpt "Vivado 2022.2 report_debug_core syntax does not accept a debug core object argument."
rpt "Use report_debug_core -full_path for the full report, then query each debug core by Tcl properties and netlist pins."
report_debug_core -full_path -file D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/debug_core_probe_list_full_path.rpt

rpt ""
rpt "=== DEBUG CORES ==="
foreach c [get_debug_cores -quiet] {
    rpt "DEBUG CORE = $c"
}

rpt ""
rpt "=== DEBUG CORE REPORT CLOCK SUMMARY ==="
set full_report [report_debug_core -full_path -return_string]
foreach line [split $full_report "\n"] {
    if {[regexp {dbg_hub:|ila_laser_axi_cfg:|ila_laser_tx:|C_CLK_INPUT_FREQ_HZ|\| clk[ ]+\| input} $line]} {
        rpt $line
    }
}

rpt ""
rpt "=== IMPLEMENTED NETLIST PIN/NET CLOCK CHECK ==="
set checks [list \
    [list "dbg_hub clock-like pins" {NAME =~ "*dbg_hub*clk*"}] \
    [list "ila_laser_axi_cfg clock-like pins" {NAME =~ "*ila_laser_axi_cfg*clk*"}] \
    [list "ila_laser_tx clock-like pins" {NAME =~ "*ila_laser_tx*clk*"}] \
]

foreach item $checks {
    set label [lindex $item 0]
    set filter_expr [lindex $item 1]
    set pins [get_pins -hier -quiet -filter $filter_expr]
    rpt "CHECK $label FILTER={$filter_expr} PIN_COUNT=[llength $pins]"
    set shown 0
    foreach p $pins {
        if {$shown >= 80} {
            rpt "  ... truncated after 80 pins ..."
            break
        }
        set nets [get_nets -quiet -of_objects $p]
        rpt "  PIN=$p"
        rpt "  NETS=$nets"
        foreach n $nets {
            rpt "    NET_NAME=[get_property NAME $n]"
            rpt "    CLOCKS=[get_clocks -quiet -of_objects $n]"
            rpt "    DRIVER_PINS=[get_pins -quiet -of_objects $n -filter {DIRECTION == OUT}]"
        }
        incr shown
    }
}

rpt ""
rpt "=== CLOCK NET NAME SEARCH ==="
foreach netpat {gt_ctrl_clk *gt_ctrl_clk* gt_txusrclk2 *txusrclk2*} {
    set nets [get_nets -hier -quiet $netpat]
    rpt "NETPAT=$netpat COUNT=[llength $nets]"
    set shown 0
    foreach n $nets {
        if {$shown < 30} {
            rpt "  NET=$n CLOCKS=[get_clocks -quiet -of_objects $n]"
        }
        incr shown
    }
}

close $fh
close_project
