//=============================================================================
// clk_manager.v — MMCM/PLL Clock Generator
// Xilinx Kintex-7: MMCME2_ADV primitive
//
// Input:  10.000 MHz reference (LVDS)
// Outputs:
//   o_clk_80m      — System clock (80 MHz)
//   o_clk_200m     — IDELAY reference (200 MHz)
//   o_clk_100m     — SPI/UART clock domain (100 MHz)
//   o_clk_25m      — Slow domain (25 MHz)
//   o_clk_80m_180  — ADC DDR strobe (80 MHz @ 180°)
//   o_clk_12m8     — Fractional 12.8 MHz (for NCO reference)
//   o_mmcm_locked  — MMCM lock indicator
//=============================================================================

module clk_manager (
    // External
    input  wire         i_refclk_p,      // 10 MHz LVDS (+)
    input  wire         i_refclk_n,      // 10 MHz LVDS (-)
    input  wire         i_rst_n,         // Async reset (active low)

    // Output clocks
    output wire         o_clk_80m,       // 80.000 MHz — sysclk
    output wire         o_clk_200m,      // 200.000 MHz — IDELAY Ctrl
    output wire         o_clk_100m,      // 100.000 MHz — SPI/UART
    output wire         o_clk_25m,       // 25.000 MHz — slow domain
    output wire         o_clk_80m_180,   // 80.000 MHz @ 180° — ADC DDR
    output wire         o_clk_12m8,      // 12.800 MHz — fractional (NCO ref)

    // Status
    output wire         o_mmcm_locked    // MMCM lock
);

    //=========================================================================
    // Parameters
    //=========================================================================
    // MMCM VCO: Fvco = Fclkin × M / D
    // Fclkin = 10 MHz, D = 1, M = 80 → Fvco = 800 MHz
    // CLKOUTx = Fvco / Ox
    //   CLKOUT0: 800 / 10 = 80.000 MHz  (sysclk)
    //   CLKOUT1: 800 / 4  = 200.000 MHz (IDELAY)
    //   CLKOUT2: 800 / 8  = 100.000 MHz (SPI/UART)
    //   CLKOUT3: 800 / 32 = 25.000 MHz  (slow)
    //   CLKOUT4: 800 / 10 = 80.000 MHz @ 180° (ADC DDR)

    localparam real CLKIN_PERIOD   = 100.0;  // 10 MHz → 100 ns
    localparam real CLKFBOUT_MULT  = 80.0;   // M = 80
    localparam real DIVCLK_DIVIDE  = 1.0;    // D = 1
    localparam real CLKOUT0_DIV    = 10.0;   // 80 MHz
    localparam real CLKOUT1_DIV    = 4.0;    // 200 MHz
    localparam real CLKOUT2_DIV    = 8.0;    // 100 MHz
    localparam real CLKOUT3_DIV    = 32.0;   // 25 MHz
    localparam real CLKOUT4_DIV    = 10.0;   // 80 MHz

    //=========================================================================
    // Signals
    //=========================================================================
    wire        mmcm_fb_out;
    wire        mmcm_fb_in;
    wire        mmcm_locked;
    wire        clk_80m_raw;
    wire        clk_200m_raw;
    wire        clk_100m_raw;
    wire        clk_25m_raw;
    wire        clk_80m_180_raw;
    reg         sync_rst_n_ff1;
    reg         sync_rst_n_ff2;
    wire        mmcm_rst = ~sync_rst_n_ff2;

    //=========================================================================
    // Reset synchronization (CDC)
    //=========================================================================
    always @(posedge clk_80m_raw or negedge i_rst_n) begin
        if (!i_rst_n) begin
            sync_rst_n_ff1 <= 1'b0;
            sync_rst_n_ff2 <= 1'b0;
        end else begin
            sync_rst_n_ff1 <= 1'b1;
            sync_rst_n_ff2 <= sync_rst_n_ff1;
        end
    end

    //=========================================================================
    // MMCME2_ADV instantiation
    //=========================================================================
    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKOUT4_CASCADE      ("FALSE"),
        .COMPENSATION         ("ZHOLD"),
        .STARTUP_WAIT         ("FALSE"),
        .DIVCLK_DIVIDE        (DIVCLK_DIVIDE),
        .CLKFBOUT_MULT_F      (CLKFBOUT_MULT),
        .CLKFBOUT_PHASE       (0.0),
        .CLKFBOUT_USE_FINE_PS ("FALSE"),
        .CLKOUT0_DIVIDE_F     (CLKOUT0_DIV),
        .CLKOUT0_PHASE        (0.0),
        .CLKOUT0_DUTY_CYCLE   (0.5),
        .CLKOUT0_USE_FINE_PS  ("FALSE"),
        .CLKOUT1_DIVIDE       (CLKOUT1_DIV),
        .CLKOUT1_PHASE        (0.0),
        .CLKOUT1_DUTY_CYCLE   (0.5),
        .CLKOUT1_USE_FINE_PS  ("FALSE"),
        .CLKOUT2_DIVIDE       (CLKOUT2_DIV),
        .CLKOUT2_PHASE        (0.0),
        .CLKOUT2_DUTY_CYCLE   (0.5),
        .CLKOUT2_USE_FINE_PS  ("FALSE"),
        .CLKOUT3_DIVIDE       (CLKOUT3_DIV),
        .CLKOUT3_PHASE        (0.0),
        .CLKOUT3_DUTY_CYCLE   (0.5),
        .CLKOUT3_USE_FINE_PS  ("FALSE"),
        .CLKOUT4_DIVIDE       (CLKOUT4_DIV),
        .CLKOUT4_PHASE        (180.0),       // 180° phase shift
        .CLKOUT4_DUTY_CYCLE   (0.5),
        .CLKOUT4_USE_FINE_PS  ("FALSE"),
        .CLKIN1_PERIOD        (CLKIN_PERIOD),
        .REF_JITTER1          (0.010)
    ) mmcm_inst (
        // Clock inputs
        .CLKIN1           (i_refclk_p),
        .CLKIN2           (1'b0),
        .CLKINSEL         (1'b1),
        // Feedback
        .CLKFBOUT         (mmcm_fb_out),
        .CLKFBIN          (mmcm_fb_in),
        // Output clocks
        .CLKOUT0          (clk_80m_raw),
        .CLKOUT1          (clk_200m_raw),
        .CLKOUT2          (clk_100m_raw),
        .CLKOUT3          (clk_25m_raw),
        .CLKOUT4          (clk_80m_180_raw),
        .CLKOUT5          (),
        .CLKOUT6          (),
        // Dynamic phase shift (unused)
        .PSCLK            (1'b0),
        .PSEN             (1'b0),
        .PSINCDEC         (1'b0),
        .PSDONE           (),
        // Reset and lock
        .PWRDWN           (1'b0),
        .RST              (mmcm_rst),
        .LOCKED           (mmcm_locked),
        // DRP (unused)
        .DADDR            (7'd0),
        .DCLK             (1'b0),
        .DEN              (1'b0),
        .DI               (16'd0),
        .DO               (),
        .DRDY             (),
        .DWE              (1'b0)
    );

    assign mmcm_fb_in = mmcm_fb_out;

    //=========================================================================
    // Output buffering (BUFG)
    //=========================================================================
    BUFG bufg_80m    (.I(clk_80m_raw),      .O(o_clk_80m));
    BUFG bufg_200m   (.I(clk_200m_raw),     .O(o_clk_200m));
    BUFG bufg_100m   (.I(clk_100m_raw),     .O(o_clk_100m));
    BUFG bufg_25m    (.I(clk_25m_raw),      .O(o_clk_25m));
    BUFG bufg_80m180 (.I(clk_80m_180_raw),  .O(o_clk_80m_180));

    //=========================================================================
    // Fractional 12.8 MHz from 80 MHz
    // 80 MHz / 6.25 = 12.8 MHz → accum(25-bit), step(4-bit)
    //=========================================================================
    localparam FRAC_ACCUM_W = 25;
    localparam FRAC_STEP    = 5;  // 2^25 / 6.25 ≈ 5,368,708 / 33,554,432
    reg [FRAC_ACCUM_W-1:0]  frac_accum;
    reg                     clk_12m8_reg;

    always @(posedge o_clk_80m or negedge sync_rst_n_ff2) begin
        if (!sync_rst_n_ff2) begin
            frac_accum  <= 0;
            clk_12m8_reg <= 1'b0;
        end else if (mmcm_locked) begin
            frac_accum <= frac_accum + FRAC_STEP;
            if (&frac_accum[FRAC_ACCUM_W-1:FRAC_ACCUM_W-2]) begin
                clk_12m8_reg <= ~clk_12m8_reg;
            end
        end
    end

    BUFG bufg_12m8 (.I(clk_12m8_reg), .O(o_clk_12m8));

    //=========================================================================
    // Lock output
    //=========================================================================
    assign o_mmcm_locked = mmcm_locked;

endmodule
