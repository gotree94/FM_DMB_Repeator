#=============================================================================
# run_synthesis.tcl — Vivado Batch Synthesis Script
#
# Usage:
#   vivado -mode batch -source run_synthesis.tcl
#
# Prerequisites:
#   Run create_project.tcl first to create the project.
#=============================================================================

set project_name "fm_dmb_repeater"
set project_dir  "D:/github/FM_DMB_Repeator/fpga/vivado"

# Open existing project
open_project "${project_dir}/${project_name}.xpr" -quiet

puts "=== Starting Synthesis ==="

# Launch synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check results
set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: ${synth_status}"

if {[string match "*synth*Complete*" $synth_status]} {
    puts "=== Synthesis PASSED ==="

    # Open synthesized design for timing analysis
    open_run synth_1 -name synth_1

    # Report timing summary
    report_timing_summary -file "${project_dir}/reports/timing_summary_synth.rpt"
    puts "Timing summary: ${project_dir}/reports/timing_summary_synth.rpt"

    # Report resource utilization
    report_utilization -file "${project_dir}/reports/utilization_synth.rpt"
    puts "Utilization: ${project_dir}/reports/utilization_synth.rpt"

    # Report clock interaction
    report_clock_interaction -file "${project_dir}/reports/clock_interaction.rpt"

    # Launch implementation
    puts "=== Starting Implementation ==="
    launch_runs impl_1 -jobs 4
    wait_on_run impl_1

    set impl_status [get_property STATUS [get_runs impl_1]]
    puts "Implementation status: ${impl_status}"

    if {[string match "*route*Complete*" $impl_status]} {
        # Open implemented design
        open_run impl_1

        # Final timing report
        report_timing_summary -file "${project_dir}/reports/timing_summary_impl.rpt"
        report_utilization -file "${project_dir}/reports/utilization_impl.rpt"
        report_power -file "${project_dir}/reports/power_impl.rpt"

        # Generate bitstream
        puts "=== Generating Bitstream ==="
        launch_runs impl_1 -to_step BitGen -jobs 4
        wait_on_run impl_1

        puts "=== Bitstream generated ==="
        puts "Bit file: ${project_dir}/${project_name}.runs/impl_1/${project_name}.bit"
    } else {
        puts "=== Implementation FAILED ==="
    }
} else {
    puts "=== Synthesis FAILED ==="
    puts "Check ${project_dir}/vivado.log for details"
}

close_project
puts "=== Done ==="
