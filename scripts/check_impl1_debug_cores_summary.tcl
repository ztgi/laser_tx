open_project ./laser_tx.xpr
open_run impl_1

set debug_cores [get_debug_cores -quiet]
puts "DEBUG_CORE_COUNT=[llength $debug_cores]"
foreach c $debug_cores {
    puts "DEBUG_CORE=$c"
}

set top_ila_cells [get_cells -hier -quiet -filter {NAME =~ "*ila_laser*"}]
puts "TOP_ILA_RELATED_CELL_COUNT=[llength $top_ila_cells]"
set shown 0
foreach c $top_ila_cells {
    if {$shown < 20} {
        puts "ILA_RELATED_CELL=$c"
    }
    incr shown
}

set dbg_hub_cells [get_cells -hier -quiet -filter {NAME =~ "*dbg_hub*"}]
puts "DBG_HUB_CELL_COUNT=[llength $dbg_hub_cells]"
set shown 0
foreach c $dbg_hub_cells {
    if {$shown < 20} {
        puts "DBG_HUB_CELL=$c"
    }
    incr shown
}

close_project
