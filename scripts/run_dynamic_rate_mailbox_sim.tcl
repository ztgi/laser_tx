set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root reports dynamic_rate_mailbox_sim]
file mkdir $out
set sources [list \
    [file join $root rtl laser_dynamic_rate_descriptor_reader.v] \
    [file join $root rtl laser_dynamic_rate_mailbox.v] \
    [file join $root rtl tb laser_dynamic_rate_mailbox_tb.sv]]
exec xvlog.bat -sv -i [file join $root rtl] {*}$sources >@stdout 2>@stderr
exec xelab.bat laser_dynamic_rate_mailbox_tb -s mailbox_sim >@stdout 2>@stderr
exec xsim.bat mailbox_sim -runall >@stdout 2>@stderr
