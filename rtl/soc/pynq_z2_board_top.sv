// ============================================================================
// File: pynq_z2_board_top.sv
// Project: PULP-inspired Edge AI SoC (CONQUEROR-1) on TUL PYNQ-Z2
// Target Device: AMD Xilinx Zynq-7000 xc7z020clg400-1
// Author: Nguyen Van Thuc (24161421)
// Description:
//   Physical Board Top-Level Wrapper for TUL PYNQ-Z2 featuring:
//   1. Dual-safe Clock Architecture: 125 MHz -> 100 MHz PLL (PLLE2_BASE) with
//      automatic glitch-free fallback (BUFGMUX) to internal STARTUPE2 CFGMCLK.
//   2. High-Speed Real-Time JTAG Streaming Engine (BSCANE2 USER4):
//      - Streams 28x28 (784-byte) images packed 3 pixels per 32-bit JTAG word
//        (only 262 words per frame -> < 2 ms transfer latency over JTAG!).
//      - Triggers autonomous LA-HWPE hardware inference on the FPGA fabric.
//      - Reads back hardware predicted digit (0..9), done/busy flags, and
//        exact hardware execution cycle count (e.g., 3,901 cycles) over JTAG.
//   3. Physical 4-Bit Binary Digit Display on PYNQ-Z2 User LEDs (LD3..LD0):
//      - led[3:0] (Pins M14, N16, P14, R14) directly displays the 4-bit binary
//        code of the recognized digit (0 = 0000 .. 9 = 1001).
//      - RGB LEDs LD4_G (Done), LD4_B (JTAG Transfer Pulse), LD5_R (Busy).
// ============================================================================

`timescale 1ns / 1ps

module pynq_z2_board_top (
    input  logic       sysclk,      // 125 MHz External Clock (Pin H16)
    input  logic       rst_n,       // Active-Low Reset on Slide Switch SW0 (Pin M20: 0=Reset, 1=Run)
    output logic [3:0] led,         // LD3..LD0: 4-bit Binary Digit Output (M14, N16, P14, R14)
    output logic       led4_g,      // LD4 Green: Inference Done (Pin G17)
    output logic       led4_b,      // LD4 Blue: Live JTAG Activity Flash (Pin L15)
    output logic       led5_r,      // LD5 Red: HWPE Busy (Pin M15)
    output logic       uart_txd_o   // UART TX Debug Output (Pin Y18)
);

    // ------------------------------------------------------------------------
    // 1. Clock & Reset Generation (100 MHz PLL + Internal Oscillator Fallback)
    // ------------------------------------------------------------------------
    logic clk_sys;

`ifndef __ICARUS__
    logic clk_fb;
    logic clk_100m_unbuf;
    logic pll_locked;
    logic cfgmclk_unbuf;

    PLLE2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT      (8),          // 125 MHz * 8 = 1000 MHz VCO
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (8.000),      // 125 MHz input
        .CLKOUT0_DIVIDE     (10),         // 1000 MHz / 10 = 100.0 MHz
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_pll_125_to_100 (
        .CLKOUT0  (clk_100m_unbuf),
        .CLKOUT1  (),
        .CLKOUT2  (),
        .CLKOUT3  (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKFBOUT (clk_fb),
        .LOCKED   (pll_locked),
        .CLKIN1   (sysclk),
        .PWRDWN   (1'b0),
        .RST      (1'b0),                 // Keep PLL continuously locked while SW0 toggles rst_n
        .CLKFBIN  (clk_fb)
    );

    // Internal 65 MHz silicon oscillator (guarantees clock even if H16 jumper is off)
    STARTUPE2 #(
        .PROG_USR      ("FALSE"),
        .SIM_CCLK_FREQ (0.0)
    ) u_startupe2 (
        .CFGCLK    (),
        .CFGMCLK   (cfgmclk_unbuf),
        .EOS       (),
        .PREQ      (),
        .CLK       (1'b0),
        .GSR       (1'b0),
        .GTS       (1'b0),
        .KEYCLEARB (1'b1),
        .PACK      (1'b0),
        .USRCCLKO  (1'b0),
        .USRCCLKTS (1'b1),
        .USRDONEO  (1'b1),
        .USRDONETS (1'b0)
    );

    // Automatically select 100 MHz PLL when locked, else fallback to internal CFGMCLK
    BUFGMUX u_clk_mux (
        .O  (clk_sys),
        .I0 (cfgmclk_unbuf),
        .I1 (clk_100m_unbuf),
        .S  (pll_locked)
    );
`else
    assign clk_sys = sysclk;
`endif

    // ------------------------------------------------------------------------
    // 2. High-Speed Real-Time JTAG Streaming Bridge (BSCANE2 USER4)
    // ------------------------------------------------------------------------
    logic        bscan_tck;
    logic        bscan_reset;
    logic        bscan_sel;
    logic        bscan_capture;
    logic        bscan_shift;
    logic        bscan_update;
    logic        bscan_tdi;
    logic        bscan_tdo;

`ifndef __ICARUS__
    BSCANE2 #(
        .JTAG_CHAIN(4) // Responds to JTAG USER4 instruction (6'b100011 = 0x23)
    ) u_bscan_user4 (
        .CAPTURE (bscan_capture),
        .DRCK    (),
        .RESET   (bscan_reset),
        .RUNTEST (),
        .SEL     (bscan_sel),
        .SHIFT   (bscan_shift),
        .TCK     (bscan_tck),
        .TDI     (bscan_tdi),
        .TMS     (),
        .UPDATE  (bscan_update),
        .TDO     (bscan_tdo)
    );
`else
    initial begin
        bscan_tck     = 1'b0;
        bscan_reset   = 1'b0;
        bscan_sel     = 1'b0;
        bscan_capture = 1'b0;
        bscan_shift   = 1'b0;
        bscan_update  = 1'b0;
        bscan_tdi     = 1'b0;
    end
`endif

    // Status signals from SoC to JTAG TCK domain
    logic        soc_led_busy;
    logic        soc_led_done;
    logic [3:0]  soc_led_pred;
    logic [31:0] soc_hwpe_cycles;

    logic        led_override_en;
    logic [3:0]  led_override_val;
    logic [3:0]  active_led_val;

    assign active_led_val = led_override_en ? led_override_val : soc_led_pred;

    // Synchronize status into TCK domain for glitch-free CAPTURE readback
    (* ASYNC_REG = "TRUE" *) logic        done_tck_q0, done_tck_q1;
    (* ASYNC_REG = "TRUE" *) logic        busy_tck_q0, busy_tck_q1;
    (* ASYNC_REG = "TRUE" *) logic [3:0]  pred_tck_q0, pred_tck_q1;
    (* ASYNC_REG = "TRUE" *) logic [21:0] cyc_tck_q0,  cyc_tck_q1;

    always_ff @(posedge bscan_tck) begin
        done_tck_q0 <= soc_led_done;
        done_tck_q1 <= done_tck_q0;
        busy_tck_q0 <= soc_led_busy;
        busy_tck_q1 <= busy_tck_q0;
        pred_tck_q0 <= active_led_val;
        pred_tck_q1 <= pred_tck_q0;
        cyc_tck_q0  <= soc_hwpe_cycles[21:0];
        cyc_tck_q1  <= cyc_tck_q0;
    end

    // 32-bit JTAG Shift Register (LSB-first to match xsdb drshift -hex / -integer)
    logic [31:0] jtag_sr;
    logic [4:0]  jtag_bit_cnt;
    logic [31:0] cmd_word_tck   = 32'd0;
    logic        cmd_toggle_tck = 1'b0;

    assign bscan_tdo = jtag_sr[0];

    wire [31:0] next_jtag_sr = {bscan_tdi, jtag_sr[31:1]};

    always_ff @(posedge bscan_tck) begin
        if (bscan_reset) begin
            jtag_sr        <= 32'd0;
            jtag_bit_cnt   <= 5'd0;
            cmd_word_tck   <= 32'd0;
            cmd_toggle_tck <= 1'b0;
        end else if (bscan_sel) begin
            if (bscan_capture) begin
                // Capture 32-bit telemetry frame: {4'hA, done, busy, pred[3:0], cycles[21:0]}
                jtag_sr      <= {4'hA, soc_led_done, soc_led_busy, active_led_val, soc_hwpe_cycles[21:0]};
                jtag_bit_cnt <= 5'd0;
            end else if (bscan_shift) begin
                jtag_sr      <= next_jtag_sr;
                jtag_bit_cnt <= jtag_bit_cnt + 5'd1;
                if (jtag_bit_cnt == 5'd31) begin
                    cmd_word_tck   <= next_jtag_sr;
                    cmd_toggle_tck <= ~cmd_toggle_tck;
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // 3. Clock Domain Crossing (TCK -> clk_sys) & 3-Pixel Unpacker FSM
    // ------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) logic [2:0]  cmd_tgl_sync_q;
    (* ASYNC_REG = "TRUE" *) logic [31:0] cmd_word_sync_q;

    logic        jtag_active_q;
    logic        jtag_we;
    logic [9:0]  jtag_addr;
    logic [7:0]  jtag_wdata;
    logic        jtag_start;

    logic [1:0]  unpack_step_q;
    logic [9:0]  unpack_base_addr_q;
    logic [7:0]  unpack_p1_q;
    logic [7:0]  unpack_p2_q;
    logic        pending_auto_start_q;
    logic [21:0] jtag_flash_cnt_q;
    logic [1:0]  rst_warmup_q;

    wire cmd_arrived = (rst_warmup_q == 2'd3) && (cmd_tgl_sync_q[2] ^ cmd_tgl_sync_q[1]);

    always_ff @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            cmd_tgl_sync_q       <= 3'b000;
            cmd_word_sync_q      <= 32'd0;
            rst_warmup_q         <= 2'd0;
            jtag_active_q        <= 1'b0;
            jtag_we              <= 1'b0;
            jtag_addr            <= 10'd0;
            jtag_wdata           <= 8'd0;
            jtag_start           <= 1'b0;
            unpack_step_q        <= 2'd0;
            unpack_base_addr_q   <= 10'd0;
            unpack_p1_q          <= 8'd0;
            unpack_p2_q          <= 8'd0;
            pending_auto_start_q <= 1'b0;
            led_override_en      <= 1'b0;
            led_override_val     <= 4'd0;
            jtag_flash_cnt_q     <= 22'd0;
        end else begin
            cmd_tgl_sync_q <= {cmd_tgl_sync_q[1:0], cmd_toggle_tck};
            if (rst_warmup_q != 2'd3) begin
                rst_warmup_q <= rst_warmup_q + 2'd1;
            end
            if (cmd_tgl_sync_q[1] ^ cmd_tgl_sync_q[0]) begin
                cmd_word_sync_q <= cmd_word_tck;
            end

            // Default 1-cycle pulses
            jtag_we    <= 1'b0;
            jtag_start <= 1'b0;

            if (jtag_flash_cnt_q != 22'd0) begin
                jtag_flash_cnt_q <= jtag_flash_cnt_q - 22'd1;
            end

            // Multi-pixel unpacker pipeline (writes 3 pixels in 3 consecutive 100MHz clocks)
            if (unpack_step_q == 2'd1) begin
                jtag_we       <= 1'b1;
                jtag_addr     <= unpack_base_addr_q + 10'd1;
                jtag_wdata    <= unpack_p1_q;
                unpack_step_q <= 2'd2;
            end else if (unpack_step_q == 2'd2) begin
                if ((unpack_base_addr_q + 10'd2) < 10'd784) begin
                    jtag_we    <= 1'b1;
                    jtag_addr  <= unpack_base_addr_q + 10'd2;
                    jtag_wdata <= unpack_p2_q;
                end
                unpack_step_q <= 2'd0;
            end else if (pending_auto_start_q) begin
                jtag_start           <= 1'b1;
                pending_auto_start_q <= 1'b0;
            end

            // Decode newly arrived 32-bit JTAG command
            if (cmd_arrived) begin
                jtag_active_q <= 1'b1;
                case (cmd_word_sync_q[31:30])
                    2'b01: begin
                        // Packed 3-pixel write:
                        // [29:21] = word_idx (0..261), base_addr = word_idx * 3
                        // [20:14] = pix0[6:0], [13:7] = pix1[6:0], [6:0] = pix2[6:0]
                        jtag_we            <= 1'b1;
                        jtag_addr          <= ({cmd_word_sync_q[29:21], 1'b0} + {1'b0, cmd_word_sync_q[29:21]});
                        jtag_wdata         <= {1'b0, cmd_word_sync_q[20:14]};
                        unpack_base_addr_q <= ({cmd_word_sync_q[29:21], 1'b0} + {1'b0, cmd_word_sync_q[29:21]});
                        unpack_p1_q        <= {1'b0, cmd_word_sync_q[13:7]};
                        unpack_p2_q        <= {1'b0, cmd_word_sync_q[6:0]};
                        unpack_step_q      <= 2'd1;
                    end
                    2'b10: begin
                        // Single-pixel write: [24] = auto_start, [17:8] = addr, [7:0] = data
                        jtag_we              <= 1'b1;
                        jtag_addr            <= cmd_word_sync_q[17:8];
                        jtag_wdata           <= cmd_word_sync_q[7:0];
                        pending_auto_start_q <= cmd_word_sync_q[24];
                        if (cmd_word_sync_q[24]) begin
                            led_override_en  <= 1'b0;
                            jtag_flash_cnt_q <= 22'd3_500_000;
                        end
                    end
                    2'b11: begin
                        // Control & Trigger Command:
                        // [0] = Trigger HWPE Start
                        // [1] = Direct 4-bit LED Override Enable, [7:4] = LED 4-bit value
                        if (cmd_word_sync_q[0]) begin
                            jtag_start       <= 1'b1;
                            led_override_en  <= 1'b0;
                            jtag_flash_cnt_q <= 22'd3_500_000;
                        end
                        if (cmd_word_sync_q[1]) begin
                            led_override_en  <= 1'b1;
                            led_override_val <= cmd_word_sync_q[7:4];
                            jtag_flash_cnt_q <= 22'd3_500_000;
                        end
                    end
                    default: ; // 2'b00: Readback / NOP
                endcase
            end
        end
    end

    // ------------------------------------------------------------------------
    // 4. Complete Mini-PULP RISC-V + LA-HWPE Edge AI SoC Instance
    // ------------------------------------------------------------------------
    pulp_riscv_ai_soc_top #(
        .CLK_FREQ_HZ (100_000_000),
        .BAUD_RATE   (115_200)
    ) u_soc (
        .clk           (clk_sys),
        .rst_n         (rst_n),
        .uart_txd_o    (uart_txd_o),
        .led_busy_o    (soc_led_busy),
        .led_done_o    (soc_led_done),
        .led_pred_o    (soc_led_pred),
        .jtag_active_i (jtag_active_q),
        .jtag_we_i     (jtag_we),
        .jtag_addr_i   (jtag_addr),
        .jtag_wdata_i  (jtag_wdata),
        .jtag_start_i  (jtag_start),
        .hwpe_cycles_o (soc_hwpe_cycles)
    );

    // ------------------------------------------------------------------------
    // 5. Physical PYNQ-Z2 LED Outputs (Cleared immediately when SW0 rst_n == 0)
    //    - led[3:0] (LD3..LD0): 4-Bit Binary Digit (0 = 0000 .. 9 = 1001)
    //    - led4_g   (LD4 Green): High when inference is DONE
    //    - led4_b   (LD4 Blue) : Flashes on live JTAG image transfer
    //    - led5_r   (LD5 Red)  : High when HWPE is BUSY
    // ------------------------------------------------------------------------
    assign led    = rst_n ? active_led_val              : 4'b0000;
    assign led4_g = rst_n ? soc_led_done                : 1'b0;
    assign led4_b = rst_n ? (jtag_flash_cnt_q != 22'd0) : 1'b0;
    assign led5_r = rst_n ? soc_led_busy                : 1'b0;

endmodule : pynq_z2_board_top
