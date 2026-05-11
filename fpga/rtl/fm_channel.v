//=============================================================================
// fm_channel.v — FM Single-Channel Processing Chain
//
// Chain: DDC → CIC (R=693, N=6) → ISOP → AGC
//=============================================================================

module fm_channel (
    input  wire         i_clk,            // 80 MHz system clock
    input  wire         i_rst_n,          // Reset

    // ADC data input (shared bus from top)
    input  wire  [15:0] i_adc_data,
    input  wire         i_adc_valid,

    // NCO frequency control (per-channel)
    input  wire  [31:0] i_phase_inc,
    input  wire         i_phase_ld,

    // AGC parameters (shared from register file)
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
    wire [15:0] cic_data;
    wire        cic_valid;
    wire [15:0] isop_data;
    wire        isop_valid;

    //=========================================================================
    // DDC — Down-convert to baseband I/Q
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
    // CIC Decimation — R=693, N=6, 56-bit accumulator
    //=========================================================================
    cic_decimation #(
        .R(693),
        .N(6),
        .ACCUM_WIDTH(56),
        .INPUT_WIDTH(16),
        .OUTPUT_WIDTH(16)
    ) u_cic (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),
        .i_data       (ddc_i),          // Use I path
        .i_valid      (ddc_valid),
        .o_data       (cic_data),
        .o_valid      (cic_valid)
    );

    //=========================================================================
    // ISOP — CIC droop compensation
    //=========================================================================
    isop #(
        .INPUT_WIDTH(16),
        .COEFF_WIDTH(16),
        .OUTPUT_WIDTH(16)
    ) u_isop (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),
        .i_data       (cic_data),
        .i_valid      (cic_valid),
        .i_coeff      (i_isop_coeff),
        .i_coeff_ld   (i_isop_ld),
        .o_data       (isop_data),
        .o_valid      (isop_valid)
    );

    //=========================================================================
    // AGC — Automatic gain control
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
