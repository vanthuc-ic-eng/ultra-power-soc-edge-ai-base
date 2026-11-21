// ============================================================================
// File: tb_uvm_top.sv
// Project: PULP-inspired Edge AI SoC Verification
// Component: Top-level UVM Testbench Module
// Standard: IEEE 1800-2012 / UVM 1.2
// ============================================================================

`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "mul_seq_item.sv"
`include "mul_if.sv"
`include "mul_driver.sv"
`include "mul_monitor.sv"
`include "mul_scoreboard.sv"
`include "mul_agent.sv"
`include "mul_env.sv"
`include "mul_sequences.sv"
`include "mul_test.sv"

module tb_uvm_top;

    // Interface
    mul_if intf();

    // Instantiate Design Under Test (DUT): Approximate Multiplier Core (v0.3.0)
    lutalm_mul_s8 #(
        .LOW_W        ( 3 ),
        .TRUNC_BITS   ( 4 ),
        .ROUND_MODE   ( 1 ),
        .ADAPTIVE_LUT ( 0 ),
        .USE_CARRY    ( 1 ),
        .QUAD_CURV    ( 0 )
    ) dut (
        .a_i ( intf.a_i ),
        .b_i ( intf.b_i ),
        .p_o ( intf.p_o )
    );

    initial begin
        // Set virtual interface in UVM config_db
        uvm_config_db#(virtual mul_if)::set(null, "*", "vif", intf);

        // Run Pure UVM Test
        run_test("mul_exhaustive_test");
    end

endmodule
