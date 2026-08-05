# Manage the checked-in GT Wizard profile locally.  The XCI under this
# repository is the only parameter source; no reference project or external
# generated HDL is copied into the production compile order.

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set project_file [file join $project_dir laser_tx.xpr]
set local_ip_dir [file join $project_dir laser_tx.srcs sources_1 ip gtwizard_0]
set local_xci [file join $local_ip_dir gtwizard_0.xci]
set adapter_rtl [file join $project_dir laser_tx.srcs sources_1 new laser_gt_tx_profile0.v]
set usrclk_rtl [file join $project_dir laser_tx.srcs sources_1 new laser_gt_usrclk_profile0.v]
set profile_xdc [file join $project_dir constraints laser_tx_gt_profile0.xdc]

proc gt_fail {message} {
    puts stderr "ERROR: $message"
    return -code error $message
}

if {![file exists $project_file]} { gt_fail "Project not found: $project_file" }
if {![file exists $local_xci]} { gt_fail "Local GT Wizard XCI not found: $local_xci" }
if {![file exists $adapter_rtl]} { gt_fail "GT adapter RTL not found: $adapter_rtl" }
if {![file exists $usrclk_rtl]} { gt_fail "GT user clock RTL not found: $usrclk_rtl" }
if {![file exists $profile_xdc]} { gt_fail "GT profile XDC not found: $profile_xdc" }

if {[llength [get_projects -quiet]] == 0} { open_project $project_file }

file mkdir $local_ip_dir

set xci_fh [open $local_xci r]
set xci_text [read $xci_fh]
close $xci_fh
set original_xci_text $xci_text
set expected_gen_dir "\"gen_directory\": \"../../../../laser_tx.gen/sources_1/ip/gtwizard_0\""
if {[string first $expected_gen_dir $xci_text] < 0} {
    regsub {"gen_directory": "[^"]+"} $xci_text $expected_gen_dir xci_text
}
set expected_output_dir "\"OUTPUTDIR\": \[ \{ \"value\": \"../../../../laser_tx.gen/sources_1/ip/gtwizard_0\" \} \]"
if {[regexp {"OUTPUTDIR": \[ \{ "value": "[^"]+" \} \]} $xci_text]} {
    regsub {"OUTPUTDIR": \[ \{ "value": "[^"]+" \} \]} $xci_text $expected_output_dir xci_text
}
if {[string first $expected_gen_dir $xci_text] < 0 || \
    [string first "../../../../project_gtx.gen" $xci_text] >= 0} {
    gt_fail "Could not sanitize GT Wizard XCI output paths."
}
if {$xci_text ne $original_xci_text} {
    set xci_fh [open $local_xci w]
    puts -nonewline $xci_fh $xci_text
    close $xci_fh
    puts "INFO: Repointed GT Wizard gen_directory to laser_tx.gen."
}

if {![llength [get_files -quiet $local_xci]]} {
    add_files -norecurse $local_xci
}
if {![llength [get_files -quiet $adapter_rtl]]} {
    add_files -norecurse $adapter_rtl
}
if {![llength [get_files -quiet $usrclk_rtl]]} {
    add_files -norecurse $usrclk_rtl
}
if {![llength [get_files -quiet $profile_xdc]]} {
    add_files -fileset constrs_1 -norecurse $profile_xdc
}

set ip [get_ips -quiet gtwizard_0]
if {[llength $ip] != 1} { gt_fail "Expected exactly one local gtwizard_0 IP; found: $ip" }
generate_target all $ip
export_ip_user_files -of_objects $ip -no_script -sync -force -quiet
update_compile_order -fileset sources_1
puts "INFO: GT Wizard profile 0 is generated.  Next run bd_connect_laser_tx_core.tcl and regenerate the HDL wrapper."
