#=============================================================================
# run_simulation.tcl — Vivado Simulator Script
#
# Usage:
#   vivado -mode batch -source run_simulation.tcl
#
# Or in Vivado GUI: Tools → Run Simulation → Run Behavioral Simulation
#=============================================================================

set project_name "fm_dmb_repeater"
set project_dir  "D:/github/FM_DMB_Repeator/fpga/vivado"

# Open project
open_project "${project_dir}/${project_name}.xpr" -quiet

#=============================================================================
# Simulation settings
#=============================================================================
set_property -name {xsim.simulate.runtime} -value {5ms} -objects [get_filesets sim_1]
set_property -name {xsim.simulate.xsim.elaborate.debug_level} -value {all} \
    -objects [get_filesets sim_1]

set_property -name {xsim.elaborate.xelab.mt_level} -value {4} \
    -objects [get_filesets sim_1]
set_property -name {xsim.elaborate.xelab.rangecheck} -value {true} \
    -objects [get_filesets sim_1]
set_property -name {xsim.elaborate.xelab.relax} -value {true} \
    -objects [get_filesets sim_1]

#=============================================================================
# Run simulation
#=============================================================================
puts "=== Starting Behavioral Simulation ==="

# Relaunch simulation
launch_simulation -simset sim_1 -mode behavioral

# Wait for simulation to complete
run all

puts "=== Simulation Complete ==="
puts "Waveform: ${project_dir}/${project_name}.sim/sim_1/behav/xsim/wave.wdb"

# Save waveform config for subsequent viewing
write_wavecfg -file "${project_dir}/sim_wave.wcfg"

# Close simulation
stop

close_project
puts "=== Done ==="
