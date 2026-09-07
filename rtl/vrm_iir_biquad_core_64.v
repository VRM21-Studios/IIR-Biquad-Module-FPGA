`timescale 1ns / 1ps

// ============================================================================
// Module: vrm_iir_biquad_core_64
// Description:
//   Event-driven 64-bit IIR biquad filter core using dedicated floating-point
//   multiplier and adder/subtractor engines.
//
//   The core implements the standard second-order biquad difference equation
//   by evaluating five coefficient-state products followed by sequential
//   accumulation and subtraction operations.
//
//   A single multiplier and a single adder/subtractor are reused across all
//   arithmetic operations under control of a finite state machine. The input
//   sample and delay-line states are processed using 64-bit datapaths.
//
// Interface:
//   - Event-driven input interface for 64-bit input samples.
//   - Five 64-bit biquad filter coefficients.
//   - 64-bit output sample with a corresponding valid indication.
//   - Active-low synchronous reset.
//
// Notes:
//   - The core uses one floating-point multiplier and one floating-point
//     adder/subtractor instance.
//   - Input processing begins when valid_in is asserted.
//   - The delay lines store the two previous input and output samples.
//   - Arithmetic operation sequencing is controlled by the main FSM.
// ============================================================================

module vrm_iir_biquad_core_64 (
    input  wire        clk,
    input  wire        rstn,
    
    // ------------------------------------------------------------------------
    // Event-Driven Input Interface
    // ------------------------------------------------------------------------
    input  wire        valid_in,
    input  wire [63:0] x_in,

    // ------------------------------------------------------------------------
    // Biquad Filter Coefficients
    // ------------------------------------------------------------------------
    input  wire [63:0] b0,
    input  wire [63:0] b1,
    input  wire [63:0] b2,
    input  wire [63:0] a1,
    input  wire [63:0] a2,

    // ------------------------------------------------------------------------
    // Output Interface
    // ------------------------------------------------------------------------
    output reg  [63:0] y_out,
    output reg         valid_out
);

    // =========================================================================
    // 1. State Machine Enumeration
    // =========================================================================
    localparam S_IDLE        = 4'd0;
    localparam S_MUL_LOAD    = 4'd1;
    localparam S_MUL_WAIT    = 4'd2;
    localparam S_ADD1_START  = 4'd3;
    localparam S_ADD1_WAIT   = 4'd4;
    localparam S_ADD2_START  = 4'd5;
    localparam S_ADD2_WAIT   = 4'd6;
    localparam S_ADD3_START  = 4'd7;
    localparam S_ADD3_WAIT   = 4'd8;
    localparam S_SUB_START   = 4'd9;
    localparam S_SUB_WAIT    = 4'd10;
    localparam S_UPDATE      = 4'd11;

    reg [3:0] state;

    // =========================================================================
    // 2. Internal Registers and Delay Lines
    // =========================================================================

    // Input and output delay lines.
    reg [63:0] x0 = 0, x1 = 0, x2 = 0;
    reg [63:0] y1 = 0, y2 = 0;

    // Registers for storing multiplier results.
    reg [63:0] m_res [0:4]; 

    // Temporary accumulators for input and feedback terms.
    reg [63:0] acc_x;
    reg [63:0] acc_y;

    // Multiplication request and completion counters.
    reg [2:0] mul_load_idx;
    reg [2:0] mul_done_idx;

    // =========================================================================
    // 3. FPU Engine Instantiations
    // =========================================================================

    // -------------------------------------------------------------------------
    // 3.1 Floating-Point Multiplier
    // -------------------------------------------------------------------------
    reg         mul_valid_in;
    reg  [63:0] mul_op_a, mul_op_b;
    wire [63:0] mul_out_res;
    wire        mul_valid_out;

    vrm_fpu_mul_64 u_mul (
        .clk(clk), .rstn(rstn), 
        .valid_in(mul_valid_in), .op_a(mul_op_a), .op_b(mul_op_b),
        .result_out(mul_out_res), .valid_out(mul_valid_out)
    );

    // -------------------------------------------------------------------------
    // 3.2 Floating-Point Adder/Subtractor
    // -------------------------------------------------------------------------
    reg         add_valid_in;
    reg         add_is_sub;
    reg  [63:0] add_op_a, add_op_b;
    wire [63:0] add_out_res;
    wire        add_valid_out;

    vrm_fpu_add_sub_64 u_add (
        .clk(clk), .rstn(rstn), 
        .valid_in(add_valid_in), .is_sub(add_is_sub), 
        .op_a(add_op_a), .op_b(add_op_b),
        .result_out(add_out_res), .valid_out(add_valid_out)
    );

    // =========================================================================
    // 4. Main Control FSM and Data Routing
    // =========================================================================
    
    always @(posedge clk) begin
        if (!rstn) begin
            state <= S_IDLE;
            valid_out <= 0;
            y_out <= 64'd0;
            x0 <= 64'd0; x1 <= 64'd0; x2 <= 64'd0;
            y1 <= 64'd0; y2 <= 64'd0;
            mul_valid_in <= 0; add_valid_in <= 0;
            mul_load_idx <= 0; mul_done_idx <= 0;
        end else begin
            
            // Capture each multiplier result independently when the FPU
            // asserts its output-valid signal.
            if (mul_valid_out) begin
                m_res[mul_done_idx] <= mul_out_res;
                mul_done_idx <= mul_done_idx + 3'd1;
            end

            // -----------------------------------------------------------------
            // 4.1 Idle State
            // -----------------------------------------------------------------
            S_IDLE:
            // -----------------------------------------------------------------
            begin
                valid_out <= 0;
                if (valid_in) begin
                    x0 <= x_in; // Latch the input sample before processing.
                    mul_load_idx <= 0;
                    mul_done_idx <= 0;
                    state <= S_MUL_LOAD;
                end
            end

            // -----------------------------------------------------------------
            // 4.2 Multiplier Load
            // -----------------------------------------------------------------
            S_MUL_LOAD:
            // -----------------------------------------------------------------
            begin
                if (mul_load_idx < 5) begin
                    mul_valid_in <= 1;

                    // Select the coefficient/state pair for the current
                    // multiplication request.
                    case (mul_load_idx)
                        0: begin mul_op_a <= b0; mul_op_b <= x0; end
                        1: begin mul_op_a <= b1; mul_op_b <= x1; end
                        2: begin mul_op_a <= b2; mul_op_b <= x2; end
                        3: begin mul_op_a <= a1; mul_op_b <= y1; end
                        4: begin mul_op_a <= a2; mul_op_b <= y2; end
                    endcase
                    mul_load_idx <= mul_load_idx + 3'd1;
                end else begin
                    mul_valid_in <= 0;
                    state <= S_MUL_WAIT;
                end
            end

            // -----------------------------------------------------------------
            // 4.3 Multiplier Completion Wait
            // -----------------------------------------------------------------
            S_MUL_WAIT:
            // -----------------------------------------------------------------
            begin
                mul_valid_in <= 0;

                // Wait until all five multiplier results have been captured.
                if (mul_done_idx == 3'd5) begin
                    state <= S_ADD1_START;
                end
            end

            // -----------------------------------------------------------------
            // 4.4 First Input-Term Addition
            // -----------------------------------------------------------------
            S_ADD1_START:
            // Compute (b0 * x0) + (b1 * x1).
            // -----------------------------------------------------------------
            begin
                add_valid_in <= 1;
                add_is_sub   <= 0;
                add_op_a     <= m_res[0]; 
                add_op_b     <= m_res[1];
                state        <= S_ADD1_WAIT;
            end

            S_ADD1_WAIT:
            begin
                add_valid_in <= 0;
                if (add_valid_out) begin
                    acc_x <= add_out_res;
                    state <= S_ADD2_START;
                end
            end

            // -----------------------------------------------------------------
            // 4.5 Final Input-Term Accumulation
            // -----------------------------------------------------------------
            S_ADD2_START:
            // Compute acc_x + (b2 * x2).
            // -----------------------------------------------------------------
            begin
                add_valid_in <= 1;
                add_is_sub   <= 0;
                add_op_a     <= acc_x; 
                add_op_b     <= m_res[2];
                state        <= S_ADD2_WAIT;
            end

            S_ADD2_WAIT:
            begin
                add_valid_in <= 0;
                if (add_valid_out) begin
                    acc_x <= add_out_res;
                    state <= S_ADD3_START;
                end
            end

            // -----------------------------------------------------------------
            // 4.6 Feedback-Term Addition
            // -----------------------------------------------------------------
            S_ADD3_START:
            // Compute (a1 * y1) + (a2 * y2).
            // -----------------------------------------------------------------
            begin
                add_valid_in <= 1;
                add_is_sub   <= 0;
                add_op_a     <= m_res[3]; 
                add_op_b     <= m_res[4];
                state        <= S_ADD3_WAIT;
            end

            S_ADD3_WAIT:
            begin
                add_valid_in <= 0;
                if (add_valid_out) begin
                    acc_y <= add_out_res;
                    state <= S_SUB_START;
                end
            end

            // -----------------------------------------------------------------
            // 4.7 Input and Feedback-Term Subtraction
            // -----------------------------------------------------------------
            S_SUB_START:
            // Compute y[n] = X_sum - Y_sum.
            // -----------------------------------------------------------------
            begin
                add_valid_in <= 1;
                add_is_sub   <= 1;
                add_op_a     <= acc_x; 
                add_op_b     <= acc_y;
                state        <= S_SUB_WAIT;
            end

            S_SUB_WAIT:
            begin
                add_valid_in <= 0;
                if (add_valid_out) begin
                    y_out <= add_out_res;
                    state <= S_UPDATE;
                end
            end

            // -----------------------------------------------------------------
            // 4.8 Delay-Line Update
            // -----------------------------------------------------------------
            S_UPDATE:
            // Shift the delay lines and assert the output-valid signal.
            // -----------------------------------------------------------------
            begin
                x2 <= x1;
                x1 <= x0;
                y2 <= y1;
                y1 <= y_out; // Store the newly calculated output sample.

                valid_out <= 1;
                state     <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
        end
    end

endmodule
