//=============================================================================
// tb_repeater_top.v — Top-Level Testbench for FM/DMB Repeater
//
// Generates:
//   1. 10 MHz reference clock
//   2. ADC DCO DDR clock (80 MHz)
//   3. Simulated ADC data (sine wave via LUT)
//   4. SPI write/read sequences
//   5. Automatic verification messages
//=============================================================================

`timescale 1ns / 1ps

module tb_repeater_top;

    //=========================================================================
    // Parameters
    //=========================================================================
    localparam REFCLK_PERIOD = 100.0;   // 10 MHz → 100 ns
    localparam DCO_PERIOD    = 12.5;    // 80 MHz → 12.5 ns
    localparam SIM_CYCLES    = 100000;  // Total simulation cycles
    localparam ADC_SINE_LUT  = 256;     // Sine LUT entries

    //=========================================================================
    // Signals
    //=========================================================================
    reg         refclk_p;
    reg         refclk_n;
    reg         rst_n;
    reg         adc_dco_p;
    reg         adc_dco_n;
    reg         adc_fclk_p;
    reg         adc_fclk_n;
    reg  [13:0] adc_data_p;
    reg  [13:0] adc_data_n;
    wire [11:0] dac_fm_data;
    wire        dac_fm_wrt;
    wire [11:0] dac_dmb_data;
    wire        dac_dmb_wrt;
    reg         spi_sclk;
    reg         spi_mosi;
    wire        spi_miso;
    reg         spi_ss_n;
    reg         uart_rx;
    wire        uart_tx;
    wire        i2c_scl;
    wire        i2c_sda;
    wire        alarm_ot;
    wire        alarm_vswr;
    wire        alarm_pa;
    wire        mmcm_locked;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    repeater_top u_dut (
        .i_refclk_p     (refclk_p),
        .i_refclk_n     (refclk_n),
        .i_rst_n        (rst_n),
        .i_adc_dco_p    (adc_dco_p),
        .i_adc_dco_n    (adc_dco_n),
        .i_adc_fclk_p   (adc_fclk_p),
        .i_adc_fclk_n   (adc_fclk_n),
        .i_adc_data_p   (adc_data_p),
        .i_adc_data_n   (adc_data_n),
        .o_dac_fm_data  (dac_fm_data),
        .o_dac_fm_wrt   (dac_fm_wrt),
        .o_dac_dmb_data (dac_dmb_data),
        .o_dac_dmb_wrt  (dac_dmb_wrt),
        .i_spi_sclk     (spi_sclk),
        .i_spi_mosi     (spi_mosi),
        .o_spi_miso     (spi_miso),
        .i_spi_ss_n     (spi_ss_n),
        .i_uart_rx      (uart_rx),
        .o_uart_tx      (uart_tx),
        .o_i2c_scl      (i2c_scl),
        .io_i2c_sda     (i2c_sda),
        .o_alarm_ot     (alarm_ot),
        .o_alarm_vswr   (alarm_vswr),
        .o_alarm_pa     (alarm_pa),
        .o_mmcm_locked  (mmcm_locked)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        refclk_p = 1'b0;
        refclk_n = 1'b1;
        forever #(REFCLK_PERIOD / 2.0) begin
            refclk_p = ~refclk_p;
            refclk_n = ~refclk_n;
        end
    end

    // ADC DCO (80 MHz DDR — toggle at 40 MHz rate = 12.5 ns period)
    initial begin
        adc_dco_p = 1'b0;
        adc_dco_n = 1'b1;
        forever #(DCO_PERIOD / 2.0) begin
            adc_dco_p = ~adc_dco_p;
            adc_dco_n = ~adc_dco_n;
        end
    end

    // ADC frame clock (not used, just toggle)
    initial begin
        adc_fclk_p = 1'b0;
        adc_fclk_n = 1'b1;
        forever #(DCO_PERIOD) begin
            adc_fclk_p = ~adc_fclk_p;
            adc_fclk_n = ~adc_fclk_n;
        end
    end

    //=========================================================================
    // Reset Sequence
    //=========================================================================
    initial begin
        rst_n = 1'b0;
        #1000;
        rst_n = 1'b1;
        #2000;
        $display("[TB] Reset de-asserted at t=%0t", $time);
    end

    //=========================================================================
    // Simulated ADC Data (Sine Wave LUT)
    //=========================================================================
    reg [13:0] sine_lut [0:ADC_SINE_LUT-1];
    integer    lut_idx;

    initial begin
        // Generate sine LUT (14-bit, centered at 8192, amplitude ±8191)
        for (lut_idx = 0; lut_idx < ADC_SINE_LUT; lut_idx = lut_idx + 1) begin
            sine_lut[lut_idx] = 8192 + $rtoi(8191.0 * $sin(2.0 * 3.14159 * lut_idx / ADC_SINE_LUT));
        end
        lut_idx = 0;
    end

    // Drive ADC data (DDR — change on both DCO edges)
    always @(posedge adc_dco_p) begin
        adc_data_p <= sine_lut[lut_idx];
        adc_data_n <= ~sine_lut[lut_idx];
        lut_idx <= (lut_idx + 1) % ADC_SINE_LUT;
    end

    //=========================================================================
    // SPI Master Tasks
    //=========================================================================
    task spi_start;
        begin
            spi_ss_n = 1'b1;
            spi_sclk = 1'b0;
            spi_mosi = 1'b0;
            #100;
            spi_ss_n = 1'b0;  // Assert CS
            #50;
        end
    endtask

    task spi_stop;
        begin
            #50;
            spi_ss_n = 1'b1;  // Deassert CS
            #100;
        end
    endtask

    task spi_write_byte(input [7:0] data);
        integer bit;
        begin
            for (bit = 7; bit >= 0; bit = bit - 1) begin
                spi_mosi = data[bit];
                #25;
                spi_sclk = 1'b1;
                #25;
                spi_sclk = 1'b0;
            end
        end
    endtask

    task spi_write_frame(input [7:0] cmd, input [7:0] addr, input [15:0] data);
        begin
            spi_start();
            spi_write_byte(cmd);
            spi_write_byte(addr);
            spi_write_byte(data[15:8]);
            spi_write_byte(data[7:0]);
            spi_stop();
            $display("[TB] SPI WR: cmd=0x%02h addr=0x%02h data=0x%04h", cmd, addr, data);
        end
    endtask

    task spi_read_frame(input [7:0] addr);
        begin
            spi_start();
            spi_write_byte(8'h01);   // READ command
            spi_write_byte(addr);
            spi_write_byte(8'd0);    // Dummy
            spi_write_byte(8'd0);
            spi_stop();
            $display("[TB] SPI RD: addr=0x%02h MISO=0x%04h", addr, spi_miso);
        end
    endtask

    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        // Initialize SPI
        spi_sclk = 1'b0;
        spi_mosi = 1'b0;
        spi_ss_n = 1'b1;
        uart_rx  = 1'b1;

        // Wait for MMCM lock
        #50000;
        wait(mmcm_locked);
        $display("[TB] MMCM locked at t=%0t", $time);

        // Test: Write FM channel 0 frequency register
        #2000;
        spi_write_frame(8'h02, 8'h00, 16'h1234);  // FM CH0 NCO L

        // Test: Write AGC parameters
        #2000;
        spi_write_frame(8'h02, 8'h40, 16'd100);    // AGC attack
        #1000;
        spi_write_frame(8'h02, 8'h41, 16'd1000);   // AGC release

        // Test: Read back status
        #2000;
        spi_read_frame(8'h60);   // Temperature
        #1000;
        spi_read_frame(8'h62);   // Alarm status

        // Run for remaining cycles
        #(DCO_PERIOD * SIM_CYCLES);

        $display("[TB] Simulation complete at t=%0t", $time);
        $display("[TB] DAC FM samples: %d", dac_fm_wrt);
        $display("[TB] DAC DMB samples: %d", dac_dmb_wrt);
        $finish;
    end

    //=========================================================================
    // VCD dump for waveform viewing
    //=========================================================================
    initial begin
        $dumpfile("tb_repeater_top.vcd");
        $dumpvars(0, tb_repeater_top);
    end

    //=========================================================================
    // Monitor important signals
    //=========================================================================
    initial begin
        $monitor("[TB] t=%0t: mmcm=%b adc_valid=%b dac_fm_wrt=%b dac_dmb_wrt=%b",
                 $time, mmcm_locked, u_dut.adc_valid,
                 dac_fm_wrt, dac_dmb_wrt);
    end

endmodule
