//=============================================================================
// dac_interface.v — AD9742 Dual DAC Driver (12-bit, 210 MSPS)
//
// Two AD9742 DACs (FM + DMB), 2-stage pipeline, underrun detection
//=============================================================================

module dac_interface (
    input  wire         i_clk,            // DAC clock (80 MHz)
    input  wire         i_rst_n,          // Reset (active low)

    // DAC0 (FM path)
    input  wire  [15:0] i_data_fm,        // FM DAC data (16-bit)
    input  wire         i_valid_fm,       // FM data valid
    output wire  [11:0] o_dac_fm_data,    // FM DAC (12-bit, upper bits)
    output wire         o_dac_fm_wrt,     // FM DAC write strobe

    // DAC1 (DMB path)
    input  wire  [15:0] i_data_dmb,       // DMB DAC data (16-bit)
    input  wire         i_valid_dmb,      // DMB data valid
    output wire  [11:0] o_dac_dmb_data,   // DMB DAC (12-bit, upper bits)
    output wire         o_dac_dmb_wrt,    // DMB DAC write strobe

    // Status
    output wire         o_underrun_fm,    // FM underrun flag
    output wire         o_underrun_dmb    // DMB underrun flag
);

    //=========================================================================
    // Pipeline registers (2-stage)
    //=========================================================================
    reg [11:0] fm_pipe1, fm_pipe2;
    reg [11:0] dmb_pipe1, dmb_pipe2;
    reg        fm_wrt_pipe1, fm_wrt_pipe2;
    reg        dmb_wrt_pipe1, dmb_wrt_pipe2;

    // Undercount monitors
    reg [4:0]  fm_underrun_cnt;
    reg [4:0]  dmb_underrun_cnt;
    reg        fm_underrun_reg;
    reg        dmb_underrun_reg;

    //=========================================================================
    // DAC pipeline
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            fm_pipe1     <= 12'd0;
            fm_pipe2     <= 12'd0;
            fm_wrt_pipe1 <= 1'b0;
            fm_wrt_pipe2 <= 1'b0;

            dmb_pipe1     <= 12'd0;
            dmb_pipe2     <= 12'd0;
            dmb_wrt_pipe1 <= 1'b0;
            dmb_wrt_pipe2 <= 1'b0;
        end else begin
            // Stage 1: input capture
            fm_pipe1     <= i_data_fm[15:4];     // Truncate upper 12 bits
            fm_wrt_pipe1 <= i_valid_fm;

            dmb_pipe1     <= i_data_dmb[15:4];
            dmb_wrt_pipe1 <= i_valid_dmb;

            // Stage 2: output to DAC
            fm_pipe2     <= fm_pipe1;
            fm_wrt_pipe2 <= fm_wrt_pipe1;

            dmb_pipe2     <= dmb_pipe1;
            dmb_wrt_pipe2 <= dmb_wrt_pipe1;
        end
    end

    //=========================================================================
    // Underrun detection
    // Count consecutive cycles without valid data
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            fm_underrun_cnt  <= 0;
            fm_underrun_reg  <= 1'b0;
        end else begin
            if (i_valid_fm) begin
                fm_underrun_cnt <= 0;
                fm_underrun_reg <= 1'b0;
            end else if (fm_underrun_cnt < 5'd16) begin
                fm_underrun_cnt <= fm_underrun_cnt + 1;
                if (fm_underrun_cnt == 5'd15) begin
                    fm_underrun_reg <= 1'b1;
                end
            end
        end
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            dmb_underrun_cnt  <= 0;
            dmb_underrun_reg  <= 1'b0;
        end else begin
            if (i_valid_dmb) begin
                dmb_underrun_cnt <= 0;
                dmb_underrun_reg <= 1'b0;
            end else if (dmb_underrun_cnt < 5'd16) begin
                dmb_underrun_cnt <= dmb_underrun_cnt + 1;
                if (dmb_underrun_cnt == 5'd15) begin
                    dmb_underrun_reg <= 1'b1;
                end
            end
        end
    end

    //=========================================================================
    // Output assignments
    //=========================================================================
    assign o_dac_fm_data  = fm_pipe2;
    assign o_dac_fm_wrt   = fm_wrt_pipe2;

    assign o_dac_dmb_data = dmb_pipe2;
    assign o_dac_dmb_wrt  = dmb_wrt_pipe2;

    assign o_underrun_fm  = fm_underrun_reg;
    assign o_underrun_dmb = dmb_underrun_reg;

endmodule
