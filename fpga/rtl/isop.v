//=============================================================================
// isop.v — Interpolated Second-Order Polynomial Compensator
//
// Compensates CIC passband droop: y[n] = x[n] − c · x[n-1] + x[n-2]
// Coefficient c is in 4.12 fixed-point format (default ≈ -1.0)
// 3-stage fully pipelined
//=============================================================================

module isop #(
    parameter INPUT_WIDTH  = 16,
    parameter COEFF_WIDTH  = 16,
    parameter OUTPUT_WIDTH = 16
) (
    input  wire                        i_clk,       // System clock
    input  wire                        i_rst_n,     // Reset

    input  wire  [INPUT_WIDTH-1:0]     i_data,      // Input data (signed)
    input  wire                        i_valid,     // Input valid

    // Coefficient update (from register)
    input  wire  [COEFF_WIDTH-1:0]     i_coeff,     // ISOP coefficient (4.12)
    input  wire                        i_coeff_ld,  // Load coefficient

    output wire  [OUTPUT_WIDTH-1:0]    o_data,      // Compensated output
    output wire                        o_valid      // Output valid
);

    //=========================================================================
    // Default coefficient
    //=========================================================================
    localparam COEFF_DEFAULT = 16'hF000;  // ≈ -1.0 in 4.12

    //=========================================================================
    // Signals
    //=========================================================================
    reg  [INPUT_WIDTH-1:0]   delay_1;
    reg  [INPUT_WIDTH-1:0]   delay_2;
    reg  [COEFF_WIDTH-1:0]   coeff_reg;
    reg  [INPUT_WIDTH+COEFF_WIDTH-1:0]  mult_result;
    reg  [INPUT_WIDTH+COEFF_WIDTH:0]    add_sum;      // + x[n] + x[n-2]
    reg  [INPUT_WIDTH+COEFF_WIDTH:0]    final_result;
    reg                                 valid_d1;
    reg                                 valid_d2;
    reg                                 valid_d3;

    //=========================================================================
    // Coefficient register
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            coeff_reg <= COEFF_DEFAULT;
        end else if (i_coeff_ld) begin
            coeff_reg <= i_coeff;
        end
    end

    //=========================================================================
    // Pipeline Stage 1: Delay line
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            delay_1  <= 0;
            delay_2  <= 0;
            valid_d1 <= 1'b0;
        end else begin
            delay_1  <= i_data;
            delay_2  <= delay_1;
            valid_d1 <= i_valid;
        end
    end

    //=========================================================================
    // Pipeline Stage 2: Multiply c × x[n-1]
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            mult_result <= 0;
            valid_d2    <= 1'b0;
        end else begin
            mult_result <= $signed(delay_1) * $signed(coeff_reg);
            valid_d2    <= valid_d1;
        end
    end

    //=========================================================================
    // Pipeline Stage 3: Sum x[n] − c·x[n-1] + x[n-2]
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            valid_d3   <= 1'b0;
            add_sum    <= 0;
            final_result <= 0;
        end else begin
            valid_d3 <= valid_d2;

            // x[n] − c·x[n-1] + x[n-2]
            add_sum <= {{(2){i_data[INPUT_WIDTH-1]}}, i_data}
                     - $signed(mult_result)
                     + {{(2){delay_2[INPUT_WIDTH-1]}}, delay_2};

            // Truncate to OUTPUT_WIDTH with saturation
            if ($signed(add_sum) > (2^(OUTPUT_WIDTH-1)-1)) begin
                final_result <= (2^(OUTPUT_WIDTH-1)-1);
            end else if ($signed(add_sum) < -(2^(OUTPUT_WIDTH-1))) begin
                final_result <= -(2^(OUTPUT_WIDTH-1));
            end else begin
                final_result <= add_sum[OUTPUT_WIDTH-1:0];
            end
        end
    end

    //=========================================================================
    // Output
    //=========================================================================
    assign o_data  = final_result[OUTPUT_WIDTH-1:0];
    assign o_valid = valid_d3;

endmodule
