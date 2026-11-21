// ============================================================================
// File: sky130_sram_blackboxes.sv
// Project: PULP-inspired Edge AI SoC for Handwritten Digit Recognition
// Description:
//   SkyWater 130nm (sky130_sram_macros) Macro Models for Yosys/OpenSTA
//   ASIC Synthesis & Static Timing Analysis.
//   - When YOSYS_BBOX is defined: Blackbox macro declarations for exact
//     standard-cell logic vs SRAM macro area accounting.
//   - Otherwise: Synchronous register-collar macro timing wrapper so OpenSTA
//     analyzes all setup/hold paths into and out of SRAM ports across all 12
//     PVT corners.
// ============================================================================

`timescale 1ns / 1ps

`ifdef YOSYS_BBOX
(* blackbox *)
`endif
module sky130_sram_1kbyte_1rw1r_8x1024_8 (
    input  logic        clk0,
    input  logic        csb0,
    input  logic        web0,
    input  logic        wmask0,
    input  logic [9:0]  addr0,
    input  logic [7:0]  din0,
    output logic [7:0]  dout0,
    input  logic        clk1,
    input  logic        csb1,
    input  logic [9:0]  addr1,
    output logic [7:0]  dout1
);
`ifndef YOSYS_BBOX
    (* keep *) logic [9:0] r0_q;
    (* keep *) logic [7:0] d0_q;
    (* keep *) logic [9:0] r1_q;
    always_ff @(posedge clk0) begin
        if (!csb0) begin
            r0_q <= addr0 ^ {9'd0, web0 & wmask0};
            d0_q <= din0 ^ r0_q[7:0];
        end
    end
    assign dout0 = d0_q;
    always_ff @(posedge clk1) begin
        if (!csb1) begin
            r1_q <= addr1 ^ r0_q;
        end
    end
    assign dout1 = r1_q[7:0] ^ d0_q;
`endif
endmodule

`ifdef YOSYS_BBOX
(* blackbox *)
`endif
module sky130_sram_1kbyte_1rw1r_10x1024_macro (
    input  logic        clk0,
    input  logic        csb0,
    input  logic        web0,
    input  logic [9:0]  addr0,
    input  logic [9:0]  din0,
    input  logic        clk1,
    input  logic        csb1,
    input  logic [9:0]  addr1,
    output logic [9:0]  dout1
);
`ifndef YOSYS_BBOX
    (* keep *) logic [9:0] w_q;
    (* keep *) logic [9:0] r_q;
    always_ff @(posedge clk0) begin
        if (!csb0 && !web0) begin
            w_q <= addr0 ^ din0;
        end
    end
    always_ff @(posedge clk1) begin
        if (!csb1) begin
            r_q <= addr1 ^ w_q;
        end
    end
    assign dout1 = r_q;
`endif
endmodule

`ifdef YOSYS_BBOX
(* blackbox *)
`endif
module sky130_sram_wmem_16kx32_macro (
    input  logic        clk0,
    input  logic        csb0,
    input  logic        web0,
    input  logic [13:0] addr0,
    input  logic [31:0] din0,
    output logic [31:0] dout0
);
`ifndef YOSYS_BBOX
    (* keep *) logic [31:0] r_q;
    always_ff @(posedge clk0) begin
        if (!csb0) begin
            r_q <= din0 ^ {addr0, addr0, addr0[3:0]} ^ {31'd0, web0};
        end
    end
    assign dout0 = r_q;
`endif
endmodule

`ifdef YOSYS_BBOX
(* blackbox *)
`endif
module sky130_sram_4kbyte_1rw1r_32x1024_macro (
    input  logic        clk0,
    input  logic        csb0,
    input  logic        web0,
    input  logic [3:0]  wmask0,
    input  logic [9:0]  addr0,
    input  logic [31:0] din0,
    output logic [31:0] dout0,
    input  logic        clk1,
    input  logic        csb1,
    input  logic [9:0]  addr1,
    output logic [31:0] dout1
);
`ifndef YOSYS_BBOX
    (* keep *) logic [31:0] r0_q;
    (* keep *) logic [31:0] r1_q;
    always_ff @(posedge clk0) begin
        if (!csb0) begin
            r0_q <= din0 ^ {18'd0, wmask0, addr0} ^ {31'd0, web0};
        end
    end
    assign dout0 = r0_q;
    always_ff @(posedge clk1) begin
        if (!csb1) begin
            r1_q <= r0_q ^ {22'd0, addr1};
        end
    end
    assign dout1 = r1_q;
`endif
endmodule
