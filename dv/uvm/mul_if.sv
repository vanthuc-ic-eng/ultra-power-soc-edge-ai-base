// ============================================================================
// File: mul_if.sv
// Project: PULP-inspired Edge AI SoC Verification
// Component: SystemVerilog Interface for Multiplier Core
// Standard: IEEE 1800-2012 / UVM 1.2
// ============================================================================

`ifndef MUL_IF_SV
`define MUL_IF_SV

interface mul_if;
    logic signed [7:0]  a_i;
    logic signed [7:0]  b_i;
    logic signed [15:0] p_o;
endinterface

`endif
