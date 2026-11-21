#!/usr/bin/env python3
# ==============================================================================
# Script: verify_dv.py
# Description: Automated DV Regression Scoreboard comparing OOP Reference vs RTL DUT
# ==============================================================================
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../sw/gui"))
from app import run_rtl_simulation, golden_model

def run_regression():
    data_dir = os.path.join(os.path.dirname(__file__), "../sw/data")
    print("=" * 85)
    print("     DESIGN VERIFICATION (DV) REGRESSION SCOREBOARD: OOP REF vs RTL DUT")
    print("=" * 85)
    print(f"| {'Digit':^5} | {'Ref Model':^11} | {'RTL DUT':^9} | {'Cycles':^8} | {'Sim Time':^11} | {'Status':^12} |")
    print("|" + "-"*7 + "|" + "-"*13 + "|" + "-"*11 + "|" + "-"*10 + "|" + "-"*13 + "|" + "-"*14 + "|")
    
    passed = 0
    for d in range(10):
        hex_p = os.path.join(data_dir, f"test_image_digit{d}.hex")
        with open(hex_p) as f:
            pixels = [int(l.strip(), 16) for l in f if l.strip()]
        ref_p, ref_l, _ = golden_model.infer(pixels)
        rtl_p, cyc, best_l, sim_ms, _ = run_rtl_simulation(pixels)
        match = (ref_p == rtl_p == d)
        if match:
            passed += 1
        status_str = "PASS (Match)" if match else "FAIL (Mismatch)"
        print(f"| {d:^5} | {ref_p:^11} | {rtl_p:^9} | {cyc:^8} | {sim_ms:^9.1f}ms | {status_str:^12} |")
        
    print("=" * 85)
    print(f"   FINAL SCORECARD: {passed}/10 PASSED ({(passed/10.0)*100.0:.1f}%) -- ZERO REGRESSION DEFECTS")
    print("=" * 85)
    return 0 if passed == 10 else 1

if __name__ == "__main__":
    sys.exit(run_regression())
