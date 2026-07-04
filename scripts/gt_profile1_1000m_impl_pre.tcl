# Implementation pre-opt hook for static GT Profile 1 1000M validation.
# This verifies the compile-time 1000M TX user-clock topology and declares the
# AXI/TX CDC relationship.  It does not implement runtime rate switching.

proc require_one_clock {description objects} {
    set clocks [get_clocks -quiet -of_objects $objects]
    if {[llength $clocks] != 1} {
        error "GT Profile 1 1000M clock check failed: expected one clock for $description, got '$clocks'."
    }
    return $clocks
}

proc require_period {description clock expected_period_ns} {
    set period [get_property PERIOD $clock]
    set delta [expr {abs($period - $expected_period_ns)}]
    if {$delta > 0.010} {
        error "GT Profile 1 1000M clock check failed: $description period is $period ns, expected $expected_period_ns ns."
    }
    puts "INFO: $description period verified: $period ns"
}

set axi_clock [get_clocks -quiet clk_fpga_0]
if {[llength $axi_clock] != 1} {
    error "GT Profile 1 1000M CDC constraint failed: expected one clk_fpga_0 clock; got '$axi_clock'."
}

set txoutclk_pin [get_pins -quiet \
    u_laser_gt_tx_profile1_1000m/u_gtwizard_0/inst/gtwizard_0_i/gt0_gtwizard_0_i/gtxe2_i/TXOUTCLK]
set txusrclk_pin [get_pins -quiet \
    u_laser_gt_tx_profile1_1000m/u_tx_usrclk_profile1_1000m/u_txusrclk_bufg/O]
set txusrclk2_pin [get_pins -quiet \
    u_laser_gt_tx_profile1_1000m/u_tx_usrclk_profile1_1000m/u_txusrclk2_bufg/O]

set txoutclk_clock [require_one_clock "GT TXOUTCLK" $txoutclk_pin]
set txusrclk_clock [require_one_clock "GT TXUSRCLK" $txusrclk_pin]
set txusrclk2_clock [require_one_clock "GT TXUSRCLK2" $txusrclk2_pin]

require_period "GT TXOUTCLK" $txoutclk_clock 32.000
require_period "GT TXUSRCLK" $txusrclk_clock 32.000
require_period "GT TXUSRCLK2" $txusrclk2_clock 64.000

set_clock_groups -asynchronous \
    -group $axi_clock \
    -group [list $txoutclk_clock $txusrclk_clock $txusrclk2_clock]
puts "INFO: Applied asynchronous clock groups: $axi_clock <-> [list $txoutclk_clock $txusrclk_clock $txusrclk2_clock]"

set impl_pre_dir [file dirname [file normalize [info script]]]
source [file join $impl_pre_dir gt_profile1_1000m_axi_bringup_debug.tcl]
