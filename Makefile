# ==============================================================================
# Makefile for Mini-PULP Edge AI SoC (CONQUEROR-1) Project
# Target Hardware: TUL PYNQ-Z2 (Zynq-7020) & Digilent Zybo Z7 (Zynq-7010)
# Author: Nguyen Van Thuc (24161421)
# ==============================================================================

SHELL     := /bin/bash
PROJ_DIR  := $(shell pwd)
SIM_DIR   := $(PROJ_DIR)/sim
SW_DIR    := $(PROJ_DIR)/sw
SYNTH_DIR := $(PROJ_DIR)/synth
VIVADO    := /tools/Xilinx/Vivado/2024.2/bin/vivado
XSDB      := /tools/Xilinx/Vivado/2024.2/bin/xsdb

.PHONY: all help demo gui run flash program jtag bit-pynq sim-jtag sim benchmark \
        train synth benchmark-fpga benchmark-asic asic-sky130 benchmark-all bitstream \
        report verify-uvm uvm verify-dv dv stop clean

all: sim-jtag verify-dv

help:
	@echo "================================================================================"
	@echo "   CONQUEROR-1 (MINI-PULP EDGE AI SOC) : MAKEFILE SHORTCUT COMMANDS"
	@echo "================================================================================"
	@echo "  make demo / run   : Khởi chạy Real-Time Web GUI + Persistent XSDB JTAG Daemon"
	@echo "  make flash        : Nạp nhanh Bitstream (conqueror1_pynq_z2.bit) xuống PYNQ-Z2"
	@echo "  make bit-pynq     : Tổng hợp Vivado & xuất Bitstream JTAG LED cho PYNQ-Z2"
	@echo "  make sim-jtag     : Mô phỏng kiểm thử cầu nối JTAG BSCANE2 & 4-bit LED (LD3..0)"
	@echo "  make dv           : Kiểm thử đối soát 10 chữ số (0..9) Golden OOP vs RTL DUT"
	@echo "  make sim          : Mô phỏng toàn bộ SoC (CPU RISC-V RV32I + Bus + LA-HWPE)"
	@echo "  make uvm          : Chạy kiểm thử UVM 1.2 vét cạn 65,536 tổ hợp (Vivado Xsim)"
	@echo "  make benchmark    : Kiểm thử phần cứng bộ tăng tốc HWPE trên 10 chữ số (0..9)"
	@echo "  make report       : Hiển thị bảng tổng hợp chỉ số PPA (FPGA & ASIC)"
	@echo "  make stop         : Dừng các tiến trình Web Server (8080) & JTAG Daemon (9999)"
	@echo "  make clean        : Dọn dẹp file mô phỏng tạm (giữ nguyên Bitstream PYNQ-Z2)"
	@echo "================================================================================"

demo: gui

run: gui

gui:
	@bash $(PROJ_DIR)/run_demo.sh

flash: program

program:
	@echo "==> [FLASH] Programming TUL PYNQ-Z2 with conqueror1_pynq_z2.bit over JTAG..."
	$(XSDB) $(PROJ_DIR)/scripts/program_pynq_z2.tcl

jtag:
	@echo "==> [JTAG DAEMON] Starting Persistent XSDB JTAG Streaming Server on port 9999..."
	$(XSDB) $(PROJ_DIR)/scripts/jtag_daemon.tcl 9999

bit-pynq:
	@echo "==> [PYNQ-Z2] Running Synthesis, Place & Route and Bitstream Generation..."
	$(VIVADO) -mode batch -source $(PROJ_DIR)/scripts/build_pynq_z2.tcl \
		-log $(PROJ_DIR)/reports/pynq_z2/vivado.log \
		-journal $(PROJ_DIR)/reports/pynq_z2/vivado.jou

sim-jtag:
	@echo "==> [SIM-JTAG] Verifying PYNQ-Z2 BSCANE2 JTAG Burst Stream & 4-Bit LED[3:0]..."
	cd $(SIM_DIR) && iverilog -g2012 -o tb_jtag.vvp \
		../rtl/pkg/pulp_hwpe_pkg.sv \
		../rtl/core/*.sv \
		../rtl/memory/*.sv \
		../rtl/controller/*.sv \
		../rtl/top/*.sv \
		../rtl/soc/*.sv \
		tb_pynq_z2_jtag.sv
	cd $(SIM_DIR) && vvp tb_jtag.vvp

sim:
	@echo "==> [SIM] Compiling and running Full SoC Verification..."
	cd $(SIM_DIR) && iverilog -g2012 -o tb_soc.vvp \
		../rtl/pkg/pulp_hwpe_pkg.sv \
		../rtl/core/*.sv \
		../rtl/memory/*.sv \
		../rtl/controller/*.sv \
		../rtl/top/*.sv \
		../rtl/soc/*.sv \
		tb_pulp_riscv_ai_soc.sv
	cd $(SIM_DIR) && vvp tb_soc.vvp

benchmark:
	@echo "==> [BENCHMARK] Running 10-Digit Multi-Sample Hardware Benchmark..."
	cd $(SIM_DIR) && iverilog -g2012 -o tb_top_sv.vvp \
		../rtl/pkg/pulp_hwpe_pkg.sv \
		../rtl/core/*.sv \
		../rtl/memory/*.sv \
		../rtl/controller/*.sv \
		../rtl/top/*.sv \
		tb_pulp_hwpe_top.sv
	cd $(SIM_DIR) && vvp tb_top_sv.vvp

train:
	@echo "==> [TRAIN] Running INT8 quantization and pre-encoded weight export..."
	python3 $(SW_DIR)/train_export.py

synth:
	@echo "==> [SYNTH] Running Vivado batch synthesis and physical implementation..."
	cd $(SYNTH_DIR) && $(VIVADO) -mode batch -source run_synth.tcl

benchmark-fpga:
	@echo "==> [FPGA BENCHMARK] Running Full Physical Sign-Off & Environmental Sweep..."
	cd $(PROJ_DIR) && $(VIVADO) -mode batch -source scripts/benchmark_fpga.tcl

benchmark-asic:
	@echo "==> [ASIC BENCHMARK] Running Yosys + OpenSTA Nangate 45nm Synthesis & STA..."
	cd $(PROJ_DIR) && ./scripts/benchmark_asic.sh

asic-sky130:
	@echo "==> [SKY130 ASIC FLOW] Running SkyWater 130nm Synthesis, 12-Corner PVT STA, GLS, GDSII & 3D Renders..."
	python3 $(PROJ_DIR)/scripts/run_asic_sky130_full_flow.py
	python3 $(PROJ_DIR)/scripts/generate_asic_gds_and_3d.py

benchmark-all: benchmark-asic benchmark-fpga
	@echo "==> [REPORT] Generating Full FPGA & ASIC Benchmark Report..."
	python3 $(PROJ_DIR)/scripts/build_full_benchmark_report.py

bitstream: bit-pynq

report:
	@python3 $(PROJ_DIR)/scripts/build_full_benchmark_report.py

uvm: verify-uvm

verify-uvm:
	@echo "==> [UVM] Running Pure UVM 1.2 Verification Suite (Vivado Xsim)..."
	bash $(PROJ_DIR)/scripts/run_uvm.sh

dv: verify-dv

verify-dv:
	@echo "==> [DV] Running 10-Digit Co-Verification Regression (Golden OOP vs RTL)..."
	@if [ ! -f $(SIM_DIR)/tb_live.vvp ]; then \
		cd $(SIM_DIR) && iverilog -g2012 -o tb_live.vvp \
			../rtl/pkg/pulp_hwpe_pkg.sv \
			../rtl/core/*.sv \
			../rtl/memory/*.sv \
			../rtl/controller/*.sv \
			../rtl/top/*.sv \
			tb_pulp_hwpe_live.sv; \
	fi
	python3 $(PROJ_DIR)/scripts/verify_dv.py

stop:
	@echo "==> [STOP] Stopping Demo Web Server & XSDB JTAG Daemon..."
	@fuser -k 8080/tcp 2>/dev/null || true
	@fuser -k 9999/tcp 2>/dev/null || true
	@echo "Stopped."

clean:
	@echo "==> [CLEAN] Cleaning temporary simulation artifacts and logs..."
	rm -f $(SIM_DIR)/*.vvp $(SIM_DIR)/*.vcd $(SIM_DIR)/*.log
	rm -f $(PROJ_DIR)/*.jou $(PROJ_DIR)/*.log $(PROJ_DIR)/clockInfo.txt $(PROJ_DIR)/*.backup.*
	rm -f $(SYNTH_DIR)/*.jou $(SYNTH_DIR)/*.log $(SYNTH_DIR)/clockInfo.txt $(SYNTH_DIR)/*.backup.*
	rm -rf $(SYNTH_DIR)/.Xil $(PROJ_DIR)/.Xil $(PROJ_DIR)/build/uvm_work $(PROJ_DIR)/build/asic
	rm -rf $(SW_DIR)/__pycache__ $(SW_DIR)/gui/__pycache__
	@echo "Clean completed (Bitstream build/bitstream_pynq_z2/conqueror1_pynq_z2.bit preserved)."
