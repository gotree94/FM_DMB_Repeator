//=============================================================================
// fir_filter.v — Symmetric Transpose FIR Filter
//
// Features:
// - Fully symmetric (N_taps = 2*NUM_UNIQUE_TAPS - 1 or 2*NUM_UNIQUE_TAPS)
// - Programmable coefficients (loaded via SPI register bus)
// - Pipelined adder tree
// - Optional decimation-by-2
//=============================================================================

module fir_filter #(
    parameter N_TAPS          = 47,              // Total taps
    parameter COEFF_WIDTH     = 16,              // Coefficient width
    parameter INPUT_WIDTH     = 16,              // Input data width
    parameter OUTPUT_WIDTH    = 32,              // Output accumulator width
    parameter DECIMATE_BY_2   = 1                // 1 = enable decimation
) (
    input  wire                      i_clk,       // System clock
    input  wire                      i_rst_n,     // Reset

    input  wire  [INPUT_WIDTH-1:0]   i_data,      // Input data (signed)
    input  wire                      i_valid,     // Input valid

    // Coefficient load interface (SPI)
    input  wire                      i_coeff_ld,  // Load coefficient
    input  wire  [7:0]               i_coeff_idx, // Coefficient index
    input  wire  [COEFF_WIDTH-1:0]   i_coeff_val, // Coefficient value

    output wire  [OUTPUT_WIDTH-1:0]  o_data,      // Filtered output
    output wire                      o_valid      // Output valid
);

    //=========================================================================
    // Local parameters
    //=========================================================================
    localparam UNIQUE_TAPS = (N_TAPS + 1) / 2;  // Symmetric half
    localparam ADDER_DEPTH = $clog2(UNIQUE_TAPS) + 1;

    //=========================================================================
    // Coefficient storage (SPI-loadable)
    //=========================================================================
    reg [COEFF_WIDTH-1:0] coeff_ram [0:UNIQUE_TAPS-1];

    // Delay line (shift register)
    reg [INPUT_WIDTH-1:0] delay_line [0:N_TAPS-1];

    // Pre-adder outputs (h0 = h_{N-1}, so pre_add[i] = delay_line[i] + delay_line[N_TAPS-1-i])
    reg [INPUT_WIDTH:0]   pre_add [0:UNIQUE_TAPS-1];  // Extra bit for sum

    // Pipelined product results
    reg [INPUT_WIDTH+COEFF_WIDTH:0] mult_stage [0:UNIQUE_TAPS-1];

    //=========================================================================
    // Coefficient loading (SPI accessible)
    //=========================================================================
    integer k;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (k = 0; k < UNIQUE_TAPS; k = k + 1) begin
                coeff_ram[k] <= 0;
            end
        end else if (i_coeff_ld) begin
            if (i_coeff_idx < UNIQUE_TAPS) begin
                coeff_ram[i_coeff_idx] <= i_coeff_val;
            end
        end
    end

    //=========================================================================
    // Delay line
    //=========================================================================
    integer d;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (d = 0; d < N_TAPS; d = d + 1) begin
                delay_line[d] <= 0;
            end
        end else if (i_valid) begin
            delay_line[0] <= i_data;
            for (d = 1; d < N_TAPS; d = d + 1) begin
                delay_line[d] <= delay_line[d-1];
            end
        end
    end

    //=========================================================================
    // Pre-add (symmetric pairs)
    //=========================================================================
    integer p;
    reg [INPUT_WIDTH:0] pre_add_comb [0:UNIQUE_TAPS-1];

    always @(*) begin
        for (p = 0; p < UNIQUE_TAPS; p = p + 1) begin
            if (N_TAPS % 2 == 1 && p == UNIQUE_TAPS - 1) begin
                // Center tap (odd-length): just the tap itself
                pre_add_comb[p] = {delay_line[p][INPUT_WIDTH-1], delay_line[p]};
            end else begin
                pre_add_comb[p] = {delay_line[p][INPUT_WIDTH-1], delay_line[p]}
                                + {delay_line[N_TAPS-1-p][INPUT_WIDTH-1], delay_line[N_TAPS-1-p]};
            end
        end
    end

    integer pr;
    always @(posedge i_clk) begin
        if (i_valid) begin
            for (pr = 0; pr < UNIQUE_TAPS; pr = pr + 1) begin
                pre_add[pr] <= pre_add_comb[pr];
            end
        end
    end

    //=========================================================================
    // Multiplier stage
    //=========================================================================
    integer m;
    always @(posedge i_clk) begin
        for (m = 0; m < UNIQUE_TAPS; m = m + 1) begin
            mult_stage[m] <= $signed(pre_add[m]) * $signed(coeff_ram[m]);
        end
    end

    //=========================================================================
    // Pipelined adder tree
    //=========================================================================
    // Using a recursive structure: sum all mult_stage values
    localparam TREE_STAGES = ADDER_DEPTH;
    reg [INPUT_WIDTH+COEFF_WIDTH+1:0] adder_tree [0:TREE_STAGES-1][0:(1 << TREE_STAGES)-1];

    integer s, t;
    reg [INPUT_WIDTH+COEFF_WIDTH+1:0] accum_result;
    reg                               accum_valid;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            accum_result <= 0;
            accum_valid  <= 1'b0;
        end else begin
            accum_valid <= i_valid;

            // Stage 0: copy mult_stage
            for (t = 0; t < UNIQUE_TAPS; t = t + 1) begin
                adder_tree[0][t] <= mult_stage[t];
            end
            // Zero-pad remaining
            for (t = UNIQUE_TAPS; t < (1 << TREE_STAGES); t = t + 1) begin
                adder_tree[0][t] <= 0;
            end

            // Tree stages
            for (s = 1; s < TREE_STAGES; s = s + 1) begin
                for (t = 0; t < (1 << TREE_STAGES) / (1 << s); t = t + 1) begin
                    adder_tree[s][t] <= $signed(adder_tree[s-1][2*t])
                                      + $signed(adder_tree[s-1][2*t+1]);
                end
            end

            accum_result <= adder_tree[TREE_STAGES-1][0];
        end
    end

    //=========================================================================
    // Decimation-by-2 (optional)
    //=========================================================================
    reg [OUTPUT_WIDTH-1:0] output_reg;
    reg                    output_valid;
    reg                    decim_phase;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            output_reg   <= 0;
            output_valid <= 1'b0;
            decim_phase  <= 1'b0;
        end else begin
            output_valid <= 1'b0;
            if (accum_valid) begin
                if (!DECIMATE_BY_2) begin
                    output_reg   <= accum_result[OUTPUT_WIDTH-1:0];
                    output_valid <= 1'b1;
                end else begin
                    decim_phase <= ~decim_phase;
                    if (decim_phase) begin
                        output_reg   <= accum_result[OUTPUT_WIDTH-1:0];
                        output_valid <= 1'b1;
                    end
                end
            end
        end
    end

    assign o_data  = output_reg;
    assign o_valid = output_valid;

endmodule
