open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
puts "SOURCE_MGMT=[get_property source_mgmt_mode [current_project]]"
puts "FS_TOP=[get_property top [get_filesets sources_1]]"
foreach p [lsort [list_property [get_filesets sources_1]]] {
    if {[string match -nocase *top* $p] || [string match -nocase *auto* $p]} {
        catch {puts "$p=[get_property $p [get_filesets sources_1]]"}
    }
}
puts "TOP_FILES_BEFORE"
foreach f [get_files -of_objects [get_filesets sources_1] -filter {NAME =~ *laser_tx_board_top.v || NAME =~ *system_wrapper.v || NAME =~ *laser_gt_tx_profile0.v}] { puts $f }
update_compile_order -fileset sources_1
puts "FS_TOP_AFTER_UPDATE=[get_property top [get_filesets sources_1]]"
close_project
