// ============================================================================
// File: hwpe_stream_ctrl.sv
// Project: PULP-inspired Edge AI SoC for Handwritten Digit Recognition
// Module: hwpe_stream_ctrl (SystemVerilog Autonomous Stream Controller)
// Author: Nguyen Van Thuc (24161421)
// Description:
//   Autonomous HWPE Stream Controller & Address Generation Unit (AGU).
//   Pipelined synchronous BRAM streaming with zero-cycle overhead.
//   SystemVerilog implementation using IEEE 1800-2012 syntax and typed enums.
// ============================================================================

`timescale 1ns / 1ps

`ifndef YOSYS
import pulp_hwpe_pkg::*;
`endif

module hwpe_stream_ctrl #(
    parameter int unsigned L1_INPUT_DIM  = pulp_hwpe_pkg::L1_INPUT_DIM,
    parameter int unsigned L1_NEURONS    = pulp_hwpe_pkg::L1_NEURONS,
    parameter int unsigned L2_NEURONS    = pulp_hwpe_pkg::L2_NEURONS,
    parameter int unsigned SHIFT_BITS    = pulp_hwpe_pkg::SHIFT_BITS
)(
    input  logic                 clk,
    input  logic                 rst_n,

    // Host Control Interface
    input  logic                 start_i,
    output logic                 busy_o,
    output logic                 done_o,
    output logic [31:0]          cycle_count_o,

    // Weight TCDM Interface
    output logic [13:0]          w_addr_o,

    // Activation TCDM Interface
    input  logic [7:0]           l1_in_data_i,
    input  logic [31:0]          l1_wb_data_i,
    output logic [9:0]           l1_in_addr_o,
    output logic                 l1_wb_we_o,
    output logic [5:0]           l1_wb_addr_o,
    output logic [5:0]           l2_in_addr_o,

    // Bias TCDM Interface
    output logic [3:0]           l1_bias_grp_o,
    output logic [1:0]           l2_bias_grp_o,

    // PE Array Control
    output logic                 pe_clr_o,
    output logic                 pe_valid_o,
    output logic                 pe_sel_l2_o, // 0: L1 inputs, 1: L2 inputs

    // Fine-Grained Memory Read & Power Controls
    output logic                 bank0_rd_en_o,
    output logic                 bank1_rd_en_o,

    // Argmax Control (2-stage pipelined timing sign-off)
    output logic                 argmax_clr_o,
    output logic                 argmax_step1_o,
    output logic                 argmax_update_o,
    output logic [1:0]           argmax_grp_o
);

    // FSM States using typed enum from pulp_hwpe_pkg
`ifdef YOSYS
    localparam [3:0] ST_IDLE         = 4'd0,
                     ST_PRESCAN      = 4'd1,
                     ST_L1_LOAD_BIAS = 4'd2,
                     ST_L1_STREAM    = 4'd3,
                     ST_L1_DRAIN     = 4'd4,
                     ST_L1_WRITEBACK = 4'd5,
                     ST_L2_LOAD_BIAS = 4'd6,
                     ST_L2_STREAM    = 4'd7,
                     ST_L2_DRAIN     = 4'd8,
                     ST_DONE         = 4'd9;
    logic [3:0] state_q, state_d;
`else
    fsm_state_e state_q, state_d;
`endif

    // Loop counters
    logic [3:0] l1_grp_q;        // 0..15 (16 groups of 4 = 64 neurons)
    logic [1:0] l2_grp_q;        // 0..2 (3 groups of 4 = 12 neurons)
    logic [5:0] l2_k_q;          // 0..63
    logic [1:0] l2_drain_step_q; // 3-cycle pipelined drain for MAC & argmax timing sign-off

    // ------------------------------------------------------------------------
    // Dual-Layer Zero-Skipping Sparsity Engine (Zero-LUT Synchronous Block RAM)
    // ------------------------------------------------------------------------
    // Layer 1: Synchronous Block RAM (RAMB18E1) storing non-zero pixel indices (0 LUTs!)
    // Index 0 is cached in `first_nz_idx_q` so BRAM prefetches index 1..N-1 with 0-cycle penalty
    (* ram_style = "block" *) logic [9:0] sparse_idx_mem [0:1023];
    logic [9:0] nz_len_q;
    logic [9:0] sparse_ptr_q;
    logic [9:0] first_nz_idx_q;
    logic [9:0] sparse_rdata_q;

    // Autonomous Pre-scan Engine registers
    logic [9:0] scan_k_q;
    logic [9:0] scan_idx_pipe;
    logic       scan_valid_pipe;

    // Lookahead BRAM Read Address: fetches [1] during ST_L1_LOAD_BIAS, [sparse_ptr_q + 2] during ST_L1_STREAM
    wire [9:0]  sparse_raddr   = (state_q == ST_L1_LOAD_BIAS) ? 10'd1 : (sparse_ptr_q + 10'd2);
    wire [9:0]  active_nz_idx  = (state_q == ST_L1_LOAD_BIAS) ? first_nz_idx_q : sparse_rdata_q;
    wire [13:0] l1_w_base      = l1_grp_q * 14'd784;
    wire [13:0] next_l1_w_addr = l1_w_base + {4'd0, active_nz_idx};

    // Pure synchronous Block RAM write & read (infers 1 RAMB18E1 on FPGA / 1KB SRAM macro on ASIC)
`ifdef ASIC_SYNTH
    sky130_sram_1kbyte_1rw1r_10x1024_macro u_sparse_sram (
        .clk0   ( clk ),
        .csb0   ( !((state_q == ST_PRESCAN) && scan_valid_pipe && (l1_in_data_i != 8'h00)) ),
        .web0   ( !((state_q == ST_PRESCAN) && scan_valid_pipe && (l1_in_data_i != 8'h00)) ),
        .addr0  ( nz_len_q ),
        .din0   ( scan_idx_pipe ),
        .clk1   ( clk ),
        .csb1   ( 1'b0 ),
        .addr1  ( sparse_raddr ),
        .dout1  ( sparse_rdata_q )
    );
`else
    always_ff @(posedge clk) begin
        if ((state_q == ST_PRESCAN) && scan_valid_pipe && (l1_in_data_i != 8'h00)) begin
            sparse_idx_mem[nz_len_q] <= scan_idx_pipe;
        end
        sparse_rdata_q <= sparse_idx_mem[sparse_raddr];
    end
`endif

    // 1-cycle pipeline delay for synchronous BRAM read
    logic stream_valid_pipe;

    // Fine-Grained Memory Power Enable Signals
    assign bank0_rd_en_o = (state_q == ST_PRESCAN) || (state_q == ST_L1_LOAD_BIAS) || (state_q == ST_L1_STREAM);
    assign bank1_rd_en_o = (state_q == ST_L2_LOAD_BIAS) || (state_q == ST_L2_STREAM);

    // Combinational Argmax Controls (2-stage pipelined)
    assign argmax_step1_o  = (state_q == ST_L2_DRAIN && (l2_drain_step_q == 2'd1));
    assign argmax_update_o = (state_q == ST_L2_DRAIN && (l2_drain_step_q == 2'd2));
    assign argmax_grp_o    = l2_grp_q;
    assign argmax_clr_o    = (state_q == ST_IDLE && start_i);

    // Cycle counter (always_ff)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count_o <= 32'd0;
        end else if (start_i && state_q == ST_IDLE) begin
            cycle_count_o <= 32'd0;
        end else if (busy_o) begin
            cycle_count_o <= cycle_count_o + 32'd1;
        end
    end

    // FSM State Register (always_ff)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
        end else begin
            state_q <= state_d;
        end
    end

    // FSM Next State and Datapath Control (always_comb)
    always_comb begin
        state_d = state_q;
        busy_o  = 1'b1;
        done_o  = 1'b0;

        case (state_q)
            ST_IDLE: begin
                busy_o = 1'b0;
                if (start_i) begin
                    state_d = ST_PRESCAN;
                end
            end

            ST_PRESCAN: begin
                if (scan_valid_pipe && (scan_idx_pipe == (L1_INPUT_DIM[9:0] - 10'd1))) begin
                    state_d = ST_L1_LOAD_BIAS;
                end
            end

            ST_L1_LOAD_BIAS: begin
                state_d = ST_L1_STREAM;
            end

            ST_L1_STREAM: begin
                if (nz_len_q == 10'd0 || sparse_ptr_q == (nz_len_q - 10'd1)) begin
                    state_d = ST_L1_DRAIN;
                end
            end

            ST_L1_DRAIN: begin
                state_d = ST_L1_WRITEBACK;
            end

            ST_L1_WRITEBACK: begin
                if (l1_grp_q == 4'd15) begin
                    state_d = ST_L2_LOAD_BIAS;
                end else begin
                    state_d = ST_L1_LOAD_BIAS;
                end
            end

            ST_L2_LOAD_BIAS: begin
                state_d = ST_L2_STREAM;
            end

            ST_L2_STREAM: begin
                if (l2_k_q == 6'd63) begin
                    state_d = ST_L2_DRAIN;
                end
            end

            ST_L2_DRAIN: begin
                if (l2_drain_step_q != 2'd2) begin
                    state_d = ST_L2_DRAIN;
                end else if (l2_grp_q == 2'd2) begin
                    state_d = ST_DONE;
                end else begin
                    state_d = ST_L2_LOAD_BIAS;
                end
            end

            ST_DONE: begin
                busy_o = 1'b0;
                done_o = 1'b1;
                if (!start_i) begin
                    state_d = ST_IDLE;
                end
            end

            default: state_d = ST_IDLE;
        endcase
    end

    // Address Generators and Control Signals (always_ff)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l1_grp_q          <= 4'd0;
            l2_grp_q          <= 2'd0;
            l2_k_q            <= 6'd0;
            l2_drain_step_q   <= 2'd0;
            w_addr_o          <= 14'd0;
            l1_in_addr_o      <= 10'd0;
            l2_in_addr_o      <= 6'd0;
            l1_bias_grp_o     <= 4'd0;
            l2_bias_grp_o     <= 2'd0;
            l1_wb_we_o        <= 1'b0;
            l1_wb_addr_o      <= 6'd0;
            pe_clr_o          <= 1'b0;
            pe_valid_o        <= 1'b0;
            pe_sel_l2_o       <= 1'b0;
            stream_valid_pipe <= 1'b0;
            nz_len_q          <= 10'd0;
            sparse_ptr_q      <= 10'd0;
            first_nz_idx_q    <= 10'd0;
            scan_k_q          <= 10'd0;
            scan_idx_pipe     <= 10'd0;
            scan_valid_pipe   <= 1'b0;
        end else begin
            pe_clr_o          <= 1'b0;
            pe_valid_o        <= stream_valid_pipe;
            l1_wb_we_o        <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    l1_grp_q          <= 4'd0;
                    l2_grp_q          <= 2'd0;
                    l2_drain_step_q   <= 2'd0;
                    stream_valid_pipe <= 1'b0;
                    nz_len_q          <= 10'd0;
                    sparse_ptr_q      <= 10'd0;
                    first_nz_idx_q    <= 10'd0;
                    scan_k_q          <= 10'd0;
                    scan_idx_pipe     <= 10'd0;
                    scan_valid_pipe   <= 1'b0;
                    l1_in_addr_o      <= 10'd0;
                end

                ST_PRESCAN: begin
                    pe_clr_o          <= 1'b0;
                    stream_valid_pipe <= 1'b0;

                    // 1. Increment non-zero pixel count & latch first non-zero index
                    if (scan_valid_pipe && (l1_in_data_i != 8'h00)) begin
                        if (nz_len_q == 10'd0) begin
                            first_nz_idx_q <= scan_idx_pipe;
                        end
                        nz_len_q <= nz_len_q + 10'd1;
                    end

                    // 2. Issue next address into Activation Memory Bank 0
                    scan_idx_pipe   <= scan_k_q;
                    scan_valid_pipe <= (scan_k_q < L1_INPUT_DIM[9:0]);
                    if (scan_k_q < L1_INPUT_DIM[9:0]) begin
                        l1_in_addr_o <= scan_k_q;
                        scan_k_q     <= scan_k_q + 10'd1;
                    end
                end

                ST_L1_LOAD_BIAS: begin
                    pe_clr_o          <= 1'b1;
                    pe_sel_l2_o       <= 1'b0;
                    l1_bias_grp_o     <= l1_grp_q;
                    sparse_ptr_q      <= 10'd0;
                    if (nz_len_q > 10'd0) begin
                        l1_in_addr_o      <= active_nz_idx;
                        w_addr_o          <= next_l1_w_addr;
                        stream_valid_pipe <= 1'b1;
                    end else begin
                        l1_in_addr_o      <= 10'd0;
                        w_addr_o          <= 14'd0;
                        stream_valid_pipe <= 1'b0;
                    end
                end

                ST_L1_STREAM: begin
                    pe_sel_l2_o <= 1'b0;
                    if (nz_len_q == 10'd0 || sparse_ptr_q == (nz_len_q - 10'd1)) begin
                        stream_valid_pipe <= 1'b0;
                    end else begin
                        stream_valid_pipe <= 1'b1;
                        sparse_ptr_q      <= sparse_ptr_q + 10'd1;
                        l1_in_addr_o      <= active_nz_idx;
                        w_addr_o          <= next_l1_w_addr;
                    end
                end

                ST_L1_DRAIN: begin
                    stream_valid_pipe <= 1'b0;
                end

                ST_L1_WRITEBACK: begin
                    l1_wb_we_o   <= 1'b1;
                    l1_wb_addr_o <= {l1_grp_q, 2'b00};
                    l1_grp_q     <= l1_grp_q + 4'd1;
                end

                ST_L2_LOAD_BIAS: begin
                    pe_clr_o          <= 1'b1;
                    pe_sel_l2_o       <= 1'b1;
                    l2_bias_grp_o     <= l2_grp_q;
                    l2_k_q            <= 6'd0;
                    w_addr_o          <= 14'd12544 + {6'd0, l2_grp_q, 6'd0};
                    l2_in_addr_o      <= 6'd0;
                    stream_valid_pipe <= 1'b1;
                end

                ST_L2_STREAM: begin
                    pe_sel_l2_o <= 1'b1;
                    if (l2_k_q == 6'd63) begin
                        stream_valid_pipe <= 1'b0;
                    end else begin
                        stream_valid_pipe <= 1'b1;
                        l2_k_q       <= l2_k_q + 6'd1;
                        l2_in_addr_o <= l2_k_q + 6'd1;
                        w_addr_o     <= 14'd12544 + {6'd0, l2_grp_q, 6'd0} + {8'd0, l2_k_q + 6'd1};
                    end
                end

                ST_L2_DRAIN: begin
                    stream_valid_pipe <= 1'b0;
                    if (l2_drain_step_q < 2'd2) begin
                        l2_drain_step_q <= l2_drain_step_q + 2'd1;
                    end else begin
                        l2_drain_step_q <= 2'd0;
                        l2_grp_q        <= l2_grp_q + 2'd1;
                    end
                end

                ST_DONE: begin
                    stream_valid_pipe <= 1'b0;
                end
            endcase
        end
    end

endmodule : hwpe_stream_ctrl
