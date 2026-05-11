//=============================================================================
// repeater_top.v — FM/DMB Digital Repeater — Top Level
//
// Architecture: Kintex-7 XC7K325T + STM32F429 (SPI/UART control)
//
// Features:
//   - 40× FM channels (88~108 MHz, 150 kHz spacing) via generate loop
//   - 6× DMB channels (174~216 MHz, 1.536 MHz spacing) via generate loop
//   - SPI slave (32-bit frame) + UART debug (115200) dual control
//   - Register file (256 × 16-bit) for all configuration
//   - System monitor: LM75A temp sensor, VSWR detection, alarms
//=============================================================================

module repeater_top (
    // Clock & Reset
    input  wire         i_refclk_p,       // 10 MHz LVDS reference
    input  wire         i_refclk_n,
    input  wire         i_rst_n,          // External reset (active low)

    // ADC (AD9649) — 14-bit LVDS @ 80 MSPS
    input  wire         i_adc_dco_p,      // ADC DCO (+)
    input  wire         i_adc_dco_n,
    input  wire         i_adc_fclk_p,     // ADC frame clock (+) — unused
    input  wire         i_adc_fclk_n,
    input  wire  [13:0] i_adc_data_p,     // ADC data 14-bit (+)
    input  wire  [13:0] i_adc_data_n,

    // DAC (AD9742 × 2) — 12-bit parallel
    output wire  [11:0] o_dac_fm_data,    // FM DAC data
    output wire         o_dac_fm_wrt,     // FM DAC write strobe
    output wire  [11:0] o_dac_dmb_data,   // DMB DAC data
    output wire         o_dac_dmb_wrt,    // DMB DAC write strobe

    // SPI (to STM32, Mode 0, 32-bit frame)
    input  wire         i_spi_sclk,
    input  wire         i_spi_mosi,
    output wire         o_spi_miso,
    input  wire         i_spi_ss_n,

    // UART (debug console, 115200 8N1)
    input  wire         i_uart_rx,
    output wire         o_uart_tx,

    // I2C (LM75A temperature sensor)
    output wire         o_i2c_scl,
    inout  wire         io_i2c_sda,

    // Status & Alarms
    output wire         o_alarm_ot,       // Over-temperature
    output wire         o_alarm_vswr,     // High VSWR
    output wire         o_alarm_pa,       // PA fault
    output wire         o_mmcm_locked     // Clock locked
);

    //=========================================================================
    // Parameters
    //=========================================================================
    localparam NUM_FM_CH  = 40;
    localparam NUM_DMB_CH = 6;
    localparam REG_WIDTH  = 16;
    localparam REG_ADDR_W = 8;

    //=========================================================================
    // Internal clock and reset
    //=========================================================================
    wire        clk_80m;
    wire        clk_200m;
    wire        clk_100m;
    wire        clk_25m;
    wire        clk_80m_180;
    wire        clk_12m8;
    wire        mmcm_locked;
    wire        sysrst_n;

    assign sysrst_n = i_rst_n && mmcm_locked;

    //=========================================================================
    // Clock generation
    //=========================================================================
    clk_manager u_clk (
        .i_refclk_p    (i_refclk_p),
        .i_refclk_n    (i_refclk_n),
        .i_rst_n       (i_rst_n),
        .o_clk_80m     (clk_80m),
        .o_clk_200m    (clk_200m),
        .o_clk_100m    (clk_100m),
        .o_clk_25m     (clk_25m),
        .o_clk_80m_180 (clk_80m_180),
        .o_clk_12m8    (clk_12m8),
        .o_mmcm_locked (mmcm_locked)
    );

    assign o_mmcm_locked = mmcm_locked;

    //=========================================================================
    // ADC Interface
    //=========================================================================
    wire [15:0] adc_data;
    wire        adc_valid;
    wire        fifo_full;
    wire        fifo_empty;

    adc_interface u_adc (
        .i_dco_p        (i_adc_dco_p),
        .i_dco_n        (i_adc_dco_n),
        .i_fclk_p       (i_adc_fclk_p),
        .i_fclk_n       (i_adc_fclk_n),
        .i_data_p       (i_adc_data_p),
        .i_data_n       (i_adc_data_n),
        .i_sysclk       (clk_80m),
        .i_sysrst_n     (sysrst_n),
        .i_idelay_rst_n (i_rst_n),
        .i_idelay_taps  (5'd16),
        .o_adc_data     (adc_data),
        .o_adc_valid    (adc_valid),
        .o_fifo_full    (fifo_full),
        .o_fifo_empty   (fifo_empty)
    );

    //=========================================================================
    // Register file (256 × 16-bit, addressable by SPI/UART)
    //=========================================================================
    reg  [REG_WIDTH-1:0] regfile [0:255];
    wire [REG_ADDR_W-1:0] spi_reg_addr;
    wire                  spi_reg_rd;
    wire                  spi_reg_wr;
    wire [REG_WIDTH-1:0]  spi_reg_wdata;
    wire [REG_WIDTH-1:0]  spi_reg_rdata;

    wire [REG_ADDR_W-1:0] uart_reg_addr;
    wire                  uart_reg_rd;
    wire                  uart_reg_wr;
    wire [REG_WIDTH-1:0]  uart_reg_wdata;

    // Arbitration (SPI has priority)
    wire [REG_ADDR_W-1:0] active_reg_addr;
    wire                  active_reg_rd;
    wire                  active_reg_wr;
    wire [REG_WIDTH-1:0]  active_reg_wdata;

    assign active_reg_addr  = spi_active ? spi_reg_addr  : uart_reg_addr;
    assign active_reg_rd    = spi_active ? spi_reg_rd    : uart_reg_rd;
    assign active_reg_wr    = spi_active ? spi_reg_wr    : uart_reg_wr;
    assign active_reg_wdata = spi_active ? spi_reg_wdata : uart_reg_wdata;

    // Register file read
    reg [REG_WIDTH-1:0] regfile_rdata;
    always @(posedge clk_80m) begin
        if (active_reg_rd) begin
            regfile_rdata <= regfile[active_reg_addr];
        end
    end

    // Register file write
    integer r;
    always @(posedge clk_80m or negedge sysrst_n) begin
        if (!sysrst_n) begin
            for (r = 0; r < 256; r = r + 1) begin
                regfile[r] <= 0;
            end
        end else if (active_reg_wr) begin
            regfile[active_reg_addr] <= active_reg_wdata;
        end
    end

    //=========================================================================
    // SPI Interface
    //=========================================================================
    wire spi_active;
    wire [REG_ADDR_W-1:0] spi_addr;
    wire [REG_WIDTH-1:0]  spi_rdata;
    wire                  spi_rd;
    wire                  spi_wr;
    wire [REG_WIDTH-1:0]  spi_wdata;

    spi_slave u_spi (
        .i_clk        (clk_100m),
        .i_rst_n      (sysrst_n),
        .i_sclk       (i_spi_sclk),
        .i_mosi       (i_spi_mosi),
        .o_miso       (o_spi_miso),
        .i_ss_n       (i_spi_ss_n),
        .o_reg_addr   (spi_addr),
        .i_reg_rdata  (spi_rdata),
        .o_reg_rd     (spi_rd),
        .o_reg_wdata  (spi_wdata),
        .o_reg_wr     (spi_wr),
        .o_spi_active (spi_active),
        .o_spi_irq    ()
    );

    assign spi_reg_addr  = spi_addr;
    assign spi_reg_rd    = spi_rd;
    assign spi_reg_wdata = spi_wdata;
    assign spi_reg_wr    = spi_wr;
    assign spi_rdata     = regfile_rdata;

    //=========================================================================
    // UART Debug Interface
    //=========================================================================
    uart_debug u_uart (
        .i_clk        (clk_80m),
        .i_rst_n      (sysrst_n),
        .i_rx         (i_uart_rx),
        .o_tx         (o_uart_tx),
        .o_reg_addr   (),
        .i_reg_rdata  (16'd0),
        .o_reg_rd     (),
        .o_reg_wdata  (),
        .o_reg_wr     (),
        .o_uart_busy  ()
    );

    //=========================================================================
    // System Monitor
    //=========================================================================
    wire [15:0] temp_raw;
    wire [7:0]  vswr_idx;
    wire        scan_busy;

    sys_monitor u_mon (
        .i_clk        (clk_80m),
        .i_rst_n      (sysrst_n),
        .o_i2c_scl    (o_i2c_scl),
        .io_i2c_sda   (io_i2c_sda),
        .i_vfwd       (regfile[16]),    // Reg 0x10: forward power
        .i_vref       (regfile[17]),    // Reg 0x11: reflected power
        .o_alarm_ot   (o_alarm_ot),
        .o_alarm_vswr (o_alarm_vswr),
        .o_alarm_pa   (o_alarm_pa),
        .o_temp_raw   (temp_raw),
        .o_vswr_idx   (vswr_idx),
        .o_scan_busy  (scan_busy)
    );

    //=========================================================================
    // FM Channel Array (generate loop, 40 channels)
    //=========================================================================
    wire [15:0] fm_ch_data  [0:NUM_FM_CH-1];
    wire        fm_ch_valid [0:NUM_FM_CH-1];

    genvar fm;
    generate
        for (fm = 0; fm < NUM_FM_CH; fm = fm + 1) begin : gen_fm_ch
            fm_channel u_fm (
                .i_clk         (clk_80m),
                .i_rst_n       (sysrst_n),
                .i_adc_data    (adc_data),
                .i_adc_valid   (adc_valid),
                .i_phase_inc   (regfile[{fm[5:0], 1'b0}]),   // FM_NCO_L = reg[ch*2]
                .i_phase_ld    (1'b0),
                .i_agc_attack  (regfile[8'h40]),
                .i_agc_release (regfile[8'h41]),
                .i_agc_ref     (regfile[8'h42]),
                .i_agc_mu      (regfile[8'h43]),
                .i_agc_gmin    (regfile[8'h44]),
                .i_agc_gmax    (regfile[8'h45]),
                .i_agc_ld      (1'b0),
                .i_isop_coeff  (16'hF000),
                .i_isop_ld     (1'b0),
                .o_data        (fm_ch_data[fm]),
                .o_valid       (fm_ch_valid[fm])
            );
        end
    endgenerate

    //=========================================================================
    // DMB Channel Array (generate loop, 6 channels)
    //=========================================================================
    wire [15:0] dmb_ch_data  [0:NUM_DMB_CH-1];
    wire        dmb_ch_valid [0:NUM_DMB_CH-1];

    genvar dmb;
    generate
        for (dmb = 0; dmb < NUM_DMB_CH; dmb = dmb + 1) begin : gen_dmb_ch
            dmb_channel u_dmb (
                .i_clk         (clk_80m),
                .i_rst_n       (sysrst_n),
                .i_adc_data    (adc_data),
                .i_adc_valid   (adc_valid),
                .i_phase_inc   (regfile[{8'h50 + dmb[2:0], 1'b0}]),
                .i_phase_ld    (1'b0),
                .i_agc_attack  (regfile[8'h46]),
                .i_agc_release (regfile[8'h47]),
                .i_agc_ref     (regfile[8'h48]),
                .i_agc_mu      (regfile[8'h49]),
                .i_agc_gmin    (regfile[8'h4A]),
                .i_agc_gmax    (regfile[8'h4B]),
                .i_agc_ld      (1'b0),
                .i_isop_coeff  (16'hF000),
                .i_isop_ld     (1'b0),
                .o_data        (dmb_ch_data[dmb]),
                .o_valid       (dmb_ch_valid[dmb])
            );
        end
    endgenerate

    //=========================================================================
    // Channel Sum (FM + DMB)
    //=========================================================================
    wire [31:0] fm_sum;
    wire        fm_sum_valid;
    wire [31:0] dmb_sum;
    wire        dmb_sum_valid;

    // FM sum — sequential accumulation via channel_sum
    channel_sum #(
        .MAX_CHANNELS(NUM_FM_CH),
        .INPUT_WIDTH(16),
        .OUTPUT_WIDTH(32)
    ) u_fm_sum (
        .i_clk         (clk_80m),
        .i_rst_n       (sysrst_n),
        .i_ch_data     (fm_ch_data[0]),   // Simplified: single channel
        .i_ch_index    (6'd0),
        .i_ch_valid    (1'b0),            // Disabled pending scheduler
        .o_sum         (fm_sum),
        .o_sum_valid   (fm_sum_valid),
        .o_saturation  (),
        .o_busy        ()
    );

    channel_sum #(
        .MAX_CHANNELS(NUM_DMB_CH),
        .INPUT_WIDTH(16),
        .OUTPUT_WIDTH(32)
    ) u_dmb_sum (
        .i_clk         (clk_80m),
        .i_rst_n       (sysrst_n),
        .i_ch_data     (dmb_ch_data[0]),
        .i_ch_index    (6'd0),
        .i_ch_valid    (1'b0),
        .o_sum         (dmb_sum),
        .o_sum_valid   (dmb_sum_valid),
        .o_saturation  (),
        .o_busy        ()
    );

    //=========================================================================
    // DUC (Digital Up-Converter) — FM + DMB
    //=========================================================================
    wire [15:0] duc_fm_out;
    wire        duc_fm_valid;
    wire [15:0] duc_dmb_out;
    wire        duc_dmb_valid;

    duc #(
        .CIC_INTERP_R(4),
        .CIC_NUM_STAGES(4),
        .DATA_WIDTH(16),
        .ACCUM_WIDTH(32)
    ) u_duc_fm (
        .i_clk        (clk_80m),
        .i_rst_n      (sysrst_n),
        .i_data       (fm_sum[15:0]),
        .i_valid      (1'b0),           // Disabled pending sum implementation
        .i_nco_inc    (32'h1999999A),
        .i_nco_ld     (1'b0),
        .o_data       (duc_fm_out),
        .o_valid      (duc_fm_valid)
    );

    duc #(
        .CIC_INTERP_R(4),
        .CIC_NUM_STAGES(4),
        .DATA_WIDTH(16),
        .ACCUM_WIDTH(32)
    ) u_duc_dmb (
        .i_clk        (clk_80m),
        .i_rst_n      (sysrst_n),
        .i_data       (dmb_sum[15:0]),
        .i_valid      (1'b0),
        .i_nco_inc    (32'h1999999A),
        .i_nco_ld     (1'b0),
        .o_data       (duc_dmb_out),
        .o_valid      (duc_dmb_valid)
    );

    //=========================================================================
    // DAC Interface
    //=========================================================================
    wire        dac_underrun_fm;
    wire        dac_underrun_dmb;

    dac_interface u_dac (
        .i_clk         (clk_80m),
        .i_rst_n       (sysrst_n),
        .i_data_fm     (duc_fm_out),
        .i_valid_fm    (duc_fm_valid),
        .o_dac_fm_data (o_dac_fm_data),
        .o_dac_fm_wrt  (o_dac_fm_wrt),
        .i_data_dmb    (duc_dmb_out),
        .i_valid_dmb   (duc_dmb_valid),
        .o_dac_dmb_data(o_dac_dmb_data),
        .o_dac_dmb_wrt (o_dac_dmb_wrt),
        .o_underrun_fm (dac_underrun_fm),
        .o_underrun_dmb(dac_underrun_dmb)
    );

    //=========================================================================
    // Status register update
    //=========================================================================
    always @(posedge clk_80m or negedge sysrst_n) begin
        if (!sysrst_n) begin
            regfile[8'h60] <= 0;  // STATUS_TEMP
            regfile[8'h61] <= 0;  // STATUS_VSWR
            regfile[8'h62] <= 0;  // STATUS_ALARM
        end else begin
            regfile[8'h60] <= temp_raw;
            regfile[8'h61] <= {8'd0, vswr_idx};
            regfile[8'h62] <= {13'd0, dac_underrun_dmb, dac_underrun_fm,
                               fifo_full};
        end
    end

endmodule
