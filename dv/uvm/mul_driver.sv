// ============================================================================
// File: mul_driver.sv
// Project: PULP-inspired Edge AI SoC Verification
// Component: UVM Driver for Multiplier
// Standard: UVM 1.2
// ============================================================================

`ifndef MUL_DRIVER_SV
`define MUL_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class mul_driver extends uvm_driver #(mul_seq_item);
    `uvm_component_utils(mul_driver)

    virtual mul_if vif;

    function new(string name = "mul_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual mul_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DRV_NOVIF", "Virtual interface vif not set in config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        mul_seq_item req;
        forever begin
            seq_item_port.get_next_item(req);
            // Drive combinational inputs
            vif.a_i = req.a_i;
            vif.b_i = req.b_i;
            #1ns; // Combinational propagation delay
            seq_item_port.item_done();
        end
    endtask
endclass

`endif
