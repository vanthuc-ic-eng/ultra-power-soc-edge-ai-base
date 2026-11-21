# ==============================================================================
# UNIVERSAL FPGA PHYSICAL IMPLEMENTATION & TIMING BENCHMARK (AMD Vivado 2024.2)
# Target Part: Digilent Zybo Z-7010 (xc7z010clg400-1)
# Project: PULP-inspired Edge AI SoC for Handwritten Digit Recognition
# Author: Nguyen Van Thuc - 24161421
# Comprehensive Environmental, Thermal, Voltage Corner & Netlist Sign-off Suite
# ==============================================================================

set_param general.maxThreads 4

set proj_dir "/workspace/projects/pulp_edge_ai_soc"
set report_dir "$proj_dir/reports/fpga"
file mkdir $report_dir

puts "\n=================================================================="
puts ">>> PROFILING FPGA: Mini-PULP Edge AI SoC (Zynq-7000 xc7z010clg400-1)"
puts ">>> Output Dir: $report_dir"
puts "=================================================================="

create_project -in_memory -part xc7z010clg400-1

# Read SystemVerilog files
read_verilog -sv $proj_dir/rtl/pkg/pulp_hwpe_pkg.sv
read_verilog -sv [glob $proj_dir/rtl/core/*.sv]
read_verilog -sv [glob $proj_dir/rtl/memory/*.sv]
read_verilog -sv [glob $proj_dir/rtl/controller/*.sv]
read_verilog -sv [glob $proj_dir/rtl/top/*.sv]
read_verilog -sv [glob $proj_dir/rtl/soc/*.sv]

# Read constraints
read_xdc $proj_dir/synth/constrs.xdc

# ------------------------------------------------------------------------------
# 1. Synthesis (Out-of-context, Full SoC)
# ------------------------------------------------------------------------------
puts "\n>>> \[STAGE 1\] Running Vivado Synthesis (Top: pulp_riscv_ai_soc_top)..."
synth_design -top pulp_riscv_ai_soc_top -part xc7z010clg400-1 -mode out_of_context

# ------------------------------------------------------------------------------
# 2. Place & Route (Physical Implementation for exact sign-off parasitics)
# ------------------------------------------------------------------------------
puts "\n>>> \[STAGE 2\] Place and Route Implementation..."
create_clock -period 10.000 [get_ports clk]
opt_design
place_design
route_design

# ------------------------------------------------------------------------------
# 3. Post-Route Utilization & Baseline Timing (100 MHz, Nominal PVT)
# ------------------------------------------------------------------------------
puts "\n>>> \[STAGE 3\] Baseline Utilization & Physical Timing Sign-Off (100 MHz)..."
report_utilization -file "${report_dir}/pnr_util.rpt"
report_utilization -hierarchical -file "${report_dir}/utilization_hierarchical.rpt"
report_timing_summary -max_paths 10 -file "${report_dir}/pnr_timing_100mhz.rpt"
report_timing -nworst 1 -max_paths 1 -path_type full_clock_expanded -file "${report_dir}/critical_path.rpt"
report_timing -delay_type min_max -max_paths 5 -file "${report_dir}/timing_paths_detailed.rpt"
report_power -file "${report_dir}/pnr_power_100mhz.rpt"
report_drc -file "${report_dir}/drc.rpt"
report_clock_utilization -file "${report_dir}/clock_utilization.rpt"
report_high_fanout_nets -max_nets 20 -file "${report_dir}/high_fanout_nets.rpt"

# ------------------------------------------------------------------------------
# 4. Multi-Frequency Power & Timing Survey (50, 75, 100, 125, 150, 180 MHz)
# ------------------------------------------------------------------------------
puts "\n>>> \[STAGE 4\] Multi-Frequency Sweep..."
set freqs {50 75 100 125 150 180}

foreach f $freqs {
    set period [format "%.3f" [expr {1000.0 / $f}]]
    create_clock -period $period [get_ports clk]
    report_timing_summary -file "${report_dir}/timing_${f}mhz.rpt"
    report_power -file "${report_dir}/power_${f}mhz.rpt"
}

# ------------------------------------------------------------------------------
# 5. Environmental & Thermal Sign-Off (Ambient Temperature Sweep: -40C to 100C)
# ------------------------------------------------------------------------------
puts "\n>>> \[STAGE 5\] Environmental & Thermal Sweep (-40C to 100C, Still Air, No Heatsink)..."
create_clock -period 10.000 [get_ports clk]
set ambient_temps {-40 0 25 50 85 100}
set thermal_csv [open "${report_dir}/thermal_ambient_sweep.csv" "w"]
puts $thermal_csv "Ambient_Temp_C,Junction_Temp_C,Thermal_Margin_C,Device_Static_W,Dynamic_W,Total_Power_W"

foreach temp $ambient_temps {
    set_operating_conditions -ambient_temp $temp -airflow 0 -heatsink none
    report_power -file "${report_dir}/power_thermal_${temp}C.rpt"
    
    set fp [open "${report_dir}/power_thermal_${temp}C.rpt" "r"]
    set content [read $fp]
    close $fp
    
    set junc_temp "N/A"
    set therm_margin "N/A"
    set dev_static "N/A"
    set dyn_power "N/A"
    set tot_power "N/A"
    
    regexp {Junction Temperature \(C\)\s+\|\s*([-\d\.]+)} $content match junc_temp
    regexp {Device Static \(W\)\s+\|\s*([<\d\.]+)} $content match dev_static
    regexp {Dynamic \(W\)\s+\|\s*([<\d\.]+)} $content match dyn_power
    regexp {Total On-Chip Power \(W\)\s+\|\s*([<\d\.]+)} $content match tot_power
    if {$junc_temp ne "N/A"} {
        set therm_margin [format "%.1f C" [expr {85.0 - $junc_temp}]]
    }
    
    puts $thermal_csv "${temp},${junc_temp},${therm_margin},${dev_static},${dyn_power},${tot_power}"
}
close $thermal_csv

# Reset to standard operating condition (25C ambient)
set_operating_conditions -ambient_temp 25.0 -airflow 0 -heatsink none

# ------------------------------------------------------------------------------
# 6. Supply Voltage Corner Sensitivity Analysis (Vccint = 0.95V, 1.00V, 1.05V)
# ------------------------------------------------------------------------------
puts "\n>>> \[STAGE 6\] Supply Voltage Corner Sensitivity Analysis..."
set v_corners {0.95 1.00 1.05}
set volt_csv [open "${report_dir}/voltage_corner_power.csv" "w"]
puts $volt_csv "Vccint_V,Total_Power_W,Dynamic_W,Static_W"

foreach v $v_corners {
    set_operating_conditions -voltage [list Vccint $v Vccaux 1.80 Vcco33 3.30]
    report_power -file "${report_dir}/power_vccint_${v}V.rpt"
    
    set fp [open "${report_dir}/power_vccint_${v}V.rpt" "r"]
    set content [read $fp]
    close $fp
    
    set tot_p "N/A"
    set dyn_p "N/A"
    set stat_p "N/A"
    regexp {Total On-Chip Power \(W\)\s+\|\s*([\d\.]+)} $content match tot_p
    regexp {Dynamic \(W\)\s+\|\s*([\d\.]+)} $content match dyn_p
    regexp {Device Static \(W\)\s+\|\s*([\d\.]+)} $content match stat_p
    
    puts $volt_csv "${v},${tot_p},${dyn_p},${stat_p}"
}
close $volt_csv

# Reset voltage to nominal
set_operating_conditions -voltage {Vccint 1.00 Vccaux 1.80 Vcco33 3.30}

# ------------------------------------------------------------------------------
# 7. Switching Activity & Toggle Rate Analysis (5% to 50%)
# ------------------------------------------------------------------------------
puts "\n>>> \[STAGE 7\] Switching Activity Survey (Toggle Rates 5% to 50%)..."
set toggle_rates {5.0 12.5 25.0 50.0}
set switch_csv [open "${report_dir}/switching_activity_sweep.csv" "w"]
puts $switch_csv "Toggle_Rate_pct,Dynamic_Power_W,Logic_Power_W,Signal_Power_W"

foreach tr $toggle_rates {
    set_switching_activity -default_toggle_rate $tr -default_static_probability 0.5
    report_power -file "${report_dir}/power_toggle_${tr}pct.rpt"
    
    set fp [open "${report_dir}/power_toggle_${tr}pct.rpt" "r"]
    set content [read $fp]
    close $fp
    
    set dyn_p "N/A"
    set log_p "N/A"
    set sig_p "N/A"
    regexp {Dynamic \(W\)\s+\|\s*([\d\.]+)} $content match dyn_p
    regexp {Logic\s+\|\s*([\d\.]+)} $content match log_p
    regexp {Signals\s+\|\s*([\d\.]+)} $content match sig_p
    
    puts $switch_csv "${tr},${dyn_p},${log_p},${sig_p}"
}
close $switch_csv

puts "\n=================================================================="
puts ">>> FPGA COMPREHENSIVE BENCHMARK COMPLETED SUCCESSFULLY!"
puts ">>> Reports saved in: $report_dir"
puts "=================================================================="
exit
