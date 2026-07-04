# 1000M Profile1 static ILA/debug self-check.
# This script is intentionally read-only for the programmed FPGA:
# - it does not program FPGA;
# - it does not modify RTL/BD/XDC/Vitis;
# - it only refreshes hardware probes, lists ILAs, then tries trigger_now + upload.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize [file join $script_dir ".."]]
set out_dir    [file normalize [file join $repo_dir "reports" "gt_profile1_1000m_static" "ila_debug_check"]]
file mkdir $out_dir

set bit_path [file normalize [file join $repo_dir "reports" "gt_profile1_1000m_static" "artifacts" "laser_tx_board_top_profile1_1000m.bit"]]
set ltx_path [file normalize [file join $repo_dir "reports" "gt_profile1_1000m_static" "artifacts" "laser_tx_board_top_profile1_1000m.ltx"]]
set log_path [file normalize [file join $out_dir "check_1000m_ila_debug.log"]]

set log_fh [open $log_path "w"]
proc log_puts {msg} {
    global log_fh
    puts $msg
    puts $log_fh $msg
    flush $log_fh
}

proc safe_property {obj prop} {
    if {[catch {set value [get_property $prop $obj]} err]} {
        return "<property $prop unavailable: $err>"
    }
    if {$value eq ""} {
        return "<empty>"
    }
    return $value
}

proc probe_list_for_ila {ila} {
    if {[catch {set probes [get_hw_probes -quiet -of_objects $ila]} err]} {
        return [list]
    }
    return $probes
}

proc test_ila_upload {ila} {
    set ila_name [safe_property $ila NAME]
    log_puts "==== TRIGGER/UPLOAD TEST: $ila_name ===="

    if {[catch {run_hw_ila -trigger_now $ila} err]} {
        log_puts "RESULT $ila_name: run_hw_ila failed: $err"
        return "run_failed"
    }

    if {[catch {wait_on_hw_ila $ila} err]} {
        log_puts "RESULT $ila_name: wait_on_hw_ila failed/timeout: $err"
        return "wait_failed_or_timeout"
    }

    if {[catch {set data_obj [upload_hw_ila_data $ila]} err]} {
        log_puts "RESULT $ila_name: upload failed/corrupted: $err"
        return "upload_failed_or_corrupted"
    }

    log_puts "UPLOAD_DATA_OBJECT $ila_name: $data_obj"

    if {[catch {display_hw_ila_data $data_obj} err]} {
        log_puts "DISPLAY_DATA $ila_name: display failed/skipped: $err"
    } else {
        log_puts "DISPLAY_DATA $ila_name: OK"
    }

    return "upload_ok"
}

log_puts "==== 1000M PROFILE1 ILA DEBUG SELF-CHECK ===="
log_puts "BIT_EXPECTED = $bit_path"
log_puts "LTX_EXPECTED = $ltx_path"
log_puts "BIT_EXISTS   = [file exists $bit_path]"
log_puts "LTX_EXISTS   = [file exists $ltx_path]"
if {[file exists $bit_path]} {
    log_puts "BIT_MTIME    = [clock format [file mtime $bit_path] -format {%Y-%m-%d %H:%M:%S}]"
    log_puts "BIT_SIZE     = [file size $bit_path]"
}
if {[file exists $ltx_path]} {
    log_puts "LTX_MTIME    = [clock format [file mtime $ltx_path] -format {%Y-%m-%d %H:%M:%S}]"
    log_puts "LTX_SIZE     = [file size $ltx_path]"
}

if {[catch {open_hw_manager} err]} {
    log_puts "ERROR open_hw_manager: $err"
    close $log_fh
    exit 1
}
if {[catch {connect_hw_server} err]} {
    log_puts "ERROR connect_hw_server: $err"
    close $log_fh
    exit 1
}
set targets [get_hw_targets -quiet]
log_puts "HW_TARGET_COUNT = [llength $targets]"
foreach t $targets {
    log_puts "HW_TARGET = $t"
}
if {[llength $targets] == 0} {
    log_puts "ERROR: no hw_target found after connect_hw_server."
    close $log_fh
    exit 1
}
current_hw_target [lindex $targets 0]
if {[catch {open_hw_target [current_hw_target]} err]} {
    log_puts "ERROR open_hw_target: $err"
    close $log_fh
    exit 1
}

set devs [get_hw_devices -quiet *xc7z100*]
if {[llength $devs] == 0} {
    set devs [get_hw_devices -quiet]
}
if {[llength $devs] == 0} {
    log_puts "ERROR: no hardware device found."
    close $log_fh
    exit 1
}

set dev [lindex $devs 0]
current_hw_device $dev
log_puts "CURRENT_DEVICE = $dev"
log_puts "DEVICE_NAME    = [safe_property $dev NAME]"
log_puts "DEVICE_PART    = [safe_property $dev PART]"
log_puts "PROGRAM_FILE   = [safe_property $dev PROGRAM.FILE]"
log_puts "PROBES_FILE_BEFORE = [safe_property $dev PROBES.FILE]"

if {[file exists $ltx_path]} {
    if {[catch {set_property PROBES.FILE $ltx_path $dev} err]} {
        log_puts "WARNING: failed to set PROBES.FILE to expected LTX: $err"
    } else {
        log_puts "PROBES_FILE_SET_TO = $ltx_path"
    }
}

if {[catch {refresh_hw_device $dev} err]} {
    log_puts "ERROR refresh_hw_device: $err"
    close $log_fh
    exit 1
}

log_puts "PROBES_FILE_AFTER = [safe_property $dev PROBES.FILE]"
set ilas [get_hw_ilas -quiet]
log_puts "HARDWARE_MANAGER_ILA_COUNT = [llength $ilas]"

log_puts "==== ILA LIST ===="
foreach ila $ilas {
    log_puts "------------------------------"
    log_puts "ILA_OBJECT = $ila"
    log_puts "NAME       = [safe_property $ila NAME]"
    log_puts "CELL_NAME  = [safe_property $ila CELL_NAME]"
    log_puts "CORE_NAME  = [safe_property $ila CORE_NAME]"
    log_puts "CLASS      = [safe_property $ila CLASS]"
    log_puts "STATUS     = [safe_property $ila STATUS]"
    set probes [probe_list_for_ila $ila]
    log_puts "PROBE_CNT  = [llength $probes]"
    log_puts "PROBES:"
    foreach p $probes {
        log_puts "  $p | NAME=[safe_property $p NAME] | WIDTH=[safe_property $p PROBE_PORT_BIT_COUNT]"
    }
}

log_puts "==== TRIGGER_NOW + UPLOAD SUMMARY ===="
array set results {}
foreach ila $ilas {
    set ila_name [safe_property $ila NAME]
    set results($ila_name) [test_ila_upload $ila]
}

log_puts "==== FINAL SUMMARY ===="
foreach ila $ilas {
    set ila_name [safe_property $ila NAME]
    log_puts "$ila_name: $results($ila_name)"
}

log_puts "LOG_FILE = $log_path"
close $log_fh
