// ============================================================================
// File: mul_scoreboard.sv
// Project: PULP-inspired Edge AI SoC Verification
// Component: UVM Scoreboard with SOTA Logarithmic Multiplier Golden Model
// Standard: UVM 1.2
// ============================================================================

`ifndef MUL_SCOREBOARD_SV
`define MUL_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class mul_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mul_scoreboard)

    uvm_analysis_imp #(mul_seq_item, mul_scoreboard) item_imp;

    int total_transactions;
    int exact_matches;
    int mismatch_count;

    // Error Metric Accumulators (Chỉ số kiểm chứng xấp xỉ cho AI)
    real total_abs_err;
    real total_rel_err;
    real max_abs_err;

    function new(string name = "mul_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        total_transactions = 0;
        exact_matches = 0;
        mismatch_count = 0;
        total_abs_err = 0.0;
        total_rel_err = 0.0;
        max_abs_err = 0.0;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_imp = new("item_imp", this);
    endfunction

    // ------------------------------------------------------------------------
    // Golden Reference Model in SystemVerilog (Bit-Exact to RTL Architecture)
    // ------------------------------------------------------------------------
    virtual function void enc(input bit signed [7:0] x,
                              output bit sign,
                              output bit zero,
                              output bit [8:0] log_val);
        bit [7:0] mag;
        int k;
        bit [7:0] bits;
        bit [2:0] upper;
        bit [2:0] addr;
        bit [2:0] low;
        bit [5:0] frac;
        bit [2:0] lut_low3[8] = '{3'd1, 3'd3, 3'd4, 3'd4, 3'd6, 3'd6, 3'd7, 3'd7};

        if (x < 0) begin
            mag = (-x) & 8'hFF;
            sign = 1'b1;
        end else begin
            mag = x & 8'hFF;
            sign = 1'b0;
        end

        zero = (x == 8'sd0) || (mag == 8'h00);
        if (zero) begin
            log_val = 9'd0;
            return;
        end

        // LOD (Leading One Detector)
        k = 0;
        for (int i = 7; i >= 0; i--) begin
            if (mag[i]) begin
                k = i;
                break;
            end
        end

        bits = ((mag << (7 - k)) & 8'hFF) & 8'h7F;
        upper = bits[6:4];
        addr  = bits[3:1];
        low   = lut_low3[addr];
        frac  = {upper, low};
        log_val = {3'(k), frac};
    endfunction

    virtual function bit signed [15:0] compute_golden(bit signed [7:0] a, bit signed [7:0] b);
        bit sa, za, sb, zb;
        bit [8:0] la, lb;
        bit [9:0] log_sum;
        bit [3:0] exp_w;
        bit [5:0] frac_s;
        bit [6:0] mantissa;
        bit [15:0] shifted;
        bit [15:0] approx_mag;
        bit sign_prod, zero_prod;
        localparam int TRUNC_BITS = 4;
        localparam int REM_BITS   = 12;
        bit round_bit;
        bit [11:0] raw_trunc;
        bit eff_sign, eff_round;
        bit [11:0] eff_raw;
        bit carry_in;
        bit [11:0] base;
        bit [11:0] signed_mag;
        bit [15:0] res;

        enc(a, sa, za, la);
        enc(b, sb, zb, lb);

        log_sum = la + lb;
        exp_w = log_sum[9:6];
        frac_s = log_sum[5:0];
        mantissa = {1'b1, frac_s};
        // Use 32-bit width to avoid truncation before right shifting by 6
        shifted = 16'(((32'(mantissa) << exp_w) >> 6) & 32'hFFFF);
        approx_mag = shifted;

        sign_prod = sa ^ sb;
        zero_prod = za | zb;

        round_bit = approx_mag[TRUNC_BITS - 1];
        raw_trunc = approx_mag[15:TRUNC_BITS];

        eff_sign  = sign_prod && (!zero_prod);
        eff_round = round_bit && (!zero_prod);
        eff_raw   = zero_prod ? 12'd0 : raw_trunc;

        carry_in   = eff_sign ? (!eff_round) : eff_round;
        base       = eff_sign ? (~eff_raw) : eff_raw;
        signed_mag = base + 12'(carry_in);
        res        = {signed_mag, 4'b0000};
        return res;
    endfunction

    virtual function void write(mul_seq_item item);
        bit signed [15:0] golden_p;
        int exact_p;
        real abs_err;

        total_transactions++;
        golden_p = compute_golden(item.a_i, item.b_i);
        exact_p = int'(item.a_i) * int'(item.b_i);

        // Verification Check: RTL MUST match Golden Model 100% Bit-Exact!
        if (item.p_o === golden_p) begin
            exact_matches++;
        end else begin
            mismatch_count++;
            `uvm_error("SCB_MISMATCH", $sformatf("MISMATCH: a=%0d b=%0d | DUT=%0d Golden=%0d | Diff=%0d",
                                                 item.a_i, item.b_i, item.p_o, golden_p, item.p_o - golden_p))
        end

        // Error Analysis
        abs_err = (item.p_o > exact_p) ? (item.p_o - exact_p) : (exact_p - item.p_o);
        total_abs_err += abs_err;
        if (exact_p != 0) begin
            total_rel_err += (abs_err / real'((exact_p > 0) ? exact_p : -exact_p));
        end
        if (abs_err > max_abs_err) max_abs_err = abs_err;
    endfunction

    virtual function void report_phase(uvm_phase phase);
        real mred;
        real med;
        super.report_phase(phase);
        mred = (total_transactions > 0) ? (total_rel_err / total_transactions) * 100.0 : 0.0;
        med  = (total_transactions > 0) ? (total_abs_err / total_transactions) : 0.0;

        `uvm_info("UVM_SCB_REPORT", "==================================================================", UVM_LOW)
        `uvm_info("UVM_SCB_REPORT", "       PURE UVM 1.2 SCOREBOARD REGRESSION SUMMARY REPORT          ", UVM_LOW)
        `uvm_info("UVM_SCB_REPORT", "==================================================================", UVM_LOW)
        `uvm_info("UVM_SCB_REPORT", $sformatf(" Total Test Vectors Processed  : %0d", total_transactions), UVM_LOW)
        `uvm_info("UVM_SCB_REPORT", $sformatf(" Bit-Exact Matches (Ref == DUT): %0d / %0d (%.2f%%)", 
                                              exact_matches, total_transactions, (exact_matches*100.0)/total_transactions), UVM_LOW)
        `uvm_info("UVM_SCB_REPORT", $sformatf(" RTL Hardware Mismatches       : %0d", mismatch_count), UVM_LOW)
        `uvm_info("UVM_SCB_REPORT", $sformatf(" Mean Relative Error (MRED)    : %.4f%%", mred), UVM_LOW)
        `uvm_info("UVM_SCB_REPORT", $sformatf(" Mean Error Distance (MED)     : %.2f", med), UVM_LOW)
        `uvm_info("UVM_SCB_REPORT", $sformatf(" Worst-Case Error (WCE)        : %0d", int'(max_abs_err)), UVM_LOW)
        `uvm_info("UVM_SCB_REPORT", "==================================================================", UVM_LOW)

        if (mismatch_count == 0) begin
            `uvm_info("UVM_SCB_REPORT", " >>> UVM TEST STATUS: 100% PASSED -- ZERO REGRESSION DEFECTS <<< ", UVM_LOW)
        end else begin
            `uvm_fatal("UVM_SCB_REPORT", " >>> UVM TEST STATUS: FAILED -- DETECTED DEFECTS IN RTL DUT <<< ")
        end
    endfunction
endclass

`endif
