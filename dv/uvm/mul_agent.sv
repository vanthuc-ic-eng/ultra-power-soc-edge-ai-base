// ============================================================================
// File: mul_agent.sv
// Project: PULP-inspired Edge AI SoC Verification
// Component: UVM Agent (Driver + Sequencer + Monitor)
// Standard: UVM 1.2
// ============================================================================

`ifndef MUL_AGENT_SV
`define MUL_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

typedef uvm_sequencer #(mul_seq_item) mul_sequencer;

class mul_agent extends uvm_agent;
    `uvm_component_utils(mul_agent)

    mul_sequencer sqr;
    mul_driver    drv;
    mul_monitor   mon;

    function new(string name = "mul_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = mul_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = mul_sequencer::type_id::create("sqr", this);
            drv = mul_driver::type_id::create("drv", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction
endclass

`endif
