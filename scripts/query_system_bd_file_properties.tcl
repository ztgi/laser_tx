open_project "D:/FPGA_Learn/laser_tx/laser_tx.xpr"
set f [get_files -quiet "D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/bd/system/system.bd"]
puts "system_bd_file=$f"
if {[llength $f] > 0} {
    foreach p [lsort [list_property $f]] {
        if {[regexp -nocase {USED|ENABLE|AUTO|FILE_TYPE|IS_} $p]} {
            catch {puts "$p=[get_property $p $f]"}
        }
    }
}
close_project
