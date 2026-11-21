# ==============================================================================
# PHYSICAL PIN CONSTRAINTS FOR DIGILENT ZYBO Z7 (AMD Zynq-7000 xc7z010clg400-1)
# Project: Mini-PULP Edge AI SoC (RISC-V + Zero-DSP Log8 HWPE Accelerator)
# Author: Nguyen Van Thuc (24161421)
# Description:
#   Full board pin mapping for bitstream generation and on-board deployment.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. System Clock (125 MHz Oscillator on Zybo Z7)
# ------------------------------------------------------------------------------
# Pin K17 is the 125 MHz system clock on Zybo Z7-10 (L16 on Zybo Classic)
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports { clk }];

# ------------------------------------------------------------------------------
# 2. Reset Button (Push Button 0 - Active-Low Reset)
# ------------------------------------------------------------------------------
# Press BTN0 (K18 / R18) to trigger asynchronous system reset
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { rst_n }];

# ------------------------------------------------------------------------------
# 3. UART Serial Output (TXD to PC Terminal via FTDI USB-UART)
# ------------------------------------------------------------------------------
# Zybo Z7 routes USB-UART via Pmod / FT2232HQ. 
# Pin W15 on Pmod JC1 (or T14 on JD1) can be jumpered or directly connected to USB-UART RX.
# Default mapped to standard high-speed Pmod pin W15 (JC1_N) and JA1 (N15)
set_property -dict { PACKAGE_PIN W15   IOSTANDARD LVCMOS33 } [get_ports { uart_txd_o }];

# ------------------------------------------------------------------------------
# 4. On-Board Status & Prediction LEDs
# ------------------------------------------------------------------------------
# LD0..LD3: Displays the 4-bit Predicted Digit (0 to 9) in Binary
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led_pred_o[0] }];
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { led_pred_o[1] }];
set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports { led_pred_o[2] }];
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { led_pred_o[3] }];

# External / Pmod Status LEDs for HWPE Core
# led_busy_o: Pmod JE1 (V12) - High when HWPE accelerator is computing
# led_done_o: Pmod JE2 (W16) - Pulses high when AI inference finishes
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { led_busy_o }];
set_property -dict { PACKAGE_PIN W16   IOSTANDARD LVCMOS33 } [get_ports { led_done_o }];

# ------------------------------------------------------------------------------
# 5. Bitstream Configuration Settings
# ------------------------------------------------------------------------------
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
