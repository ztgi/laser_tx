open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
open_run impl_1

puts "=== report_debug_core help ==="
catch {report_debug_core -help} rc
puts $rc

puts "=== debug_port properties ==="
set p [get_debug_ports -quiet dbg_hub/clk]
puts "PORT=$p"
if {[llength $p] > 0} {
    puts "PROPERTIES=[list_property [lindex $p 0]]"
    foreach prop [list_property [lindex $p 0]] {
        catch {puts "$prop=[get_property $prop [lindex $p 0]]"}
    }
}

puts "=== debug core properties ==="
foreach c [get_debug_cores -quiet] {
    puts "CORE=$c"
    puts "PROPERTIES=[list_property $c]"
    foreach prop [list_property $c] {
        if {[regexp {CLK|CLOCK|PORT|NET|NAME|CELL|FREQ|USER|SCAN} $prop]} {
            catch {puts "  $prop=[get_property $prop $c]"}
        }
    }
}

close_project
