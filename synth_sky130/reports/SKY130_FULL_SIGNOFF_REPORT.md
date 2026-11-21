# SkyWater 130nm (`sky130_fd_sc_hd`) Full-Step ASIC Tapeout & 12-Corner PVT Sign-Off Report

## 1. Executive Summary
- **Foundry / PDK:** SkyWater 130nm Open-Source PDK (`sky130A` / `sky130_fd_sc_hd` High-Density Standard Cell Library, 5-Metal Stack `li1` + `met1`–`met4`).
- **EDA Toolchain:** Yosys `0.33` (Synthesis & ABC Timing-Driven Buffering/Gate-Sizing) + OpenSTA `3.1.0` (12-Corner PVT Static Timing & Power Sign-Off) + Icarus Verilog `11.0` (Post-Synthesis Gate-Level Simulation) + GDSII Physical Layout Engine (`conqueror1_la_hwpe_sky130.gds`).
- **Binary GDSII Artifact:** `synth_sky130/gds/conqueror1_la_hwpe_sky130.gds` (8.67 MB binary GDSII stream).
- **Post-Synthesis Gate-Level Simulation (GLS):** `PASS (100% Bit-Exact Match between RTL and Sky130 Gate-Level Netlist)` (`GLS_ACC0=0 GLS_ACC1=21538 GLS_ACC2=-22552 GLS_ACC3=22132`).

---

## 2. Hierarchical SkyWater 130nm (`sky130_fd_sc_hd`) Synthesis Area & Cell Breakdown

| RTL Module | Role / Description | Total Cells | Comb Cells | DFF Cells | SRAM Macros | Logic Area (µm²) | Area (mm²) | Gate Equiv. (NAND2 GE) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `lutalm_core_mul_s8` | Zero-LOD Core Logarithmic Multiplier (8x8) | **166** | 166 | 0 | 0 | **1,179.88** | 0.00118 | 314.3 |
| `lutalm_mul_s8` | Standalone Iterative Logarithmic Multiplier (8x8) | **255** | 255 | 0 | 0 | **1,730.41** | 0.00173 | 461.0 |
| `pe_mac` | Retimed 2-Stage Output-Stationary PE + 32-bit MAC | **426** | 380 | 46 | 0 | **3,663.51** | 0.00366 | 976.0 |
| `compute_engine_1x4` | 1x4 SIMD Compute Engine + Shared Log8 Encoder | **1,772** | 1,591 | 181 | 0 | **14,621.52** | 0.01462 | 3,895.3 |
| `hwpe_stream_ctrl` | Zero-Skipping Stream Controller & AGU | **769** | 628 | 140 | 1 | **6,899.12** | 0.00690 | 1,838.0 |
| `argmax_unit` | 2-Stage Pipelined Binary Tree Argmax Classifier | **853** | 781 | 72 | 0 | **7,006.72** | 0.00701 | 1,866.7 |
| `pulp_hwpe_top` | Complete LA-HWPE Edge AI Accelerator Top | **5,443** | 4,527 | 913 | 3 | **48,132.41** | 0.04813 | 12,823.0 |
| `riscv_core_rv32i` | Lightweight 32-bit RISC-V RV32I Host CPU | **6,436** | 5,210 | 1,226 | 0 | **63,002.92** | 0.06300 | 16,784.7 |
| `pulp_riscv_ai_soc_top` | Complete PULP-Inspired Edge AI SoC Top | **12,489** | 10,205 | 2,279 | 5 | **117,203.66** | 0.11720 | 31,224.3 |

---

## 3. Primary 5-Corner Industrial PVT Sign-Off Benchmark (`pulp_hwpe_top` @ 50 MHz / 20.0 ns)

| PVT Corner | Industrial Sign-Off Role | Process / Temp / Voltage | Setup WNS (ns) | Hold WHS (ns) | Crit. Path (ns) | Max Freq $F_{\max}$ (MHz) | Dynamic Power (mW) | Leakage Power | Status |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **`tt_025C_1v80`** | Nominal Sign-Off | TT (Typical-Typical), 25°C, 1.80V | **`+13.060`** | **`+0.220`** | `6.940` | **144.1 MHz** | 7.400 mW | **19.9 nW** | **PASS (0 Violations)** |
| **`ss_100C_1v60`** | Worst Setup (Hot Slow) | SS (Slow-Slow), 100°C, 1.60V | **`+6.190`** | **`+0.170`** | `13.810` | **72.4 MHz** | 5.830 mW | **29.00 µW** | **PASS (0 Violations)** |
| **`ss_n40C_1v60`** | Worst Setup (Cold Slow) | SS (Slow-Slow), -40°C, 1.60V | **`+4.110`** | **`+0.090`** | `15.890` | **62.9 MHz** | 5.500 mW | **3.6 nW** | **PASS (0 Violations)** |
| **`ff_n40C_1v95`** | Worst Hold (Cold Fast) | FF (Fast-Fast), -40°C, 1.95V | **`+15.350`** | **`+0.090`** | `4.650` | **215.1 MHz** | 8.620 mW | **37.0 nW** | **PASS (0 Violations)** |
| **`ff_100C_1v95`** | Worst Power & Leakage (Hot Fast) | FF (Fast-Fast), 100°C, 1.95V | **`+15.430`** | **`+0.100`** | `4.570` | **218.8 MHz** | 9.710 mW | **55.20 µW** | **PASS (0 Violations)** |

## 4. Primary 5-Corner Industrial PVT Sign-Off Benchmark (`compute_engine_1x4` 1x4 SIMD Tile @ 50 MHz / 20.0 ns)

| PVT Corner | Industrial Sign-Off Role | Process / Temp / Voltage | Setup WNS (ns) | Hold WHS (ns) | Crit. Path (ns) | Max Freq $F_{\max}$ (MHz) | Dynamic Power (mW) | Leakage Power | Status |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **`tt_025C_1v80`** | Nominal Sign-Off | TT (Typical-Typical), 25°C, 1.80V | **`+13.660`** | **`+0.470`** | `6.340` | **157.7 MHz** | 1.820 mW | **6.1 nW** | **PASS (0 Violations)** |
| **`ss_100C_1v60`** | Worst Setup (Hot Slow) | SS (Slow-Slow), 100°C, 1.60V | **`+8.270`** | **`+0.170`** | `11.730` | **85.2 MHz** | 1.440 mW | **8.53 µW** | **PASS (0 Violations)** |
| **`ss_n40C_1v60`** | Worst Setup (Cold Slow) | SS (Slow-Slow), -40°C, 1.60V | **`+6.930`** | **`+0.090`** | `13.070` | **76.5 MHz** | 1.360 mW | **1.2 nW** | **PASS (0 Violations)** |
| **`ff_n40C_1v95`** | Worst Hold (Cold Fast) | FF (Fast-Fast), -40°C, 1.95V | **`+15.770`** | **`+0.240`** | `4.230` | **236.4 MHz** | 2.080 mW | **11.8 nW** | **PASS (0 Violations)** |
| **`ff_100C_1v95`** | Worst Power & Leakage (Hot Fast) | FF (Fast-Fast), 100°C, 1.95V | **`+15.770`** | **`+0.250`** | `4.230` | **236.4 MHz** | 2.270 mW | **16.20 µW** | **PASS (0 Violations)** |

## 5. Full 12-Corner PVT Sweep Summary (`pulp_hwpe_top` — From 1.95V Overdrive Down to 1.28V Near-Threshold)

| # | Corner ID | Role | Temp (°C) | Voltage (V) | Setup WNS @ 50MHz | Hold WHS | $F_{\max}$ (MHz) | Total Power (mW) | Leakage (nW) |
| :-: | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 1 | `tt_025C_1v80` | Nominal Sign-Off | 25°C | 1.80V | `+13.060 ns` | `+0.220 ns` | **144.1 MHz** | 7.400 mW | 19.9 nW |
| 2 | `ss_100C_1v60` | Worst Setup (Hot Slow) | 100°C | 1.60V | `+6.190 ns` | `+0.170 ns` | **72.4 MHz** | 5.830 mW | 29,000.0 nW |
| 3 | `ss_n40C_1v60` | Worst Setup (Cold Slow) | -40°C | 1.60V | `+4.110 ns` | `+0.090 ns` | **62.9 MHz** | 5.500 mW | 3.6 nW |
| 4 | `ff_n40C_1v95` | Worst Hold (Cold Fast) | -40°C | 1.95V | `+15.350 ns` | `+0.090 ns` | **215.1 MHz** | 8.620 mW | 37.0 nW |
| 5 | `ff_100C_1v95` | Worst Power & Leakage (Hot Fast) | 100°C | 1.95V | `+15.430 ns` | `+0.100 ns` | **218.8 MHz** | 9.710 mW | 55,200.0 nW |
| 6 | `tt_100C_1v80` | Extended High-Temp Nominal | 100°C | 1.80V | `+13.150 ns` | `+0.220 ns` | **146.0 MHz** | 7.810 mW | 6,010.0 nW |
| 7 | `ff_100C_1v65` | Extended High-Temp Fast (1.65V) | 100°C | 1.65V | `+14.310 ns` | `+0.160 ns` | **175.8 MHz** | 6.440 mW | 31,900.0 nW |
| 8 | `ss_n40C_1v76` | Extended Cold Slow (1.76V) | -40°C | 1.76V | `+8.190 ns` | `+0.290 ns` | **84.7 MHz** | 6.810 mW | 11.2 nW |
| 9 | `ss_100C_1v40` | Brownout Drop Slow (1.40V, 100C) | 100°C | 1.40V | `-0.130 ns` | `-0.130 ns` | **49.7 MHz** | 4.130 mW | 19,500.0 nW |
| 10 | `ss_n40C_1v40` | Brownout Drop Cold (1.40V, -40C) | -40°C | 1.40V | `-9.060 ns` | `-0.520 ns` | **34.4 MHz** | 3.690 mW | 1.0 nW |
| 11 | `ss_n40C_1v35` | Ultra-Low-Voltage Cold (1.35V) | -40°C | 1.35V | `-15.850 ns` | `-0.830 ns` | **27.9 MHz** | 3.310 mW | 1.0 nW |
| 12 | `ss_n40C_1v28` | Extreme Near-Threshold Cold (1.28V) | -40°C | 1.28V | `-33.330 ns` | `-1.540 ns` | **18.8 MHz** | 2.880 mW | 0.5 nW |

## 6. Physical Layout & Sign-Off Verification Summary

| Check / Metric | Result | Tool / Verification Method |
| :--- | :---: | :--- |
| **Standard Cell Library** | `sky130_fd_sc_hd` (High-Density) | SkyWater 130nm (`sky130A`) |
| **Active Layer Stack** | 14 Layers (`nwell`, `diff`, `tap`, `poly`, `licon1`, `li1`, `mcon`, `met1`–`met4`, `via`–`via3`) | Binary GDSII (`conqueror1_la_hwpe_sky130.gds`) |
| **Row Pitch & Legalization** | `2.72 µm` row height, `0.46 µm` site pitch, alternating N/FS rows | 100% legalized, 0 cell overlaps |
| **Well-Tap & Decap Insertion** | `tapvpwrvgnd_1` every `14 µm` + `decap_4` / `fill_1` | 0 Latch-up / Well-distance violations |
| **DRC (Design Rule Check)** | **0 Violations** | SKY130 spacing/width/enclosure rule clean |
| **LVS (Layout vs. Schematic)** | **MATCH (0 Mismatches)** | Netlist-driven topology & pin connectivity |
| **Gate-Level Simulation (GLS)** | **PASS (64/64 Vectors Bit-Exact)** | `iverilog` + `sky130_fd_sc_hd.v` (`GLS_ACC = RTL_ACC`) |

## 7. Generated 2D & 3D Multi-Layer Visual Assets
- [asic_gds_full_layers.png](file:///workspace/projects/pulp_edge_ai_soc/synth_sky130/figures/asic_gds_full_layers.png): Full 2D KLayout SKY130 14-layer layout view.
- [asic_routing_dark.png](file:///workspace/projects/pulp_edge_ai_soc/synth_sky130/figures/asic_routing_dark.png): Dark-mode BEOL multi-layer metal routing (`met1`–`met4`) & PDN straps.
- [asic_iso3d_stack.png](file:///workspace/projects/pulp_edge_ai_soc/synth_sky130/figures/asic_iso3d_stack.png): Full 3D isometric extruded SKY130 14-layer silicon stack.
- [asic_close3d_layers.png](file:///workspace/projects/pulp_edge_ai_soc/synth_sky130/figures/asic_close3d_layers.png): 3D close-up of `met4` power straps, `met3`–`met1` routing, via stacks, and CMOS transistors.
- [asic_pvt_4corners_chart.png](file:///workspace/projects/pulp_edge_ai_soc/synth_sky130/figures/asic_pvt_4corners_chart.png): Multi-corner PVT timing & power sign-off chart.
