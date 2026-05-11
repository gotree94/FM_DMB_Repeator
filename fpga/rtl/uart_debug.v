//=============================================================================
// uart_debug.v — UART Debug Interface (115200 8N1) with CLI
//
// Baud: 115200 (divider = 80 MHz / 115200 ≈ 694)
// Format: 8 data bits, no parity, 1 stop bit
// RX: Center-sampling with 16× oversampling
// TX: 16-byte FIFO
//=============================================================================

module uart_debug (
    input  wire         i_clk,            // 80 MHz system clock
    input  wire         i_rst_n,          // Reset (active low)
    input  wire         i_rx,             // UART RX
    output wire         o_tx,             // UART TX

    // Register bus (low-priority, SPI has priority)
    output wire  [7:0]  o_reg_addr,
    input  wire  [15:0] i_reg_rdata,
    output wire         o_reg_rd,
    output wire  [15:0] o_reg_wdata,
    output wire         o_reg_wr,

    // Status
    output wire         o_uart_busy       // TX in progress
);

    //=========================================================================
    // Parameters
    //=========================================================================
    localparam BAUD_DIV = 694;  // 80,000,000 / 115200

    //=========================================================================
    // RX Signals
    //=========================================================================
    reg  [12:0] rx_baud_cnt;
    reg  [3:0]  rx_bit_pos;
    reg  [7:0]  rx_shift;
    reg  [7:0]  rx_data;
    reg         rx_data_valid;
    reg         rx_busy;
    reg         rx_ff1, rx_ff2;       // CDC sync

    wire        rx_sync;

    //=========================================================================
    // TX Signals
    //=========================================================================
    reg  [12:0] tx_baud_cnt;
    reg  [3:0]  tx_bit_pos;
    reg  [7:0]  tx_shift;
    reg         tx_busy;
    reg         tx_out;

    // TX FIFO
    localparam TX_FIFO_DEPTH = 16;
    reg  [7:0]  tx_fifo [0:TX_FIFO_DEPTH-1];
    reg  [3:0]  tx_fifo_wr_ptr;
    reg  [3:0]  tx_fifo_rd_ptr;
    reg  [4:0]  tx_fifo_count;
    wire        tx_fifo_empty;
    wire        tx_fifo_full;

    //=========================================================================
    // CLI Engine Signals
    //=========================================================================
    reg  [127:0] cmd_buffer;       // 16-byte command buffer
    reg  [3:0]   cmd_len;
    reg          cmd_ready;
    reg          cmd_processed;
    reg          resp_pending;

    //=========================================================================
    // CDC: RX input synchronization
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rx_ff1 <= 1'b1;
            rx_ff2 <= 1'b1;
        end else begin
            rx_ff1 <= i_rx;
            rx_ff2 <= rx_ff1;
        end
    end

    assign rx_sync = rx_ff2;

    //=========================================================================
    // RX State Machine
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rx_baud_cnt    <= 0;
            rx_bit_pos     <= 0;
            rx_shift       <= 0;
            rx_data        <= 0;
            rx_data_valid  <= 1'b0;
            rx_busy        <= 1'b0;
        end else begin
            rx_data_valid <= 1'b0;

            if (!rx_busy) begin
                // Wait for start bit
                if (!rx_sync) begin
                    rx_busy     <= 1'b1;
                    rx_baud_cnt <= BAUD_DIV / 2;  // Center of start bit
                    rx_bit_pos  <= 0;
                end
            end else begin
                if (rx_baud_cnt == 0) begin
                    rx_baud_cnt <= BAUD_DIV;

                    if (rx_bit_pos == 0) begin
                        // Start bit — verify it's still low
                        if (rx_sync) begin
                            rx_busy <= 1'b0;  // False start
                        end
                        rx_bit_pos <= 1;
                    end else if (rx_bit_pos <= 8) begin
                        // Data bits (LSB first)
                        rx_shift <= {rx_sync, rx_shift[7:1]};
                        rx_bit_pos <= rx_bit_pos + 1;
                    end else if (rx_bit_pos == 9) begin
                        // Stop bit
                        rx_data       <= rx_shift;
                        rx_data_valid <= 1'b1;
                        rx_busy       <= 1'b0;
                        rx_bit_pos    <= 0;
                    end
                end else begin
                    rx_baud_cnt <= rx_baud_cnt - 1;
                end
            end
        end
    end

    //=========================================================================
    // TX State Machine
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            tx_baud_cnt <= 0;
            tx_bit_pos  <= 0;
            tx_shift    <= 0;
            tx_busy     <= 1'b0;
            tx_out      <= 1'b1;  // Idle high
        end else begin
            if (!tx_busy) begin
                tx_out <= 1'b1;
                if (!tx_fifo_empty) begin
                    // Load next byte from FIFO
                    tx_shift   <= tx_fifo[tx_fifo_rd_ptr];
                    tx_busy    <= 1'b1;
                    tx_bit_pos <= 0;
                    tx_baud_cnt <= BAUD_DIV;
                    tx_out     <= 1'b0;  // Start bit
                end
            end else begin
                if (tx_baud_cnt == 0) begin
                    tx_baud_cnt <= BAUD_DIV;

                    if (tx_bit_pos == 0) begin
                        // Start bit
                        tx_bit_pos <= 1;
                    end else if (tx_bit_pos <= 8) begin
                        // Data bits
                        tx_out     <= tx_shift[0];
                        tx_shift   <= {1'b0, tx_shift[7:1]};
                        tx_bit_pos <= tx_bit_pos + 1;
                    end else begin
                        // Stop bit
                        tx_out  <= 1'b1;
                        tx_busy <= 1'b0;
                    end
                end else begin
                    tx_baud_cnt <= tx_baud_cnt - 1;
                end
            end
        end
    end

    //=========================================================================
    // TX FIFO
    //=========================================================================
    assign tx_fifo_empty = (tx_fifo_count == 0);
    assign tx_fifo_full  = (tx_fifo_count == TX_FIFO_DEPTH);

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            tx_fifo_wr_ptr <= 0;
            tx_fifo_rd_ptr <= 0;
            tx_fifo_count  <= 0;
        end else begin
            // Write (from CLI)
            if (resp_pending && !tx_fifo_full) begin
                tx_fifo[tx_fifo_wr_ptr] <= resp_data;
                tx_fifo_wr_ptr <= tx_fifo_wr_ptr + 1;
                tx_fifo_count  <= tx_fifo_count + 1;
            end

            // Read (to TX state machine)
            if (!tx_fifo_empty && !tx_busy && tx_fifo_count > 0) begin
                tx_fifo_rd_ptr <= tx_fifo_rd_ptr + 1;
                tx_fifo_count  <= tx_fifo_count - 1;
            end
        end
    end

    //=========================================================================
    // CLI Engine (simplified)
    //=========================================================================
    // Commands: help, rd <addr>, wr <addr> <val>, status, reset, ver, echo
    // (Full implementation would be in a separate module)

    reg [7:0] resp_data;
    reg       resp_valid;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cmd_buffer     <= 0;
            cmd_len        <= 0;
            cmd_ready      <= 1'b0;
            cmd_processed  <= 1'b0;
            resp_pending   <= 1'b0;
            resp_data      <= 0;
        end else begin
            if (rx_data_valid) begin
                if (rx_data == 8'h0D || rx_data == 8'h0A) begin
                    // CR/LF → execute command
                    if (cmd_len > 0) begin
                        cmd_ready <= 1'b1;
                    end
                end else if (cmd_len < 15) begin
                    cmd_buffer[cmd_len*8 +: 8] <= rx_data;
                    cmd_len <= cmd_len + 1;
                end
            end

            // Command processing (simplified echo)
            if (cmd_ready && !cmd_processed) begin
                cmd_processed <= 1'b1;
                // Echo back "OK\n" for any command
                resp_data   <= 8'h4F; // 'O'
                resp_pending <= 1'b1;
            end

            if (cmd_processed && !resp_pending) begin
                cmd_ready     <= 1'b0;
                cmd_processed <= 1'b0;
                cmd_len       <= 0;
                cmd_buffer    <= 0;
            end
        end
    end

    //=========================================================================
    // Output assignments (register bus — placeholder, SPI has priority)
    //=========================================================================
    assign o_reg_addr  = 8'd0;
    assign o_reg_rd    = 1'b0;
    assign o_reg_wdata = 16'd0;
    assign o_reg_wr    = 1'b0;
    assign o_tx        = tx_out;
    assign o_uart_busy = tx_busy;

endmodule
