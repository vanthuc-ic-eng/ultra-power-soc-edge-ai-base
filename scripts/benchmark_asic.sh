#!/usr/bin/env bash
# ==============================================================================
# UNIVERSAL ASIC SYNTHESIS & STA/POWER BENCHMARK SUITE (Yosys + OpenSTA + Nangate 45nm)
# Project: PULP-inspired Edge AI SoC for Handwritten Digit Recognition
# Author: Nguyen Van Thuc (24161421)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJ_DIR}"

REPORT_DIR="${PROJ_DIR}/reports/asic"
BUILD_DIR="${PROJ_DIR}/build/asic"
LIB="${PROJ_DIR}/lib/nangate45/normal.lib"

mkdir -p "${REPORT_DIR}" "${BUILD_DIR}"

if [ ! -f "${LIB}" ]; then
    echo "ERROR: Nangate 45nm library not found at ${LIB}" >&2
    exit 1
fi

echo "=================================================================="
echo ">>> RUNNING FULL ASIC BENCHMARK SUITE (Nangate 45nm)"
echo ">>> Toolchain: Yosys 0.33 + OpenSTA"
echo ">>> Output Reports: ${REPORT_DIR}"
echo "=================================================================="

# Modules to profile in ASIC:
if grep -q "lutalm_core_mul_s8" "${PROJ_DIR}/rtl/core/pe_mac.sv"; then
    CORE_MUL="lutalm_core_mul_s8"
else
    CORE_MUL="exact_mul_s8"
fi
MODULES=("${CORE_MUL}" "pe_mac" "compute_engine_1x4" "riscv_core_rv32i")

for MOD in "${MODULES[@]}"; do
    echo "------------------------------------------------------------------"
    echo ">>> [ASIC SYNTH] Profiling Module: ${MOD}..."
    YS_SCRIPT="${BUILD_DIR}/synth_${MOD}.ys"
    NETLIST="${BUILD_DIR}/netlist_${MOD}.v"
    
    cat << EOF > "${YS_SCRIPT}"
read_verilog -sv ${PROJ_DIR}/rtl/pkg/pulp_hwpe_pkg.sv
$(for f in ${PROJ_DIR}/rtl/core/*.sv; do echo "read_verilog -sv $f"; done)
read_verilog -sv ${PROJ_DIR}/rtl/soc/riscv_core_rv32i.sv

hierarchy -check -top ${MOD}
synth -top ${MOD} -flatten
opt -purge
dfflibmap -liberty ${LIB}
abc -liberty ${LIB}
clean
tee -o ${REPORT_DIR}/asic_stat_${MOD}.rpt stat -liberty ${LIB}
write_verilog -noattr -noexpr ${NETLIST}
EOF

    yosys -s "${YS_SCRIPT}" > "${REPORT_DIR}/yosys_synth_${MOD}.log" 2>&1
    
    CELLS=$(grep "Number of cells:" "${REPORT_DIR}/asic_stat_${MOD}.rpt" | awk '{print $NF}')
    AREA=$(grep "Chip area for module" "${REPORT_DIR}/asic_stat_${MOD}.rpt" | awk '{print $NF}')
    echo "    [PASS] Cells: ${CELLS} | Area: ${AREA} um^2"

    # Static Timing Analysis (STA) at 200 MHz (5.0 ns period)
    STA_SCRIPT="${BUILD_DIR}/sta_${MOD}.tcl"
    cat << STA_EOF > "${STA_SCRIPT}"
read_liberty ${LIB}
read_verilog ${NETLIST}
link_design ${MOD}
create_clock -name clk -period 5.0 [get_ports clk]
set_input_delay -clock clk 0.0 [all_inputs]
set_output_delay -clock clk 0.0 [all_outputs]
report_checks -path_delay max -format full > ${REPORT_DIR}/asic_timing_${MOD}.rpt
report_power > ${REPORT_DIR}/asic_power_${MOD}.rpt
exit
STA_EOF

    sta "${STA_SCRIPT}" > "${REPORT_DIR}/opensta_${MOD}.log" 2>&1

    DELAY=$(grep -E "\s+[0-9\.]+\s+data arrival time" "${REPORT_DIR}/asic_timing_${MOD}.rpt" | head -n 1 | awk '{print $1}')
    TOTAL_PWR=$(grep -E "^Total\s+" "${REPORT_DIR}/asic_power_${MOD}.rpt" | awk '{printf "%.2f", $5 * 1000000}')
    DYN_PWR=$(grep -E "^Total\s+" "${REPORT_DIR}/asic_power_${MOD}.rpt" | awk '{printf "%.2f", ($2 + $3) * 1000000}')
    LEAK_PWR=$(grep -E "^Total\s+" "${REPORT_DIR}/asic_power_${MOD}.rpt" | awk '{printf "%.2f", $4 * 1000000}')
    echo "    [PASS] Critical Path Delay: ${DELAY} ns | P_dyn: ${DYN_PWR} uW | P_leak: ${LEAK_PWR} uW | P_total: ${TOTAL_PWR} uW"
done

echo "=================================================================="
echo ">>> ASIC BENCHMARK COMPLETED SUCCESSFULLY!"
echo ">>> Reports generated in: ${REPORT_DIR}"
echo "=================================================================="
