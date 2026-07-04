open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
set f D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v
puts "FILE=$f"
foreach p [lsort [list_property [get_files $f]]] {
  if {[string match -nocase *enable* $p] || [string match -nocase *disable* $p] || [string match -nocase *auto* $p] || [string match -nocase *used* $p]} {
    catch {puts "$p=[get_property $p [get_files $f]]"}
  }
}
close_project
