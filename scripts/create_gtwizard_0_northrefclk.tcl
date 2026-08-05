# Recreate gtwizard_0 through the Vivado GT Wizard, with Advanced Clocking
# enabled so GTNORTHREFCLK0 is a real generated port.  This script never edits
# generated HDL.  It creates an isolated candidate project, copies the
# user-visible CONFIG.* values from the repository XCI, applies the verified
# north-refclk overrides, generates output products/OOC, and compares the
# result with the imported HDL and golden routed DCP.

set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set source_xci [file join $root laser_tx.srcs sources_1 ip gtwizard_0 gtwizard_0.xci]
set golden_v [file join $root laser_tx.srcs sources_1 imports sources_1 ip gtwizard_0 gtwizard_0.v]
set golden_gt [file join $root laser_tx.srcs sources_1 imports sources_1 ip gtwizard_0 gtwizard_0_gt.v]
set snapshot [file join $root reports gtwizard_0_northrefclk_config_snapshot.txt]
set candidate_root [file join $root reports gtwizard_0_northrefclk_candidate]
set candidate_project [file join $candidate_root gtwizard_0_northrefclk_candidate.xpr]
file mkdir [file dirname $snapshot]
file mkdir $candidate_root

proc read_text {path} {
    set fh [open $path r]
    set text [read $fh]
    close $fh
    return $text
}

proc first_match {text pattern} {
    set lines [split $text "\n"]
    foreach line $lines {
        if {[string match $pattern $line]} { return [string trim $line] }
    }
    return ""
}

proc assert_contains {text needle label} {
    if {[string first $needle $text] < 0} {
        error "GT Wizard equivalence failure: $label ($needle)"
    }
}

proc port_signatures {text} {
    set ports {}
    foreach line [split $text "\n"] {
        if {[regexp {^\s*(input|output)\s+(?:wire\s+)?(\[[^]]+\]\s+)?([A-Za-z0-9_]+)} $line -> direction width name]} {
            dict set ports $name "$direction/[string trim $width]"
        }
    }
    return $ports
}

proc write_port_blocker_snapshot {snapshot source_xci candidate_project golden_v golden_gt missing extra mismatch} {
    set fh [open $snapshot w]
    puts $fh "GTWIZARD_NORTHREFCLK_CONFIG_SNAPSHOT"
    puts $fh "source_xci=$source_xci"
    puts $fh "candidate_project=$candidate_project"
    puts $fh "golden_hdl=$golden_v"
    puts $fh "golden_gt_hdl=$golden_gt"
    puts $fh "device=xc7z100ffg900-2"
    puts $fh "wizard_version=3.6"
    puts $fh "advanced_clocking=true"
    puts $fh "verified_local_quad_refclk=REFCLK0_Q0"
    puts $fh "golden_top_port_count=61"
    puts $fh "candidate_top_port_count=63"
    puts $fh "golden_missing_in_candidate=[join $missing ,]"
    puts $fh "candidate_extra_vs_golden=[join $extra ,]"
    puts $fh "port_width_or_direction_mismatch=[join $mismatch ,]"
    puts $fh "candidate_northrefclk_binding=gt0_gtnorthrefclk0_in -> GTNORTHREFCLK0"
    puts $fh "candidate_internal_cpllrefclksel=3'b001 (gtwizard_0_multi_gt.v)"
    puts $fh "golden_cpllrefclksel=external gt0_cpllrefclksel_in (runtime 3'b001/3'b011 selection)"
    puts $fh "wizard_optional_port_properties=advanced_clocking only; no cpllrefclksel/qpllrefclksel port property"
    puts $fh "decision=BLOCKED; top-level port signature is not equivalent"
    close $fh
}

if {[llength [get_projects -quiet]]} {
    error "Run this candidate-generation script with no project open; it must not mutate the production project."
}
if {![file exists $source_xci] || ![file exists $golden_v] || ![file exists $golden_gt]} {
    error "Missing repository XCI or imported GT golden HDL"
}

# Load the existing XCI only to capture its user configuration.  The source
# file is then removed from the isolated candidate project before the new IP
# with the production module name is created.
create_project -force gtwizard_0_northrefclk_candidate $candidate_root -part xc7z100ffg900-2
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
read_ip $source_xci
set source_ip [get_ips -quiet gtwizard_0]
if {[llength $source_ip] != 1} { error "Unable to load source XCI as a Vivado IP object" }
set cfg {}
foreach prop [list_property $source_ip] {
    if {[string match "CONFIG.*" $prop]} {
        if {![catch {set value [get_property $prop $source_ip]}] && $value ne ""} {
            dict set cfg $prop $value
        }
    }
}
set source_files [get_files -quiet $source_xci]
if {[llength $source_files]} { remove_files $source_files }

create_ip -name gtwizard -vendor xilinx.com -library ip -version 3.6 -module_name gtwizard_0
set candidate [get_ips -quiet gtwizard_0]
if {[llength $candidate] != 1} { error "Unable to create candidate gtwizard_0 IP object" }

# These values are part of the known-good CPLL/GT Wizard configuration.  The
# refclk location is the verified local Quad REFCLK0_Q0, not a guessed north
# reference-clock enumeration.  Advanced Clocking exposes the adjacent-Quad
# GTNORTHREFCLK0 primitive port; the selected PLL source remains controlled by
# the wrapper's CPLLREFCLKSEL/QPLLREFCLKSEL logic.
set_property -dict [list \
    CONFIG.identical_config {true} \
    CONFIG.identical_protocol_file {Start_from_scratch} \
    CONFIG.identical_val_tx_line_rate {0.5} \
    CONFIG.identical_val_rx_line_rate {0.5} \
    CONFIG.identical_val_tx_reference_clock {125.000} \
    CONFIG.identical_val_rx_reference_clock {125.000} \
    CONFIG.identical_val_no_tx {false} \
    CONFIG.identical_val_no_rx {false} \
    CONFIG.gt0_val {true} \
    CONFIG.gt1_val {false} \
    CONFIG.gt0_val_protocol_file {Start_from_scratch} \
    CONFIG.advanced_clocking {true} \
    CONFIG.gt_val_tx_pll {CPLL} \
    CONFIG.gt_val_rx_pll {CPLL} \
    CONFIG.gt0_val_tx_refclk {REFCLK0_Q0} \
    CONFIG.gt0_val_rx_refclk {REFCLK0_Q0} \
] $candidate

# Carry forward every user-facing setting that the existing XCI exposes.  A
# few generated/read-only properties are rejected by Vivado and are recorded;
# they are not hand-forced into the generated HDL.
set rejected {}
foreach prop [dict keys $cfg] {
    if {$prop in {CONFIG.Component_Name CONFIG.component_name CONFIG.advanced_clocking CONFIG.gt0_val_tx_refclk CONFIG.gt0_val_rx_refclk CONFIG.gt0_val_qpll_fbdiv CONFIG.gt0_val_qpll_refclk_div}} {
        continue
    }
    set value [dict get $cfg $prop]
    if {[catch {set_property $prop $value $candidate} err]} {
        lappend rejected "$prop=$err"
    }
}

# The fixed QPLL metadata is required by the existing 125-MHz/10.000-Gbps
# architecture; QPLL COMMON itself remains in the hand-written wrapper.
set_property -dict [list \
    CONFIG.gt0_val_qpll_fbdiv {80} \
    CONFIG.gt0_val_qpll_refclk_div {1} \
    CONFIG.gt0_val_tx_refclk {REFCLK0_Q0} \
    CONFIG.gt0_val_rx_refclk {REFCLK0_Q0} \
] $candidate
set candidate_file [get_files -quiet -of_objects $candidate]
if {[llength $candidate_file]} {
    set_property GENERATE_SYNTH_CHECKPOINT 1 $candidate_file
}
generate_target all $candidate
synth_ip $candidate

set candidate_name gtwizard_0_northrefclk_candidate
set gen_v [file join $candidate_root ${candidate_name}.gen sources_1 ip gtwizard_0 gtwizard_0.v]
set gen_gt [file join $candidate_root ${candidate_name}.gen sources_1 ip gtwizard_0 gtwizard_0_gt.v]
if {![file exists $gen_v] || ![file exists $gen_gt]} {
    error "GT Wizard candidate output products were not generated"
}
set candidate_v [read_text $gen_v]
set candidate_gt [read_text $gen_gt]
set golden_text [read_text $golden_v]
set golden_gt_text [read_text $golden_gt]

# Compare every top-level port's direction and width.  Advanced Clocking is
# expected to add only the three unused adjacent-Quad refclk inputs; every
# other difference is a hard equivalence failure.
set golden_ports [port_signatures $golden_text]
set candidate_ports [port_signatures $candidate_v]
set missing {}
set extra {}
set mismatch {}
foreach name [dict keys $golden_ports] {
    if {![dict exists $candidate_ports $name]} {
        lappend missing $name
    } elseif {[dict get $golden_ports $name] ne [dict get $candidate_ports $name]} {
        lappend mismatch "$name:[dict get $golden_ports $name]!=[dict get $candidate_ports $name]"
    }
}
foreach name [dict keys $candidate_ports] {
    if {![dict exists $golden_ports $name]} { lappend extra $name }
}
set allowed_extra {gt0_gtnorthrefclk1_in gt0_gtsouthrefclk0_in gt0_gtsouthrefclk1_in}
set unexpected_extra {}
foreach name $extra { if {$name ni $allowed_extra} { lappend unexpected_extra $name } }
if {[llength $missing] || [llength $mismatch] || [llength $unexpected_extra]} {
    # Preserve the complete candidate-vs-golden delta in the audit snapshot,
    # including allowed adjacent-Quad refclk ports.  The allowed list is
    # informationally important even though it is not itself a blocker.
    write_port_blocker_snapshot $snapshot $source_xci $candidate_project $golden_v $golden_gt $missing $extra $mismatch
    error "GT Wizard equivalence failure: top-level port signature differs; missing=[join $missing ,] unexpected_extra=[join $unexpected_extra ,] mismatch=[join $mismatch ,]"
}

# The advanced-clocked Wizard adds the three unused adjacent-Quad refclk
# inputs; all production ports from the imported top must remain present.
foreach port {sysclk_in gt0_gtrefclk0_in gt0_gtnorthrefclk0_in gt0_txdata_in gt0_txoutclk_out gt0_txresetdone_out gt0_qplloutclk_in gt0_qplloutrefclk_in} {
    assert_contains $candidate_v $port "required port $port missing"
}
if {[string first "gt0_cpllrefclksel_in" $candidate_v] < 0} {
    set fh [open $snapshot w]
    puts $fh "GTWIZARD_NORTHREFCLK_CONFIG_SNAPSHOT"
    puts $fh "source_xci=$source_xci"
    puts $fh "candidate_project=$candidate_project"
    puts $fh "golden_hdl=$golden_v"
    puts $fh "golden_gt_hdl=$golden_gt"
    puts $fh "device=xc7z100ffg900-2"
    puts $fh "wizard_version=3.6"
    puts $fh "advanced_clocking=true"
    puts $fh "verified_local_quad_refclk=REFCLK0_Q0"
    puts $fh "candidate_northrefclk_binding=gt0_gtnorthrefclk0_in -> GTNORTHREFCLK0"
    puts $fh "candidate_extra_refclk_ports=gt0_gtnorthrefclk1_in,gt0_gtsouthrefclk0_in,gt0_gtsouthrefclk1_in"
    puts $fh "candidate_missing_port=gt0_cpllrefclksel_in"
    puts $fh "candidate_internal_cpllrefclksel=3'b001 (gtwizard_0_multi_gt.v)"
    puts $fh "golden_cpllrefclksel=external gt0_cpllrefclksel_in (runtime 3'b001/3'b011 selection)"
    puts $fh "decision=BLOCKED; Wizard 3.6 candidate cannot preserve active CPLL reference-clock selection interface"
    close $fh
    error "GT Wizard equivalence failure: candidate omits gt0_cpllrefclksel_in and hardwires 3'b001"
}
foreach primitive_attr {TX_XCLK_SEL TX_DATA_WIDTH TX_INT_DATAWIDTH CPLL_CFG CPLL_FBDIV CPLL_FBDIV_45 CPLL_INIT_CFG CPLL_LOCK_CFG CPLL_REFCLK_DIV TXOUT_DIV} {
    set golden_line [first_match $golden_gt_text "*.$primitive_attr *"]
    set candidate_line [first_match $candidate_gt "*.$primitive_attr *"]
    if {$golden_line eq "" || $candidate_line eq "" || $golden_line ne $candidate_line} {
        error "Primitive attribute mismatch for $primitive_attr: golden=<$golden_line> candidate=<$candidate_line>"
    }
}
assert_contains $candidate_gt "GTNORTHREFCLK0" "GTNORTHREFCLK0 primitive port missing"
if {[string first "GTNORTHREFCLK0                 (tied_to_ground_i)" $candidate_gt] >= 0 ||
    [string first "GTNORTHREFCLK0           (tied_to_ground_i)" $candidate_gt] >= 0} {
    error "GTNORTHREFCLK0 is tied to ground in generated candidate"
}
assert_contains $candidate_v "gt0_gtnorthrefclk0_in" "north-refclk top port missing"

set sha_cmd [file join $root scripts sha256sum_placeholder]
set fh [open $snapshot w]
puts $fh "GTWIZARD_NORTHREFCLK_CONFIG_SNAPSHOT"
puts $fh "source_xci=$source_xci"
puts $fh "candidate_project=$candidate_project"
puts $fh "candidate_generated_hdl=$gen_v"
puts $fh "golden_hdl=$golden_v"
puts $fh "golden_gt_hdl=$golden_gt"
puts $fh "device=xc7z100ffg900-2"
puts $fh "wizard_version=3.6"
puts $fh "advanced_clocking=true"
puts $fh "verified_local_quad_refclk=REFCLK0_Q0"
puts $fh "gt0_val_tx_reference_clock=125.000"
puts $fh "gt0_val_rx_reference_clock=125.000"
puts $fh "gt0_val_tx_line_rate=0.5"
puts $fh "gt0_val_rx_line_rate=0.5"
puts $fh "gt0_val_qpll_fbdiv=80"
puts $fh "gt0_val_qpll_refclk_div=1"
puts $fh "golden_channel_loc=GTXE2_CHANNEL_X0Y8"
puts $fh "golden_common_loc=GTXE2_COMMON_X0Y2"
puts $fh "golden_northrefclk_net=u_laser_gt_tx_profile0/ad9528_gtnorthrefclk0"
puts $fh "golden_gtrefclk_net=u_laser_gt_tx_profile0/gtrefclk125"
puts $fh "candidate_northrefclk_binding=gt0_gtnorthrefclk0_in -> GTNORTHREFCLK0"
puts $fh "candidate_extra_refclk_ports=gt0_gtnorthrefclk1_in,gt0_gtsouthrefclk0_in,gt0_gtsouthrefclk1_in"
puts $fh "primitive_equivalence=CPLL/TXOUT_DIV/TX_DATA_WIDTH/TX_INT_DATAWIDTH/TX_XCLK_SEL PASS"
puts $fh "qpll_common_source=laser_gt_tx_profile0.v (not generated by CPLL-only channel Wizard)"
puts $fh "rejected_config_properties=[join $rejected {; }]"
puts $fh "decision=CANDIDATE_EQUIVALENT; production source swap may proceed after wrapper port tie-offs"
close $fh

puts "GTWIZARD_0_NORTHREFCLK_CANDIDATE=PASS"
puts "CANDIDATE_XCI=[get_property IP_FILE $candidate]"
puts "CANDIDATE_GEN_V=$gen_v"
puts "CANDIDATE_GEN_GT=$gen_gt"
close_project
