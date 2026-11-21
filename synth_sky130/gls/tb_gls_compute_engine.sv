`timescale 1ns / 1ps
`define FUNCTIONAL
`define UNIT_DELAY #1

module tb_gls_compute_engine;
    reg         clk = 0;
    reg         rst_n = 0;
    reg         valid_i = 0;
    reg         clr_i = 0;
    reg  [7:0]  act_i = 0;
    reg  [31:0] weights_i = 0;
    reg  [127:0] biases_i = 0;
    wire [127:0] acc_gls;

    always #10 clk = ~clk;

    compute_engine_1x4 u_dut_gls (
        .clk(clk),
        .rst_n(rst_n),
        .valid_i(valid_i),
        .clr_i(clr_i),
        .act_i(act_i),
        .weights_i(weights_i),
        .biases_i(biases_i),
        .acc_o(acc_gls)
    );

    integer i;
    initial begin
        rst_n = 0;
        #45;
        rst_n = 1;
        @(posedge clk);
        clr_i <= 1'b1;
        biases_i <= {32'sd100, -32'sd200, 32'sd50, 32'sd0};
        @(posedge clk);
        clr_i <= 1'b0;
        for (i = 0; i < 64; i = i + 1) begin
            valid_i   <= 1'b1;
            act_i     <= ((i * 19 + 7) & 8'h7F);
            weights_i <= {8'h34 ^ i[7:0], 8'hB2 ^ i[7:0], 8'h28 ^ i[7:0], 8'h7F};
            @(posedge clk);
        end
        valid_i <= 1'b0;
        @(posedge clk);
        @(posedge clk);
        #5;
        $display("GLS_ACC0=%0d GLS_ACC1=%0d GLS_ACC2=%0d GLS_ACC3=%0d",
                 $signed(acc_gls[31:0]), $signed(acc_gls[63:32]),
                 $signed(acc_gls[95:64]), $signed(acc_gls[127:96]));
        $finish;
    end
endmodule
