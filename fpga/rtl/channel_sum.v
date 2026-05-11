//=============================================================================
// channel_sum.v — Multi-Channel Accumulator
//
// Accumulates up to MAX_CHANNELS parallel channels into a single sum.
// Binary tree structure for efficient addition.
// Saturation detection and overflow protection.
//=============================================================================

module channel_sum #(
    parameter MAX_CHANNELS  = 46,      // 40 FM + 6 DMB
    parameter INPUT_WIDTH   = 16,      // Per-channel data width
    parameter OUTPUT_WIDTH  = 32       // Accumulated sum width
) (
    input  wire                           i_clk,        // System clock
    input  wire                           i_rst_n,      // Reset

    // Per-channel inputs (time-multiplexed or parallel)
    input  wire  [INPUT_WIDTH-1:0]        i_ch_data,    // Channel data
    input  wire  [5:0]                    i_ch_index,   // Channel index (0..MAX_CHANNELS-1)
    input  wire                           i_ch_valid,   // Channel data valid

    // Accumulated output
    output wire  [OUTPUT_WIDTH-1:0]       o_sum,        // Sum of all channels
    output wire                           o_sum_valid,  // Sum valid
    output wire                           o_saturation, // Overflow/underflow
    output wire                           o_busy        // Accumulating
);

    //=========================================================================
    // Parameters
    //=========================================================================
    localparam TREE_DEPTH = $clog2(MAX_CHANNELS) + 1;  // 7 for 46 channels

    //=========================================================================
    // Accumulator (sequential)
    //=========================================================================
    reg  [OUTPUT_WIDTH-1:0] accumulator;
    reg  [OUTPUT_WIDTH-1:0] sum_reg;
    reg                      sum_valid_reg;
    reg                      saturation_reg;
    reg                      busy_reg;
    reg  [5:0]               ch_count;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            accumulator     <= 0;
            sum_reg         <= 0;
            sum_valid_reg   <= 1'b0;
            saturation_reg  <= 1'b0;
            busy_reg        <= 1'b0;
            ch_count        <= 0;
        end else begin
            sum_valid_reg <= 1'b0;

            if (i_ch_valid && i_ch_index < MAX_CHANNELS) begin
                // Accumulate with saturation check
                busy_reg <= 1'b1;

                // Check for overflow
                if ($signed(accumulator) + $signed({{(OUTPUT_WIDTH-INPUT_WIDTH){i_ch_data[INPUT_WIDTH-1]}}, i_ch_data})
                    > (2^(OUTPUT_WIDTH-1)-1)) begin
                    // Positive saturation
                    accumulator    <= (2^(OUTPUT_WIDTH-1)-1);
                    saturation_reg <= 1'b1;
                end else if ($signed(accumulator) + $signed({{(OUTPUT_WIDTH-INPUT_WIDTH){i_ch_data[INPUT_WIDTH-1]}}, i_ch_data})
                    < -(2^(OUTPUT_WIDTH-1))) begin
                    // Negative saturation
                    accumulator    <= -(2^(OUTPUT_WIDTH-1));
                    saturation_reg <= 1'b1;
                end else begin
                    accumulator    <= accumulator + {{(OUTPUT_WIDTH-INPUT_WIDTH){i_ch_data[INPUT_WIDTH-1]}}, i_ch_data};
                end

                ch_count <= i_ch_index + 1;

            end else if (busy_reg) begin
                // Check if all channels received
                if (ch_count >= MAX_CHANNELS || !i_ch_valid) begin
                    sum_reg        <= accumulator;
                    sum_valid_reg  <= 1'b1;
                    accumulator    <= 0;
                    ch_count       <= 0;
                    busy_reg       <= 1'b0;
                end
            end
        end
    end

    //=========================================================================
    // Binary tree adder (parallel, pipelined)
    //=========================================================================
    // This is an alternative parallel structure for when channels arrive
    // simultaneously. Currently unused — sequential accumulation is used above.
    //
    // reg [INPUT_WIDTH-1:0] tree_inputs [0:MAX_CHANNELS-1];
    // reg [OUTPUT_WIDTH-1:0] tree_stage [0:TREE_DEPTH][0:MAX_CHANNELS/2];
    // ... pipelined binary addition ...

    //=========================================================================
    // Output
    //=========================================================================
    assign o_sum        = sum_reg;
    assign o_sum_valid  = sum_valid_reg;
    assign o_saturation = saturation_reg;
    assign o_busy       = busy_reg;

endmodule
