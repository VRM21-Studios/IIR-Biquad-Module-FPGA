`timescale 1ns / 1ps
// ============================================================
// Testbench: IIR Biquad Core (Mono)
// ------------------------------------------------------------
// - Stimulus berbasis sinyal audio sintetis (low + high tone)
// - Verifikasi:
//   * Respons low-pass
//   * Runtime coefficient switching
//   * Respons high-pass
// - Output dicatat ke CSV untuk analisis offline
// ============================================================

module tb_iir_biquad;

    // --------------------------------------------------------
    // 1. Clock, Reset, Control
    // --------------------------------------------------------
    reg clk;
    reg rst;
    reg en;

    // --------------------------------------------------------
    // 2. DUT I/O
    // --------------------------------------------------------
    reg  signed [15:0] x_in;
    wire signed [15:0] y_out;

    reg signed [15:0] b0, b1, b2, a1, a2;

    // --------------------------------------------------------
    // 3. Signal generation (real-valued reference)
    // --------------------------------------------------------
    real phase_low;
    real phase_high;
    real signal_val;

    // --------------------------------------------------------
    // 4. CSV logging
    // --------------------------------------------------------
    integer f;

    // --------------------------------------------------------
    // 5. DUT Instantiation
    // --------------------------------------------------------
    iir_biquad_core_16 #(
        .ACC_W(64)
    ) dut (
        .clk   (clk),
        .rst   (rst),
        .en    (en),
        .x_in  (x_in),
        .y_out (y_out),
        .b0    (b0),
        .b1    (b1),
        .b2    (b2),
        .a1    (a1),
        .a2    (a2)
    );

    // --------------------------------------------------------
    // 6. Clock Generation (100 MHz)
    // --------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // 10 ns period
    end

    // --------------------------------------------------------
    // 7. Main Test Sequence
    // --------------------------------------------------------
    initial begin
        // Init
        rst        = 1'b1;
        en         = 1'b0;
        phase_low  = 0.0;
        phase_high = 0.0;

        // Open CSV
        f = $fopen("tb_iir_biquad_core.csv", "w");
        $fwrite(f, "time_ns,x_in,y_out\n");

        // ----------------------------------------------------
        // Coefficient Set 1: Low-pass-like behavior
        // Q1.15 fixed-point
        // ----------------------------------------------------
        b0 = 16'sd4000;
        b1 = 16'sd8000;
        b2 = 16'sd4000;
        a1 = -16'sd5000;
        a2 = 16'sd2000;

        // Reset release
        #100;
        rst = 1'b0;
        en  = 1'b1;

        $display("TB: Running with coefficient set 1 (LPF-like)");

        // Run ~2000 samples
        #20000;

        // ----------------------------------------------------
        // Coefficient Set 2: High-pass-like behavior
        // ----------------------------------------------------
        $display("TB: Switching to coefficient set 2 (HPF-like)");

        b0 = 16'sd14000;
        b1 = -16'sd14000;
        b2 = 16'sd0;
        a1 = 16'sd1000;
        a2 = 16'sd0;

        #20000;

        // Finish
        $display("TB: Simulation complete");
        $fclose(f);
        $finish;
    end

    // --------------------------------------------------------
    // 8. Input Signal Generator
    // --------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            x_in <= 16'sd0;
        end else if (en) begin
            phase_low  = phase_low  + 0.05; // Low frequency
            phase_high = phase_high + 0.80; // High frequency

            signal_val =
                (15000.0 * $sin(phase_low)) +
                ( 5000.0 * $sin(phase_high));

            x_in <= $rtoi(signal_val);
        end
    end

    // --------------------------------------------------------
    // 9. CSV Logger
    // --------------------------------------------------------
    always @(posedge clk) begin
        if (!rst && en) begin
            $fwrite(f, "%0d,%0d,%0d\n", $time, x_in, y_out);
        end
    end

endmodule
