#=============================================================================
# repeater_top.xdc — Timing and Pin Constraints
#
# Target:  Xilinx Kintex-7 XC7K325T-2FFG900
# Design:  FM/DMB Digital Repeater (repeater_top)
# Created: 2026-05-12
#
# Clock domains:
#   CLK_REF_10M     — 10.000 MHz LVDS external reference (primary)
#   CLK_80M         — 80.000 MHz system clock (MMCM generated)
#   CLK_200M        — 200.000 MHz IDELAY reference (MMCM generated)
#   CLK_100M        — 100.000 MHz SPI/UART domain (MMCM generated)
#   CLK_25M         — 25.000 MHz slow domain (MMCM generated)
#   CLK_80M_180     — 80.000 MHz @ 180° ADC DDR strobe (MMCM generated)
#   CLK_12M8        — 12.800 MHz fractional NCO ref (from 80 MHz)
#=============================================================================

#=============================================================================
# 1. PRIMARY CLOCK — 10 MHz LVDS Reference
#=============================================================================
create_clock -period 100.000 -name clk_ref_10m [get_ports i_refclk_p]

#=============================================================================
# 2. GENERATED CLOCKS — MMCME2_ADV Outputs
#=============================================================================
# CLKOUT0: 80 MHz (system clock)
create_generated_clock -name clk_80m \
    -source [get_pins u_clk/mmcm_inst/CLKIN1] \
    -divide_by 10 -multiply_by 80 \
    [get_pins u_clk/bufg_80m/O]

# CLKOUT1: 200 MHz (IDELAY reference)
create_generated_clock -name clk_200m \
    -source [get_pins u_clk/mmcm_inst/CLKIN1] \
    -divide_by 4 -multiply_by 80 \
    [get_pins u_clk/bufg_200m/O]

# CLKOUT2: 100 MHz (SPI/UART domain)
create_generated_clock -name clk_100m \
    -source [get_pins u_clk/mmcm_inst/CLKIN1] \
    -divide_by 8 -multiply_by 80 \
    [get_pins u_clk/bufg_100m/O]

# CLKOUT3: 25 MHz (slow domain)
create_generated_clock -name clk_25m \
    -source [get_pins u_clk/mmcm_inst/CLKIN1] \
    -divide_by 32 -multiply_by 80 \
    [get_pins u_clk/bufg_25m/O]

# CLKOUT4: 80 MHz @ 180° (ADC DDR strobe)
create_generated_clock -name clk_80m_180 \
    -source [get_pins u_clk/mmcm_inst/CLKIN1] \
    -divide_by 10 -multiply_by 80 -phase 180 \
    [get_pins u_clk/bufg_80m180/O]

# Fractional 12.8 MHz (from clk_80m via fractional divider)
create_generated_clock -name clk_12m8 \
    -source [get_pins u_clk/bufg_80m/O] \
    -edges {1 625 1250} \
    [get_pins u_clk/bufg_12m8/O]

#=============================================================================
# 3. CLOCK GROUP DEFINITIONS (for CDC paths)
#=============================================================================
set_clock_groups -asynchronous \
    -group {clk_ref_10m} \
    -group {clk_80m clk_80m_180 clk_100m clk_200m clk_25m clk_12m8}

set_clock_groups -physically_exclusive \
    -group {clk_80m clk_80m_180}

#=============================================================================
# 4. FALSE PATHS — CDC Crossings
#=============================================================================

# ADC DCO domain → sysclk (async FIFO with Gray code)
set_false_path -from [get_clocks clk_80m_180] -to [get_clocks clk_80m]
set_false_path -from [get_clocks clk_80m] -to [get_clocks clk_80m_180]

# SPI pins → sysclk (2-FF synchronizer)
set_false_path -from [get_ports i_spi_sclk] -to [get_clocks clk_100m]
set_false_path -from [get_ports i_spi_mosi] -to [get_clocks clk_100m]
set_false_path -from [get_ports i_spi_ss_n] -to [get_clocks clk_100m]

# UART RX → sysclk (2-FF synchronizer)
set_false_path -from [get_ports i_uart_rx] -to [get_clocks clk_80m]

# I2C SDA/SCL → sysclk (bit-bang, slow)
set_false_path -from [get_ports io_i2c_sda] -to [get_clocks clk_80m]
set_false_path -from [get_ports o_i2c_scl] -to [get_clocks clk_80m]

# MISO output (SPI clock domain)
set_false_path -from [get_clocks clk_100m] -to [get_ports o_spi_miso]

#=============================================================================
# 5. INPUT DELAY CONSTRAINTS
#=============================================================================

# ADC data (DCO clock domain, DDR)
set_input_delay -clock [get_clocks clk_80m_180] -max 2.000 \
    [get_ports i_adc_data_p[*]]
set_input_delay -clock [get_clocks clk_80m_180] -min 0.500 \
    [get_ports i_adc_data_p[*]]

# SPI inputs (external master)
set_input_delay -clock [get_clocks clk_100m] -max 5.000 \
    [get_ports i_spi_sclk]
set_input_delay -clock [get_clocks clk_100m] -max 5.000 \
    [get_ports i_spi_mosi]
set_input_delay -clock [get_clocks clk_100m] -max 5.000 \
    [get_ports i_spi_ss_n]

#=============================================================================
# 6. OUTPUT DELAY CONSTRAINTS
#=============================================================================

# DAC outputs (80 MHz domain)
set_output_delay -clock [get_clocks clk_80m] -max 3.000 \
    [get_ports {o_dac_fm_data[*] o_dac_fm_wrt o_dac_dmb_data[*] o_dac_dmb_wrt}]
set_output_delay -clock [get_clocks clk_80m] -min 1.000 \
    [get_ports {o_dac_fm_data[*] o_dac_fm_wrt o_dac_dmb_data[*] o_dac_dmb_wrt}]

# UART TX (80 MHz domain)
set_output_delay -clock [get_clocks clk_80m] -max 5.000 [get_ports o_uart_tx]

# I2C SCL
set_output_delay -clock [get_clocks clk_80m] -max 10.000 [get_ports o_i2c_scl]

# Alarm outputs
set_output_delay -clock [get_clocks clk_80m] -max 5.000 \
    [get_ports {o_alarm_ot o_alarm_vswr o_alarm_pa o_mmcm_locked}]

#=============================================================================
# 7. IDELAYCTRL CONSTRAINT
#=============================================================================
# IDELAYCTRL requires a 200 MHz reference clock
set_property LOC IDELAYCTRL_X0Y0 [get_cells u_adc/gen_idelay[*]/idelay_inst]
create_clock -period 5.000 -name clk_idelay_ref [get_pins ...]

#=============================================================================
# 8. PIN ASSIGNMENTS (placeholder — customize for your PCB)
#=============================================================================

# ---- Reference Clock ----
#set_property PACKAGE_PIN xx [get_ports i_refclk_p]
#set_property PACKAGE_PIN xx [get_ports i_refclk_n]
#set_property IOSTANDARD LVDS [get_ports {i_refclk_p i_refclk_n}]

# ---- ADC (AD9649) — Bank 3x ----
#set_property PACKAGE_PIN xx [get_ports i_adc_dco_p]
#set_property IOSTANDARD LVDS [get_ports {i_adc_dco_p i_adc_dco_n}]
#set_property PACKAGE_PIN xx [get_ports i_adc_fclk_p]
#set_property IOSTANDARD LVDS [get_ports {i_adc_fclk_p i_adc_fclk_n}]
#for {set i 0} {$i < 14} {incr i} {
#    set_property PACKAGE_PIN xx [get_ports i_adc_data_p[$i]]
#    set_property PACKAGE_PIN xx [get_ports i_adc_data_n[$i]]
#    set_property IOSTANDARD LVDS [get_ports "i_adc_data_p[$i] i_adc_data_n[$i]"]
#}

# ---- DAC (AD9742 × 2) — Bank 1x ----
#for {set i 0} {$i < 12} {incr i} {
#    set_property PACKAGE_PIN xx [get_ports o_dac_fm_data[$i]]
#    set_property IOSTANDARD LVCMOS33 [get_ports o_dac_fm_data[$i]]
#}
#set_property PACKAGE_PIN xx [get_ports o_dac_fm_wrt]
#set_property IOSTANDARD LVCMOS33 [get_ports o_dac_fm_wrt]
# ... (same for DMB DAC)

# ---- SPI — Bank 1x ----
#set_property PACKAGE_PIN xx [get_ports i_spi_sclk]
#set_property PACKAGE_PIN xx [get_ports i_spi_mosi]
#set_property PACKAGE_PIN xx [get_ports o_spi_miso]
#set_property PACKAGE_PIN xx [get_ports i_spi_ss_n]
#set_property IOSTANDARD LVCMOS33 [get_ports {i_spi_sclk i_spi_mosi o_spi_miso i_spi_ss_n}]

# ---- UART — Bank 1x ----
#set_property PACKAGE_PIN xx [get_ports i_uart_rx]
#set_property PACKAGE_PIN xx [get_ports o_uart_tx]
#set_property IOSTANDARD LVCMOS33 [get_ports {i_uart_rx o_uart_tx}]

# ---- I2C — Bank 1x ----
#set_property PACKAGE_PIN xx [get_ports o_i2c_scl]
#set_property PACKAGE_PIN xx [get_ports io_i2c_sda]
#set_property IOSTANDARD LVCMOS33 [get_ports {o_i2c_scl io_i2c_sda}]

# ---- Alarms — LED drivers ----
#set_property PACKAGE_PIN xx [get_ports {o_alarm_ot o_alarm_vswr o_alarm_pa o_mmcm_locked}]
#set_property IOSTANDARD LVCMOS33 [get_ports {o_alarm_ot o_alarm_vswr o_alarm_pa o_mmcm_locked}]

# ---- Reset ----
#set_property PACKAGE_PIN xx [get_ports i_rst_n]
#set_property IOSTANDARD LVCMOS33 [get_ports i_rst_n]

#=============================================================================
# 9. CONFIGURATION
#=============================================================================
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

#=============================================================================
# 10. TIMING EXCEPTIONS — Multi-cycle paths (slow DSP paths)
#=============================================================================
set_multicycle_path 2 -setup -from [get_cells -hierarchical -filter {NAME =~ *u_cic/*}]
set_multicycle_path 2 -hold  -from [get_cells -hierarchical -filter {NAME =~ *u_cic/*}]

#=============================================================================
# End of constraint file
#=============================================================================
