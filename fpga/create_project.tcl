#=============================================================================
# create_project.tcl — Vivado Project Creation Script
#
# Target: Xilinx Kintex-7 XC7K325T-2FFG900
# Design: FM/DMB Digital Repeater (40 FM + 6 DMB channels)
#
# Usage:
#   vivado -mode batch -source create_project.tcl
#   or in Vivado Tcl Console: source create_project.tcl
#=============================================================================

#---------------------------------------------------------------------------
# Project settings
#---------------------------------------------------------------------------
set project_name   "fm_dmb_repeater"
set project_dir    "D:/github/FM_DMB_Repeator/fpga/vivado"
set part_name      "xc7k325tffg900-2"
set rtl_dir        "D:/github/FM_DMB_Repeator/fpga/rtl"
set sim_dir        "D:/github/FM_DMB_Repeator/fpga/sim"
set constrs_dir    "D:/github/FM_DMB_Repeator/fpga/constrs"

#---------------------------------------------------------------------------
# Create project in memory first, then write to disk
#---------------------------------------------------------------------------
create_project -name $project_name -dir $project_dir -part $part_name -force

# Set project properties
set_property "default_lib"          "work"              [current_project]
set_property "simulator_language"   "Mixed"             [current_project]
set_property "target_language"      "Verilog"           [current_project]
set_property "ip_cache_repo"        "${project_dir}/ip_cache" [current_project]

#---------------------------------------------------------------------------
# Add RTL source files (Wave 1: Independent modules)
#---------------------------------------------------------------------------
read_verilog [list \
    "${rtl_dir}/clk_manager.v" \
    "${rtl_dir}/adc_interface.v" \
    "${rtl_dir}/dac_interface.v" \
    "${rtl_dir}/spi_slave.v" \
    "${rtl_dir}/uart_debug.v" \
    "${rtl_dir}/sys_monitor.v" \
]

# Wave 2: DSP core modules
read_verilog [list \
    "${rtl_dir}/ddc.v" \
    "${rtl_dir}/cic_decimation.v" \
    "${rtl_dir}/fir_filter.v" \
    "${rtl_dir}/isop.v" \
    "${rtl_dir}/agc.v" \
    "${rtl_dir}/duc.v" \
    "${rtl_dir}/channel_sum.v" \
]

# Wave 3: Integration modules
read_verilog [list \
    "${rtl_dir}/fm_channel.v" \
    "${rtl_dir}/dmb_channel.v" \
    "${rtl_dir}/repeater_top.v" \
]

puts "RTL sources added: 16 files"

#---------------------------------------------------------------------------
# Add constraint files
#---------------------------------------------------------------------------
if {[file exists "${constrs_dir}/repeater_top.xdc"]} {
    read_xdc "${constrs_dir}/repeater_top.xdc"
    puts "Constraint file added"
} else {
    puts "WARNING: Constraint file not found at ${constrs_dir}/repeater_top.xdc"
}

#---------------------------------------------------------------------------
# Set top module
#---------------------------------------------------------------------------
set_property top "repeater_top" [current_fileset]

#---------------------------------------------------------------------------
# Synthesis settings
#---------------------------------------------------------------------------
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY "rebuilt" [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING "true" [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FSM_EXTRACTION "one_hot" [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS "true" [get_runs synth_1]

#---------------------------------------------------------------------------
# Implementation settings (for generate loops with 46 channels)
#---------------------------------------------------------------------------
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE "Default" [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE "Default" [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE "Default" [get_runs impl_1]

#=============================================================================
# Simulation Fileset
#=============================================================================
if {[file exists "${sim_dir}/tb_repeater_top.v"]} {
    create_fileset -simset sim_1
    read_verilog -simset [get_filesets sim_1] "${sim_dir}/tb_repeater_top.v"
    # Add all RTL to sim fileset too
    add_files -norecurse -simset [get_filesets sim_1] [get_files -all [current_fileset]]
    set_property top "tb_repeater_top" [get_filesets sim_1]
    set_property -name {xsim.simulate.runtime} -value {10ms} -objects [get_filesets sim_1]
    puts "Simulation fileset created: tb_repeater_top"
}

#=============================================================================
# Generate IP cores (placeholder — DDS Compiler for NCO)
#=============================================================================
# Note: DDS Compiler IP core generation requires Vivado IP Catalog.
# Uncomment and customize if using IP integrator flow:
#
# create_ip -name dds_compiler -vendor xilinx.com -library ip -version 6.0 \
#     -module_name dds_nco -dir ${project_dir}/ip
# set_property -dict [list \
#     CONFIG.PartsPresent {Sine_Cosine} \
#     CONFIG.PhaseWidth {32} \
#     CONFIG.OutputWidth {14} \
#     CONFIG.OutputSelection {Sine_and_Cosine} \
#     CONFIG.UseTlast {false} \
#     CONFIG.S_PHASE_WIDTH {32} \
#     CONFIG.Latency {6} \
#     CONFIG.Memory_Type {Block_ROM} \
#     CONFIG.PhaseIncrement {Streaming} \
# ] [get_ips dds_nco]

#---------------------------------------------------------------------------
# Write project
#---------------------------------------------------------------------------
close_project
puts "Project created: ${project_dir}/${project_name}.xpr"
puts ""
puts "To open in GUI:  vivado ${project_dir}/${project_name}.xpr"
puts "To run synthesis: vivado -mode batch -source run_synthesis.tcl"
puts "=========================================================================="
