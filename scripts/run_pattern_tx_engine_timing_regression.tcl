set repo_root [file normalize [file join [file dirname [info script]] ..]]
set sim_dir [file join $repo_root reports ad9528_gt_rate_planner pattern_tx_engine_sim]
file mkdir $sim_dir
cd $sim_dir

set rtl [file join $repo_root laser_tx.srcs sources_1 new laser_tx_core pattern_tx_engine.v]
set tb  [file join $repo_root laser_tx.srcs sim_1 new tb_pattern_tx_engine_timing.sv]

exec xvlog.bat -sv $rtl $tb >@stdout 2>@stderr
exec xelab.bat -debug typical -top tb_pattern_tx_engine_timing -snapshot pattern_tx_engine_timing_sim >@stdout 2>@stderr
exec xsim.bat pattern_tx_engine_timing_sim -runall >@stdout 2>@stderr
