//=============================================================================
// adc_interface.v — AD9649 LVDS Receiver (14-bit, 80 MSPS)
//
// Primitives: IBUFDS (×14), IDELAYE2 (×14), IDDR (×14), Async FIFO
// Clock: DCO (DDR, 80 MHz) → IDDR → 80 MHz domain → CDC → sysclk (80 MHz)
//=============================================================================

module adc_interface (
    input  wire         i_dco_p,          // ADC DCO (+), 80 MHz DDR
    input  wire         i_dco_n,
    input  wire         i_fclk_p,         // ADC frame clock (+) — unused
    input  wire         i_fclk_n,
    input  wire  [13:0] i_data_p,         // ADC data (+), 14-bit
    input  wire  [13:0] i_data_n,
    input  wire         i_sysclk,         // System clock (80 MHz)
    input  wire         i_sysrst_n,       // System reset (active low)
    input  wire         i_idelay_rst_n,   // IDELAY calibration reset
    input  wire  [4:0]  i_idelay_taps,    // IDELAY tap count

    output wire  [15:0] o_adc_data,       // ADC data (16-bit, zero-padded)
    output wire         o_adc_valid,      // Data valid flag
    output wire         o_fifo_full,      // FIFO overflow
    output wire         o_fifo_empty      // FIFO empty
);

    //=========================================================================
    // Parameters
    //=========================================================================
    localparam IDELAY_CTRL_REF_FREQ = 200;  // MHz
    localparam FIFO_DEPTH           = 4;    // Async FIFO depth

    //=========================================================================
    // Signals
    //=========================================================================
    wire        dco_bufg;           // DCO after BUFG
    wire        dco_bufr;           // DCO after BUFR (div=1)
    wire        dco_pol;            // DCO inverted (for falling edge)
    wire [13:0] data_delayed;       // After IDELAYE2 (×14)
    wire [13:0] data_ddr;           // After IDDR (×14, SAME_EDGE_PIPELINED)
    wire        fifo_wr_en;
    wire        fifo_rd_en;
    wire        fifo_empty;
    wire        fifo_full;
    wire  [3:0] fifo_wr_count;
    wire  [3:0] fifo_rd_count;

    // Gray code synchronization
    reg  [3:0]  wr_ptr_gray;
    reg  [3:0]  wr_ptr_gray_sync1;
    reg  [3:0]  wr_ptr_gray_sync2;
    reg  [3:0]  rd_ptr_gray;
    reg  [3:0]  rd_ptr_gray_sync1;
    reg  [3:0]  rd_ptr_gray_sync2;

    // FIFO memory
    reg  [15:0] fifo_mem [0:FIFO_DEPTH-1];
    reg  [1:0]  wr_ptr;
    reg  [1:0]  rd_ptr;
    reg  [15:0] fifo_out_reg;
    reg         valid_reg;

    //=========================================================================
    // DCO clock buffering
    //=========================================================================
    IBUFGDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"))
        ibufg_dco (.I(i_dco_p), .IB(i_dco_n), .O(dco_bufr));

    BUFG bufg_dco (.I(dco_bufr), .O(dco_bufg));

    //=========================================================================
    // IDELAYE2 (×14, one per data bit)
    //=========================================================================
    genvar i;
    generate
        for (i = 0; i < 14; i = i + 1) begin : gen_idelay
            IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"))
                ibuf_d (.I(i_data_p[i]), .IB(i_data_n[i]), .O(data_delayed_raw));

            IDELAYE2 #(
                .IDELAY_TYPE("VAR_LOAD"),
                .IDELAY_VALUE(0),
                .DELAY_SRC("IDATAIN"),
                .HIGH_PERFORMANCE_MODE("TRUE"),
                .SIGNAL_PATTERN("DATA"),
                .REFCLK_FREQUENCY(IDELAY_CTRL_REF_FREQ)
            ) idelay_inst (
                .IDATAIN(data_delayed_raw),
                .DATAOUT(data_delayed[i]),
                .DATAIN(1'b0),
                .C(i_sysclk),
                .CE(1'b0),
                .INC(1'b0),
                .LD(~i_idelay_rst_n),
                .LDPIPEEN(1'b0),
                .CNTVALUEIN(i_idelay_taps),
                .CNTVALUEOUT(),
                .REGRST(1'b0)
            );
        end
    endgenerate

    //=========================================================================
    // IDDR (SAME_EDGE_PIPELINED) — ×14
    //=========================================================================
    generate
        for (i = 0; i < 14; i = i + 1) begin : gen_iddr
            IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED"), .INIT_Q1(0), .INIT_Q2(0), .SRTYPE("SYNC"))
                iddr_inst (
                .Q1(data_ddr[i]),
                .Q2(),                  // Not used — SAME_EDGE_PIPELINED
                .C(dco_bufg),
                .CE(1'b1),
                .D(data_delayed[i]),
                .R(1'b0),
                .S(1'b0)
            );
        end
    endgenerate

    //=========================================================================
    // Async FIFO — DCO domain → sysclk domain
    //=========================================================================
    // Write pointer (DCO domain)
    always @(posedge dco_bufg or negedge i_sysrst_n) begin
        if (!i_sysrst_n) begin
            wr_ptr <= 0;
        end else begin
            if (!fifo_full) begin
                fifo_mem[wr_ptr] <= {2'b00, data_ddr};  // 14→16-bit zero-pad
                wr_ptr <= wr_ptr + 1;
            end
        end
    end

    assign fifo_wr_en = !fifo_full;

    // Write pointer → Gray code (DCO domain)
    always @(posedge dco_bufg or negedge i_sysrst_n) begin
        if (!i_sysrst_n) begin
            wr_ptr_gray <= 0;
        end else begin
            wr_ptr_gray <= wr_ptr ^ (wr_ptr >> 1);
        end
    end

    // Gray code CDC: DCO → sysclk (2-FF)
    always @(posedge i_sysclk or negedge i_sysrst_n) begin
        if (!i_sysrst_n) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    // Read pointer (sysclk domain)
    always @(posedge i_sysclk or negedge i_sysrst_n) begin
        if (!i_sysrst_n) begin
            rd_ptr <= 0;
        end else begin
            if (!fifo_empty) begin
                fifo_out_reg <= fifo_mem[rd_ptr];
                rd_ptr <= rd_ptr + 1;
            end
        end
    end

    assign fifo_rd_en = !fifo_empty;

    // Read pointer → Gray code (sysclk domain)
    always @(posedge i_sysclk or negedge i_sysrst_n) begin
        if (!i_sysrst_n) begin
            rd_ptr_gray <= 0;
        end else begin
            rd_ptr_gray <= rd_ptr ^ (rd_ptr >> 1);
        end
    end

    // Gray code CDC: sysclk → DCO (2-FF) — for full/empty calculation
    always @(posedge dco_bufg or negedge i_sysrst_n) begin
        if (!i_sysrst_n) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // Gray → Binary conversion for full/empty
    wire [1:0] wr_ptr_sync = {wr_ptr_gray_sync2[1] ^ wr_ptr_gray_sync2[0],
                              wr_ptr_gray_sync2[0]};
    wire [1:0] rd_ptr_dco  = {rd_ptr_gray_sync2[1] ^ rd_ptr_gray_sync2[0],
                              rd_ptr_gray_sync2[0]};

    assign fifo_full  = (wr_ptr == (rd_ptr_dco ^ 2'b10));  // Almost full
    assign fifo_empty = (rd_ptr == wr_ptr_sync);

    // Output
    assign o_adc_data  = fifo_out_reg;
    assign o_adc_valid = fifo_rd_en;

    assign o_fifo_full  = fifo_full;
    assign o_fifo_empty = fifo_empty;

endmodule
