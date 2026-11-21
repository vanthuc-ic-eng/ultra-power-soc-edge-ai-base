#!/usr/bin/env bash
# ==============================================================================
# File: run_demo.sh
# Project: CONQUEROR-1 Mini-PULP Edge AI SoC (TUL PYNQ-Z2 Live JTAG & Web Demo)
# Description: One-click launcher for Real-Time JTAG Daemon + Web GUI Server
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "================================================================================"
echo "   CONQUEROR-1 : REAL-TIME PYNQ-Z2 JTAG & WEB LIVE DEMO LAUNCHER"
echo "================================================================================"
echo -e "${NC}"

# Free ports 8080 and 9999 if occupied
fuser -k 8080/tcp 2>/dev/null || true
fuser -k 9999/tcp 2>/dev/null || true

# Compile tb_live.vvp if not already compiled
if [ ! -f "sim/tb_live.vvp" ]; then
    echo -e "${GREEN}[+] Compiling SystemVerilog RTL Live Engine (tb_live.vvp)...${NC}"
    (cd sim && iverilog -g2012 -o tb_live.vvp \
        ../rtl/pkg/pulp_hwpe_pkg.sv \
        ../rtl/core/*.sv \
        ../rtl/memory/*.sv \
        ../rtl/controller/*.sv \
        ../rtl/top/*.sv \
        tb_pulp_hwpe_live.sv)
fi

PORT="${PORT:-8080}"
JTAG_PORT="${JTAG_PORT:-9999}"

# Start persistent XSDB JTAG daemon in background if xsdb is installed
if [ -x "/tools/Xilinx/Vivado/2024.2/bin/xsdb" ]; then
    echo -e "${GREEN}[+] Starting Persistent XSDB JTAG Streaming Daemon on 127.0.0.1:${JTAG_PORT}...${NC}"
    /tools/Xilinx/Vivado/2024.2/bin/xsdb scripts/jtag_daemon.tcl "${JTAG_PORT}" > /tmp/jtag_daemon.log 2>&1 &
    sleep 0.6
fi

echo -e "${GREEN}[+] Starting Real-Time Web Server on Port ${PORT}...${NC}"
echo -e "${BOLD}--> Live JTAG + LED Dashboard : ${CYAN}http://localhost:${PORT}/${NC}"
echo -e "${BOLD}--> Technical Whitepaper Web  : ${CYAN}http://localhost:${PORT}/paper${NC}"
echo -e "${BOLD}--> (Bấm Ctrl+C để dừng toàn bộ server)${NC}"
echo ""

exec python3 sw/gui/app.py
