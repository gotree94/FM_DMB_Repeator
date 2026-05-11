//=============================================================================
// sys_monitor.v — System Monitor (I2C LM75A, VSWR, Alarms)
//
// I2C bit-bang master for LM75A temperature sensor
// VSWR calculation from forward/reflected power ADC inputs
// 3 alarm outputs: over-temperature, high VSWR, PA fault
// Scan cycle: 50 ms
//=============================================================================

module sys_monitor (
    input  wire         i_clk,            // 80 MHz system clock
    input  wire         i_rst_n,          // Reset (active low)

    // I2C bus (to LM75A)
    output wire         o_i2c_scl,        // I2C clock
    inout  wire         io_i2c_sda,       // I2C data

    // VSWR inputs (from ADC envelope detectors)
    input  wire  [15:0] i_vfwd,           // Forward power (magnitude)
    input  wire  [15:0] i_vref,           // Reflected power (magnitude)

    // Alarm outputs
    output wire         o_alarm_ot,       // Over-temperature
    output wire         o_alarm_vswr,     // High VSWR
    output wire         o_alarm_pa,       // PA fault

    // Status registers (read by SPI/UART)
    output wire  [15:0] o_temp_raw,       // Temperature raw value (LM75A)
    output wire  [7:0]  o_vswr_idx,       // VSWR band index (0=OK, 5=critical)
    output wire         o_scan_busy       // Scan in progress
);

    //=========================================================================
    // Parameters
    //=========================================================================
    localparam HALF_PERIOD   = 400;    // 80 MHz / 100 kHz / 2 = 400
    localparam LM75A_ADDR    = 7'h48;
    localparam SCAN_INTERVAL = 4000000; // 50 ms @ 80 MHz (4,000,000 cycles)

    // VSWR thresholds (5 bands)
    localparam VSWR_BAND_1 = 32'd0;     // Ratio ≥ 2.0 (VSWR 1.2:1)
    localparam VSWR_BAND_2 = 32'd0;     // Ratio ≥ 2.0 (VSWR 1.5:1)
    localparam VSWR_BAND_3 = 32'd0;     // Ratio ≥ 2.0 (VSWR 2.0:1)
    localparam VSWR_BAND_4 = 32'd0;     // Ratio ≥ 2.0 (VSWR 3.0:1)
    localparam VSWR_BAND_5 = 32'd0;     // Ratio ≥ 2.0 (VSWR 5.0:1)

    // Simplified VSWR bands using reflected power threshold
    localparam REFL_THRESH_1 = 16'd100;  // VSWR ~1.2:1
    localparam REFL_THRESH_2 = 16'd250;  // VSWR ~1.5:1
    localparam REFL_THRESH_3 = 16'd500;  // VSWR ~2.0:1
    localparam REFL_THRESH_4 = 16'd1000; // VSWR ~3.0:1
    localparam REFL_THRESH_5 = 16'd2000; // VSWR ~5.0:1

    // Temperature thresholds
    localparam TEMP_ALARM_THRESH = 16'h4B00; // 75°C (75 << 8)

    //=========================================================================
    // Timing signals
    //=========================================================================
    reg [31:0] scan_timer;
    reg        scan_tick;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            scan_timer <= 0;
            scan_tick  <= 1'b0;
        end else begin
            scan_tick <= 1'b0;
            if (scan_timer >= SCAN_INTERVAL) begin
                scan_timer <= 0;
                scan_tick  <= 1'b1;
            end else begin
                scan_timer <= scan_timer + 1;
            end
        end
    end

    //=========================================================================
    // I2C Bit-Bang Master (LM75A)
    //=========================================================================
    reg [7:0]  i2c_state;
    reg [31:0] i2c_timer;
    reg        scl_reg;
    reg        sda_out_reg;
    reg        sda_in;
    reg        sda_dir;        // 0=output, 1=input
    reg [15:0] temp_raw_reg;
    reg        i2c_busy;
    reg        i2c_done;

    localparam I2C_IDLE       = 8'd0;
    localparam I2C_START      = 8'd1;
    localparam I2C_SEND_ADDR  = 8'd2;
    localparam I2C_ACK_ADDR   = 8'd3;
    localparam I2C_SEND_REG   = 8'd4;
    localparam I2C_ACK_REG    = 8'd5;
    localparam I2C_REP_START  = 8'd6;
    localparam I2C_SEND_RD    = 8'd7;
    localparam I2C_ACK_RD     = 8'd8;
    localparam I2C_READ_MSB   = 8'd9;
    localparam I2C_ACK_MSB    = 8'd10;
    localparam I2C_READ_LSB   = 8'd11;
    localparam I2C_NACK       = 8'd12;
    localparam I2C_STOP       = 8'd13;
    localparam I2C_DONE       = 8'd14;

    reg [3:0]  bit_idx;
    reg [7:0]  tx_byte;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            i2c_state   <= I2C_IDLE;
            i2c_timer   <= 0;
            scl_reg     <= 1'b1;
            sda_out_reg <= 1'b1;
            sda_dir     <= 1'b0;
            i2c_busy    <= 1'b0;
            i2c_done    <= 1'b0;
            temp_raw_reg <= 0;
            bit_idx     <= 0;
            tx_byte     <= 0;
        end else begin
            i2c_done <= 1'b0;

            case (i2c_state)
                I2C_IDLE: begin
                    scl_reg     <= 1'b1;
                    sda_out_reg <= 1'b1;
                    sda_dir     <= 1'b0;
                    if (scan_tick) begin
                        i2c_busy  <= 1'b1;
                        i2c_state <= I2C_START;
                        i2c_timer <= 0;
                    end
                end

                I2C_START: begin
                    // SDA low while SCL high → START condition
                    if (i2c_timer < HALF_PERIOD) begin
                        sda_out_reg <= 1'b1;
                        i2c_timer <= i2c_timer + 1;
                    end else if (i2c_timer < HALF_PERIOD * 2) begin
                        sda_out_reg <= 1'b0;
                        i2c_timer <= i2c_timer + 1;
                    end else begin
                        scl_reg   <= 1'b0;
                        i2c_timer <= 0;
                        bit_idx   <= 4'd7;
                        tx_byte   <= {LM75A_ADDR, 1'b0}; // Write address
                        i2c_state <= I2C_SEND_ADDR;
                    end
                end

                I2C_SEND_ADDR: begin
                    if (i2c_timer < HALF_PERIOD) begin
                        i2c_timer <= i2c_timer + 1;
                    end else begin
                        scl_reg     <= ~scl_reg;  // Toggle SCL
                        if (scl_reg) begin
                            // SCL high: set data
                            sda_out_reg <= tx_byte[bit_idx];
                            sda_dir     <= 1'b0;
                            if (bit_idx == 0) begin
                                bit_idx   <= 0;
                                i2c_state <= I2C_ACK_ADDR;
                            end else begin
                                bit_idx <= bit_idx - 1;
                            end
                        end
                        i2c_timer <= 0;
                    end
                end

                I2C_ACK_ADDR: begin
                    if (i2c_timer < HALF_PERIOD) begin
                        i2c_timer <= i2c_timer + 1;
                    end else begin
                        scl_reg <= ~scl_reg;
                        if (scl_reg) begin
                            sda_dir <= 1'b1;  // Release SDA for ACK
                        end else begin
                            // ACK sampled
                            tx_byte   <= 8'h00;  // Temperature register
                            bit_idx   <= 4'd7;
                            i2c_state <= I2C_SEND_REG;
                        end
                        i2c_timer <= 0;
                    end
                end

                I2C_SEND_REG: begin
                    if (i2c_timer < HALF_PERIOD) begin
                        i2c_timer <= i2c_timer + 1;
                    end else begin
                        scl_reg <= ~scl_reg;
                        if (scl_reg) begin
                            sda_out_reg <= tx_byte[bit_idx];
                            sda_dir     <= 1'b0;
                            if (bit_idx == 0) begin
                                i2c_state <= I2C_ACK_REG;
                            end else begin
                                bit_idx <= bit_idx - 1;
                            end
                        end
                        i2c_timer <= 0;
                    end
                end

                I2C_ACK_REG: begin
                    if (i2c_timer < HALF_PERIOD) begin
                        i2c_timer <= i2c_timer + 1;
                    end else begin
                        scl_reg <= ~scl_reg;
                        if (scl_reg) begin
                            sda_dir <= 1'b1;
                        end else begin
                            // Repeated START
                            i2c_state <= I2C_REP_START;
                            i2c_timer <= 0;
                        end
                        i2c_timer <= 0;
                    end
                end

                I2C_REP_START: begin
                    if (i2c_timer < HALF_PERIOD) begin
                        sda_out_reg <= 1'b0;
                        i2c_timer <= i2c_timer + 1;
                    end else begin
                        scl_reg   <= 1'b0;
                        i2c_timer <= 0;
                        tx_byte   <= {LM75A_ADDR, 1'b1}; // Read address
                        bit_idx   <= 4'd7;
                        i2c_state <= I2C_SEND_RD;
                    end
                end

                I2C_SEND_RD: begin
                    if (i2c_timer < HALF_PERIOD) begin
                        i2c_timer <= i2c_timer + 1;
                    end else begin
                        scl_reg <= ~scl_reg;
                        if (scl_reg) begin
                            sda_out_reg <= tx_byte[bit_idx];
                            sda_dir     <= 1'b0;
                            if (bit_idx == 0) begin
                                i2c_state <= I2C_ACK_RD;
                            end else begin
                                bit_idx <= bit_idx - 1;
                            end
                        end
                        i2c_timer <= 0;
                    end
                end

                I2C_ACK_RD: begin
                    if (i2c_timer < HALF_PERIOD) begin
                        i2c_timer <= i2c_timer + 1;
                    end else begin
                        scl_reg <= ~scl_reg;
                        if (scl_reg) begin
                            sda_dir <= 1'b1;
                        end else begin
                            bit_idx   <= 4'd7;
                            i2c_state <= I2C_READ_MSB;
                        end
                        i2c_timer <= 0;
                    end
                end

                I2C_READ_MSB: begin
                    if (i2c_timer < HALF_PERIOD) begin
                        i2c_timer <= i2c_timer + 1;
                    end else begin
                        scl_reg <= ~scl_reg;
                        if (scl_reg) begin
                            // Sample SDA
                            temp_raw_reg[15:8] <= {temp_raw_reg[14:8], sda_in};
                            if (bit_idx == 0) begin
                                i2c_state <= I2C_ACK_MSB;
                            end else begin
                                bit_idx <= bit_idx - 1;
                            end
                        end
                        i2c_timer <= 0;
                    end
                end

                I2C_ACK_MSB: begin
                    if (i2c_timer < HALF_PERIOD) begin
                        i2c_timer <= i2c_timer + 1;
                    end else begin
                        scl_reg <= ~scl_reg;
                        if (!scl_reg) begin
                            sda_out_reg <= 1'b0;  // ACK
                            sda_dir     <= 1'b0;
                            bit_idx     <= 4'd7;
                            i2c_state   <= I2C_READ_LSB;
                        end
                        i2c_timer <= 0;
                    end
                end

                I2C_READ_LSB: begin
                    if (i2c_timer < HALF_PERIOD) begin
                        i2c_timer <= i2c_timer + 1;
                    end else begin
                        scl_reg <= ~scl_reg;
                        if (scl_reg) begin
                            temp_raw_reg[7:0] <= {temp_raw_reg[6:0], sda_in};
                            if (bit_idx == 0) begin
                                i2c_state <= I2C_NACK;
                            end else begin
                                bit_idx <= bit_idx - 1;
                            end
                        end
                        i2c_timer <= 0;
                    end
                end

                I2C_NACK: begin
                    if (i2c_timer < HALF_PERIOD) begin
                        i2c_timer <= i2c_timer + 1;
                    end else begin
                        scl_reg <= ~scl_reg;
                        if (!scl_reg) begin
                            sda_out_reg <= 1'b1;  // NACK
                            sda_dir     <= 1'b0;
                            i2c_state   <= I2C_STOP;
                        end
                        i2c_timer <= 0;
                    end
                end

                I2C_STOP: begin
                    if (i2c_timer < HALF_PERIOD) begin
                        scl_reg     <= 1'b1;
                        sda_out_reg <= 1'b0;
                        i2c_timer   <= i2c_timer + 1;
                    end else begin
                        sda_out_reg <= 1'b1;  // STOP condition
                        i2c_done    <= 1'b1;
                        i2c_busy    <= 1'b0;
                        i2c_state   <= I2C_DONE;
                    end
                end

                I2C_DONE: begin
                    i2c_state <= I2C_IDLE;
                end

                default: i2c_state <= I2C_IDLE;
            endcase
        end
    end

    assign io_i2c_sda = sda_dir ? 1'bz : sda_out_reg;
    assign o_i2c_scl  = scl_reg;

    //=========================================================================
    // VSWR Calculation (lookup-based)
    //=========================================================================
    reg [7:0] vswr_idx_reg;
    reg       vswr_alarm_reg;
    reg       pa_alarm_reg;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            vswr_idx_reg   <= 0;
            vswr_alarm_reg <= 1'b0;
            pa_alarm_reg   <= 1'b0;
        end else begin
            // Simplified VSWR band classification
            if (i_vref > REFL_THRESH_5) begin
                vswr_idx_reg <= 8'd5;   // Critical
                vswr_alarm_reg <= 1'b1;
            end else if (i_vref > REFL_THRESH_4) begin
                vswr_idx_reg <= 8'd4;   // Severe
                vswr_alarm_reg <= 1'b1;
            end else if (i_vref > REFL_THRESH_3) begin
                vswr_idx_reg <= 8'd3;   // High
                vswr_alarm_reg <= 1'b1;
            end else if (i_vref > REFL_THRESH_2) begin
                vswr_idx_reg <= 8'd2;   // Moderate
                vswr_alarm_reg <= 1'b0;
            end else if (i_vref > REFL_THRESH_1) begin
                vswr_idx_reg <= 8'd1;   // Low
                vswr_alarm_reg <= 1'b0;
            end else begin
                vswr_idx_reg <= 8'd0;   // Normal
                vswr_alarm_reg <= 1'b0;
            end

            // PA fault detection (simplified: reflected power too high)
            if (i_vref > REFL_THRESH_5) begin
                pa_alarm_reg <= 1'b1;
            end else begin
                pa_alarm_reg <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Temperature Alarm
    //=========================================================================
    reg ot_alarm_reg;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            ot_alarm_reg <= 1'b0;
        end else begin
            if (temp_raw_reg > TEMP_ALARM_THRESH) begin
                ot_alarm_reg <= 1'b1;
            end else begin
                ot_alarm_reg <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Output assignments
    //=========================================================================
    assign o_temp_raw   = temp_raw_reg;
    assign o_vswr_idx   = vswr_idx_reg;
    assign o_alarm_ot   = ot_alarm_reg;
    assign o_alarm_vswr = vswr_alarm_reg;
    assign o_alarm_pa   = pa_alarm_reg;
    assign o_scan_busy  = i2c_busy;

endmodule
