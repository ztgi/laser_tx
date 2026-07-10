# Create isolated 10.000G QPLL GT Wizard comparison packages.
#
# This script must not open or modify laser_tx.xpr.  It copies the current
# Profile 0 XCI into reports/ and asks Vivado to resolve two throw-away
# 10.000G QPLL variants for parameter extraction only:
#   - 125.000 MHz REFCLK, expected QPLL_N/FBDIV = 80
#   - 156.250 MHz REFCLK, expected QPLL_N/FBDIV = 64
#
# The generated packages are not integrated into the main project and must not
# be treated as validated dynamic profiles.

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set source_xci [file join $project_dir laser_tx.srcs sources_1 ip gtwizard_0 gtwizard_0.xci]
set out_root [file join $project_dir reports qpll_10g_parameter_compare]

proc fail {msg} {
    puts stderr "ERROR: $msg"
    return -code error $msg
}

proc patch_xci_output_dir {xci_path gen_dir} {
    set gen_dir_norm [string map {\\ /} [file normalize $gen_dir]]
    set fh [open $xci_path r]
    set txt [read $fh]
    close $fh
    regsub {"gen_directory": "[^"]+"} $txt "\"gen_directory\": \"$gen_dir_norm\"" txt
    if {[regexp {"OUTPUTDIR": \[ \{ "value": "[^"]+" \} \]} $txt]} {
        regsub {"OUTPUTDIR": \[ \{ "value": "[^"]+" \} \]} $txt "\"OUTPUTDIR\": \[ \{ \"value\": \"$gen_dir_norm\" \} \]" txt
    }
    set fh [open $xci_path w]
    puts -nonewline $fh $txt
    close $fh
}

proc safe_set_ip_property {ip prop value log_var} {
    upvar $log_var log
    if {[catch {set_property $prop $value $ip} err]} {
        append log "FAILED set_property $prop $value: $err\n"
        return 0
    }
    append log "OK set_property $prop $value\n"
    return 1
}

proc report_ip_properties {ip prop_report selected_props} {
    set fh [open $prop_report w]
    puts $fh "# Selected GT Wizard 10.000G QPLL comparison properties"
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
}

proc create_one_compare {source_xci out_root name refclk_mhz qpll_fbdiv} {
    set out_dir [file join $out_root $name]
    set work_dir [file join $out_dir vivado_work]
    set copied_ip_dir [file join $out_dir copied_ip]
    set copied_xci [file join $copied_ip_dir gtwizard_0.xci]
    set gen_dir [file join $out_dir generated_ip gtwizard_0]
    set prop_report [file join $out_dir gtwizard_10g_selected_properties.txt]
    set log_report [file join $out_dir gtwizard_10g_generation_summary.txt]
    set example_dir [file join $out_dir example_design]

    file mkdir $out_dir
    file mkdir $copied_ip_dir
    file copy -force $source_xci $copied_xci
    patch_xci_output_dir $copied_xci $gen_dir

    if {[file exists $work_dir]} {
        file delete -force $work_dir
    }
    if {[file exists $gen_dir]} {
        file delete -force $gen_dir
    }
    file mkdir $work_dir

    create_project gt_10g_qpll_$name $work_dir -part xc7z100ffg900-2 -force
    add_files -norecurse $copied_xci

    set ip [get_ips -quiet gtwizard_0]
    if {[llength $ip] != 1} {
        fail "Expected one gtwizard_0 IP in isolated project $name; got '$ip'"
    }

    set set_log {}
    set set_ok 1
    foreach {prop value} [list \
        CONFIG.identical_val_tx_line_rate 10.0 \
        CONFIG.identical_val_tx_reference_clock $refclk_mhz \
        CONFIG.identical_val_rx_reference_clock $refclk_mhz \
        CONFIG.gt0_val_tx_line_rate       10.0 \
        CONFIG.gt0_val_rx_line_rate       10.0 \
        CONFIG.gt_val_tx_pll              QPLL \
        CONFIG.gt0_val_tx_reference_clock $refclk_mhz \
        CONFIG.gt0_val_rx_reference_clock $refclk_mhz \
        CONFIG.gt0_val_tx_data_width      64 \
        CONFIG.gt0_val_encoding           None \
        CONFIG.gt0_val_tx_int_datawidth   32 \
        CONFIG.gt0_val_qpll_refclk_div    1 \
        CONFIG.gt0_val_qpll_fbdiv         $qpll_fbdiv \
        CONFIG.gt0_val_cpll_txout_div     1 \
        CONFIG.gt0_val_cpll_rxout_div     1 \
        CONFIG.gt0_val_tx_refclk          REFCLK0_Q0 \
        CONFIG.gt0_val_txusrclk           TXOUTCLK \
        CONFIG.gt0_val_port_txsysclksel   true \
        CONFIG.gt0_val_port_qpllpd        true \
    ] {
        if {![safe_set_ip_property $ip $prop $value set_log]} {
            set set_ok 0
        }
    }

    if {!$set_ok} {
        set fh [open $log_report w]
        puts $fh $set_log
        close $fh
        puts stderr "ERROR: One or more 10G QPLL properties could not be set for $name. See $log_report"
        return 0
    }

    set gen_ok 1
    if {[catch {generate_target all $ip} gen_err]} {
        append set_log "FAILED generate_target all: $gen_err\n"
        set gen_ok 0
    } else {
        append set_log "OK generate_target all\n"
    }

    if {$gen_ok} {
        if {[catch {export_ip_user_files -of_objects $ip -no_script -sync -force -quiet} export_err]} {
            append set_log "WARNING export_ip_user_files failed: $export_err\n"
        }
        if {[catch {open_example_project -force -dir $example_dir $ip} ex_err]} {
            append set_log "WARNING open_example_project failed: $ex_err\n"
        } else {
            append set_log "OK open_example_project: $example_dir\n"
        }
    }

    set selected_props {
        identical_val_tx_line_rate
        identical_val_tx_reference_clock
        identical_val_rx_reference_clock
        gt_val_tx_pll
        gt_val_tx_qpll
        gt_val_rx_qpll
        gt0_val_tx_refclk
        gt0_val_tx_line_rate
        gt0_val_rx_line_rate
        gt0_val_tx_data_width
        gt0_val_encoding
        gt0_val_tx_int_datawidth
        gt0_val_tx_reference_clock
        gt0_val_rx_reference_clock
        gt0_val_qpll_refclk_div
        gt0_val_qpll_fbdiv
        gt0_val_cpll_txout_div
        gt0_val_drp
        gt0_val_drp_clock
        gt0_val_txusrclk
        gt0_val_txoutclk_source
        gt0_val_port_txsysclksel
        gt0_val_port_cpllpd
        gt0_val_port_qpllpd
    }
    report_ip_properties $ip $prop_report $selected_props

    set fh [open $log_report w]
    puts $fh $set_log
    puts $fh "Source XCI: $source_xci"
    puts $fh "Copied XCI: $copied_xci"
    puts $fh "Selected property report: $prop_report"
    puts $fh "Vivado work dir: $work_dir"
    puts $fh "Example design dir: $example_dir"
    close $fh

    puts "INFO: 10G QPLL comparison $name finished; generate_ok=$gen_ok"
    puts "INFO: $prop_report"
    puts "INFO: $log_report"
    return $gen_ok
}

if {![file exists $source_xci]} {
    fail "Source Profile 0 XCI not found: $source_xci"
}

file mkdir $out_root
set ok125 [create_one_compare $source_xci $out_root "10g_125m_qpll_n80" "125.000" "80"]
set ok156 [create_one_compare $source_xci $out_root "10g_156p25m_qpll_n64" "156.250" "64"]

if {!$ok125 || !$ok156} {
    fail "One or more 10G QPLL comparison packages failed. 125M=$ok125 156p25M=$ok156"
}

puts "INFO: Both 10G QPLL comparison packages generated successfully."
