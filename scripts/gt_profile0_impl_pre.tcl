# Implementation pre-opt hook: verify the GT Profile 0 user-clock topology and
# declare the real AXI/TX CDC relationship after link_design has created clocks.
# All AXI<->TX crossings in laser_tx_core/laser_gt_tx_profile0 are handled by
# explicit RTL synchronizers.

proc require_one_clock {description objects} {
    set clocks [get_clocks -quiet -of_objects $objects]
    if {[llength $clocks] != 1} {
        error "GT Profile 0 clock check failed: expected one clock for $description, got '$clocks'."
    }
    return $clocks
}

proc require_period {description clock expected_period_ns} {
    set period [get_property PERIOD $clock]
    set delta [expr {abs($period - $expected_period_ns)}]
    if {$delta > 0.010} {
        error "GT Profile 0 clock check failed: $description period is $period ns, expected $expected_period_ns ns."
    }
    puts "INFO: $description period verified: $period ns"
}

proc unique_clock_or_empty {description clocks} {
    set clocks [lsort -unique $clocks]
    if {[llength $clocks] > 1} {
        error "GT Profile 0 CDC constraint failed: found multiple candidate clocks for $description: '$clocks'."
    }
    return $clocks
}

proc find_unique_ps7_fclk_clk0_pin {} {
    # Prefer the concrete PS7 wrapper output pin under the generated IP
    # instance.  A broad *FCLK_CLK0* query can return both the BD cell pin and
    # the generated instance pin; using both for create_clock would be
    # ambiguous and is intentionally rejected.
    set fclk_pins [get_pins -hier -quiet *FCLK_CLK0*]
    set preferred {}
    foreach pin $fclk_pins {
        if {[string match "*/processing_system7_0/inst/FCLK_CLK0" $pin]} {
            lappend preferred $pin
        }
    }
    if {[llength $preferred] == 1} {
        return $preferred
    }

    if {[llength $fclk_pins] == 1} {
        return $fclk_pins
    }

    puts "INFO: Candidate FCLK_CLK0 pins for controlled fallback: $fclk_pins"
    return {}
}

proc report_axi_fclk_clock_debug {context} {
    set gt_ctrl_nets [get_nets -hier -quiet *gt_ctrl_clk*]
    set fclk_pins [get_pins -hier -quiet *FCLK_CLK0*]

    puts "INFO: $context all clocks: [get_clocks -quiet]"
    puts "INFO: $context gt_ctrl_clk nets: $gt_ctrl_nets"
    puts "INFO: $context clk_fpga_0 nets: [get_nets -hier -quiet *clk_fpga_0*]"
    puts "INFO: $context FCLK_CLK0 pins: $fclk_pins"
    puts "INFO: $context clocks of FCLK_CLK0 pins: [get_clocks -quiet -of_objects $fclk_pins]"
    puts "INFO: $context clocks of gt_ctrl_clk nets: [get_clocks -quiet -of_objects $gt_ctrl_nets]"
}

proc find_axi_fclk_clock {} {
    set candidates {}

    # Preferred path: locate the explicit top/BD AXI clock net and ask Vivado for
    # the clock object propagated onto that net.  In some implementation hook
    # contexts, the clock object exists but direct name lookup with
    # get_clocks clk_fpga_0 can return empty.
    set gt_ctrl_nets [get_nets -hier -quiet *gt_ctrl_clk*]
    if {[llength $gt_ctrl_nets] > 0} {
        set candidates [concat $candidates [get_clocks -quiet -of_objects $gt_ctrl_nets]]
    }

    set candidates [unique_clock_or_empty "gt_ctrl_clk net(s)" $candidates]
    if {[llength $candidates] == 1} {
        puts "INFO: AXI/FCLK clock resolved from gt_ctrl_clk net: $candidates"
        return $candidates
    }

    # Fallback path: use the PS7 FCLK_CLK0 output pin.
    set fclk_pins [get_pins -hier -quiet *FCLK_CLK0*]
    if {[llength $fclk_pins] > 0} {
        set candidates [get_clocks -quiet -of_objects $fclk_pins]
    } else {
        set candidates {}
    }

    set candidates [unique_clock_or_empty "FCLK_CLK0 pin(s)" $candidates]
    if {[llength $candidates] == 1} {
        puts "INFO: AXI/FCLK clock resolved from FCLK_CLK0 pin: $candidates"
        return $candidates
    }

    # Last fallback: name-based clock lookup.
    set candidates [concat \
        [get_clocks -quiet *clk_fpga_0*] \
        [get_clocks -quiet *FCLK_CLK0*]]
    set candidates [unique_clock_or_empty "clock name match *clk_fpga_0*/*FCLK_CLK0*" $candidates]
    if {[llength $candidates] == 1} {
        puts "INFO: AXI/FCLK clock resolved by name match: $candidates"
        return $candidates
    }

    # Controlled constraint fallback:
    # Some project implementation hook contexts contain the gt_ctrl_clk net and
    # PS7 FCLK_CLK0 pin but do not carry the PS7-generated clk_fpga_0 clock
    # object into this pre-hook.  In that exact case only, recreate the missing
    # 50 MHz AXI/FCLK clock on the unique PS7 FCLK_CLK0 pin so the existing CDC
    # and debug-hub constraints can be applied deterministically.
    set existing_clk_fpga_0 [get_clocks -quiet clk_fpga_0]
    if {[llength $existing_clk_fpga_0] > 0} {
        report_axi_fclk_clock_debug "AXI/FCLK fallback blocked: clk_fpga_0 already exists"
        error "GT Profile 0 CDC constraint failed: clk_fpga_0 exists but could not be uniquely associated with gt_ctrl_clk/FCLK_CLK0: '$existing_clk_fpga_0'."
    }

    set fclk_pin [find_unique_ps7_fclk_clk0_pin]
    if {[llength $fclk_pin] != 1} {
        report_axi_fclk_clock_debug "AXI/FCLK fallback failed"
        error "GT Profile 0 CDC constraint failed: cannot create fallback clk_fpga_0 because a unique PS7 FCLK_CLK0 pin was not found."
    }

    puts "INFO: AXI/FCLK clock object missing; creating controlled fallback clock clk_fpga_0 on $fclk_pin with period 20.000 ns."
    create_clock -name clk_fpga_0 -period 20.000 $fclk_pin

    set created_by_name [get_clocks -quiet clk_fpga_0]
    set created_by_pin [get_clocks -quiet -of_objects $fclk_pin]
    set created_by_gt_ctrl_net [get_clocks -quiet -of_objects [get_nets -hier -quiet *gt_ctrl_clk*]]

    puts "INFO: AXI/FCLK fallback get_clocks clk_fpga_0: $created_by_name"
    puts "INFO: AXI/FCLK fallback clocks of FCLK_CLK0 pin: $created_by_pin"
    puts "INFO: AXI/FCLK fallback clocks of gt_ctrl_clk nets: $created_by_gt_ctrl_net"

    set candidates [concat $created_by_name $created_by_pin $created_by_gt_ctrl_net]
    set candidates [unique_clock_or_empty "controlled fallback clk_fpga_0" $candidates]
    if {[llength $candidates] == 1} {
        puts "INFO: AXI/FCLK clock resolved from controlled fallback create_clock: $candidates"
        return $candidates
    }

    report_axi_fclk_clock_debug "AXI/FCLK fallback unresolved"
    error "GT Profile 0 CDC constraint failed: fallback create_clock did not resolve a unique AXI/FCLK clock."
}

set axi_clock [find_axi_fclk_clock]
puts "INFO: GT Profile 0 CDC AXI/FCLK clock used: $axi_clock"

set txoutclk_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_gtwizard_0/inst/gtwizard_0_i/gt0_gtwizard_0_i/gtxe2_i/TXOUTCLK]
set txusrclk_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk_bufg/O]
set txusrclk2_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk2_bufg/O]

set txoutclk_clock [require_one_clock "GT TXOUTCLK" $txoutclk_pin]
set txusrclk_clock [require_one_clock "GT TXUSRCLK" $txusrclk_pin]
set txusrclk2_clock [require_one_clock "GT TXUSRCLK2" $txusrclk2_pin]

require_period "GT TXOUTCLK / TXUSRCLK" $txoutclk_clock 64.000
require_period "GT TXUSRCLK" $txusrclk_clock 64.000
require_period "GT TXUSRCLK2" $txusrclk2_clock 128.000

set_clock_groups -asynchronous \
    -group $axi_clock \
    -group [list $txoutclk_clock $txusrclk_clock $txusrclk2_clock]
puts "INFO: Applied asynchronous clock groups: $axi_clock <-> [list $txoutclk_clock $txusrclk_clock $txusrclk2_clock]"

# The AD9528 OUT0 ODIV2 monitor crosses into gt_ctrl_clk through an explicit
# Gray-counter synchronizer.  Constrain only these two clock domains as
# asynchronous; synchronous paths inside either domain remain timed.
set ad9528_measure_clock [get_clocks -quiet ad9528_out0_odiv2_raw]
if {[llength $ad9528_measure_clock] != 1} {
    error "AD9528 measurement CDC constraint failed: expected one ODIV2 clock; got '$ad9528_measure_clock'."
}
set_clock_groups -asynchronous \
    -group $axi_clock \
    -group $ad9528_measure_clock
puts "INFO: Applied AD9528 measurement asynchronous clock group: $axi_clock <-> $ad9528_measure_clock"

# Keep Hardware Manager bring-up independent of the GT TX user clock.  The
# debug hub must run from the stable PS FCLK / gt_ctrl_clk domain so it remains
# visible even when GT TXOUTCLK/MMCM/TXUSRCLK2 are not yet locked.
set dbg_hub_core [get_debug_cores -quiet dbg_hub]
if {[llength $dbg_hub_core] != 1} {
    error "GT Profile 0 debug hub clock fix failed: expected one dbg_hub core, got '$dbg_hub_core'."
}

set dbg_hub_clk_net [get_nets -hier -quiet gt_ctrl_clk]
if {[llength $dbg_hub_clk_net] != 1} {
    set dbg_hub_clk_net [get_nets -hier -quiet *gt_ctrl_clk*]
}
if {[llength $dbg_hub_clk_net] < 1} {
    error "GT Profile 0 debug hub clock fix failed: cannot find gt_ctrl_clk net."
}
set dbg_hub_clk_net [lindex $dbg_hub_clk_net 0]

catch {disconnect_debug_port dbg_hub/clk}
connect_debug_port dbg_hub/clk $dbg_hub_clk_net
set_property C_CLK_INPUT_FREQ_HZ 50000000 $dbg_hub_core
set_property C_ENABLE_CLK_DIVIDER false $dbg_hub_core
set_property C_USER_SCAN_CHAIN 1 $dbg_hub_core
puts "INFO: dbg_hub/clk forced to AXI/FCLK net: $dbg_hub_clk_net"

# Add the independent AD9528 OUT0 measurement ILA without changing the BD ILA.
source [file join [file dirname [file normalize [info script]]] \
    add_ad9528_out0_measurement_ila.tcl]
