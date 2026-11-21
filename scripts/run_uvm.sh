#!/usr/bin/env bash
# ==============================================================================
# Script: run_uvm_test.sh
# Project: PULP-inspired Edge AI SoC Verification
# Description: Compiles and runs the Pure UVM 1.2 Verification Suite in Vivado Xsim
# ==============================================================================
set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PROJ_DIR=$(dirname "$SCRIPT_DIR")
DV_DIR="$PROJ_DIR/dv/uvm"
WORK_DIR="$PROJ_DIR/build/uvm_work"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "====================================================================================="
echo "   COMPILING PURE UVM 1.2 VERIFICATION ENVIRONMENT (IEEE 1800.2 / VIVADO XSIM)"
echo "====================================================================================="

# 1. Compile RTL Core + UVM Testbench
xvlog -sv -L uvm \
  -i "$DV_DIR" \
  -i "$PROJ_DIR/rtl/core" \
  "$PROJ_DIR/rtl/core"/*.sv \
  "$DV_DIR/tb_uvm_top.sv"

# 2. Elaborate
xelab tb_uvm_top -L uvm -s uvm_sim --timescale 1ns/1ps

# 3. Simulate and Run Full Exhaustive Test
echo "====================================================================================="
echo "   EXECUTING UVM EXHAUSTIVE REGRESSION TEST (CORNER + RANDOM + 65,536 FULL SWEEP)"
echo "====================================================================================="
xsim uvm_sim -R
