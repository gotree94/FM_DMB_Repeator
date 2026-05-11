//=============================================================================
// dmb_channel.v — DMB Single-Channel Processing Chain
//
// Chain: DDC → CIC1(R=5,N=5,28b) → CIC2(R=5,N=4,24b) → FIR1(47tap,dec2)
//        → FIR2(104tap) → ISOP → AGC
//=============================================================================

module dmb_channel (
    input  wire         i_clk,            // 80 MHz system clock
    input  wire         i_rst_n,          // Reset

    // ADC data input
    input  wire  [15:0] i_adc_data,
    input  wire         i_adc_valid,

    // NCO frequency control
    input  wire  [31:0] i_phase_inc,
    input  wire         i_phase_ld,

    // AGC parameters
    input  wire  [15:0] i_agc_attack,
    input  wire  [15:0] i_agc_release,
    input  wire  [15:0] i_agc_ref,
    input  wire  [15:0] i_agc_mu,
    input  wire  [15:0] i_agc_gmin,
    input  wire  [15:0] i_agc_gmax,
    input  wire         i_agc_ld,

    // ISOP coefficient
    input  wire  [15:0] i_isop_coeff,
    input  wire         i_isop_ld,

    // Output
    output wire  [15:0] o_data,
    output wire         o_valid
);

    //=========================================================================
    // Interconnect signals
    //=========================================================================
    wire [15:0] ddc_i, ddc_q;
    wire        ddc_valid;
    wire [15:0] cic1_data;
    wire        cic1_valid;
    wire [15:0] cic2_data;
    wire        cic2_valid;
    wire [31:0] fir1_data;
    wire        fir1_valid;
    wire [31:0] fir2_data;
    wire        fir2_valid;
    wire [15:0] isop_data;
    wire        isop_valid;

    //=========================================================================
    // DDC
    //=========================================================================
    ddc #(
        .PHASE_WIDTH(32),
        .LUT_WIDTH(14),
        .ADDR_WIDTH(10)
    ) u_ddc (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),
        .i_data       (i_adc_data),
        .i_valid      (i_adc_valid),
        .i_phase_inc  (i_phase_inc),
        .i_phase_ld   (i_phase_ld),
        .o_mixer_i    (ddc_i),
        .o_mixer_q    (ddc_q),
        .o_valid      (ddc_valid)
    );

    //=========================================================================
    // CIC1 — First decimation (R=5, N=5, 28-bit)
    //=========================================================================
    cic_decimation #(
        .R(5),
        .N(5),
        .ACCUM_WIDTH(28),
        .INPUT_WIDTH(16),
        .OUTPUT_WIDTH(16)
    ) u_cic1 (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),
        .i_data       (ddc_i),
        .i_valid      (ddc_valid),
        .o_data       (cic1_data),
        .o_valid      (cic1_valid)
    );

    //=========================================================================
    // CIC2 — Second decimation (R=5, N=4, 24-bit)
    //=========================================================================
    cic_decimation #(
        .R(5),
        .N(4),
        .ACCUM_WIDTH(24),
        .INPUT_WIDTH(16),
        .OUTPUT_WIDTH(16)
    ) u_cic2 (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),
        .i_data       (cic1_data),
        .i_valid      (cic1_valid),
        .o_data       (cic2_data),
        .o_valid      (cic2_valid)
    );

    //=========================================================================
    // FIR1 — Channel select filter (47 tap, X decimate#2)
    //=========================================================================
    fir_filter #(
        .N_TAPS(47),
        .COEFF_WIDTH(16),
        .INPUT_WIDTH(16),
        .OUTPUT_WIDTH(32),
        .DECIMATE_BY_2(1)
    ) u_fir1 (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),
        .i_data       (cic2_data),
        .i_valid      (cic2_valid),
        .i_coeff_ld   (1'b0),
        .i_coeff_idx  (8'd0),
        .i_coeff_val  (16'd0),
        .o_data       (fir1_data),
        .o_valid      (fir1_valid)
    );

    //=========================================================================
    // FIR2 — Matched filter (104 tap)
    //=========================================================================
    fir_filter #(
        .N_TAPS(104),
        .COEFF_WIDTH(16),
        .INPUT_WIDTH(32),
        .OUTPUT_WIDTH(32),
        .DECIMATE_BY_2(0)
    ) u_fir2 (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),
        .i_data       (fir1_data[31:16]),  // Truncate to 16-bit
        .i_valid      (fir1_valid),
        .i_coeff_ld   (1'b0),
        .i_coeff_idx  (8'd0),
        .i_coeff_val  (16'd0),
        .o_data       (fir2_data),
        .o_valid      (fir2_valid)
    );

    //=========================================================================
    // ISOP
    //=========================================================================
    isop #(
        .INPUT_WIDTH(16),
        .COEFF_WIDTH(16),
        .OUTPUT_WIDTH(16)
    ) u_isop (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),
        .i_data       (fir2_data[15:0]),
        .i_valid      (fir2_valid),
        .i_coeff      (i_isop_coeff),
        .i_coeff_ld   (i_isop_ld),
        .o_data       (isop_data),
        .o_valid      (isop_valid)
    );

    //=========================================================================
    // AGC
    //=========================================================================
    agc #(
        .DATA_WIDTH(16),
        .GAIN_WIDTH(16)
    ) u_agc (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_data        (isop_data),
        .i_valid       (isop_valid),
        .o_data        (o_data),
        .o_valid       (o_valid),
        .i_attack_alpha(i_agc_attack),
        .i_release_alpha(i_agc_release),
        .i_ref_level   (i_agc_ref),
        .i_mu          (i_agc_mu),
        .i_gain_min    (i_agc_gmin),
        .i_gain_max    (i_agc_gmax),
        .i_param_ld    (i_agc_ld)
    );

endmodule
