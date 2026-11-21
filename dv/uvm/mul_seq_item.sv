// ============================================================================
// File: mul_seq_item.sv
// Project: PULP-inspired Edge AI SoC Verification
// Component: UVM Sequence Item for Approximate Multiplier (lutalm_mul_s8)
// Standard: UVM 1.2 (IEEE 1800.2)
// ============================================================================

`ifndef MUL_SEQ_ITEM_SV
`define MUL_SEQ_ITEM_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class mul_seq_item extends uvm_sequence_item;
    `uvm_object_utils(mul_seq_item)

    // Stimulus fields
    rand bit signed [7:0] a_i;
    rand bit signed [7:0] b_i;

    // Response field from DUT
    bit signed [15:0]     p_o;

    // Golden model expected value
    bit signed [15:0]     expected_p;

    function new(string name = "mul_seq_item");
        super.new(name);
    endfunction

    // Standard do_copy / do_compare / convert2string
    virtual function string convert2string();
        return $sformatf("a_i=%0d (0x%02h), b_i=%0d (0x%02h) -> p_o=%0d (exp=%0d)",
                         a_i, a_i, b_i, b_i, p_o, expected_p);
    endfunction
endclass

`endif
