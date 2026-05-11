//=============================================================================
// duc.v — Digital Up-Converter (CIC Interpolation + NCO Up-Mixer)
//
// Steps:
//   1. Zero-insertion upsampling (factor = CIC_INTERP_R)
//   2. CIC interpolation filter (N stages)
//   3. NCO complex-to-real up-conversion
//=============================================================================

module duc #(
    parameter CIC_INTERP_R   = 4,      // Interpolation ratio
    parameter CIC_NUM_STAGES = 4,      // CIC stages
    parameter DATA_WIDTH     = 16,     // Input data width
    parameter ACCUM_WIDTH    = 32,     // CIC accumulator width
    parameter NCO_WIDTH      = 14      // NCO LUT width
) (
    input  wire                        i_clk,         // System clock (80 MHz)
    input  wire                        i_rst_n,       // Reset

    // Input (baseband, from channel_sum)
    input  wire  [DATA_WIDTH-1:0]      i_data,        // Input data (signed)
    input  wire                        i_valid,       // Input valid

    // NCO frequency control
    input  wire  [31:0]                i_nco_inc,     // NCO phase increment
    input  wire                        i_nco_ld,      // Load NCO increment

    // Output (real, up-converted)
    output wire  [DATA_WIDTH-1:0]      o_data,        // Up-converted output
    output wire                        o_valid        // Output valid
);

    //=========================================================================
    // Zero-insertion upsampler
    //=========================================================================
    reg  [DATA_WIDTH-1:0] upsamp_data;
    reg                   upsamp_valid;
    reg  [3:0]            upsamp_cnt;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            upsamp_data  <= 0;
            upsamp_valid <= 1'b0;
            upsamp_cnt   <= 0;
        end else begin
            upsamp_valid <= 1'b0;

            if (i_valid) begin
                upsamp_data  <= i_data;
                upsamp_valid <= 1'b1;
                upsamp_cnt   <= 1;
            end else if (upsamp_cnt > 0 && upsamp_cnt < CIC_INTERP_R) begin
                upsamp_data  <= 0;      // Zero insertion
                upsamp_valid <= 1'b1;
                upsamp_cnt   <= upsamp_cnt + 1;
            end
        end
    end

    //=========================================================================
    // CIC Interpolation (N-stage, rate = CIC_INTERP_R)
    //=========================================================================
    // Architecture: Comb (at low rate) → Zero-insert → Integrator (at high rate)
    // Simplified: Integrator-only chain at output rate

    reg  [ACCUM_WIDTH-1:0] cic_int [0:CIC_NUM_STAGES-1];
    wire [ACCUM_WIDTH-1:0] cic_int_in [0:CIC_NUM_STAGES-1];
    wire [ACCUM_WIDTH-1:0] cic_int_out [0:CIC_NUM_STAGES-1];

    genvar i;
    generate
        for (i = 0; i < CIC_NUM_STAGES; i = i + 1) begin : gen_cic_interp
            if (i == 0) begin
                // Sign-extend input to accumulator width
                assign cic_int_in[i]
                     = {{(ACCUM_WIDTH-DATA_WIDTH){upsamp_data[DATA_WIDTH-1]}}, upsamp_data};
            end else begin
                assign cic_int_in[i] = cic_int_out[i-1];
            end

            always @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) begin
                    cic_int[i] <= 0;
                end else if (upsamp_valid) begin
                    cic_int[i] <= cic_int[i] + cic_int_in[i];
                end
            end

            assign cic_int_out[i] = cic_int[i];
        end
    endgenerate

    //=========================================================================
    // NCO (Quadrant-based, similar to DDC)
    //=========================================================================
    reg  [31:0] nco_phase_acc;
    reg  [31:0] nco_inc_reg;
    reg  [1:0]  nco_quadrant;
    reg  [7:0]  nco_angle;
    reg  [NCO_WIDTH-1:0] nco_sin;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            nco_phase_acc <= 0;
            nco_inc_reg   <= 32'h1999999A;  // ~100 MHz output
        end else begin
            if (i_nco_ld) begin
                nco_inc_reg <= i_nco_inc;
            end
            nco_phase_acc <= nco_phase_acc + nco_inc_reg;
        end
    end

    // Quadrant/sine generation (same simplified approach as DDC)
    always @(*) begin
        nco_quadrant = nco_phase_acc[31:30];
        nco_angle    = nco_phase_acc[29:22];
        case (nco_quadrant)
            2'b00: nco_sin =  {4'b0, nco_angle};
            2'b01: nco_sin =  ~{4'b0, nco_angle} + 1;
            2'b10: nco_sin = -{4'b0, nco_angle};
            2'b11: nco_sin = -~{4'b0, nco_angle} - 1;
        endcase
    end

    //=========================================================================
    // Up-mixer (oversampled CIC output × NCO)
    //=========================================================================
    reg  [DATA_WIDTH+NCO_WIDTH-1:0] upmix_result;
    reg  [DATA_WIDTH-1:0]           upmix_out;
    reg                             upmix_valid;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            upmix_result <= 0;
            upmix_out    <= 0;
            upmix_valid  <= 1'b0;
        end else begin
            upmix_valid <= upsamp_valid;
            if (upsamp_valid) begin
                // mix = CIC_out × sine (signed)
                upmix_result <= $signed(cic_int_out[CIC_NUM_STAGES-1][DATA_WIDTH+NCO_WIDTH-2:0])
                              * $signed(nco_sin);
                upmix_out    <= upmix_result[DATA_WIDTH+NCO_WIDTH-2:NCO_WIDTH];
            end
        end
    end

    assign o_data  = upmix_out;
    assign o_valid = upmix_valid;

endmodule
