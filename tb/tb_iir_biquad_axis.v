`timescale 1ns / 1ps
// ============================================================
// Testbench: AXI-Stream Stereo IIR Biquad
// ------------------------------------------------------------
// - AXI-Lite: konfigurasi koefisien & control
// - AXI-Stream: stereo audio streaming
// - Logging ke CSV saat transaksi AXI valid
// ============================================================

module tb_iir_biquad_axis;

    // ========================================================
    // 1. Parameters
    // ========================================================
    parameter integer DATA_WIDTH = 32; // [31:16]=L, [15:0]=R
    parameter integer ADDR_WIDTH = 5;

    // ========================================================
    // 2. Clock & Reset
    // ========================================================
    reg aclk;
    reg aresetn;

    // ========================================================
    // 3. AXI-Stream (Slave Input)
    // ========================================================
    reg  [DATA_WIDTH-1:0] s_axis_tdata;
    reg                   s_axis_tvalid;
    wire                  s_axis_tready;
    reg                   s_axis_tlast;

    // ========================================================
    // 4. AXI-Stream (Master Output)
    // ========================================================
    wire [DATA_WIDTH-1:0] m_axis_tdata;
    wire                  m_axis_tvalid;
    reg                   m_axis_tready;
    wire                  m_axis_tlast;

    // ========================================================
    // 5. AXI-Lite
    // ========================================================
    reg  [ADDR_WIDTH-1:0] s_axi_awaddr;
    reg                   s_axi_awvalid;
    wire                  s_axi_awready;

    reg  [31:0]           s_axi_wdata;
    reg  [3:0]            s_axi_wstrb;
    reg                   s_axi_wvalid;
    wire                  s_axi_wready;

    wire [1:0]            s_axi_bresp;
    wire                  s_axi_bvalid;
    reg                   s_axi_bready;

    reg  [ADDR_WIDTH-1:0] s_axi_araddr;
    reg                   s_axi_arvalid;
    wire                  s_axi_arready;

    wire [31:0]           s_axi_rdata;
    wire [1:0]            s_axi_rresp;
    wire                  s_axi_rvalid;
    reg                   s_axi_rready;

    // ========================================================
    // 6. CSV Logging
    // ========================================================
    integer f_csv;

    // ========================================================
    // 7. DUT
    // ========================================================
    iir_biquad_axis dut (
        .aclk(aclk),
        .aresetn(aresetn),

        .s_axis_tdata (s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast (s_axis_tlast),

        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast),

        .s_axi_awaddr (s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata  (s_axi_wdata),
        .s_axi_wstrb  (s_axi_wstrb),
        .s_axi_wvalid (s_axi_wvalid),
        .s_axi_wready (s_axi_wready),
        .s_axi_bresp  (s_axi_bresp),
        .s_axi_bvalid (s_axi_bvalid),
        .s_axi_bready (s_axi_bready),
        .s_axi_araddr (s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata  (s_axi_rdata),
        .s_axi_rresp  (s_axi_rresp),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready)
    );

    // ========================================================
    // 8. Clock Generation (100 MHz)
    // ========================================================
    initial begin
        aclk = 1'b0;
        forever #5 aclk = ~aclk;
    end

    // ========================================================
    // 9. AXI-Lite Write Task
    // ========================================================
    task axi_write(input [ADDR_WIDTH-1:0] addr, input [31:0] data);
        begin
            @(posedge aclk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wvalid  <= 1'b1;
            s_axi_wstrb   <= 4'hF;
            s_axi_bready  <= 1'b0;

            wait (s_axi_awready && s_axi_wready);

            @(posedge aclk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;

            s_axi_bready <= 1'b1;
            wait (s_axi_bvalid);
            @(posedge aclk);
            s_axi_bready <= 1'b0;
        end
    endtask

    // ========================================================
    // 10. Stimulus
    // ========================================================
    real phase_l, phase_r;
    real val_l, val_r;
    reg signed [15:0] fix_l, fix_r;
    integer i;

    initial begin
        // Init
        phase_l = 0.0;
        phase_r = 0.0;

        aresetn       = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata  = 32'd0;
        s_axis_tlast  = 1'b0;
        m_axis_tready = 1'b1;

        // Explicit AXI-Lite Init
        s_axi_awaddr  = 5'd0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = 32'd0;
        s_axi_wstrb   = 4'd0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_araddr  = 5'd0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;

        f_csv = $fopen("tb_iir_biquad_axis.csv", "w");
        $fwrite(f_csv, "time_ns,in_L,in_R,out_L,out_R\n");

        // Reset
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (10) @(posedge aclk);

        // --------------------------------------------
        // Configure coefficients (LPF-like)
        // --------------------------------------------
        axi_write(5'h04, 32'd4000);   // b0
        axi_write(5'h08, 32'd8000);   // b1
        axi_write(5'h0C, 32'd4000);   // b2
        axi_write(5'h10, -32'd5000);  // a1
        axi_write(5'h14, 32'd2000);   // a2

        // Enable + soft clear
        axi_write(5'h00, 32'h0000_0003);
        axi_write(5'h00, 32'h0000_0001);

        // --------------------------------------------
        // Stream audio samples
        // --------------------------------------------
        for (i = 0; i < 1000; i = i + 1) begin
            phase_l = phase_l + 0.1;
            phase_r = phase_r + 0.8;

            val_l = 10000.0 * $sin(phase_l);
            val_r =  8000.0 * $sin(phase_r);

            fix_l = $rtoi(val_l);
            fix_r = $rtoi(val_r);

            wait (s_axis_tready);
            @(posedge aclk);

            s_axis_tdata  <= {fix_l, fix_r};
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= (i == 999) ? 1'b1 : 1'b0;

            @(posedge aclk);
            while (!s_axis_tready) @(posedge aclk);

            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            repeat (2) @(posedge aclk);
        end

        repeat (50) @(posedge aclk);
        $fclose(f_csv);
        $finish;
    end

    // ========================================================
    // 11. CSV Logger (AXI-Stream boundary)
    // ========================================================
    always @(posedge aclk) begin
        if (aresetn && m_axis_tvalid && m_axis_tready) begin
            $fwrite(
                f_csv,
                "%0d,%d,%d,%d,%d\n",
                $time,
                fix_l,
                fix_r,
                $signed(m_axis_tdata[31:16]),
                $signed(m_axis_tdata[15:0])
            );
        end
    end

endmodule
