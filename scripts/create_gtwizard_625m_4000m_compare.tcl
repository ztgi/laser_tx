# Create isolated 625M and 4000M CPLL GT Wizard parameter packages.
#
# This script never opens laser_tx.xpr. It copies the existing GT Wizard XCI
# into reports/cpll_candidate_parameter_compare/, creates throw-away projects,
# and generates HDL/example designs for parameter extraction only.

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set source_xci [file join $project_dir laser_tx.srcs sources_1 ip gtwizard_0 gtwizard_0.xci]
set out_root [file join $project_dir reports cpll_candidate_parameter_compare]

proc fail {msg} {
    puts stderr "ERROR: $msg"
    return -code error $msg
}

proc patch_xci_output_dir {xci_path gen_dir} {
    set gen_dir_norm [string map {\\ /} [file normalize $gen_dir]]
    set fh [open $xci_path r]
    set text [read $fh]
    close $fh
    regsub {"gen_directory": "[^"]+"} $text "\"gen_directory\": \"$gen_dir_norm\"" text
    if {[regexp {"OUTPUTDIR": \[ \{ "value": "[^"]+" \} \]} $text]} {
        regsub {"OUTPUTDIR": \[ \{ "value": "[^"]+" \} \]} $text "\"OUTPUTDIR\": \[ \{ \"value\": \"$gen_dir_norm\" \} \]" text
    }
    set fh [open $xci_path w]
    puts -nonewline $fh $text
    close $fh
}

proc set_checked {ip prop value log_var} {
    upvar $log_var log
    if {[catch {set_property $prop $value $ip} err]} {
        append log "FAILED set_property $prop $value: $err\n"
        return 0
    }
    append log "OK set_property $prop $value\n"
    return 1
}

proc emit_property_dump {ip path label} {
    set properties {
        identical_val_tx_line_rate
        identical_val_tx_reference_clock
        gt_val_tx_pll
        gt0_val_no_rx
        gt0_val_tx_line_rate
        gt0_val_tx_reference_clock
        gt0_val_tx_data_width
        gt0_val_tx_int_datawidth
        gt0_val_encoding
        gt0_val_cpll_refclk_div
        gt0_val_cpll_fbdiv_45
        gt0_val_cpll_fbdiv
        gt0_val_cpll_txout_div
        gt0_val_txusrclk
        gt0_val_txoutclk_source
        gt0_val_port_txsysclksel
        gt0_val_port_cpllpd
        gt0_val_port_qpllpd
    }
    set fh [open $path w]
    puts $fh "# Selected GT Wizard properties: $label"
    puts $fh "# Isolated package only; not added to laser_tx.xpr"
    foreach prop $properties {
        if {[catch {set value [get_property CONFIG.$prop $ip]} err]} {
            puts $fh "$prop = <unavailable: $err>"
        } else {
            puts $fh "$prop = $value"
        }
    }
    close $fh
}

proc create_compare {source_xci out_root label line_rate txout_div cpll_n1 cpll_n2} {
    set out_dir [file join $out_root $label]
    set work_dir [file join $out_dir vivado_work]
    set copied_dir [file join $out_dir copied_ip]
    set copied_xci [file join $copied_dir gtwizard_0.xci]
    set generated_dir [file join $out_dir generated_ip gtwizard_0]
    set example_dir [file join $out_dir example_design]
    set property_dump [file join $out_dir selected_properties.txt]
    set summary [file join $out_dir generation_summary.txt]

    file mkdir $out_dir
    file mkdir $copied_dir
    file copy -force $source_xci $copied_xci
    patch_xci_output_dir $copied_xci $generated_dir
    foreach dir [list $work_dir $generated_dir $example_dir] {
        if {[file exists $dir]} { file delete -force $dir }
    }
    file mkdir $work_dir

    create_project cpll_candidate_$label $work_dir -part xc7z100ffg900-2 -force
    add_files -norecurse $copied_xci
    set ip [get_ips -quiet gtwizard_0]
    if {[llength $ip] != 1} {
        fail "Expected one gtwizard_0 in $label package; got '$ip'"
    }

    set log {}
    set ok 1
    foreach {prop value} [list \
        CONFIG.identical_config                 false \
        CONFIG.gt0_val_no_rx                    true \
        CONFIG.gt_val_tx_pll                    CPLL \
        CONFIG.gt0_val_tx_line_rate             $line_rate \
        CONFIG.gt0_val_tx_reference_clock       125.000 \
        CONFIG.gt0_val_tx_data_width            64 \
        CONFIG.gt0_val_tx_int_datawidth         32 \
        CONFIG.gt0_val_encoding                 None \
        CONFIG.gt0_val_cpll_refclk_div          1 \
        CONFIG.gt0_val_cpll_fbdiv_45            $cpll_n1 \
        CONFIG.gt0_val_cpll_fbdiv               $cpll_n2 \
        CONFIG.gt0_val_cpll_txout_div           $txout_div \
        CONFIG.gt0_val_txusrclk                 TXOUTCLK \
        CONFIG.gt0_val_port_txsysclksel         true \
    ] {
        if {![set_checked $ip $prop $value log]} { set ok 0 }
    }
    if {!$ok} {
        set fh [open $summary w]
        puts $fh $log
        close $fh
        fail "$label property setup failed; see $summary"
    }

    if {[catch {generate_target all $ip} err]} {
        append log "FAILED generate_target all: $err\n"
        set fh [open $summary w]
        puts $fh $log
        close $fh
        fail "$label generate_target failed; see $summary"
    }
    append log "OK generate_target all\n"
    if {[catch {export_ip_user_files -of_objects $ip -no_script -sync -force -quiet} err]} {
        append log "WARNING export_ip_user_files failed: $err\n"
    }
    emit_property_dump $ip $property_dump $label
    if {[catch {open_example_project -force -dir $example_dir $ip} err]} {
        append log "WARNING open_example_project failed: $err\n"
    } else {
        append log "OK open_example_project $example_dir\n"
    }
    set fh [open $summary w]
    puts $fh $log
    puts $fh "source_xci = $source_xci"
    puts $fh "copied_xci = $copied_xci"
    puts $fh "property_dump = $property_dump"
    puts $fh "generated_dir = $generated_dir"
    puts $fh "example_dir = $example_dir"
    close $fh
    puts "INFO: completed isolated package $label"
}

if {![file exists $source_xci]} { fail "Source XCI not found: $source_xci" }
file mkdir $out_root
create_compare $source_xci $out_root 625m_125m_cpll 0.625 8 4 5
create_compare $source_xci $out_root 4000m_125m_cpll 4.000 1 4 4
puts "INFO: all isolated CPLL candidate packages completed"
