// ============================================================================
// File: tb_pulp_hwpe_live.sv
// Project: PULP-inspired Edge AI SoC for Handwritten Digit Recognition
// Module: tb_pulp_hwpe_live (Single-Inference Live Co-Simulation Testbench)
// Author: Nguyen Van Thuc (24161421)
// Description:
//   Loads a single input image from a temporary hex file, triggers the HWPE
//   autonomous inference, and prints exact bit-level results and logits to stdout.
//   Designed for real-time co-simulation with the Interactive Web GUI.
// ============================================================================

`timescale 1ns / 1ps

import pulp_hwpe_pkg::*;

module tb_pulp_hwpe_live;

    logic clk;
    logic rst_n;
    logic start_i;
    logic busy_o;
    logic done_o;
    logic [3:0] pred_class_o;
    logic signed [31:0] best_logit_o;
    logic [31:0] cycle_count_o;

    logic host_we_i;
    logic [9:0] host_addr_i;
    logic [7:0] host_wdata_i;

    // Parameterized image path passed via command line (+IMG_HEX=path)
    string img_hex_path;

    // Instantiate Top-level Accelerator
    pulp_hwpe_top #(
        .SHIFT_BITS(11),
        .WEIGHTS_FILE("/workspace/projects/pulp_edge_ai_soc/sw/data/weights_tcdm.hex"),
        .BIAS_L1_FILE("/workspace/projects/pulp_edge_ai_soc/sw/data/biases_l1.hex"),
        .BIAS_L2_FILE("/workspace/projects/pulp_edge_ai_soc/sw/data/biases_l2.hex"),
        .INIT_IMAGE_FILE("")
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_i(start_i),
        .busy_o(busy_o),
        .done_o(done_o),
        .pred_class_o(pred_class_o),
        .best_logit_o(best_logit_o),
        .cycle_count_o(cycle_count_o),
        .host_we_i(host_we_i),
        .host_addr_i(host_addr_i),
        .host_wdata_i(host_wdata_i)
    );

    // 100 MHz Clock Generation
    always #5 clk = ~clk;

    logic [7:0] temp_img [0:783];

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start_i = 1'b0;
        host_we_i = 1'b0;
        host_addr_i = 10'd0;
        host_wdata_i = 8'd0;

        if (!$value$plusargs("IMG_HEX=%s", img_hex_path)) begin
            img_hex_path = "/workspace/projects/pulp_edge_ai_soc/sw/data/test_image_digit0.hex";
        end

        $readmemh(img_hex_path, temp_img);

        #40;
        rst_n = 1'b1;
        #20;

        // DMA write image into TCDM Buffer (Bank 0)
        @(posedge clk);
        #1;
        for (int i = 0; i < 784; i++) begin
            host_we_i = 1'b1;
            host_addr_i = 10'(i);
            host_wdata_i = temp_img[i];
            @(posedge clk);
            #1;
        end
        host_we_i = 1'b0;

        // Trigger autonomous HWPE inference
        @(posedge clk);
        start_i = 1'b1;
        @(posedge clk);
        start_i = 1'b0;

        // Wait for accelerator DONE flag
        wait(done_o == 1'b1);
        @(posedge clk);

        // Print Machine-Readable Co-Simulation Result
        $display("[RTL_RESULT] PRED=%0d CYCLES=%0d BEST_LOGIT=%0d", 
                 pred_class_o, cycle_count_o, best_logit_o);

        #20;
        $finish;
    end

endmodule : tb_pulp_hwpe_live
