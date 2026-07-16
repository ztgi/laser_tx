# Create and build the runtime-rate bringup application in the clean workspace.

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set workspace [file join $project_dir reports runtime_rate_vitis]
set source_dir [file join $project_dir vitis_bringup bringup src]
set platform_name runtime_rate_artifact_platform
set domain_name standalone_ps7_cortexa9_0
set app_name bringup

if {![file isdirectory $workspace]} {
    error "Clean Vitis workspace is missing: $workspace"
}
if {![file isdirectory $source_dir]} {
    error "Bringup source directory is missing: $source_dir"
}

set c_sources [glob -nocomplain -directory $source_dir *.c]
if {[llength $c_sources] != 16} {
    error "Expected 16 managed C sources, found [llength $c_sources]"
}

setws $workspace
platform active $platform_name
domain active $domain_name

if {[file exists [file join $workspace $app_name]]} {
    error "Refusing to overwrite existing managed application: [file join $workspace $app_name]"
}

app create -name $app_name -platform $platform_name -domain $domain_name \
    -template {Empty Application(C)}
importsources -name $app_name -path $source_dir
app clean -name $app_name
app build -name $app_name

puts "RUNTIME_RATE_VITIS_APP=PASS"
puts "workspace=$workspace"
puts "application=$app_name"
puts "managed_c_sources=[llength $c_sources]"
