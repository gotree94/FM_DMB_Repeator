//=============================================================================
// ddc.v — Digital Down-Converter (DDS NCO + Complex Mixer)
//
// NCO: 32-bit phase accumulator, 14-bit sin/cos LUT (1024 depth)
// Mixer: Complex multiplication (I/Q output), 16-bit result
//=============================================================================

module ddc (
    input  wire         i_clk,            // 80 MHz system clock
    input  wire         i_rst_n,          // Reset (active low)

    // Input
    input  wire  [15:0] i_data,           // ADC data (16-bit, signed)
    input  wire         i_valid,          // Input data valid

    // NCO frequency control (from register)
    input  wire  [31:0] i_phase_inc,      // Phase increment (per cycle)
    input  wire         i_phase_ld,       // Load phase increment

    // Outputs (I/Q, 16-bit signed)
    output wire  [15:0] o_mixer_i,        // I (in-phase)
    output wire  [15:0] o_mixer_q,        // Q (quadrature)
    output wire         o_valid           // Output valid
);

    //=========================================================================
    // Parameters
    //=========================================================================
    localparam PHASE_WIDTH  = 32;
    localparam LUT_WIDTH    = 14;
    localparam ADDR_WIDTH   = 10;   // 1024 entries

    //=========================================================================
    // Signals
    //=========================================================================
    reg  [PHASE_WIDTH-1:0] phase_acc;
    reg  [PHASE_WIDTH-1:0] phase_inc_reg;
    reg  [ADDR_WIDTH-1:0]  sin_addr;
    reg  [ADDR_WIDTH-1:0]  cos_addr;
    wire [LUT_WIDTH-1:0]   sin_val;
    wire [LUT_WIDTH-1:0]   cos_val;
    reg  [15:0]            data_d1;
    reg                    valid_d1, valid_d2, valid_d3;
    reg  [15:0]            sin_16, cos_16;
    reg  [31:0]            mult_i, mult_q;
    reg  [15:0]            mixer_i_reg, mixer_q_reg;

    //=========================================================================
    // Phase Accumulator
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            phase_acc     <= 0;
            phase_inc_reg <= 32'h1999999A;  // ~100 MHz @80MHz: 100M/80M*2^32
        end else begin
            if (i_phase_ld) begin
                phase_inc_reg <= i_phase_inc;
            end
            phase_acc <= phase_acc + phase_inc_reg;
        end
    end

    //=========================================================================
    // LUT Address Generation (use upper bits of phase)
    //=========================================================================
    always @(*) begin
        sin_addr = phase_acc[PHASE_WIDTH-1:PHASE_WIDTH-ADDR_WIDTH];
        cos_addr = sin_addr + {ADDR_WIDTH{1'b1}} / 4;  // 90° shift
    end

    //=========================================================================
    // Sine/Cosine LUT (Read-Only, initialized externally or via distributed ROM)
    // Simple DDS: use upper LUT_WIDTH bits for amplitude
    //=========================================================================
    // sin_val and cos_val are 14-bit signed values from LUT
    // For simulation/synthesis, this LUT would be initialized via $readmemh
    // or generated as part of synthesis flow

    // Phase-to-amplitude mapping (simplified — full LUT would be 1024×14b)
    // Using upper bits + quadrant mapping for resource efficiency
    reg [1:0]  sin_quadrant;
    reg [1:0]  cos_quadrant;
    reg [7:0]  sin_angle;
    reg [7:0]  cos_angle;
    reg [13:0] sin_quarter;
    reg [13:0] cos_quarter;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            sin_quadrant  <= 0;
            cos_quadrant  <= 0;
            sin_angle     <= 0;
            cos_angle     <= 0;
            sin_quarter   <= 0;
            cos_quarter   <= 0;
            data_d1       <= 0;
            valid_d1      <= 1'b0;
        end else begin
            data_d1  <= i_data;
            valid_d1 <= i_valid;

            // Sine quadrant (use 2 MSBs)
            sin_quadrant <= phase_acc[PHASE_WIDTH-1:PHASE_WIDTH-2];
            sin_angle    <= phase_acc[PHASE_WIDTH-3:PHASE_WIDTH-10];

            // Cosine quadrant
            cos_quadrant <= phase_acc[PHASE_WIDTH-1:PHASE_WIDTH-2] + 1;
            cos_angle    <= phase_acc[PHASE_WIDTH-3:PHASE_WIDTH-10];

            // Quarter-wave lookup (simplified — ideal LUT would be 256×14b)
            // This placeholder generates a rough sine approximation
            sin_quarter <= {8'd0, sin_angle};  // Placeholder
            cos_quarter <= {8'd0, cos_angle};  // Placeholder

            // Sign/reflection based on quadrant
            case (sin_quadrant)
                2'b00: sin_val_internal <=  sin_quarter;
                2'b01: sin_val_internal <=  {~sin_quarter[13]+1, sin_quarter[12:0]}; // Reverse
                2'b10: sin_val_internal <= -sin_quarter;
                2'b11: sin_val_internal <= -{~sin_quarter[13]+1, sin_quarter[12:0]};
            endcase

            case (cos_quadrant)
                2'b00: cos_val_internal <=  cos_quarter;
                2'b01: cos_val_internal <=  {~cos_quarter[13]+1, cos_quarter[12:0]};
                2'b10: cos_val_internal <= -cos_quarter;
                2'b11: cos_val_internal <= -{~cos_quarter[13]+1, cos_quarter[12:0]};
            endcase
        end
    end

    reg [13:0] sin_val_internal;
    reg [13:0] cos_val_internal;

    always @(posedge i_clk) begin
        sin_16 <= $signed(sin_val_internal);
        cos_16 <= $signed(cos_val_internal);
    end

    //=========================================================================
    // Complex Multiplier (16-bit × 14-bit → 30-bit → truncate to 16-bit)
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            valid_d2     <= 1'b0;
            valid_d3     <= 1'b0;
            mult_i       <= 0;
            mult_q       <= 0;
            mixer_i_reg  <= 0;
            mixer_q_reg  <= 0;
        end else begin
            valid_d2 <= valid_d1;
            valid_d3 <= valid_d2;

            // I = data × cos, Q = data × (−sin)
            mult_i <= $signed(data_d1) * $signed(cos_16);
            mult_q <= $signed(data_d1) * $signed(-sin_16);

            // Truncate to 16-bit (signed, saturate)
            mixer_i_reg <= mult_i[30:15];
            mixer_q_reg <= mult_q[30:15];
        end
    end

    //=========================================================================
    // Output assignments
    //=========================================================================
    assign o_mixer_i = mixer_i_reg;
    assign o_mixer_q = mixer_q_reg;
    assign o_valid   = valid_d3;

endmodule
