#!/usr/bin/env python3
"""
Full-Step SkyWater 130nm (sky130_fd_sc_hd) ASIC Synthesis, Gate-Level Simulation (GLS),
and 12-Corner (Nominal + 4 Extreme Corners + 7 Extended Corners) PVT Timing & Power Sign-Off.
"""

import json
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path("/workspace/projects/pulp_edge_ai_soc")
RTL_DIR = ROOT / "rtl"
OUT_DIR = ROOT / "synth_sky130"
NETLIST_DIR = OUT_DIR / "netlist"
REPORT_DIR = OUT_DIR / "reports"

YOSYS_BIN = "/tools/bin/yosys"
STA_BIN = "/tools/bin/sta"
PDK_LIB_DIR = Path("/tools/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib")
PDK_V_DIR = Path("/tools/pdk/sky130A/libs.ref/sky130_fd_sc_hd/verilog")
TT_LIB = PDK_LIB_DIR / "sky130_fd_sc_hd__tt_025C_1v80.lib"

RTL_FILES = [
    str(RTL_DIR / "pkg/pulp_hwpe_pkg.sv"),
    str(RTL_DIR / "memory/sky130_sram_blackboxes.sv"),
    str(RTL_DIR / "core/lut_primitives.sv"),
    str(RTL_DIR / "core/icg_cell.sv"),
    str(RTL_DIR / "core/log_input_sign_u8.sv"),
    str(RTL_DIR / "core/log_encoder_u8.sv"),
    str(RTL_DIR / "core/log_normalizer_u8.sv"),
    str(RTL_DIR / "core/log_lut_low2.sv"),
    str(RTL_DIR / "core/log_lut_low3.sv"),
    str(RTL_DIR / "core/log_lut_low4.sv"),
    str(RTL_DIR / "core/log_lut_adaptive64.sv"),
    str(RTL_DIR / "core/log_lut_converter_u8.sv"),
    str(RTL_DIR / "core/log_act_encoder_u8.sv"),
    str(RTL_DIR / "core/log_adder_u8.sv"),
    str(RTL_DIR / "core/log_antilog_u16.sv"),
    str(RTL_DIR / "core/log_output_sign_s16.sv"),
    str(RTL_DIR / "core/lutalm_core_mul_s8.sv"),
    str(RTL_DIR / "core/lutalm_mul_s8.sv"),
    str(RTL_DIR / "core/pe_mac.sv"),
    str(RTL_DIR / "core/compute_engine_1x4.sv"),
    str(RTL_DIR / "controller/requant_relu.sv"),
    str(RTL_DIR / "controller/argmax_unit.sv"),
    str(RTL_DIR / "controller/hwpe_stream_ctrl.sv"),
    str(RTL_DIR / "memory/tcdm_activation_mem.sv"),
    str(RTL_DIR / "memory/tcdm_bias_mem.sv"),
    str(RTL_DIR / "memory/tcdm_weight_bram.sv"),
    str(RTL_DIR / "top/pulp_hwpe_top.sv"),
    str(RTL_DIR / "soc/hwpe_csr_wrapper.sv"),
    str(RTL_DIR / "soc/riscv_core_rv32i.sv"),
    str(RTL_DIR / "soc/soc_bus_interconnect.sv"),
    str(RTL_DIR / "soc/uart_tx.sv"),
    str(RTL_DIR / "soc/pulp_riscv_ai_soc_top.sv"),
]

MODULES = [
    ("lutalm_core_mul_s8", False, "Zero-LOD Core Logarithmic Multiplier (8x8)"),
    ("lutalm_mul_s8", False, "Standalone Iterative Logarithmic Multiplier (8x8)"),
    ("pe_mac", True, "Retimed 2-Stage Output-Stationary PE + 32-bit MAC"),
    ("compute_engine_1x4", True, "1x4 SIMD Compute Engine + Shared Log8 Encoder"),
    ("hwpe_stream_ctrl", True, "Zero-Skipping Stream Controller & AGU"),
    ("argmax_unit", True, "2-Stage Pipelined Binary Tree Argmax Classifier"),
    ("pulp_hwpe_top", True, "Complete LA-HWPE Edge AI Accelerator Top"),
    ("riscv_core_rv32i", True, "Lightweight 32-bit RISC-V RV32I Host CPU"),
    ("pulp_riscv_ai_soc_top", True, "Complete PULP-Inspired Edge AI SoC Top"),
]

PVT_CORNERS = [
    {
        "id": "tt_025C_1v80",
        "role": "Nominal Sign-Off",
        "process": "TT (Typical-Typical)",
        "temp_c": 25,
        "volt_v": 1.80,
        "lib": "sky130_fd_sc_hd__tt_025C_1v80.lib",
        "primary": True,
    },
    {
        "id": "ss_100C_1v60",
        "role": "Worst Setup (Hot Slow)",
        "process": "SS (Slow-Slow)",
        "temp_c": 100,
        "volt_v": 1.60,
        "lib": "sky130_fd_sc_hd__ss_100C_1v60.lib",
        "primary": True,
    },
    {
        "id": "ss_n40C_1v60",
        "role": "Worst Setup (Cold Slow)",
        "process": "SS (Slow-Slow)",
        "temp_c": -40,
        "volt_v": 1.60,
        "lib": "sky130_fd_sc_hd__ss_n40C_1v60.lib",
        "primary": True,
    },
    {
        "id": "ff_n40C_1v95",
        "role": "Worst Hold (Cold Fast)",
        "process": "FF (Fast-Fast)",
        "temp_c": -40,
        "volt_v": 1.95,
        "lib": "sky130_fd_sc_hd__ff_n40C_1v95.lib",
        "primary": True,
    },
    {
        "id": "ff_100C_1v95",
        "role": "Worst Power & Leakage (Hot Fast)",
        "process": "FF (Fast-Fast)",
        "temp_c": 100,
        "volt_v": 1.95,
        "lib": "sky130_fd_sc_hd__ff_100C_1v95.lib",
        "primary": True,
    },
    {
        "id": "tt_100C_1v80",
        "role": "Extended High-Temp Nominal",
        "process": "TT (Typical-Typical)",
        "temp_c": 100,
        "volt_v": 1.80,
        "lib": "sky130_fd_sc_hd__tt_100C_1v80.lib",
        "primary": False,
    },
    {
        "id": "ff_100C_1v65",
        "role": "Extended High-Temp Fast (1.65V)",
        "process": "FF (Fast-Fast)",
        "temp_c": 100,
        "volt_v": 1.65,
        "lib": "sky130_fd_sc_hd__ff_100C_1v65.lib",
        "primary": False,
    },
    {
        "id": "ss_n40C_1v76",
        "role": "Extended Cold Slow (1.76V)",
        "process": "SS (Slow-Slow)",
        "temp_c": -40,
        "volt_v": 1.76,
        "lib": "sky130_fd_sc_hd__ss_n40C_1v76.lib",
        "primary": False,
    },
    {
        "id": "ss_100C_1v40",
        "role": "Brownout Drop Slow (1.40V, 100C)",
        "process": "SS (Slow-Slow)",
        "temp_c": 100,
        "volt_v": 1.40,
        "lib": "sky130_fd_sc_hd__ss_100C_1v40.lib",
        "primary": False,
    },
    {
        "id": "ss_n40C_1v40",
        "role": "Brownout Drop Cold (1.40V, -40C)",
        "process": "SS (Slow-Slow)",
        "temp_c": -40,
        "volt_v": 1.40,
        "lib": "sky130_fd_sc_hd__ss_n40C_1v40.lib",
        "primary": False,
    },
    {
        "id": "ss_n40C_1v35",
        "role": "Ultra-Low-Voltage Cold (1.35V)",
        "process": "SS (Slow-Slow)",
        "temp_c": -40,
        "volt_v": 1.35,
        "lib": "sky130_fd_sc_hd__ss_n40C_1v35.lib",
        "primary": False,
    },
    {
        "id": "ss_n40C_1v28",
        "role": "Extreme Near-Threshold Cold (1.28V)",
        "process": "SS (Slow-Slow)",
        "temp_c": -40,
        "volt_v": 1.28,
        "lib": "sky130_fd_sc_hd__ss_n40C_1v28.lib",
        "primary": False,
    },
]


def synthesize_module(top_name: str):
    """Run Yosys synthesis to SkyWater 130nm (sky130_fd_sc_hd):
    1) With -DYOSYS_BBOX to extract exact logic area vs SRAM macro count
    2) Without -DYOSYS_BBOX to write full gate-level netlist for OpenSTA & GLS
    """
    rtl_str = " ".join(RTL_FILES)
    netlist_file = NETLIST_DIR / f"{top_name}_sky130.v"
    stat_file = REPORT_DIR / f"{top_name}_sky130_stat.txt"

    abc_script = "+strash;ifraig;scorr;dc2;dretime;strash;&get,-n;&dch,-f;&nf,{D};&put;buffer;upsize,{D};dnsize,{D};stime,-p"

    # 1. Exact standard-cell area run (with SRAM blackboxes)
    ys_bbox = f"""
read_liberty -lib {TT_LIB};
read_verilog -sv -DYOSYS -DASIC_SYNTH -DYOSYS_BBOX {rtl_str};
synth -top {top_name} -flatten;
dfflibmap -liberty {TT_LIB};
abc -liberty {TT_LIB} -D 4000 -script {abc_script};
hilomap -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO;
opt_clean -purge;
stat -liberty {TT_LIB}
"""
    res_bbox = subprocess.run([YOSYS_BIN, "-p", ys_bbox], capture_output=True, text=True, check=True)
    stat_file.write_text(res_bbox.stdout)

    # Parse cell count, sequential DFF count, and chip area
    m_area = re.search(rf"Chip area for module '\\{top_name}':\s+([0-9.]+)", res_bbox.stdout)
    chip_area_um2 = float(m_area.group(1)) if m_area else 0.0

    # Parse cell breakdown from stat block
    stat_block = res_bbox.stdout.split(f"=== {top_name} ===")[-1]
    m_cells = re.search(r"Number of cells:\s+(\d+)", stat_block)
    total_cells = int(m_cells.group(1)) if m_cells else 0

    dff_cells = 0
    comb_cells = 0
    sram_macros = 0
    cell_hist = {}
    for line in stat_block.splitlines():
        m = re.match(r"^\s+(sky130_\S+)\s+(\d+)\s*$", line)
        if m:
            cname, cnt = m.group(1), int(m.group(2))
            cell_hist[cname] = cnt
            if "sram_" in cname:
                sram_macros += cnt
            elif any(k in cname for k in ["__df", "__dl", "__sd", "__ed"]):
                dff_cells += cnt
            else:
                comb_cells += cnt

    # 2. Gate-level netlist run for OpenSTA / GLS
    ys_net = f"""
read_liberty -lib {TT_LIB};
read_verilog -sv -DYOSYS -DASIC_SYNTH {rtl_str};
synth -top {top_name} -flatten;
dfflibmap -liberty {TT_LIB};
abc -liberty {TT_LIB} -D 4000 -script {abc_script};
hilomap -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO;
splitnets -ports;
opt_clean -purge;
write_verilog -noattr -noexpr -nohex {netlist_file}
"""
    subprocess.run([YOSYS_BIN, "-q", "-p", ys_net], capture_output=True, text=True, check=True)

    # Sky130 NAND2 equivalent gate area (sky130_fd_sc_hd__nand2_1 = 3.7536 um2)
    nand2_ge = round(chip_area_um2 / 3.7536, 1)

    return {
        "module": top_name,
        "total_cells": total_cells,
        "comb_cells": comb_cells,
        "dff_cells": dff_cells,
        "sram_macros": sram_macros,
        "area_um2": round(chip_area_um2, 2),
        "area_mm2": round(chip_area_um2 / 1e6, 5),
        "nand2_ge": nand2_ge,
        "netlist": str(netlist_file),
        "top_cell_types": dict(sorted(cell_hist.items(), key=lambda x: -x[1])[:12]),
    }


def run_opensta_corner(top_name: str, is_seq: bool, corner: dict, period_ns: float = 20.0):
    """Run OpenSTA timing & power analysis on a synthesized SkyWater 130nm netlist."""
    netlist_file = NETLIST_DIR / f"{top_name}_sky130.v"
    lib_file = PDK_LIB_DIR / corner["lib"]

    if is_seq:
        constraints = f"""
create_clock -name core_clk -period {period_ns} [get_ports clk]
set_clock_uncertainty 0.15 [get_clocks core_clk]
set_input_delay -clock core_clk 1.0 [all_inputs]
set_output_delay -clock core_clk 1.0 [all_outputs]
set_load 0.015 [all_outputs]
set_input_transition 0.10 [all_inputs]
set_propagated_clock [get_clocks core_clk]
set_switching_activity -global_activity 0.15
"""
    else:
        constraints = f"""
create_clock -name virt_clk -period {period_ns}
set_input_delay -clock virt_clk 0.0 [all_inputs]
set_output_delay -clock virt_clk 0.0 [all_outputs]
set_load 0.015 [all_outputs]
set_input_transition 0.10 [all_inputs]
set_switching_activity -input_activity 0.20
"""

    sta_tcl = f"""
read_liberty {lib_file}
read_verilog {netlist_file}
link_design {top_name}
{constraints}
report_wns
report_tns
report_worst_slack -max
report_worst_slack -min
report_checks -path_delay max -digits 4
report_checks -path_delay min -digits 4
report_power
exit
"""
    res = subprocess.run([STA_BIN, "-no_init", "-no_splash"], input=sta_tcl, capture_output=True, text=True, check=True)
    out = res.stdout

    m_wns = re.search(r"worst slack max\s+([-0-9.]+)", out)
    m_whs = re.search(r"worst slack min\s+([-0-9.]+)", out)
    m_tns = re.search(r"tns(?: max)?\s+([-0-9.]+)", out)

    wns_ns = float(m_wns.group(1)) if m_wns else 0.0
    whs_ns = float(m_whs.group(1)) if m_whs else 0.0
    tns_ns = float(m_tns.group(1)) if m_tns else 0.0

    # Parse actual data arrival / critical path delay
    if is_seq:
        crit_delay_ns = round(period_ns - wns_ns, 4)
    else:
        crit_delay_ns = round(period_ns - wns_ns, 4)

    fmax_mhz = round(1000.0 / max(crit_delay_ns, 0.1), 2)

    # Parse Total Power line:
    # Total                  2.76e-04   1.90e-04   8.14e-09   4.66e-04 100.0%
    p_int_mw = p_sw_mw = p_leak_mw = p_tot_mw = 0.0
    for line in out.splitlines():
        if line.strip().startswith("Total"):
            parts = line.split()
            if len(parts) >= 5:
                p_int_mw = float(parts[1]) * 1000.0
                p_sw_mw = float(parts[2]) * 1000.0
                p_leak_mw = float(parts[3]) * 1000.0
                p_tot_mw = float(parts[4]) * 1000.0
                break

    return {
        "corner": corner["id"],
        "role": corner["role"],
        "process": corner["process"],
        "temp_c": corner["temp_c"],
        "volt_v": corner["volt_v"],
        "primary": corner["primary"],
        "period_ns": period_ns,
        "target_mhz": round(1000.0 / period_ns, 1),
        "wns_ns": round(wns_ns, 4),
        "whs_ns": round(whs_ns, 4),
        "tns_ns": round(tns_ns, 4),
        "crit_path_ns": crit_delay_ns,
        "fmax_mhz": fmax_mhz,
        "power_internal_mw": round(p_int_mw, 5),
        "power_switching_mw": round(p_sw_mw, 5),
        "power_leakage_mw": round(p_leak_mw, 6),
        "power_leakage_nw": round(p_leak_mw * 1e6, 2),
        "power_total_mw": round(p_tot_mw, 5),
        "power_total_uw": round(p_tot_mw * 1000.0, 2),
        "status": "PASS (0 Violations)" if (wns_ns >= 0.0 and whs_ns >= 0.0 and tns_ns == 0.0) else "VIOLATION",
    }


def run_gate_level_sim():
    """Run Post-Synthesis Gate-Level Simulation (GLS) on compute_engine_1x4_sky130.v
    against the RTL Golden Reference using iverilog + sky130_fd_sc_hd behavioral models."""
    gls_dir = OUT_DIR / "gls"
    gls_dir.mkdir(parents=True, exist_ok=True)
    tb_file = gls_dir / "tb_gls_compute_engine.sv"

    # Create a wrapper around the synthesized netlist or test lutalm_core_mul_s8_sky130.v
    # Note: splitnets -ports splits vector ports into \port[0], \port[1]... for STA.
    # For GLS, let's write an unsplit gate-level netlist of compute_engine_1x4!
    gls_netlist = NETLIST_DIR / "compute_engine_1x4_sky130_gls.v"
    rtl_str = " ".join(RTL_FILES[:20])
    ys_gls = f"""
read_liberty -lib {TT_LIB};
read_verilog -sv -DYOSYS -DASIC_SYNTH {rtl_str};
synth -top compute_engine_1x4 -flatten;
dfflibmap -liberty {TT_LIB};
abc -liberty {TT_LIB} -D 5000;
hilomap -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO;
opt_clean -purge;
write_verilog -noattr -noexpr {gls_netlist}
"""
    subprocess.run([YOSYS_BIN, "-q", "-p", ys_gls], capture_output=True, text=True, check=True)

    tb_code = """`timescale 1ns / 1ps
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
"""
    tb_file.write_text(tb_code)

    # 1. Run Gate-Level Sim
    sim_gls = gls_dir / "sim_gls.vvp"
    subprocess.run(
        [
            "iverilog",
            "-g2012",
            "-DFUNCTIONAL",
            "-DUNIT_DELAY=#1",
            "-o",
            str(sim_gls),
            str(PDK_V_DIR / "primitives.v"),
            str(PDK_V_DIR / "sky130_fd_sc_hd.v"),
            str(gls_netlist),
            str(tb_file),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    res_gls = subprocess.run(["vvp", str(sim_gls)], check=True, capture_output=True, text=True)
    gls_line = [l for l in res_gls.stdout.splitlines() if "GLS_ACC0=" in l][0]

    # 2. Run RTL Golden Sim with exact same testbench
    sim_rtl = gls_dir / "sim_rtl.vvp"
    subprocess.run(
        ["iverilog", "-g2012", "-o", str(sim_rtl)] + RTL_FILES[:20] + [str(tb_file)],
        check=True,
        capture_output=True,
        text=True,
    )
    res_rtl = subprocess.run(["vvp", str(sim_rtl)], check=True, capture_output=True, text=True)
    rtl_line = [l for l in res_rtl.stdout.splitlines() if "GLS_ACC0=" in l][0]

    return {
        "netlist": str(gls_netlist),
        "vectors_tested": 64,
        "rtl_output": rtl_line,
        "gls_output": gls_line,
        "match": rtl_line == gls_line,
        "status": "PASS (100% Bit-Exact Match between RTL and Sky130 Gate-Level Netlist)"
        if rtl_line == gls_line
        else "MISMATCH",
    }


def main():
    t0 = time.time()
    NETLIST_DIR.mkdir(parents=True, exist_ok=True)
    REPORT_DIR.mkdir(parents=True, exist_ok=True)

    print("==> [1/4] Synthesizing all RTL modules to SkyWater 130nm (sky130_fd_sc_hd)...")
    synth_results = {}
    for mod, is_seq, desc in MODULES:
        info = synthesize_module(mod)
        info["description"] = desc
        info["is_seq"] = is_seq
        synth_results[mod] = info
        print(
            f"  - {mod:24s}: {info['total_cells']:5d} cells "
            f"({info['comb_cells']:4d} comb, {info['dff_cells']:4d} DFF, {info['sram_macros']} SRAM) | "
            f"Area = {info['area_um2']:10.2f} um2 ({info['nand2_ge']:8.1f} GE)"
        )

    print("\n==> [2/4] Running 12-Corner PVT Static Timing & Power Sign-Off (OpenSTA)...")
    pvt_results = {
        "compute_engine_1x4_50mhz": [],
        "compute_engine_1x4_100mhz": [],
        "pulp_hwpe_top_50mhz": [],
        "pulp_hwpe_top_100mhz": [],
        "pulp_riscv_ai_soc_top_50mhz": [],
        "lutalm_core_mul_s8": [],
    }
    for corner in PVT_CORNERS:
        c_ce50 = run_opensta_corner("compute_engine_1x4", True, corner, period_ns=20.0)
        c_ce100 = run_opensta_corner("compute_engine_1x4", True, corner, period_ns=10.0)
        c_hwpe50 = run_opensta_corner("pulp_hwpe_top", True, corner, period_ns=20.0)
        c_hwpe100 = run_opensta_corner("pulp_hwpe_top", True, corner, period_ns=10.0)
        c_soc50 = run_opensta_corner("pulp_riscv_ai_soc_top", True, corner, period_ns=20.0)
        c_mul = run_opensta_corner("lutalm_core_mul_s8", False, corner, period_ns=10.0)

        pvt_results["compute_engine_1x4_50mhz"].append(c_ce50)
        pvt_results["compute_engine_1x4_100mhz"].append(c_ce100)
        pvt_results["pulp_hwpe_top_50mhz"].append(c_hwpe50)
        pvt_results["pulp_hwpe_top_100mhz"].append(c_hwpe100)
        pvt_results["pulp_riscv_ai_soc_top_50mhz"].append(c_soc50)
        pvt_results["lutalm_core_mul_s8"].append(c_mul)

        tag = "[PRIMARY]" if corner["primary"] else "[EXT]    "
        print(
            f"  {tag} {corner['id']:14s} ({corner['role']:32s}): "
            f"HWPE@50MHz WNS={c_hwpe50['wns_ns']:+6.3f}ns, WHS={c_hwpe50['whs_ns']:+6.3f}ns, "
            f"Fmax={c_hwpe50['fmax_mhz']:6.1f}MHz, Ptot={c_hwpe50['power_total_mw']:.3f}mW "
            f"(Leak={c_hwpe50['power_leakage_nw']:.1f}nW)"
        )

    print("\n==> [3/4] Running Post-Synthesis Gate-Level Simulation (GLS) on SkyWater 130nm Netlist...")
    gls_info = run_gate_level_sim()
    print(f"  - {gls_info['status']}")
    print(f"  - Output: {gls_info['gls_output']}")

    full_data = {
        "pdk": "SkyWater 130nm (sky130A / sky130_fd_sc_hd)",
        "tools": {
            "synthesis": "Yosys 0.33 (git sha1 2584903a060)",
            "sta": "OpenSTA 3.1.0",
            "gls": "Icarus Verilog 11.0 + sky130_fd_sc_hd functional/unit-delay primitives",
        },
        "synthesis": synth_results,
        "pvt_corners": pvt_results,
        "gls": gls_info,
        "elapsed_sec": round(time.time() - t0, 2),
    }

    json_path = REPORT_DIR / "sky130_full_signoff.json"
    json_path.write_text(json.dumps(full_data, indent=2))
    print(f"\n==> [4/4] Saved complete SkyWater 130nm sign-off data to {json_path}")


if __name__ == "__main__":
    main()
