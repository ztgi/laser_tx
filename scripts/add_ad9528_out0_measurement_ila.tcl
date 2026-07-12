# Insert a dedicated debug-only ILA for the AD9528 OUT0 ODIV2 frequency meter.
# This runs in the implementation pre-opt hook after synthesis/link. It does
# not modify the block design or the existing 50-probe AXI/FCLK ILA.

proc ad9528_measure_require_scalar {name} {
    # Prefer the exact top-level net.  With -hier Vivado also returns every
    # hierarchical segment of the same routed signal, which is not an
    # ambiguity for this purpose but cannot be passed as an ILA clock list.
    set exact [get_nets -quiet $name]
    if {[llength $exact] == 1} {
        return $exact
    }

    set candidates {}
    foreach net [get_nets -hier -quiet *$name*] {
        set net_name [get_property NAME $net]
        if {$net_name eq $name || [file tail $net_name] eq $name} {
            lappend candidates $net
        }
    }
    if {[llength $candidates] != 1} {
        error "AD9528 measurement ILA: expected one net for $name, got '$candidates'."
    }
    return $candidates
}

proc ad9528_measure_require_bus {base width} {
    set nets {}
    for {set i 0} {$i < $width} {incr i} {
        set leaf [format {%s[%d]} $base $i]
        set candidates {}
        foreach net [get_nets -hier -quiet *$base*] {
            if {[file tail [get_property NAME $net]] eq $leaf} {
                lappend candidates $net
            }
        }
        if {[llength $candidates] != 1} {
            error "AD9528 measurement ILA: expected one net for $leaf, got '$candidates'."
        }
        lappend nets [lindex $candidates 0]
    }
    return $nets
}

set core_name ila_ad9528_out0_measure
if {[llength [get_debug_cores -quiet $core_name]] != 0} {
    error "AD9528 measurement ILA: debug core $core_name already exists in pre-hook netlist."
}

create_debug_core $core_name ila
set core [get_debug_cores $core_name]
set_property C_DATA_DEPTH 2048 $core
set_property C_TRIGIN_EN false $core
set_property C_TRIGOUT_EN false $core

while {[llength [get_debug_ports -quiet $core/probe4]] == 0} {
    create_debug_port $core probe
}
set_property port_width 1  [get_debug_ports $core/probe0]
set_property port_width 1  [get_debug_ports $core/probe1]
set_property port_width 32 [get_debug_ports $core/probe2]
set_property port_width 1  [get_debug_ports $core/probe3]
set_property port_width 1  [get_debug_ports $core/probe4]

set clk_net [ad9528_measure_require_scalar gt_ctrl_clk]
connect_debug_port $core/clk $clk_net
connect_debug_port $core/probe0 [ad9528_measure_require_scalar ad9528_odiv2_alive_axi]
connect_debug_port $core/probe1 [ad9528_measure_require_scalar ad9528_odiv2_toggle_axi]
connect_debug_port $core/probe2 [ad9528_measure_require_bus ad9528_odiv2_count_axi 32]
connect_debug_port $core/probe3 [ad9528_measure_require_scalar ad9528_odiv2_in_range_axi]
connect_debug_port $core/probe4 [ad9528_measure_require_scalar ad9528_measure_valid_axi]

puts "INFO: Added $core_name on gt_ctrl_clk with probes alive/toggle/count/in_range/valid."
