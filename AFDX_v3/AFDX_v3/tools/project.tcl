# Existing V3 project registration and optional validation, no board/bitstream.
# vivado -mode batch -source tools/project.tcl -tclargs configure|simulate|synthesize [tb]
# Vivado 2018.3 Tcl misnormalizes Documents under host sandboxing. Keep the
# absolute, lexical script path instead of resolving it through file normalize.
set script_path [info script]
if {[file pathtype $script_path] ne "absolute"} {set script_path [file join [pwd] $script_path]}
set root [file dirname [file dirname $script_path]]
set mode [lindex $argv 0]
if {$mode eq ""} {set mode configure}
if {$mode ni {configure simulate synthesize}} {error "Unsupported mode: $mode"}
set top [lindex $argv 1]
if {$top eq ""} {set top tb_afdx_end_system}
set project_file [file join $root AFDX_v3.xpr]
set out [file join $root artifacts]
file mkdir $out
set backup [file join $out project_before_migration.xpr]
if {![file exists $backup]} {file copy $project_file $backup}
open_project $project_file
# Remove registrations for sources explicitly removed from the V3 baseline.
foreach obsolete {afdx_es_multivl_top.v afdx_vl_queue.v afdx_vl_csr.v tb_afdx_vl_csr.v} {
    set registered [get_files -quiet */$obsolete]
    if {[llength $registered] != 0} {remove_files $registered}
}
set rtl [lsort [glob [file join $root AFDX_v3.srcs sources_1 new *.v]]]
set tests [lsort [glob [file join $root AFDX_v3.srcs sim_1 new *.v]]]
foreach source $rtl {
    if {[llength [get_files -quiet $source]] == 0} {add_files -fileset sources_1 -norecurse $source}
}
foreach source $tests {
    if {[llength [get_files -quiet $source]] == 0} {add_files -fileset sim_1 -norecurse $source}
}
set constraint [file join $root constraints mac_stream_80ns.xdc]
if {[llength [get_files -quiet $constraint]] == 0} {add_files -fileset constrs_1 $constraint}
set_property top AFDX_top [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
set_property top $top [get_filesets sim_1]
set_property top_auto_set false [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
if {$mode eq "simulate"} {
    # This validation mode uses XSim regardless of the user's saved simulator.
    set saved_simulator [get_property target_simulator [current_project]]
    set_property target_simulator XSim [current_project]
    launch_simulation
    close_sim
    set_property target_simulator $saved_simulator [current_project]
    set log [file join $root AFDX_v3.sim sim_1 behav xsim simulate.log]
    file copy -force $log [file join $out xsim_${top}.log]
    set fp [open $log r];set text [read $fp];close $fp
    if {![string match {*PASSED*} $text] || [regexp -nocase {FATAL|TIMEOUT|FAILED} $text]} {error "V3 XSim self-check failed"}
    puts "V3 XSIM PASSED: $top"
}
if {$mode eq "synthesize"} {
    reset_run synth_1
    launch_runs synth_1 -jobs 2
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "V3 synthesis did not complete"}
    open_run synth_1
    report_utilization -file [file join $out v3_utilization.rpt]
    report_timing_summary -file [file join $out v3_timing.rpt]
    write_checkpoint -force [file join $out v3_synth.dcp]
    puts "V3 SYNTHESIS PASSED"
}
close_project
puts "V3 PROJECT CONFIGURED: AFDX_top / $top"
exit 0
