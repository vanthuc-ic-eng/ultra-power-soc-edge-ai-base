# ==============================================================================
# Script: build_bitstream.tcl
# Project: Mini-PULP Edge AI SoC (Zynq-7000 xc7z010clg400-1)
# Author: Nguyen Van Thuc (24161421)
# Description:
#   Full implementation and Bitstream Generation (.bit) for Zybo Z7.
# ==============================================================================

set_param general.maxThreads 4

set proj_dir "/workspace/projects/pulp_edge_ai_soc"
set bit_dir  "$proj_dir/build/bitstream"
file mkdir $bit_dir

create_project -in_memory -part xc7z010clg400-1

# Read SystemVerilog files
read_verilog -sv $proj_dir/rtl/pkg/pulp_hwpe_pkg.sv
read_verilog -sv [glob $proj_dir/rtl/core/*.sv]
read_verilog -sv [glob $proj_dir/rtl/memory/*.sv]
read_verilog -sv [glob $proj_dir/rtl/controller/*.sv]
read_verilog -sv [glob $proj_dir/rtl/top/*.sv]
read_verilog -sv [glob $proj_dir/rtl/soc/*.sv]

# Read Zybo Z7 Physical Constraints
read_xdc $proj_dir/synth/constrs_zybo_z7.xdc

# 1. Synthesis
puts "\n==> \[STEP 1/5\] Running Synthesis for Bitstream..."
synth_design -top pulp_riscv_ai_soc_top -part xc7z010clg400-1

# 2. Logic Optimization
puts "\n==> \[STEP 2/5\] Running Logic Optimization..."
opt_design

# 3. Placement
puts "\n==> \[STEP 3/5\] Running Placement..."
place_design

# 4. Routing
puts "\n==> \[STEP 4/5\] Running Routing..."
route_design

# 5. Write Bitstream
puts "\n==> \[STEP 5/5\] Generating FPGA Bitstream (.bit)..."
write_bitstream -force "$bit_dir/pulp_riscv_ai_soc.bit"

puts "\n=================================================================="
puts ">>> BITSTREAM GENERATION SUCCEEDED!"
puts ">>> Bitstream File: $bit_dir/pulp_riscv_ai_soc.bit"
puts "=================================================================="
exit
