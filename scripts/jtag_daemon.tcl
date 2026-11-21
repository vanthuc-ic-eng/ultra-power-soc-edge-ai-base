# ==============================================================================
# File: jtag_daemon.tcl
# Project: Mini-PULP Edge AI SoC (CONQUEROR-1) on TUL PYNQ-Z2
# Author: Nguyen Van Thuc (24161421)
# Description:
#   Persistent Zero-Latency XSDB JTAG Streaming Server (TCP Port 9999).
#   Eliminates the 8-10s Vivado/XSDB startup overhead by keeping the JTAG TAP
#   session open and executing 8416-bit single-shot BSCANE2 (user4) bursts
#   in ~10-20 ms per frame on the physical TUL PYNQ-Z2 (xc7z020).
# ==============================================================================

set port 9999
if {[llength $argv] > 0} {
    set port [lindex $argv 0]
}

set proj_dir "/workspace/projects/pulp_edge_ai_soc"
set bit_file "$proj_dir/build/bitstream_pynq_z2/conqueror1_pynq_z2.bit"

puts "=================================================================="
puts "   CONQUEROR-1 PERSISTENT REAL-TIME JTAG DAEMON (XSDB)"
puts "   Listening on TCP 127.0.0.1:$port"
puts "=================================================================="

set server_connected 0
set board_programmed 0

proc program_fpga_bitstream {} {
    global bit_file server_connected board_programmed
    if {![file exists $bit_file]} {
        return "ERR_NO_BITFILE"
    }
    if {[catch {
        if {!$server_connected} {
            connect
            set server_connected 1
        }
        targets -set -filter {name =~ "*xc7z*" || name =~ "*XC7Z*"}
        fpga -file $bit_file
        set board_programmed 1
    } err]} {
        return "ERR_PROG:$err"
    }
    return "OK_PROGRAMMED"
}

proc ensure_jtag_ready {} {
    global server_connected board_programmed
    if {[catch {
        if {!$server_connected} {
            connect
            set server_connected 1
        }
        jtag targets -set -filter {name =~ "*xc7z*" || name =~ "*XC7Z*"}
    } err]} {
        return 0
    }
    return 1
}

proc run_jtag_burst {hex_payload} {
    if {![ensure_jtag_ready]} {
        return "ERR_NO_BOARD"
    }
    if {[catch {
        set nbits [expr {[string length $hex_payload] * 4}]
        set seq [jtag sequence]
        $seq state RESET
        $seq irshift -state IDLE -register user4
        $seq drshift -state IDLE -hex $nbits $hex_payload
        $seq delay 120
        $seq drshift -capture -state IDLE -hex 32 00000000
        set res [$seq run -hex]
        $seq delete

        # Auto-program bitstream on first connection or if FPGA was power-cycled (magic header != 0xA)
        set high_nib [string index $res 6]
        if {!$board_programmed || [string tolower $high_nib] ne "a"} {
            program_fpga_bitstream
            jtag targets -set -filter {name =~ "*xc7z*" || name =~ "*XC7Z*"}
            set seq2 [jtag sequence]
            $seq2 state RESET
            $seq2 irshift -state IDLE -register user4
            $seq2 drshift -state IDLE -hex $nbits $hex_payload
            $seq2 delay 120
            $seq2 drshift -capture -state IDLE -hex 32 00000000
            set res [$seq2 run -hex]
            $seq2 delete
        }
    } err]} {
        return "ERR_JTAG:$err"
    }
    return "OK $res"
}

proc run_jtag_single_word {hex_word8} {
    if {![ensure_jtag_ready]} {
        return "ERR_NO_BOARD"
    }
    if {[catch {
        set seq [jtag sequence]
        $seq state RESET
        $seq irshift -state IDLE -register user4
        $seq drshift -capture -state IDLE -hex 32 $hex_word8
        set res [$seq run -hex]
        $seq delete
    } err]} {
        return "ERR_JTAG:$err"
    }
    return "OK $res"
}

proc handle_client {chan} {
    if {[eof $chan]} {
        fileevent $chan readable {}
        close $chan
        return
    }
    if {[gets $chan line] < 0} {
        return
    }
    set line [string trim $line]
    if {$line eq ""} {
        return
    }

    set cmd [lindex [split $line " "] 0]
    set arg [lindex [split $line " "] 1]

    if {$cmd eq "PING"} {
        puts $chan [run_jtag_single_word "00000000"]
    } elseif {$cmd eq "WORD"} {
        puts $chan [run_jtag_single_word $arg]
    } elseif {$cmd eq "STREAM"} {
        puts $chan [run_jtag_burst $arg]
    } elseif {$cmd eq "PROGRAM"} {
        puts $chan [program_fpga_bitstream]
    } else {
        puts $chan "ERR_UNKNOWN_CMD"
    }
    flush $chan
}

proc accept_conn {chan addr cport} {
    fconfigure $chan -buffering line -translation auto
    fileevent $chan readable [list handle_client $chan]
}

# Initial auto-connect & auto-program on startup if board is connected
if {[ensure_jtag_ready]} {
    puts ">>> Auto-programming PYNQ-Z2 bitstream on startup..."
    program_fpga_bitstream
}

socket -server accept_conn -myaddr 127.0.0.1 $port
vwait forever
