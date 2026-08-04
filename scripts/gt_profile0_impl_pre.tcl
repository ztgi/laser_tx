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

proc find_unique_ps7_fclk_clock_source {} {
    # The legal primary-clock root is the PS7 primitive FCLKCLK[0] output.
    # Do not create a primary clock on the processing_system7 wrapper
    # FCLK_CLK0 pin or on the downstream BUFG output: both have timing arcs
    # and trigger TIMING-2.
    set sources [get_pins -hier -quiet -filter \
        {REF_NAME == PS7 && REF_PIN_NAME == {FCLKCLK[0]}}]
    if {[llength $sources] == 1} {
        return $sources
    }

    puts "INFO: Candidate PS7 FCLKCLK[0] primitive pins: $sources"
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
    # Some project implementation hook contexts do not carry the PS7-generated
    # clk_fpga_0 clock object into this pre-hook.  In that exact case only,
    # recreate the missing 50 MHz AXI/FCLK clock on the PS7 primitive
    # FCLKCLK[0] output.  This is the real hardware clock source and does not
    # overwrite an existing auto-derived clock.
    set existing_clk_fpga_0 [get_clocks -quiet clk_fpga_0]
    if {[llength $existing_clk_fpga_0] > 0} {
        report_axi_fclk_clock_debug "AXI/FCLK fallback blocked: clk_fpga_0 already exists"
        error "GT Profile 0 CDC constraint failed: clk_fpga_0 exists but could not be uniquely associated with gt_ctrl_clk/FCLK_CLK0: '$existing_clk_fpga_0'."
    }

    set fclk_source [find_unique_ps7_fclk_clock_source]
    if {[llength $fclk_source] != 1} {
        report_axi_fclk_clock_debug "AXI/FCLK fallback failed"
        error "GT Profile 0 CDC constraint failed: cannot create clk_fpga_0 because a unique PS7 primitive FCLKCLK[0] source was not found."
    }

    puts "INFO: AXI/FCLK clock object missing; creating clk_fpga_0 on legal PS7 primitive source $fclk_source with period 20.000 ns."
    create_clock -name clk_fpga_0 -period 20.000 $fclk_source

    set created_by_name [get_clocks -quiet clk_fpga_0]
    set created_by_pin [get_clocks -quiet -of_objects $fclk_source]
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

# The maintained adapter binds the local XCI lower module directly.  Resolve
# the primitive pin by cell/pin identity rather than the generated wrapper
# path, so imported and adapter-backed hierarchies use the same clock model.
set txoutclk_pin [get_pins -hier -quiet -filter \
    {REF_NAME == GTXE2_CHANNEL && REF_PIN_NAME == TXOUTCLK}]
if {[llength $txoutclk_pin] != 1} {
    set txoutclk_pin [get_pins -quiet \
        u_laser_gt_tx_profile0/u_gtwizard_0/gt0_gtwizard_0_i/gtxe2_i/TXOUTCLK]
}
set mmcm_clkin_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk_mmcm/CLKIN1]
set mmcm_txusrclk_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk_mmcm/CLKOUT1]
set mmcm_txusrclk2_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk_mmcm/CLKOUT0]
set mmcm_eom_clk_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk_mmcm/CLKOUT2]
set txusrclk_bufg_input_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk_bufg/I]
set txusrclk2_bufg_input_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk2_bufg/I]
set eom_clk_bufg_input_pin [get_pins -quiet \
    u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_eom_clk_bufg/I]

foreach {description object} [list \
    "GT TXOUTCLK" $txoutclk_pin \
    "TX user-clock MMCM CLKIN1" $mmcm_clkin_pin \
    "TX user-clock MMCM CLKOUT1" $mmcm_txusrclk_pin \
    "TX user-clock MMCM CLKOUT0" $mmcm_txusrclk2_pin \
    "TX user-clock MMCM CLKOUT2" $mmcm_eom_clk_pin \
    "TXUSRCLK BUFG input" $txusrclk_bufg_input_pin \
    "TXUSRCLK2 BUFG input" $txusrclk2_bufg_input_pin \
    "EOM clock BUFG input" $eom_clk_bufg_input_pin] {
    if {[llength $object] != 1} {
        error "GT Profile 0 clock check failed: expected one $description pin, got '$object'."
    }
}

# The current static netlist contains QPLL_N=80, TXOUT_DIV=8,
# TX_INT_DATAWIDTH=32 and TXOUTCLKSEL=3'b010.  With the real 125 MHz GTREFCLK,
# Vivado derives a 1.25 Gb/s static QPLL/DIV8 combination and therefore a
# 39.0625 MHz (25.600 ns) TXOUTCLK.  This is not the 500M runtime profile; it is
# the only waveform consistent with the linked static GT primitive.  The
# runtime MMCM profiles are modeled separately below.
if {[llength $txoutclk_pin] == 1 &&
    [llength [get_clocks -quiet -of_objects $txoutclk_pin]] == 0} {
    create_clock -name GT_TXOUTCLK_STATIC_NETLIST -period 25.600 $txoutclk_pin
    puts "INFO: Created static-netlist GT TXOUTCLK clock (25.600 ns) on $txoutclk_pin."
}

set txoutclk_clock [require_one_clock "GT TXOUTCLK" $txoutclk_pin]
require_period "static-netlist GT TXOUTCLK" $txoutclk_clock 25.600

# Keep Vivado's 25.600 ns GT primitive waveform for static-netlist/QPLL
# analysis, but do not let that candidate waveform drive the power-up MMCM
# model.  The real reset profile is 500M/CPLL:
#   TXOUTCLK = 15.625 MHz (64.000 ns)
# Model that profile only at the MMCM input boundary.  The 2/5 ratio below is a
# timing-model overlay between the retained 25.600 ns static GT candidate and
# the selected 64.000 ns startup profile; it is not a physical divider.
create_generated_clock -name GT_TXOUTCLK_INITIAL_500M \
    -source $txoutclk_pin -multiply_by 2 -divide_by 5 \
    $mmcm_clkin_pin
set startup_txoutclk_clock [require_one_clock \
    "500M/CPLL startup MMCM CLKIN1" $mmcm_clkin_pin]
require_period "500M/CPLL startup MMCM CLKIN1" \
    $startup_txoutclk_clock 64.000

# With the legal 64 ns input in place, retain the clocks Vivado derives from
# the static MMCM attributes (MULT=40, DIVCLK=1; output divides 40/80/5).
# Do not create clocks on CLKOUT0/1/2: doing so overrides these auto-derived
# clocks and triggers Constraints 18-1056.
update_timing
set static_txusrclk_clock [require_one_clock \
    "auto-derived MMCM CLKOUT1/TXUSRCLK" $mmcm_txusrclk_pin]
set static_txusrclk2_clock [require_one_clock \
    "auto-derived MMCM CLKOUT0/TXUSRCLK2" $mmcm_txusrclk2_pin]
set static_eom_clk_clock [require_one_clock \
    "auto-derived MMCM CLKOUT2/EOM" $mmcm_eom_clk_pin]
require_period "auto-derived MMCM CLKOUT1/TXUSRCLK" \
    $static_txusrclk_clock 64.000
require_period "auto-derived MMCM CLKOUT0/TXUSRCLK2" \
    $static_txusrclk2_clock 128.000
require_period "auto-derived MMCM CLKOUT2/EOM" \
    $static_eom_clk_clock 8.000
set static_mmcm_output_clocks [list \
    $static_txusrclk_clock $static_txusrclk2_clock $static_eom_clk_clock]
puts "INFO: Retained auto-derived 500M/CPLL MMCM output clocks: $static_mmcm_output_clocks"

# The runtime planner chooses K=16/8/4/2/1 and always programs
# EOM_CLK = K * TXUSRCLK2.  Independent 161.13 MHz TXUSRCLK2 and 200 MHz EOM
# maxima describe a combination that cannot exist.  Model the legal K-family
# envelopes as related sibling clocks from the same TXOUTCLK master instead.
# Each family uses its fastest legal pair:
#   K16: TXUSRCLK2/EOM <= 12.5/200 MHz
#   K8 : TXUSRCLK2/EOM <= 25/200 MHz
#   K4 : TXUSRCLK2/EOM <= 50/200 MHz
#   K2 : TXUSRCLK2/EOM <= 100/200 MHz
#   K1 : TXUSRCLK2/EOM <= 161.1328125/161.1328125 MHz
# Lower fixed profiles have the same integer relationship and are covered by
# the corresponding family envelope.
#
# Each -master_clock query deliberately resolves the auto-derived clock from
# its MMCM output pin.  Do not pass an auto-derived clock name through a helper
# proc: Vivado records that form as a name reference and raises TIMING-28.
#
# Ratios are relative to the auto-derived 500M/CPLL startup MMCM outputs:
#   CLKOUT1/TXUSRCLK  =  64.000 ns
#   CLKOUT0/TXUSRCLK2 = 128.000 ns
#   CLKOUT2/EOM       =   8.000 ns
# Each runtime clock starts at the real MMCM output pin and is attached to the
# downstream BUFG input.  This preserves the complete
# GT TXOUTCLK -> MMCM CLKIN1 -> MMCM CLKOUTx -> BUFG topology without
# redefining a BUFG output clock.
create_generated_clock -name GT_TXUSRCLK_RUNTIME_K16_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk_pin] \
    -source $mmcm_txusrclk_pin -multiply_by 8 -divide_by 5 \
    $txusrclk_bufg_input_pin
create_generated_clock -name GT_TXUSRCLK2_RUNTIME_K16_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk2_pin] \
    -source $mmcm_txusrclk2_pin -multiply_by 8 -divide_by 5 \
    $txusrclk2_bufg_input_pin
create_generated_clock -name GT_EOM_CLK_RUNTIME_K16_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_eom_clk_pin] \
    -source $mmcm_eom_clk_pin -multiply_by 8 -divide_by 5 \
    $eom_clk_bufg_input_pin

create_generated_clock -name GT_TXUSRCLK_RUNTIME_K8_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk_pin] \
    -source $mmcm_txusrclk_pin -multiply_by 16 -divide_by 5 \
    $txusrclk_bufg_input_pin
create_generated_clock -name GT_TXUSRCLK2_RUNTIME_K8_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk2_pin] \
    -source $mmcm_txusrclk2_pin -multiply_by 16 -divide_by 5 \
    $txusrclk2_bufg_input_pin
create_generated_clock -name GT_EOM_CLK_RUNTIME_K8_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_eom_clk_pin] \
    -source $mmcm_eom_clk_pin -multiply_by 8 -divide_by 5 \
    $eom_clk_bufg_input_pin

create_generated_clock -name GT_TXUSRCLK_RUNTIME_K4_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk_pin] \
    -source $mmcm_txusrclk_pin -multiply_by 32 -divide_by 5 \
    $txusrclk_bufg_input_pin
create_generated_clock -name GT_TXUSRCLK2_RUNTIME_K4_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk2_pin] \
    -source $mmcm_txusrclk2_pin -multiply_by 32 -divide_by 5 \
    $txusrclk2_bufg_input_pin
create_generated_clock -name GT_EOM_CLK_RUNTIME_K4_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_eom_clk_pin] \
    -source $mmcm_eom_clk_pin -multiply_by 8 -divide_by 5 \
    $eom_clk_bufg_input_pin

create_generated_clock -name GT_TXUSRCLK_RUNTIME_K2_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk_pin] \
    -source $mmcm_txusrclk_pin -multiply_by 64 -divide_by 5 \
    $txusrclk_bufg_input_pin
create_generated_clock -name GT_TXUSRCLK2_RUNTIME_K2_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk2_pin] \
    -source $mmcm_txusrclk2_pin -multiply_by 64 -divide_by 5 \
    $txusrclk2_bufg_input_pin
create_generated_clock -name GT_EOM_CLK_RUNTIME_K2_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_eom_clk_pin] \
    -source $mmcm_eom_clk_pin -multiply_by 8 -divide_by 5 \
    $eom_clk_bufg_input_pin

create_generated_clock -name GT_TXUSRCLK_RUNTIME_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk_pin] \
    -source $mmcm_txusrclk_pin -multiply_by 165 -divide_by 8 \
    $txusrclk_bufg_input_pin
create_generated_clock -name GT_TXUSRCLK2_RUNTIME_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_txusrclk2_pin] \
    -source $mmcm_txusrclk2_pin -multiply_by 165 -divide_by 8 \
    $txusrclk2_bufg_input_pin
create_generated_clock -name GT_EOM_CLK_RUNTIME_MAX -add \
    -master_clock [get_clocks -of_objects $mmcm_eom_clk_pin] \
    -source $mmcm_eom_clk_pin -multiply_by 165 -divide_by 128 \
    $eom_clk_bufg_input_pin

set runtime_profile_clock_groups [list \
    [get_clocks {GT_TXUSRCLK_RUNTIME_K16_MAX \
        GT_TXUSRCLK2_RUNTIME_K16_MAX GT_EOM_CLK_RUNTIME_K16_MAX}] \
    [get_clocks {GT_TXUSRCLK_RUNTIME_K8_MAX \
        GT_TXUSRCLK2_RUNTIME_K8_MAX GT_EOM_CLK_RUNTIME_K8_MAX}] \
    [get_clocks {GT_TXUSRCLK_RUNTIME_K4_MAX \
        GT_TXUSRCLK2_RUNTIME_K4_MAX GT_EOM_CLK_RUNTIME_K4_MAX}] \
    [get_clocks {GT_TXUSRCLK_RUNTIME_K2_MAX \
        GT_TXUSRCLK2_RUNTIME_K2_MAX GT_EOM_CLK_RUNTIME_K2_MAX}] \
    [get_clocks {GT_TXUSRCLK_RUNTIME_MAX \
        GT_TXUSRCLK2_RUNTIME_MAX GT_EOM_CLK_RUNTIME_MAX}]]

set txusrclk_clock [get_clocks GT_TXUSRCLK_RUNTIME_MAX]
set txusrclk2_clock [get_clocks GT_TXUSRCLK2_RUNTIME_MAX]
set eom_clk_clock [get_clocks GT_EOM_CLK_RUNTIME_MAX]
require_period "runtime maximum GT TXUSRCLK" $txusrclk_clock 3.103
require_period "runtime maximum GT TXUSRCLK2" $txusrclk2_clock 6.206
require_period "K=1 paired EOM clock" $eom_clk_clock 6.206

# Only one MMCM DRP profile can be active at a time.  Keep clocks inside each
# legal K family related, while making clocks from different runtime profiles
# logically exclusive.  This avoids impossible zero-cycle cross-profile paths
# without masking any real path within an active profile.
set profile_exclusive_cmd [list set_clock_groups \
    -name GT_RUNTIME_PROFILE_LOGICAL_EXCLUSIVITY -logically_exclusive]
if {[llength $static_mmcm_output_clocks] > 0} {
    lappend profile_exclusive_cmd -group $static_mmcm_output_clocks
}
foreach profile_clocks $runtime_profile_clock_groups {
    lappend profile_exclusive_cmd -group $profile_clocks
}
{*}$profile_exclusive_cmd

set all_runtime_clocks {}
foreach profile_clocks $runtime_profile_clock_groups {
    set all_runtime_clocks [concat $all_runtime_clocks $profile_clocks]
}

set_clock_groups -asynchronous \
    -group $axi_clock \
    -group [concat [list $txoutclk_clock] $all_runtime_clocks]
puts "INFO: Applied asynchronous clock groups: $axi_clock <-> [concat [list $txoutclk_clock] $all_runtime_clocks]"

# The AD9528 OUT0 ODIV2 monitor crosses into gt_ctrl_clk through an explicit
# Gray-counter synchronizer.  Constrain only these two clock domains as
# asynchronous; synchronous paths inside either domain remain timed.
set ad9528_measure_clock [get_clocks -quiet -of_objects \
    [get_pins -quiet u_ad9528_out0_ibufds_gte2/ODIV2]]
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
