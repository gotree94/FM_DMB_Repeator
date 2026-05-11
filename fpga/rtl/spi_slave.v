//=============================================================================
// spi_slave.v — SPI Slave Interface (32-bit Frame)
//
// Protocol: Mode 0 (CPOL=0, CPHA=0)
// Frame: [CMD:8][ADDR:8][DATA:16] — MSB first
//   CMD 0x01 = READ  (DATA → MISO on next transaction)
//   CMD 0x02 = WRITE (DATA captured from MOSI)
//
// Register file: 256 × 16-bit (addr 0x00~0xFF)
//=============================================================================

module spi_slave (
    input  wire         i_clk,            // System clock (100 MHz)
    input  wire         i_rst_n,          // Reset (active low)

    // SPI bus
    input  wire         i_sclk,           // SPI clock (from master)
    input  wire         i_mosi,           // Master Out Slave In
    output wire         o_miso,           // Master In Slave Out
    input  wire         i_ss_n,           // Slave Select (active low)

    // Register bus interface (to top)
    output wire  [7:0]  o_reg_addr,       // Register address
    input  wire  [15:0] i_reg_rdata,      // Register read data
    output wire         o_reg_rd,         // Register read strobe
    output wire  [15:0] o_reg_wdata,      // Register write data
    output wire         o_reg_wr,         // Register write strobe
    output wire         o_spi_active,     // SPI transaction active
    output wire         o_spi_irq         // SPI interrupt (transaction done)
);

    //=========================================================================
    // Parameters
    //=========================================================================
    localparam SPI_WIDTH = 32;

    //=========================================================================
    // Signals
    //=========================================================================
    // CDC: SPI domain → sysclk domain (2-FF)
    reg  sclk_ff1, sclk_ff2;
    reg  mosi_ff1, mosi_ff2;
    reg  ss_n_ff1, ss_n_ff2;

    wire sclk_sync;
    wire mosi_sync;
    wire ss_n_sync;

    wire sclk_falling;
    wire sclk_rising;
    reg  sclk_prev;
    reg  ss_n_prev;

    // SPI state
    reg  [4:0]  bit_cnt;          // 0..31
    reg  [31:0] shift_reg;        // Incoming shift register
    reg  [31:0] miso_shift;       // Outgoing shift register
    reg         miso_dir;         // MISO direction (0=read, 1=write)
    reg  [7:0]  cmd_reg;
    reg  [7:0]  addr_reg;
    reg  [15:0] data_reg;

    // Register bus handshake
    reg         reg_rd_pulse;
    reg         reg_wr_pulse;
    reg         spi_active_reg;
    reg         spi_irq_reg;
    reg         transaction_done;

    //=========================================================================
    // CDC — 2-FF synchronizer (SPI pins → sysclk)
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            sclk_ff1 <= 1'b0; sclk_ff2 <= 1'b0;
            mosi_ff1 <= 1'b0; mosi_ff2 <= 1'b0;
            ss_n_ff1 <= 1'b1; ss_n_ff2 <= 1'b1;
        end else begin
            sclk_ff1 <= i_sclk;     sclk_ff2 <= sclk_ff1;
            mosi_ff1 <= i_mosi;     mosi_ff2 <= mosi_ff1;
            ss_n_ff1 <= i_ss_n;     ss_n_ff2 <= ss_n_ff1;
        end
    end

    assign sclk_sync = sclk_ff2;
    assign mosi_sync = mosi_ff2;
    assign ss_n_sync = ss_n_ff2;

    //=========================================================================
    // Edge detection
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            sclk_prev <= 1'b0;
            ss_n_prev <= 1'b1;
        end else begin
            sclk_prev <= sclk_sync;
            ss_n_prev <= ss_n_sync;
        end
    end

    assign sclk_rising  =  sclk_sync && ~sclk_prev;
    assign sclk_falling = ~sclk_sync &&  sclk_prev;

    //=========================================================================
    // SPI State Machine
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            bit_cnt          <= 0;
            shift_reg        <= 0;
            miso_shift       <= 0;
            cmd_reg          <= 0;
            addr_reg         <= 0;
            data_reg         <= 0;
            miso_dir         <= 1'b0;
            reg_rd_pulse     <= 1'b0;
            reg_wr_pulse     <= 1'b0;
            spi_active_reg   <= 1'b0;
            transaction_done <= 1'b0;
            spi_irq_reg      <= 1'b0;
        end else begin
            // Defaults
            reg_rd_pulse     <= 1'b0;
            reg_wr_pulse     <= 1'b0;
            transaction_done <= 1'b0;

            if (ss_n_sync) begin
                // Deselected: reset
                bit_cnt        <= 0;
                spi_active_reg <= 1'b0;
            end else begin
                // Selected
                spi_active_reg <= 1'b1;

                if (sclk_rising) begin
                    // Capture MOSI on rising edge
                    shift_reg <= {shift_reg[30:0], mosi_sync};
                    bit_cnt   <= bit_cnt + 1;

                    if (bit_cnt == 5'd31) begin
                        // Full frame received
                        cmd_reg  <= shift_reg[31:24];
                        addr_reg <= shift_reg[23:16];
                        data_reg <= {shift_reg[14:0], mosi_sync};

                        if (shift_reg[31:24] == 8'h02) begin
                            // WRITE command
                            reg_wr_pulse <= 1'b1;
                        end

                        // Prepare MISO response (for READ)
                        if (shift_reg[31:24] == 8'h01) begin
                            miso_dir     <= 1'b1;  // Drive MISO
                            miso_shift   <= {i_reg_rdata, 16'h0000};
                        end else begin
                            miso_dir     <= 1'b0;  // Hi-Z
                        end

                        transaction_done <= 1'b1;
                        bit_cnt <= 0;
                    end
                end

                if (sclk_falling && miso_dir) begin
                    // Shift out MISO on falling edge
                    miso_shift <= {miso_shift[30:0], 1'b0};
                end
            end

            // IRQ generation (single-cycle pulse)
            if (transaction_done) begin
                spi_irq_reg <= 1'b1;
            end else begin
                spi_irq_reg <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Output assignments
    //=========================================================================
    assign o_miso       = miso_dir ? miso_shift[31] : 1'bz;
    assign o_reg_addr   = addr_reg;
    assign o_reg_wdata  = data_reg;
    assign o_reg_rd     = reg_rd_pulse;
    assign o_reg_wr     = reg_wr_pulse;
    assign o_spi_active = spi_active_reg;
    assign o_spi_irq    = spi_irq_reg;

endmodule
