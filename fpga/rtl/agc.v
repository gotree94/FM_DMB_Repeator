//=============================================================================
// agc.v — Automatic Gain Control (RMS + IIR + Gain Integrator)
//
// Architecture:
//   1. RMS envelope: y[n] = alpha * |x[n]| + (1-alpha) * y[n-1]
//   2. Reference comparison: error = ref - rms
//   3. Gain integrator: gain[n] = gain[n-1] + mu * error
//   4. Output: out[n] = x[n] * gain[n]
//
// Alpha values: attack_alpha (fast), release_alpha (slow)
// Gain clamp: [MIN_GAIN, MAX_GAIN]
// All values in Q15 fixed-point format
//=============================================================================

module agc #(
    parameter DATA_WIDTH  = 16,
    parameter GAIN_WIDTH  = 16
) (
    input  wire                         i_clk,         // System clock
    input  wire                         i_rst_n,       // Reset

    // Data path
    input  wire  [DATA_WIDTH-1:0]       i_data,        // Input (signed)
    input  wire                         i_valid,       // Input valid
    output wire  [DATA_WIDTH-1:0]       o_data,        // Output (scaled)
    output wire                         o_valid,       // Output valid

    // AGC parameters (from registers, Q15 format)
    input  wire  [DATA_WIDTH-1:0]       i_attack_alpha, // Attack time const (0-32767)
    input  wire  [DATA_WIDTH-1:0]       i_release_alpha,// Release time const
    input  wire  [DATA_WIDTH-1:0]       i_ref_level,   // Target RMS level
    input  wire  [DATA_WIDTH-1:0]       i_mu,          // Step size (0-32767)
    input  wire  [GAIN_WIDTH-1:0]       i_gain_min,    // Min gain (0.0 = 0x0000)
    input  wire  [GAIN_WIDTH-1:0]       i_gain_max,    // Max gain (1.0 = 0x7FFF)
    input  wire                         i_param_ld     // Load parameters
);

    //=========================================================================
    // RMS detector (1-pole IIR)
    //=========================================================================
    reg  [DATA_WIDTH-1:0] abs_x;
    reg  [31:0]           rms_prod;
    reg  [DATA_WIDTH-1:0] rms_prev;
    reg  [DATA_WIDTH-1:0] rms_out;
    reg  [DATA_WIDTH-1:0] alpha_sel;
    reg  [31:0]           rms_alpha_prod;
    reg  [31:0]           rms_one_minus_alpha;
    reg  [DATA_WIDTH-1:0] attack_reg;
    reg  [DATA_WIDTH-1:0] release_reg;
    reg  [DATA_WIDTH-1:0] mu_reg;
    reg  [DATA_WIDTH-1:0] ref_reg;
    reg  [GAIN_WIDTH-1:0] gain_min_reg;
    reg  [GAIN_WIDTH-1:0] gain_max_reg;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            attack_reg   <= 16'd100;    // Default attack (~16ms at 80MHz)
            release_reg  <= 16'd1000;   // Default release (~160ms)
            mu_reg       <= 16'd328;    // Default mu = 0.01 in Q15
            ref_reg      <= 16'h4000;   // Default ref = 0.5 in Q15
            gain_min_reg <= 16'h0080;   // Min gain ~0.0025
            gain_max_reg <= 16'h7FFF;   // Max gain ~1.0
        end else if (i_param_ld) begin
            attack_reg   <= i_attack_alpha;
            release_reg  <= i_release_alpha;
            mu_reg       <= i_mu;
            ref_reg      <= i_ref_level;
            gain_min_reg <= i_gain_min;
            gain_max_reg <= i_gain_max;
        end
    end

    // Stage 1: Absolute value & alpha select
    always @(posedge i_clk) begin
        abs_x <= i_data[DATA_WIDTH-1] ? (~i_data + 1) : i_data;
        alpha_sel <= (abs_x > rms_prev) ? attack_reg : release_reg;
    end

    // Stage 2: RMS IIR filter y[n] = alpha*|x| + (1-alpha)*y[n-1]
    always @(posedge i_clk) begin
        rms_alpha_prod     <= $signed(abs_x) * $signed(alpha_sel);
        rms_one_minus_alpha <= $signed(rms_prev) * $signed(~alpha_sel + 1);  // (1-alpha)
    end

    // Stage 3: Sum and store
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rms_out  <= 0;
            rms_prev <= 0;
        end else if (i_valid) begin
            rms_prev <= (rms_alpha_prod[30:15] + rms_one_minus_alpha[30:15]);
            rms_out  <= (rms_alpha_prod[30:15] + rms_one_minus_alpha[30:15]);
        end
    end

    //=========================================================================
    // Gain Integrator: gain[n] = gain[n-1] + mu * (ref - rms)
    //=========================================================================
    reg  [DATA_WIDTH:0]  error;        // ref - rms (signed, 17-bit)
    reg  [31:0]          mu_error;     // mu * error (signed)
    reg  [GAIN_WIDTH-1:0] gain_reg;
    reg  [GAIN_WIDTH-1:0] gain_clamped;

    // Stage 1: error calculation
    always @(posedge i_clk) begin
        error <= {ref_reg[15], ref_reg} - {rms_out[15], rms_out};
    end

    // Stage 2: mu * error
    always @(posedge i_clk) begin
        mu_error <= $signed(error) * $signed(mu_reg);
    end

    // Stage 3: gain integration with clamp
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            gain_reg <= 16'h4000;  // Initial gain = 0.5
        end else if (i_valid) begin
            gain_reg <= gain_reg + mu_error[30:15];
        end
    end

    // Clamp
    always @(*) begin
        if ($signed(gain_reg) < $signed(gain_min_reg)) begin
            gain_clamped = gain_min_reg;
        end else if ($signed(gain_reg) > $signed(gain_max_reg)) begin
            gain_clamped = gain_max_reg;
        end else begin
            gain_clamped = gain_reg;
        end
    end

    //=========================================================================
    // Output multiplier: out = data * gain
    //=========================================================================
    reg  [31:0]  out_prod;
    reg  [DATA_WIDTH-1:0] out_data;
    reg                   out_valid;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            out_prod  <= 0;
            out_data  <= 0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= i_valid;
            if (i_valid) begin
                out_prod <= $signed(i_data) * $signed(gain_clamped);
                out_data <= out_prod[30:15];
            end
        end
    end

    assign o_data  = out_data;
    assign o_valid = out_valid;

endmodule
