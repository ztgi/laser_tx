# Create an isolated 1000 Mb/s GT Wizard comparison project.
#
# This script must not open or modify laser_tx.xpr.  It copies the current
# Profile 0 XCI into reports/ and asks Vivado to resolve a 1.0 Gb/s variant
# in a throw-away project so the generated XCI/properties can be inspected
# before any real DRP or wrapper work is attempted.

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set source_xci [file join $project_dir laser_tx.srcs sources_1 ip gtwizard_0 gtwizard_0.xci]
set out_root [file join $project_dir reports gt_dynamic_rate_phase2_design_pkg gtwizard_1000m_compare]
set work_dir [file join $out_root vivado_work]
set copied_ip_dir [file join $out_root copied_ip]
set copied_xci [file join $copied_ip_dir gtwizard_0.xci]
set compare_gen_dir [file join $out_root generated_ip gtwizard_0]
set prop_report [file join $out_root gtwizard_1000m_selected_properties.txt]
set log_report [file join $out_root gtwizard_1000m_generation_summary.txt]
set example_dir [file join $out_root example_design]

proc fail {msg} {
    puts stderr "ERROR: $msg"
    return -code error $msg
}

if {![file exists $source_xci]} {
    fail "Source Profile 0 XCI not found: $source_xci"
}

file mkdir $out_root
file mkdir $copied_ip_dir
file copy -force $source_xci $copied_xci

set compare_gen_dir_norm [string map {\\ /} [file normalize $compare_gen_dir]]
set xci_fh [open $copied_xci r]
set xci_text [read $xci_fh]
close $xci_fh
regsub {"gen_directory": "[^"]+"} $xci_text "\"gen_directory\": \"$compare_gen_dir_norm\"" xci_text
if {[regexp {"OUTPUTDIR": \[ \{ "value": "[^"]+" \} \]} $xci_text]} {
    regsub {"OUTPUTDIR": \[ \{ "value": "[^"]+" \} \]} $xci_text "\"OUTPUTDIR\": \[ \{ \"value\": \"$compare_gen_dir_norm\" \} \]" xci_text
}
set xci_fh [open $copied_xci w]
puts -nonewline $xci_fh $xci_text
close $xci_fh

if {[file exists $work_dir]} {
    file delete -force $work_dir
}
if {[file exists $compare_gen_dir]} {
    file delete -force $compare_gen_dir
}
file mkdir $work_dir

create_project gt_1000m_compare $work_dir -part xc7z100ffg900-2 -force
add_files -norecurse $copied_xci

set ip [get_ips -quiet gtwizard_0]
if {[llength $ip] != 1} {
    fail "Expected one gtwizard_0 IP in isolated project; got '$ip'"
}

set set_ok 1
set set_log {}
foreach {prop value} {
    CONFIG.identical_val_tx_line_rate 1.0
    CONFIG.gt0_val_tx_line_rate       1.0
    CONFIG.gt0_val_rx_line_rate       1.0
    CONFIG.gt0_val_cpll_txout_div     4
    CONFIG.gt0_val_cpll_rxout_div     4
} {
    if {[catch {set_property $prop $value $ip} err]} {
        set set_ok 0
        append set_log "FAILED set_property $prop $value: $err\n"
    } else {
        append set_log "OK set_property $prop $value\n"
    }
}

if {!$set_ok} {
    set fh [open $log_report w]
    puts $fh $set_log
    close $fh
    fail "One or more 1000M GT Wizard properties could not be set. See $log_report"
}

if {[catch {generate_target all $ip} gen_err]} {
    set fh [open $log_report w]
    puts $fh $set_log
    puts $fh "FAILED generate_target all: $gen_err"
    close $fh
    fail "generate_target all failed. See $log_report"
}

if {[catch {export_ip_user_files -of_objects $ip -no_script -sync -force -quiet} export_err]} {
    append set_log "WARNING export_ip_user_files failed: $export_err\n"
}

set selected_props {
    identical_val_tx_line_rate
    gt0_val_tx_line_rate
    gt0_val_rx_line_rate
    gt0_val_tx_data_width
    gt0_val_encoding
    gt0_val_tx_int_datawidth
    gt0_val_tx_reference_clock
    gt0_val_cpll_fbdiv_45
    gt0_val_cpll_fbdiv
    gt0_val_cpll_refclk_div
    gt0_val_cpll_txout_div
    gt0_val_cpll_rxout_div
    gt0_val_drp
    gt0_val_drp_clock
    gt0_val_txusrclk
    gt0_val_txoutclk_source
    gt0_val_port_tx8b10ben
    gt0_val_port_txsysclksel
    gt0_val_port_cpllpd
    gt0_val_port_qpllpd
}

set fh [open $prop_report w]
puts $fh "# Selected GT Wizard 1000M comparison properties"
puts $fh "# Generated in isolated project, not added to laser_tx.xpr"
foreach prop $selected_props {
    set full_prop CONFIG.$prop
    if {[catch {set value [get_property $full_prop $ip]} err]} {
        puts $fh "$prop = <unavailable: $err>"
    } else {
        puts $fh "$prop = $value"
    }
}
close $fh

if {[catch {open_example_project -force -dir $example_dir $ip} ex_err]} {
    append set_log "WARNING open_example_project failed: $ex_err\n"
} else {
    append set_log "OK open_example_project: $example_dir\n"
}

set fh [open $log_report w]
puts $fh $set_log
puts $fh "OK generate_target all"
puts $fh "Copied source XCI: $source_xci"
puts $fh "1000M comparison XCI: $copied_xci"
puts $fh "Selected property report: $prop_report"
puts $fh "Vivado work dir: $work_dir"
puts $fh "Example design dir: $example_dir"
close $fh

puts "INFO: 1000M GT Wizard comparison generation finished."
puts "INFO: $prop_report"
puts "INFO: $log_report"
