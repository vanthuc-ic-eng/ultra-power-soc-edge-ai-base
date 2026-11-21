// ============================================================================
// File: mul_monitor.sv
// Project: PULP-inspired Edge AI SoC Verification
// Component: UVM Monitor & Functional Coverage for Multiplier
// Standard: UVM 1.2
// ============================================================================

`ifndef MUL_MONITOR_SV
`define MUL_MONITOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class mul_monitor extends uvm_monitor;
    `uvm_component_utils(mul_monitor)

    virtual mul_if vif;
    uvm_analysis_port #(mul_seq_item) ap;

    // ------------------------------------------------------------------------
    // Functional Coverage Group: Quét đầy đủ Corner Cases và không gian đầu vào
    // ------------------------------------------------------------------------
    covergroup mul_cov;
        option.per_instance = 1;
        option.name = "mul_input_space_coverage";

        // Bins cho toán hạng a_i (INT8: -128..127)
        cov_a: coverpoint vif.a_i {
            bins zero     = {8'sd0};
            bins min_neg  = {-8'sd128};
            bins max_pos  = {8'sd127};
            bins neg_one  = {-8'sd1};
            bins pos_one  = {8'sd1};
            bins neg_mid  = {[-8'sd127 : -8'sd2]};
            bins pos_mid  = {[8'sd2 : 8'sd126]};
        }

        // Bins cho toán hạng b_i (INT8: -128..127)
        cov_b: coverpoint vif.b_i {
            bins zero     = {8'sd0};
            bins min_neg  = {-8'sd128};
            bins max_pos  = {8'sd127};
            bins neg_one  = {-8'sd1};
            bins pos_one  = {8'sd1};
            bins neg_mid  = {[-8'sd127 : -8'sd2]};
            bins pos_mid  = {[8'sd2 : 8'sd126]};
        }

        // Cross coverage 7x7 = 49 bins: bao phủ mọi tổ hợp dấu và góc biên!
        cov_cross: cross cov_a, cov_b;
    endgroup

    function new(string name = "mul_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
        mul_cov = new();
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual mul_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("MON_NOVIF", "Virtual interface vif not set in config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        mul_seq_item item;
        forever begin
            #1ns;
            // Sample covergroup
            mul_cov.sample();

            item = mul_seq_item::type_id::create("mon_item");
            item.a_i = vif.a_i;
            item.b_i = vif.b_i;
            item.p_o = vif.p_o;
            ap.write(item);
        end
    endtask
endclass

`endif
