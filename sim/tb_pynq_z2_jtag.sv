// ============================================================================
// File: tb_pynq_z2_jtag.sv
// Description: Cycle-Accurate Verification of PYNQ-Z2 BSCANE2 JTAG Bridge
//              & 4-Bit Binary LED Output (LD3..LD0)
// ============================================================================
`timescale 1ns / 1ps

module tb_pynq_z2_jtag;

    logic       sysclk = 1'b0;
    logic       rst_n  = 1'b0; // Active-low reset on PYNQ-Z2 Slide Switch SW0 (M20)
    logic [3:0] led;
    logic       led4_g, led4_b, led5_r, uart_txd_o;

    // 100 MHz system clock (10 ns period)
    always #5.0 sysclk = ~sysclk;

    pynq_z2_board_top u_dut (
        .sysclk     (sysclk),
        .rst_n      (rst_n),
        .led        (led),
        .led4_g     (led4_g),
        .led4_b     (led4_b),
        .led5_r     (led5_r),
        .uart_txd_o (uart_txd_o)
    );

    // Helper task: JTAG shift 32-bit word LSB-first on USER4 (15 MHz TCK -> 66 ns period)
    task automatic jtag_shift_word(input logic [31:0] tdi_word, output logic [31:0] tdo_word);
        u_dut.bscan_sel = 1'b1;
        // 1. CAPTURE-DR state
        u_dut.bscan_capture = 1'b1;
        u_dut.bscan_shift   = 1'b0;
        #33 u_dut.bscan_tck = 1'b1;
        #33 u_dut.bscan_tck = 1'b0;
        u_dut.bscan_capture = 1'b0;

        // 2. SHIFT-DR state (32 bits, LSB first)
        u_dut.bscan_shift = 1'b1;
        for (int i = 0; i < 32; i++) begin
            u_dut.bscan_tdi = tdi_word[i];
            tdo_word[i]     = u_dut.bscan_tdo;
            #33 u_dut.bscan_tck = 1'b1;
            #33 u_dut.bscan_tck = 1'b0;
        end
        u_dut.bscan_shift = 1'b0;

        // 3. UPDATE-DR & IDLE
        u_dut.bscan_update = 1'b1;
        #33 u_dut.bscan_tck = 1'b1;
        #33 u_dut.bscan_tck = 1'b0;
        u_dut.bscan_update = 1'b0;
    endtask

    logic [7:0] img_mem [0:783];
    logic [31:0] rx_status;
    int idx0, idx1, idx2;
    logic [6:0] p0, p1, p2;
    logic [31:0] word32;

    initial begin : main_tb

        $display("=========================================================================");
        $display("   VERIFYING PYNQ-Z2 BSCANE2 JTAG STREAMING BRIDGE & 4-BIT LED DISPLAY");
        $display("=========================================================================");

        // Pull SW0 (rst_n) high to 1 to release reset and run SoC
        #100;
        rst_n = 1'b1;
        #200;

        // Test Digit 7 via JTAG packed 3-pixel burst
        $readmemh("/workspace/projects/pulp_edge_ai_soc/sw/data/test_image_digit7.hex", img_mem);

        for (int w = 0; w < 262; w++) begin
            idx0 = w * 3;
            idx1 = w * 3 + 1;
            idx2 = w * 3 + 2;
            p0 = img_mem[idx0][6:0];
            p1 = (idx1 < 784) ? img_mem[idx1][6:0] : 7'd0;
            p2 = (idx2 < 784) ? img_mem[idx2][6:0] : 7'd0;
            word32 = {2'b01, 9'(w), p0, p1, p2};
            jtag_shift_word(word32, rx_status);
        end

        // Send Start Command (2'b11, bit 0 = 1)
        jtag_shift_word(32'hC000_0001, rx_status);

        // Wait 60 us (simulating JTAG sequence delay 100 us)
        #60000;

        // Readback Status Word
        jtag_shift_word(32'h0000_0000, rx_status);

        $display("[JTAG-TB] Readback Raw Word = 0x%08x", rx_status);
        $display("[JTAG-TB] Magic Header      = 0x%1x (Expected 0xA)", rx_status[31:28]);
        $display("[JTAG-TB] Done Flag         = %0d", rx_status[27]);
        $display("[JTAG-TB] JTAG Pred Digit   = %0d", rx_status[25:22]);
        $display("[JTAG-TB] Physical LED[3:0] = 4'b%04b (Decimal %0d)", led, led);
        $display("[JTAG-TB] Hardware Cycles   = %0d", rx_status[21:0]);

        if (rx_status[31:28] == 4'hA && led == 4'd7 && rx_status[25:22] == 4'd7) begin
            $display(">>> [PASS 1/2] PACKED JTAG STREAM + 4-BIT LED (LD3..LD0 = 0111 = 7) VERIFIED!");
        end else begin
            $display(">>> [FAIL] Mismatch detected!");
            $finish(1);
        end

        // Test 2: Single Continuous 8416-bit SHIFT-DR Burst (Digit 4 -> LED = 0100)
        $readmemh("/workspace/projects/pulp_edge_ai_soc/sw/data/test_image_digit4.hex", img_mem);
        u_dut.bscan_sel     = 1'b1;
        u_dut.bscan_capture = 1'b1;
        u_dut.bscan_shift   = 1'b0;
        #33 u_dut.bscan_tck = 1'b1;
        #33 u_dut.bscan_tck = 1'b0;
        u_dut.bscan_capture = 1'b0;
        u_dut.bscan_shift   = 1'b1;

        for (int w = 0; w < 263; w++) begin
            if (w < 262) begin
                idx0 = w * 3;
                idx1 = w * 3 + 1;
                idx2 = w * 3 + 2;
                p0 = img_mem[idx0][6:0];
                p1 = (idx1 < 784) ? img_mem[idx1][6:0] : 7'd0;
                p2 = (idx2 < 784) ? img_mem[idx2][6:0] : 7'd0;
                word32 = {2'b01, 9'(w), p0, p1, p2};
            end else begin
                word32 = 32'hC000_0001; // Start command at word 262
            end
            for (int b = 0; b < 32; b++) begin
                u_dut.bscan_tdi = word32[b];
                #33 u_dut.bscan_tck = 1'b1;
                #33 u_dut.bscan_tck = 1'b0;
            end
        end
        u_dut.bscan_shift  = 1'b0;
        u_dut.bscan_update = 1'b1;
        #33 u_dut.bscan_tck = 1'b1;
        #33 u_dut.bscan_tck = 1'b0;
        u_dut.bscan_update = 1'b0;

        #60000;
        jtag_shift_word(32'h0000_0000, rx_status);
        $display("[JTAG-TB] Burst-8416 Readback = 0x%08x | LED[3:0] = 4'b%04b (%0d) | Cycles = %0d",
                 rx_status, led, led, rx_status[21:0]);
        if (rx_status[31:28] == 4'hA && led == 4'd4 && rx_status[25:22] == 4'd4) begin
            $display(">>> [PASS 2/2] SINGLE-SHOT 8416-BIT CONTINUOUS JTAG STREAM (LD3..LD0 = 0100 = 4) VERIFIED!");
        end else begin
            $display(">>> [FAIL] Continuous stream mismatch!");
            $finish(1);
        end
        $finish;
    end

endmodule
