# ==============================================================================
# File: constrs_pynq_z2.xdc
# Project: Mini-PULP Edge AI SoC (CONQUEROR-1) on TUL PYNQ-Z2
# Target Part: AMD Xilinx Zynq-7000 xc7z020clg400-1
# Author: Nguyen Van Thuc (24161421)
# ==============================================================================

# 1. 125 MHz System Clock Input (Pin H16 on TUL PYNQ-Z2)
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { sysclk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { sysclk }];

# 2. Slide Switch Reset Input (SW0 - Pin M20, Active-Low Reset: 0 = Reset, 1 = Run)
set_property -dict { PACKAGE_PIN M20   IOSTANDARD LVCMOS33 } [get_ports { rst_n }];

# 3. 4-Bit Binary Predicted Digit Output on User LEDs LD0..LD3
#    led[0] = LD0 (LSB, 2^0), led[1] = LD1 (2^1), led[2] = LD2 (2^2), led[3] = LD3 (MSB, 2^3)
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

# 4. Status RGB LEDs (LD4 Green = Done, LD4 Blue = JTAG Transfer, LD5 Red = Busy)
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { led4_g }];
set_property -dict { PACKAGE_PIN L15   IOSTANDARD LVCMOS33 } [get_ports { led4_b }];
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { led5_r }];

# 5. Debug UART TX Output (PMODA Pin 1 - Y18)
set_property -dict { PACKAGE_PIN Y18   IOSTANDARD LVCMOS33 } [get_ports { uart_txd_o }];

# 6. Asynchronous CDC False Paths between JTAG TCK and System Clock
set_false_path -from [get_cells -hierarchical -filter {NAME =~ *cmd_toggle_tck*}] -to [get_cells -hierarchical -filter {NAME =~ *cmd_tgl_sync_q*}]
set_false_path -from [get_cells -hierarchical -filter {NAME =~ *cmd_word_tck*}]   -to [get_cells -hierarchical -filter {NAME =~ *cmd_word_sync_q*}]
set_false_path -to   [get_cells -hierarchical -filter {NAME =~ *_tck_q0*}]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
