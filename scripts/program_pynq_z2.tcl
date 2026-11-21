# ==============================================================================
# File: program_pynq_z2.tcl
# Description: Fast XSDB JTAG Bitstream Programmer for TUL PYNQ-Z2 (xc7z020)
# ==============================================================================
set bit_file "/workspace/projects/pulp_edge_ai_soc/build/bitstream_pynq_z2/conqueror1_pynq_z2.bit"

puts "=================================================================="
puts ">>> PROGRAMMING TUL PYNQ-Z2 OVER JTAG: $bit_file"
puts "=================================================================="

connect

set found 0
for {set i 0} {$i < 10} {incr i} {
    if {![catch {targets -set -nocase -filter {name =~ "*xc7z020*" || name =~ "*xc7z010*"}}]} {
        set found 1
        break
    }
    after 400
}

if {!$found} {
    puts "ERROR: No PYNQ-Z2 (xc7z020) target found on JTAG! Available targets:"
    puts [targets]
    exit 1
}

fpga -file $bit_file

puts "=================================================================="
puts ">>> SUCCESS: PYNQ-Z2 PROGRAMMED! SW0 (M20) = Reset, LD3..LD0 = Digit"
puts "=================================================================="
exit 0
