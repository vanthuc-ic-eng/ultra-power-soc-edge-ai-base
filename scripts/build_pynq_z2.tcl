# ==============================================================================
# Script: build_pynq_z2.tcl
# Project: Mini-PULP Edge AI SoC (CONQUEROR-1) on TUL PYNQ-Z2 (xc7z020clg400-1)
# Author: Nguyen Van Thuc (24161421)
# Description:
#   Full Physical Synthesis, Place & Route, Reports, and Bitstream Generation
#   for TUL PYNQ-Z2 featuring the Real-Time BSCANE2 JTAG Streaming Bridge
#   and 4-Bit Binary Digit Display on LD3..LD0.
# ==============================================================================

set_param general.maxThreads 4

set proj_dir "/workspace/projects/pulp_edge_ai_soc"
set rpt_dir  "$proj_dir/reports/pynq_z2"
set bit_dir  "$proj_dir/build/bitstream_pynq_z2"
file mkdir $rpt_dir
file mkdir $bit_dir

create_project -in_memory -part xc7z020clg400-1

# Read SystemVerilog files
read_verilog -sv $proj_dir/rtl/pkg/pulp_hwpe_pkg.sv
read_verilog -sv [glob $proj_dir/rtl/core/*.sv]
read_verilog -sv [glob $proj_dir/rtl/memory/*.sv]
read_verilog -sv [glob $proj_dir/rtl/controller/*.sv]
read_verilog -sv [glob $proj_dir/rtl/top/*.sv]
read_verilog -sv [glob $proj_dir/rtl/soc/*.sv]

# Read TUL PYNQ-Z2 Physical Constraints
read_xdc $proj_dir/synth/constrs_pynq_z2.xdc

puts "\n==> \[STEP 1/5\] Running Synthesis for TUL PYNQ-Z2 (xc7z020clg400-1)..."
synth_design -top pynq_z2_board_top -part xc7z020clg400-1

puts "\n==> \[STEP 2/5\] Running Logic Optimization..."
opt_design

puts "\n==> \[STEP 3/5\] Running Placement..."
place_design

puts "\n==> \[STEP 4/5\] Running Routing..."
route_design

# Generate Physical Implementation Reports
report_utilization -file "$rpt_dir/pnr_util.rpt"
report_utilization -hierarchical -file "$rpt_dir/pnr_util_hierarchical.rpt"
report_timing_summary -delay_type min_max -max_paths 5 -file "$rpt_dir/pnr_timing_100mhz.rpt"
report_power -file "$rpt_dir/pnr_power_100mhz.rpt"

puts "\n==> \[STEP 5/5\] Generating PYNQ-Z2 Bitstream (.bit)..."
write_bitstream -force "$bit_dir/conqueror1_pynq_z2.bit"

puts "\n>>> PYNQ-Z2 BUILD & REPORTS SUCCEEDED!"
exit
