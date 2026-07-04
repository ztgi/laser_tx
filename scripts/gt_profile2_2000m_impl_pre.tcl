# Implementation pre-opt hook for static GT Profile 2 2000M validation.
# This verifies the compile-time 2000M TX user-clock topology and declares the
# AXI/TX CDC relationship.  It does not implement runtime rate switching.

proc require_one_clock {description objects} {
    set clocks [get_clocks -quiet -of_objects $objects]
    if {[llength $clocks] != 1} {
        error "GT Profile 2 2000M clock check failed: expected one clock for $description, got '$clocks'."
    }
    return $clocks
}

proc require_period {description clock expected_period_ns} {
    set period [get_property PERIOD $clock]
    set delta [expr {abs($period - $expected_period_ns)}]
    if {$delta > 0.010} {
        error "GT Profile 2 2000M clock check failed: $description period is $period ns, expected $expected_period_ns ns."
    }
    puts "INFO: $description period verified: $period ns"
}

proc print_axi_clock_debug {gt_ctrl_clk_nets fclk_pins} {
    puts "INFO: Available clocks:"
    foreach c [get_clocks -quiet] {
        puts "INFO:   clock=$c period=[get_property PERIOD $c]"
    }
    puts "INFO: gt_ctrl_clk nets: $gt_ctrl_clk_nets"
    puts "INFO: FCLK_CLK0 pins: $fclk_pins"
    if {[llength $gt_ctrl_clk_nets] > 0} {
        puts "INFO: clocks of gt_ctrl_clk nets: [get_clocks -quiet -of_objects $gt_ctrl_clk_nets]"
    }
    if {[llength $fclk_pins] > 0} {
        puts "INFO: clocks of FCLK_CLK0 pins: [get_clocks -quiet -of_objects $fclk_pins]"
    }
}

proc resolve_axi_fclk_clock {} {
    set candidates [list]

    set by_name [get_clocks -quiet clk_fpga_0]
    if {[llength $by_name] > 0} {
        set candidates [concat $candidates $by_name]
    }

    set gt_ctrl_clk_nets [get_nets -quiet -hier *gt_ctrl_clk*]
    if {[llength $gt_ctrl_clk_nets] > 0} {
        set candidates [concat $candidates [get_clocks -quiet -of_objects $gt_ctrl_clk_nets]]
    }

    set fclk_pins [get_pins -quiet -hier *FCLK_CLK0]
    set fclk_source_pins [list]
    foreach p $fclk_pins {
        if {[regexp {/inst/FCLK_CLK0$} $p]} {
            lappend fclk_source_pins $p
        }
    }
    if {[llength $fclk_source_pins] > 0} {
        set candidates [concat $candidates [get_clocks -quiet -of_objects $fclk_source_pins]]
    } elseif {[llength $fclk_pins] > 0} {
        set candidates [concat $candidates [get_clocks -quiet -of_objects $fclk_pins]]
    }

    set name_matches [get_clocks -quiet -filter {NAME =~ "*clk_fpga_0*" || NAME =~ "*FCLK_CLK0*"}]
    if {[llength $name_matches] > 0} {
        set candidates [concat $candidates $name_matches]
    }

    set candidates [lsort -unique $candidates]

    if {[llength $candidates] == 0} {
        set create_clock_pin ""
        if {[llength $fclk_source_pins] == 1} {
            set create_clock_pin $fclk_source_pins
        } elseif {[llength $fclk_pins] == 1} {
            set create_clock_pin $fclk_pins
        }
        if {$create_clock_pin ne "" && [llength $by_name] == 0} {
            puts "WARNING: No AXI/FCLK clock object found. Creating controlled fallback clock clk_fpga_0 on $create_clock_pin with 20.000 ns period."
            create_clock -name clk_fpga_0 -period 20.000 $create_clock_pin
            set candidates [lsort -unique [concat \
                [get_clocks -quiet clk_fpga_0] \
                [get_clocks -quiet -of_objects $create_clock_pin] \
                [get_clocks -quiet -of_objects $gt_ctrl_clk_nets]]]
        }
    }

    if {[llength $candidates] != 1} {
        print_axi_clock_debug $gt_ctrl_clk_nets $fclk_pins
        error "GT Profile 2 2000M CDC constraint failed: expected one AXI/FCLK clock candidate; got '$candidates'."
    }

    puts "INFO: GT Profile 2 2000M AXI/FCLK clock resolved to '$candidates'."
    return $candidates
}

set axi_clock [resolve_axi_fclk_clock]

set txoutclk_pin [get_pins -quiet \
    u_laser_gt_tx_profile2_2000m/u_gtwizard_0/inst/gtwizard_0_i/gt0_gtwizard_0_i/gtxe2_i/TXOUTCLK]
set txusrclk_pin [get_pins -quiet \
    u_laser_gt_tx_profile2_2000m/u_tx_usrclk_profile2_2000m/u_txusrclk_bufg/O]
set txusrclk2_pin [get_pins -quiet \
    u_laser_gt_tx_profile2_2000m/u_tx_usrclk_profile2_2000m/u_txusrclk2_bufg/O]

set txoutclk_clock [require_one_clock "GT TXOUTCLK" $txoutclk_pin]
set txusrclk_clock [require_one_clock "GT TXUSRCLK" $txusrclk_pin]
set txusrclk2_clock [require_one_clock "GT TXUSRCLK2" $txusrclk2_pin]

require_period "GT TXOUTCLK" $txoutclk_clock 16.000
require_period "GT TXUSRCLK" $txusrclk_clock 16.000
require_period "GT TXUSRCLK2" $txusrclk2_clock 32.000

set_clock_groups -asynchronous \
    -group $axi_clock \
    -group [list $txoutclk_clock $txusrclk_clock $txusrclk2_clock]
puts "INFO: Applied asynchronous clock groups: $axi_clock <-> [list $txoutclk_clock $txusrclk_clock $txusrclk2_clock]"

set impl_pre_dir [file dirname [file normalize [info script]]]
source [file join $impl_pre_dir gt_profile2_2000m_axi_bringup_debug.tcl]

