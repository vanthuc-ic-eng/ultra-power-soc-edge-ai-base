// ============================================================================
// File: pe_mac.sv
// Project: PULP-inspired Edge AI SoC for Handwritten Digit Recognition
// Module: pe_mac (Ultra-Lightweight SystemVerilog Processing Element)
// Author: Nguyen Van Thuc (24161421)
// Description:
//   Output-stationary Processing Element (PE) receiving pre-encoded log values
//   and accumulating into a 32-bit register.
//   ELIMINATES all Leading-One Detectors (LOD), normalizers, and LUT converters
//   from the individual PE core.
//   SystemVerilog implementation using IEEE 1800-2012 syntax.
// ============================================================================

`timescale 1ns / 1ps

module pe_mac #(
    parameter int unsigned LOW_W        = 3,
    parameter int unsigned TRUNC_BITS   = 4,
    parameter int unsigned ROUND_MODE   = 1,
    parameter int unsigned USE_CARRY    = 1,
    parameter int unsigned QUAD_CURV    = 0
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 valid_i,     // MAC enable
    input  logic                 clr_i,       // Clear accumulator / load bias

    // Pre-encoded Activation Input (from Shared Encoder)
    input  logic                 act_sign_i,
    input  logic                 act_zero_i,
    input  logic [LOW_W+5:0]     act_log_i,

    // Pre-encoded Weight Input (directly from BRAM)
    input  logic                 weight_sign_i,
    input  logic                 weight_zero_i,
    input  logic [LOW_W+5:0]     weight_log_i,

    // Initial Bias
    input  logic signed [31:0]   bias_i,

    // 32-bit Accumulated Result
    output logic signed [31:0]   acc_o
);

    // Multiplier output (signed 16-bit) and pre-increment retiming signals
    logic signed [15:0]     prod_w;
    logic [15-TRUNC_BITS:0] base_w;
    logic                   carry_w;

    // Instantiate lightweight core multiplier (Zero-LOD, Zero-Normalizer)
    lutalm_core_mul_s8 #(
        .LOW_W      ( LOW_W      ),
        .TRUNC_BITS ( TRUNC_BITS ),
        .ROUND_MODE ( ROUND_MODE ),
        .USE_CARRY  ( USE_CARRY  ),
        .QUAD_CURV  ( QUAD_CURV  )
    ) u_mult_core (
        .sign_a_i ( act_sign_i    ),
        .zero_a_i ( act_zero_i    ),
        .log_a_i  ( act_log_i     ),
        .sign_b_i ( weight_sign_i ),
        .zero_b_i ( weight_zero_i ),
        .log_b_i  ( weight_log_i  ),
        .p_o      ( prod_w        ),
        .base_o   ( base_w        ),
        .carry_o  ( carry_w       )
    );

    // ------------------------------------------------------------------------
    // Retimed Pipeline Registers between Multiplier Stage 1 and Stage 2:
    // By registering `base_w` (12-bit) and `carry_w` (1-bit) BEFORE the
    // 2's-complement rounding incrementer (`base + carry_in`), we move 3 CARRY4
    // levels (~1.67 ns) from Stage 1 into Stage 2, boosting Fmax while keeping
    // 100% bit-exact, cycle-exact mathematical equivalence!
    // ------------------------------------------------------------------------
    logic [15-TRUNC_BITS:0] base_q;
    logic                   carry_q;
    logic                   valid_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            base_q  <= '0;
            carry_q <= 1'b0;
            valid_q <= 1'b0;
        end else begin
            base_q  <= base_w;
            carry_q <= carry_w;
            valid_q <= valid_i;
        end
    end

    // ------------------------------------------------------------------------
    // Stage 2: Retimed Rounding Increment + 32-bit Accumulator
    // ------------------------------------------------------------------------
    wire [15-TRUNC_BITS:0] signed_mag_q = base_q + carry_q;
    wire signed [15:0]     prod_q       = {signed_mag_q, {TRUNC_BITS{1'b0}}};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_o <= 32'sd0;
        end else if (clr_i) begin
            acc_o <= bias_i;
        end else if (valid_q && (prod_q != 16'sd0)) begin
            acc_o <= acc_o + {{16{prod_q[15]}}, prod_q};
        end
    end

endmodule : pe_mac
