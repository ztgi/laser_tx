set project_path "D:/FPGA_Learn/laser_tx/laser_tx.xpr"
set report_dir "D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/gt_profile0_clock_query"
file mkdir $report_dir

proc write_list {path values} {
    set fp [open $path w]
    foreach v $values {
        puts $fp $v
    }
    close $fp
}

proc dump_clock_objects {label objects fp} {
    puts $fp "===== $label ====="
    puts $fp "objects=$objects"
    set clocks [get_clocks -quiet -of_objects $objects]
    puts $fp "clocks=$clocks"
    foreach c $clocks {
        puts $fp "clock=$c PERIOD=[get_property PERIOD $c] SOURCE_PINS=[get_property SOURCE_PINS $c] MASTER_CLOCK=[get_property MASTER_CLOCK $c]"
    }
    puts $fp ""
}

open_project $project_path

set fs [get_filesets sources_1]
set_property source_mgmt_mode All [current_project]
set_property top laser_tx_board_top $fs
set_property top_file D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v $fs
update_compile_order -fileset sources_1

# Open the completed synthesis result instead of calling link_design directly
# from the active project sources_1 fileset. This is read-only and avoids the
# Vivado project error:
# "The RTL fileset 'sources_1' is being used by an active synthesis run".
open_run synth_1 -name gt_profile0_clock_query_synth

set fp [open "$report_dir/link_design_clock_query.txt" w]
puts $fp "all_clocks=[get_clocks]"
puts $fp ""

puts $fp "===== get_clocks detail ====="
foreach c [get_clocks] {
    puts $fp "clock=$c PERIOD=[get_property PERIOD $c] SOURCE_PINS=[get_property SOURCE_PINS $c] MASTER_CLOCK=[get_property MASTER_CLOCK $c]"
}
puts $fp ""

set gt_ctrl_nets [get_nets -hier -quiet *gt_ctrl_clk*]
set clk_fpga_nets [get_nets -hier -quiet *clk_fpga_0*]
set fclk_pins [get_pins -hier -quiet *FCLK_CLK0*]

puts $fp "get_nets -hier *gt_ctrl_clk* = $gt_ctrl_nets"
puts $fp "get_nets -hier *clk_fpga_0* = $clk_fpga_nets"
puts $fp "get_pins -hier *FCLK_CLK0* = $fclk_pins"
puts $fp ""

dump_clock_objects "clocks of gt_ctrl_clk nets" $gt_ctrl_nets $fp
dump_clock_objects "clocks of clk_fpga_0 nets" $clk_fpga_nets $fp
dump_clock_objects "clocks of FCLK_CLK0 pins" $fclk_pins $fp

puts $fp "===== name matched clocks ====="
puts $fp "get_clocks *clk_fpga_0* = [get_clocks -quiet *clk_fpga_0*]"
puts $fp "get_clocks *FCLK_CLK0* = [get_clocks -quiet *FCLK_CLK0*]"
puts $fp "get_clocks *gt_ctrl_clk* = [get_clocks -quiet *gt_ctrl_clk*]"
close $fp

report_clocks -file "$report_dir/report_clocks_after_open_synth.rpt"

puts "clock_query_report=$report_dir/link_design_clock_query.txt"
puts "report_clocks=$report_dir/report_clocks_after_open_synth.rpt"
close_project
