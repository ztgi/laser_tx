set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root reports tx_sequence_v2_sim]
file mkdir $out
cd $out
set core [file join $root laser_tx.srcs sources_1 new laser_tx_core]
exec xvlog.bat -sv [file join $core pattern_tx_engine.v] [file join $root laser_tx.srcs sim_1 new tb_pattern_tx_engine_timing.sv] >@stdout 2>@stderr
exec xelab.bat -top tb_pattern_tx_engine_timing -snapshot txseq_engine >@stdout 2>@stderr
exec xsim.bat txseq_engine -runall >@stdout 2>@stderr
exec xvlog.bat -sv [file join $core tx_eom_geometry_precompute.v] [file join $core tx_eom_window_generator.v] [file join $core pattern_tx_engine.v] [file join $root laser_tx.srcs sim_1 new tb_tx_eom_v2.sv] >@stdout 2>@stderr
exec xelab.bat -top tb_tx_eom_v2 -snapshot txseq_eom >@stdout 2>@stderr
exec xsim.bat txseq_eom -runall >@stdout 2>@stderr
exec xvlog.bat -sv [file join $core config_loader.v] [file join $root laser_tx.srcs sim_1 new tb_config_loader_v2.sv] >@stdout 2>@stderr
exec xelab.bat -top tb_config_loader_v2 -snapshot txseq_loader >@stdout 2>@stderr
exec xsim.bat txseq_loader -runall >@stdout 2>@stderr
# Compile the complete production core inventory so internal interface changes
# cannot pass the focused testbenches while leaving laser_tx_core stale.
exec xvlog.bat -sv \
    [file join $core cdc_toggle_sync.v] \
    [file join $core config_loader.v] \
    [file join $core pattern_source.v] \
    [file join $core pattern_tx_engine.v] \
    [file join $core sync_signal_gen.v] \
    [file join $core status_register.v] \
    [file join $core tx_eom_geometry_precompute.v] \
    [file join $core tx_eom_window_generator.v] \
    [file join $core laser_tx_core.v] >@stdout 2>@stderr