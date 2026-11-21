// ============================================================================
// File: icg_cell.sv
// Project: PULP-inspired Edge AI SoC for Handwritten Digit Recognition
// Module: icg_cell (Latch-Based Integrated Clock Gating Cell)
// Author: Nguyen Van Thuc (24161421)
// Description:
//   Industry-standard glitch-free latch-based clock gating cell (ICG).
//   Captures enable signal while clock is LOW to ensure hazard-free gating
//   at clock rising edge. Fully compatible with ASIC (Nangate 45nm CLKGATE_X*)
//   and FPGA (AMD Vivado BUFGCE / Slice Clock Enable).
// ============================================================================

`timescale 1ns / 1ps

module icg_cell (
    input  logic clk_i,
    input  logic en_i,
    input  logic test_en_i,
    output logic clk_o
);

    logic en_latched;

    // Glitch-suppressing latch: transparent when clk_i is LOW, latches when clk_i is HIGH
    always_latch begin
        if (!clk_i) begin
            en_latched <= en_i | test_en_i;
        end
    end

    // Gated clock output
    assign clk_o = clk_i & en_latched;

endmodule : icg_cell
