//=============================================================================
// cic_decimation.v — Cascaded Integrator-Comb Decimation Filter
//
// Fully parameterized: R (decimation ratio), N (stages), ACCUM_WIDTH
//
// FM path:  R=693, N=6, ACCUM_WIDTH=56
// DMB path: R=5,   N=5, ACCUM_WIDTH=28
//
// Architecture: Integrator → Decimate (by R) → Comb (N stages)
//=============================================================================

module cic_decimation #(
    parameter R            = 693,   // Decimation ratio
    parameter N            = 6,     // Number of stages
    parameter ACCUM_WIDTH  = 56,    // Accumulator width (ceil(N*log2(R*2^B)) + B)
    parameter INPUT_WIDTH  = 16,    // Input data width
    parameter OUTPUT_WIDTH = 16     // Output data width
) (
    input  wire                  i_clk,        // System clock (80 MHz)
    input  wire                  i_rst_n,      // Reset (active low)

    input  wire  [INPUT_WIDTH-1:0]  i_data,    // Input data (signed)
    input  wire                     i_valid,   // Input valid

    output wire  [OUTPUT_WIDTH-1:0] o_data,    // Decimated output
    output wire                     o_valid    // Output valid
);

    //=========================================================================
    // Local parameters
    //=========================================================================
    localparam R_CNT_WIDTH = $clog2(R+1);
    localparam DIFF_DELAY  = 1;  // Differential delay (typically 1 or 2)

    //=========================================================================
    // Integrator section (N stages)
    //=========================================================================
    reg  [ACCUM_WIDTH-1:0] int_reg [0:N-1];
    wire [ACCUM_WIDTH-1:0] int_in [0:N-1];
    wire [ACCUM_WIDTH-1:0] int_out [0:N-1];

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : gen_integrator
            if (i == 0) begin
                assign int_in[i] = {{(ACCUM_WIDTH-INPUT_WIDTH){i_data[INPUT_WIDTH-1]}}, i_data};
            end else begin
                assign int_in[i] = int_out[i-1];
            end

            always @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) begin
                    int_reg[i] <= 0;
                end else if (i_valid) begin
                    int_reg[i] <= int_reg[i] + int_in[i];
                end
            end

            assign int_out[i] = int_reg[i];
        end
    endgenerate

    //=========================================================================
    // Decimation counter
    //=========================================================================
    reg [R_CNT_WIDTH-1:0] decim_cnt;
    reg                   decim_tick;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            decim_cnt  <= 0;
            decim_tick <= 1'b0;
        end else if (i_valid) begin
            decim_tick <= 1'b0;
            if (decim_cnt >= R-1) begin
                decim_cnt  <= 0;
                decim_tick <= 1'b1;
            end else begin
                decim_cnt <= decim_cnt + 1;
            end
        end
    end

    //=========================================================================
    // Comb section (N stages, differential delay = 1)
    //=========================================================================
    reg  [ACCUM_WIDTH-1:0] comb_delay [0:N-1];
    reg  [ACCUM_WIDTH-1:0] comb_out_reg [0:N-1];
    wire [ACCUM_WIDTH-1:0] comb_in [0:N-1];
    wire [ACCUM_WIDTH-1:0] comb_diff;

    generate
        for (i = 0; i < N; i = i + 1) begin : gen_comb
            if (i == 0) begin
                assign comb_in[i] = int_out[N-1];
            end else begin
                assign comb_in[i] = comb_out_reg[i-1];
            end

            always @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) begin
                    comb_delay[i]    <= 0;
                    comb_out_reg[i]  <= 0;
                end else if (decim_tick) begin
                    comb_out_reg[i] <= comb_in[i] - comb_delay[i];
                    comb_delay[i]   <= comb_in[i];
                end
            end
        end
    endgenerate

    //=========================================================================
    // Output truncation with rounding
    //=========================================================================
    reg  [OUTPUT_WIDTH-1:0] data_out;
    reg                     valid_out;

    // Gain scaling: G = (R * DIFF_DELAY)^N
    // Output = comb_out / G (shift right)
    localparam GAIN_SHIFT = $clog2(R) * N;  // Approximate gain = 2^(log2(R)*N)
    reg [ACCUM_WIDTH-1:0] scaled_in;
    reg [ACCUM_WIDTH-1:0] round_add;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            scaled_in  <= 0;
            round_add  <= 0;
            data_out   <= 0;
            valid_out  <= 1'b0;
        end else begin
            valid_out <= decim_tick;

            if (decim_tick) begin
                // Scale and round
                scaled_in <= comb_out_reg[N-1];
                round_add <= scaled_in + (1 << (GAIN_SHIFT - 1));
                data_out  <= round_add[ACCUM_WIDTH-1:ACCUM_WIDTH-OUTPUT_WIDTH];
            end
        end
    end

    assign o_data  = data_out;
    assign o_valid = valid_out;

endmodule
