// ============================================================================
// File: mul_sequences.sv
// Project: PULP-inspired Edge AI SoC Verification
// Component: UVM Sequences (Corner-Case, Random, and Exhaustive 65,536 Sweep)
// Standard: UVM 1.2
// ============================================================================

`ifndef MUL_SEQUENCES_SV
`define MUL_SEQUENCES_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

// ----------------------------------------------------------------------------
// 1. Corner-Case Sequence: Điểm cực đoan (Zero, Min Neg, Max Pos, +1, -1)
// ----------------------------------------------------------------------------
class mul_corner_sequence extends uvm_sequence #(mul_seq_item);
    `uvm_object_utils(mul_corner_sequence)

    function new(string name = "mul_corner_sequence");
        super.new(name);
    endfunction

    virtual task body();
        bit signed [7:0] corners[5] = '{-8'sd128, -8'sd1, 8'sd0, 8'sd1, 8'sd127};
        mul_seq_item item;

        `uvm_info("UVM_SEQ", ">>> Starting Corner-Cases Sequence (5x5 = 25 Edge Combinations)...", UVM_LOW)
        for (int i = 0; i < 5; i++) begin
            for (int j = 0; j < 5; j++) begin
                item = mul_seq_item::type_id::create("corner_item");
                start_item(item);
                item.a_i = corners[i];
                item.b_i = corners[j];
                finish_item(item);
            end
        end
    endtask
endclass

// ----------------------------------------------------------------------------
// 2. Constrained Random Sequence: 1,000 ca kiểm thử ngẫu nhiên có trọng số
// ----------------------------------------------------------------------------
class mul_random_sequence extends uvm_sequence #(mul_seq_item);
    `uvm_object_utils(mul_random_sequence)

    rand int num_items;
    constraint c_items { num_items inside {[500 : 2000]}; }

    function new(string name = "mul_random_sequence");
        super.new(name);
        num_items = 1000;
    endfunction

    virtual task body();
        mul_seq_item item;
        `uvm_info("UVM_SEQ", $sformatf(">>> Starting Constrained Random Sequence (%0d items)...", num_items), UVM_LOW)
        for (int i = 0; i < num_items; i++) begin
            item = mul_seq_item::type_id::create("rand_item");
            start_item(item);
            if (!item.randomize()) begin
                `uvm_error("RAND_FAIL", "Randomization failed for seq item")
            end
            finish_item(item);
        end
    endtask
endclass

// ----------------------------------------------------------------------------
// 3. Exhaustive Full-Sweep Sequence: Quét TOÀN BỘ 256 x 256 = 65,536 trường hợp
// ----------------------------------------------------------------------------
class mul_exhaustive_sequence extends uvm_sequence #(mul_seq_item);
    `uvm_object_utils(mul_exhaustive_sequence)

    function new(string name = "mul_exhaustive_sequence");
        super.new(name);
    endfunction

    virtual task body();
        mul_seq_item item;
        `uvm_info("UVM_SEQ", ">>> Starting EXHAUSTIVE SEQUENCE: Sweeping ALL 65,536 Input Combinations (-128..127 x -128..127) <<<", UVM_LOW)
        for (int a = -128; a <= 127; a++) begin
            for (int b = -128; b <= 127; b++) begin
                item = mul_seq_item::type_id::create("exh_item");
                start_item(item);
                item.a_i = 8'(signed'(a));
                item.b_i = 8'(signed'(b));
                finish_item(item);
            end
            if (a % 32 == 0) begin
                `uvm_info("UVM_SEQ_PROGRESS", $sformatf("... Exhaustive Progress: a = %0d / 127 (Total: %0d vectors)", a, (a + 128) * 256), UVM_MEDIUM)
            end
        end
    endtask
endclass

`endif
