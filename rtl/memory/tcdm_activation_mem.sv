// ============================================================================
// File: tcdm_activation_mem.sv
// Project: PULP-inspired Edge AI SoC for Handwritten Digit Recognition
// Module: tcdm_activation_mem (SystemVerilog TCDM Activation Memory)
// Author: Nguyen Van Thuc (24161421)
// Description:
//   Tightly-Coupled Data Memory (TCDM) for Activations.
//   - Bank 0 (Input Image): 1024 bytes (Stores 784 input pixels).
//   - Bank 1 (Hidden Layer): 64 bytes (Stores 64 hidden activations).
//   SystemVerilog implementation using IEEE 1800-2012 syntax.
// ============================================================================

`timescale 1ns / 1ps

module tcdm_activation_mem #(
    parameter INIT_IMAGE_FILE = ""
)(
    input  logic        clk,
    input  logic        rst_n,

    // Host / Input loading interface
    input  logic        host_we_i,
    input  logic [9:0]  host_addr_i,
    input  logic [7:0]  host_wdata_i,

    // Layer 1 input read interface (Bank 0)
    input  logic        bank0_rd_en_i,
    input  logic [9:0]  l1_raddr_i,
    output logic [7:0]  l1_rdata_o,

    // Layer 1 writeback interface (Bank 1: writes 4 bytes into hidden bank)
    input  logic        l1_wb_we_i,
    input  logic [5:0]  l1_wb_addr_i, // Base address for 4 neurons (e.g. 0, 4, 8, ...)
    input  logic [31:0] l1_wb_data_i, // {act3, act2, act1, act0}

    // Layer 2 input read interface (Bank 1)
    input  logic        bank1_rd_en_i,
    input  logic [5:0]  l2_raddr_i,
    output logic [7:0]  l2_rdata_o
);

    // Bank 0: Input Image (1024 x 8-bit Distributed LUTRAM on FPGA / 1KB SRAM macro on ASIC)
    (* ram_style = "distributed" *) logic [7:0] bank0_in [0:1023];

    // Bank 1: Hidden Layer packed as 16 x 32-bit words (1 write port + 1 read port -> infers 32 LUTRAMs, 0 FFs!)
    (* ram_style = "distributed" *) logic [31:0] bank1_hidden_w32 [0:15];

`ifndef YOSYS
    initial begin
        for (int idx = 0; idx < 1024; idx++) bank0_in[idx] = 8'h00;
        for (int idx = 0; idx < 16; idx++)   bank1_hidden_w32[idx] = 32'h0000_0000;
        if (INIT_IMAGE_FILE != "") begin
            $readmemh(INIT_IMAGE_FILE, bank0_in);
        end
    end
`endif

`ifdef ASIC_SYNTH
    sky130_sram_1kbyte_1rw1r_8x1024_8 u_bank0_sram (
        .clk0   ( clk ),
        .csb0   ( !host_we_i ),
        .web0   ( !host_we_i ),
        .wmask0 ( 1'b1 ),
        .addr0  ( host_addr_i ),
        .din0   ( host_wdata_i ),
        .dout0  ( ),
        .clk1   ( clk ),
        .csb1   ( !bank0_rd_en_i ),
        .addr1  ( l1_raddr_i ),
        .dout1  ( l1_rdata_o )
    );
`else
    // Bank 0 write / read with Fine-Grained Clock Gating Enable
    always_ff @(posedge clk) begin
        if (host_we_i) begin
            bank0_in[host_addr_i] <= host_wdata_i;
        end
        if (bank0_rd_en_i) begin
            l1_rdata_o <= bank0_in[l1_raddr_i];
        end
    end
`endif

    // Bank 1 32-bit word write (from Layer 1 4-lane SIMD writeback) and byte-selected read (to Layer 2)
    wire [31:0] bank1_word_rdata = bank1_hidden_w32[l2_raddr_i[5:2]];

    always_ff @(posedge clk) begin
        if (l1_wb_we_i) begin
            bank1_hidden_w32[l1_wb_addr_i[5:2]] <= l1_wb_data_i;
        end
        if (bank1_rd_en_i) begin
            case (l2_raddr_i[1:0])
                2'b00: l2_rdata_o <= bank1_word_rdata[7:0];
                2'b01: l2_rdata_o <= bank1_word_rdata[15:8];
                2'b10: l2_rdata_o <= bank1_word_rdata[23:16];
                2'b11: l2_rdata_o <= bank1_word_rdata[31:24];
            endcase
        end
    end

endmodule : tcdm_activation_mem
