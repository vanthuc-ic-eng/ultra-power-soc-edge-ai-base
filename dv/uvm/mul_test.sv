// ============================================================================
// File: mul_test.sv
// Project: PULP-inspired Edge AI SoC Verification
// Component: UVM Test Base & Full Exhaustive Test
// Standard: UVM 1.2
// ============================================================================

`ifndef MUL_TEST_SV
`define MUL_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class mul_test_base extends uvm_test;
    `uvm_component_utils(mul_test_base)

    mul_env env;

    function new(string name = "mul_test_base", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = mul_env::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction
endclass

// Comprehensive Exhaustive Test running Corner -> Random -> Full 65,536
class mul_exhaustive_test extends mul_test_base;
    `uvm_component_utils(mul_exhaustive_test)

    function new(string name = "mul_exhaustive_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        mul_corner_sequence     corner_seq;
        mul_random_sequence     rand_seq;
        mul_exhaustive_sequence exh_seq;

        phase.raise_objection(this);

        `uvm_info("UVM_TEST", "==================================================================", UVM_LOW)
        `uvm_info("UVM_TEST", "  STARTING UVM EXHAUSTIVE VERIFICATION: CORNER + RANDOM + 65,536 ", UVM_LOW)
        `uvm_info("UVM_TEST", "==================================================================", UVM_LOW)

        // 1. Chạy Corner-Cases
        corner_seq = mul_corner_sequence::type_id::create("corner_seq");
        corner_seq.start(env.agent.sqr);

        // 2. Chạy Constrained Random (1000 mẫu)
        rand_seq = mul_random_sequence::type_id::create("rand_seq");
        rand_seq.start(env.agent.sqr);

        // 3. Quét TOÀN BỘ 65,536 vector (100% không gian toán học)
        exh_seq = mul_exhaustive_sequence::type_id::create("exh_seq");
        exh_seq.start(env.agent.sqr);

        #10ns;
        phase.drop_objection(this);
    endtask
endclass

`endif
