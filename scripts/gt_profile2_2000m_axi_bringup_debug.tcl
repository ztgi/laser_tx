# Insert a stable AXI/FCLK-domain bring-up ILA for static 2000M Profile 2.
#
# This script runs on the synthesized design from the implementation pre-hook.
# It does not modify laser_tx_core functionality, GT Wizard parameters, GTX DRP
# or MMCM DRP.  It only changes debug instrumentation in the isolated 2000M
# implementation.

proc dbg_unique_list {items} {
    set result {}
    foreach item $items {
        if {[lsearch -exact $result $item] < 0} {
            lappend result $item
        }
    }
    return $result
}

proc dbg_match_score {net preferred_patterns} {
    set name [get_property NAME $net]
    set best 1000000
    set priority 0
    foreach pattern $preferred_patterns {
        if {[string match $pattern $name]} {
            set score [expr {$priority * 1000 + [string length $name]}]
            if {$score < $best} {
                set best $score
            }
        }
        incr priority
    }
    return $best
}

proc dbg_select_net_from_candidates {description candidates {preferred_patterns {}}} {
    set candidates [dbg_unique_list $candidates]
    if {[llength $candidates] == 0} {
        error "2000M AXI bring-up ILA insertion failed: no net found for $description."
    }
    if {[llength $candidates] == 1} {
        return [lindex $candidates 0]
    }

    set best_net ""
    set best_score 1000000
    foreach net $candidates {
        set score [dbg_match_score $net $preferred_patterns]
        if {$score < $best_score} {
            set best_score $score
            set best_net $net
        }
    }
    if {$best_net ne "" && $best_score < 1000000} {
        puts "INFO: selected net for $description from candidates '$candidates': $best_net"
        return $best_net
    }

    set sorted_candidates [lsort $candidates]
    set chosen [lindex $sorted_candidates 0]
    puts "WARNING: multiple candidate nets for $description; selected first sorted net '$chosen' from '$sorted_candidates'."
    return $chosen
}

proc dbg_require_one_net {description patterns {preferred_patterns {}}} {
    set candidates {}
    foreach pattern $patterns {
        foreach net [get_nets -hier -quiet $pattern] {
            lappend candidates $net
        }
    }
    if {[llength $candidates] == 0} {
        error "2000M AXI bring-up ILA insertion failed: no net found for $description using patterns '$patterns'."
    }
    return [dbg_select_net_from_candidates $description $candidates $preferred_patterns]
}

proc dbg_require_bus_nets {description base msb lsb} {
    set nets {}
    set leaf [file tail $base]
    if {$msb >= $lsb} {
        for {set i $lsb} {$i <= $msb} {incr i} {
            set bit_leaf [format {%s[%d]} $leaf $i]
            set bit_candidates {}
            foreach net [get_nets -hier -quiet "*$leaf*"] {
                if {[file tail [get_property NAME $net]] eq $bit_leaf} {
                    lappend bit_candidates $net
                }
            }
            lappend nets [dbg_select_net_from_candidates "$description\[$i\]" $bit_candidates [list "$base/$bit_leaf" "*$base/$bit_leaf" "*$bit_leaf"]]
        }
    } else {
        for {set i $lsb} {$i >= $msb} {incr i -1} {
            set bit_leaf [format {%s[%d]} $leaf $i]
            set bit_candidates {}
            foreach net [get_nets -hier -quiet "*$leaf*"] {
                if {[file tail [get_property NAME $net]] eq $bit_leaf} {
                    lappend bit_candidates $net
                }
            }
            lappend nets [dbg_select_net_from_candidates "$description\[$i\]" $bit_candidates [list "$base/$bit_leaf" "*$base/$bit_leaf" "*$bit_leaf"]]
        }
    }
    return $nets
}

proc dbg_connect_probe {core index description nets} {
    puts "INFO: connect $core/probe$index <= $description : $nets"
    connect_debug_port $core/probe$index $nets
}

proc dbg_ensure_probe_port {core index width} {
    while {[llength [get_debug_ports -quiet $core/probe$index]] == 0} {
        create_debug_port $core probe
    }
    set port [get_debug_ports $core/probe$index]
    set_property port_width $width $port
}

set axi_clk_net [dbg_require_one_net "AXI/FCLK debug clock" \
    [list "gt_ctrl_clk" "*gt_ctrl_clk"] \
    [list "gt_ctrl_clk" "u_system_wrapper/system_i/gt_ctrl_clk" "u_system_wrapper/gt_ctrl_clk" "*gt_ctrl_clk"]]

if {[llength [get_debug_cores -quiet dbg_hub]] == 0} {
    create_debug_core dbg_hub dbg_hub
}
set dbg_hub_core [get_debug_cores dbg_hub]
catch {disconnect_debug_port dbg_hub/clk}
connect_debug_port dbg_hub/clk $axi_clk_net
set_property C_CLK_INPUT_FREQ_HZ 50000000 $dbg_hub_core
puts "INFO: dbg_hub/clk forced to AXI/FCLK net: $axi_clk_net"

set bringup_core_name ila_2000m_bringup_axi
if {[llength [get_debug_cores -quiet $bringup_core_name]] == 0} {
    create_debug_core $bringup_core_name ila
}
set bringup_core [get_debug_cores $bringup_core_name]
set_property C_DATA_DEPTH 2048 $bringup_core
set_property ALL_PROBE_SAME_MU true $bringup_core
set_property ALL_PROBE_SAME_MU_CNT 1 $bringup_core
connect_debug_port $bringup_core/clk $axi_clk_net
puts "INFO: $bringup_core_name/clk connected to AXI/FCLK net: $axi_clk_net"

dbg_ensure_probe_port $bringup_core 0 1
dbg_ensure_probe_port $bringup_core 1 1
dbg_ensure_probe_port $bringup_core 2 1
dbg_ensure_probe_port $bringup_core 3 1
dbg_ensure_probe_port $bringup_core 4 1
dbg_ensure_probe_port $bringup_core 5 1
dbg_ensure_probe_port $bringup_core 6 32
dbg_ensure_probe_port $bringup_core 7 32
dbg_ensure_probe_port $bringup_core 8 1
dbg_ensure_probe_port $bringup_core 9 1
dbg_ensure_probe_port $bringup_core 10 1
dbg_ensure_probe_port $bringup_core 11 1
dbg_ensure_probe_port $bringup_core 12 1
dbg_ensure_probe_port $bringup_core 13 1
dbg_ensure_probe_port $bringup_core 14 1
dbg_ensure_probe_port $bringup_core 15 1
dbg_ensure_probe_port $bringup_core 16 1
dbg_ensure_probe_port $bringup_core 17 1

dbg_connect_probe $bringup_core 0  "cplllock_axi" \
    [dbg_require_one_net "cplllock_axi" [list "*cplllock_sync*"] [list "u_laser_gt_tx_profile2_2000m/cplllock_sync" "*u_laser_gt_tx_profile2_2000m/cplllock_sync"]]
dbg_connect_probe $bringup_core 1  "txresetdone_axi" \
    [dbg_require_one_net "txresetdone_axi" [list "*txresetdone_sync*"] [list "u_laser_gt_tx_profile2_2000m/txresetdone_sync" "*u_laser_gt_tx_profile2_2000m/txresetdone_sync"]]
dbg_connect_probe $bringup_core 2  "tx_mmcm_locked_axi" \
    [dbg_require_one_net "tx_mmcm_locked_axi" [list "*tx_mmcm_locked_sync*"] [list "u_laser_gt_tx_profile2_2000m/tx_mmcm_locked_sync" "*u_laser_gt_tx_profile2_2000m/tx_mmcm_locked_sync"]]
dbg_connect_probe $bringup_core 3  "gt_ready_axi" \
    [dbg_require_one_net "gt_ready_axi" [list "*gt_ready_ctrl*"] [list "u_laser_gt_tx_profile2_2000m/gt_ready_ctrl" "*u_laser_gt_tx_profile2_2000m/gt_ready_ctrl"]]
dbg_connect_probe $bringup_core 4  "txusrclk2_alive_axi" \
    [dbg_require_one_net "txusrclk2_alive_axi" [list "*txusrclk2_alive_axi*"] [list "u_laser_gt_tx_profile2_2000m/txusrclk2_alive_axi" "*u_laser_gt_tx_profile2_2000m/txusrclk2_alive_axi"]]
dbg_connect_probe $bringup_core 5  "txusrclk2_toggle_axi" \
    [dbg_require_one_net "txusrclk2_toggle_axi" [list "*txusrclk2_toggle_axi*"] [list "u_laser_gt_tx_profile2_2000m/txusrclk2_toggle_axi" "*u_laser_gt_tx_profile2_2000m/txusrclk2_toggle_axi"]]
dbg_connect_probe $bringup_core 6  "txusrclk2_freq_counter_axi[31:0]" \
    [dbg_require_bus_nets "txusrclk2_freq_counter_axi" "u_laser_gt_tx_profile2_2000m/txusrclk2_freq_counter_axi" 31 0]
dbg_connect_probe $bringup_core 7  "gpio_ctrl_axi[31:0]" \
    [dbg_require_bus_nets "gpio_ctrl_axi" "u_system_wrapper/system_i/axi_gpio_0_gpio_io_o" 31 0]
dbg_connect_probe $bringup_core 8  "gpio_apply_toggle_axi" \
    [dbg_require_bus_nets "gpio_apply_toggle_axi" "u_system_wrapper/system_i/axi_gpio_0_gpio_io_o" 8 8]
dbg_connect_probe $bringup_core 9  "gpio_enable_axi" \
    [dbg_require_bus_nets "gpio_enable_axi" "u_system_wrapper/system_i/axi_gpio_0_gpio_io_o" 9 9]
dbg_connect_probe $bringup_core 10 "gpio_soft_reset_axi" \
    [dbg_require_bus_nets "gpio_soft_reset_axi" "u_system_wrapper/system_i/axi_gpio_0_gpio_io_o" 10 10]
dbg_connect_probe $bringup_core 11 "cfg_valid_axi" \
    [dbg_require_one_net "cfg_valid_axi" [list "*dbg_axi_cfg_valid*"] [list "u_system_wrapper/system_i/laser_tx_core_0/inst/dbg_axi_cfg_valid" "*laser_tx_core_0/inst/dbg_axi_cfg_valid"]]
dbg_connect_probe $bringup_core 12 "cfg_error_axi" \
    [dbg_require_one_net "cfg_error_axi" [list "*dbg_axi_cfg_error*"] [list "u_system_wrapper/system_i/laser_tx_core_0/inst/dbg_axi_cfg_error" "*laser_tx_core_0/inst/dbg_axi_cfg_error"]]
dbg_connect_probe $bringup_core 13 "busy_tx_axi" \
    [dbg_require_one_net "busy_tx_axi" [list "*dbg_axi_busy_tx*"] [list "u_system_wrapper/system_i/laser_tx_core_0/inst/dbg_axi_busy_tx" "*laser_tx_core_0/inst/dbg_axi_busy_tx"]]
dbg_connect_probe $bringup_core 14 "done_tx_axi" \
    [dbg_require_one_net "done_tx_axi" [list "*dbg_axi_done_tx*"] [list "u_system_wrapper/system_i/laser_tx_core_0/inst/dbg_axi_done_tx" "*laser_tx_core_0/inst/dbg_axi_done_tx"]]
dbg_connect_probe $bringup_core 15 "cfg_update_seen_axi" \
    [dbg_require_one_net "cfg_update_seen_axi" [list "*dbg_axi_cfg_update_seen*"] [list "u_system_wrapper/system_i/laser_tx_core_0/inst/dbg_axi_cfg_update_seen" "*laser_tx_core_0/inst/dbg_axi_cfg_update_seen"]]
dbg_connect_probe $bringup_core 16 "engine_start_seen_axi" \
    [dbg_require_one_net "engine_start_seen_axi" [list "*dbg_axi_engine_start_seen*"] [list "u_system_wrapper/system_i/laser_tx_core_0/inst/dbg_axi_engine_start_seen" "*laser_tx_core_0/inst/dbg_axi_engine_start_seen"]]
dbg_connect_probe $bringup_core 17 "pattern_valid_axi" \
    [dbg_require_one_net "pattern_valid_axi" [list "*dbg_axi_pattern_valid*"] [list "u_system_wrapper/system_i/laser_tx_core_0/inst/dbg_axi_pattern_valid" "*laser_tx_core_0/inst/dbg_axi_pattern_valid"]]

puts "INFO: Inserted $bringup_core_name with stable AXI/FCLK clock."

