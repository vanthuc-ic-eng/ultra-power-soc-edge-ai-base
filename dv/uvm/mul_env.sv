// ============================================================================
// File: mul_env.sv
// Project: PULP-inspired Edge AI SoC Verification
// Component: UVM Environment
// Standard: UVM 1.2
// ============================================================================

`ifndef MUL_ENV_SV
`define MUL_ENV_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class mul_env extends uvm_env;
    `uvm_component_utils(mul_env)

    mul_agent      agent;
    mul_scoreboard scb;

    function new(string name = "mul_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = mul_agent::type_id::create("agent", this);
        scb   = mul_scoreboard::type_id::create("scb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.mon.ap.connect(scb.item_imp);
    endfunction
endclass

`endif
