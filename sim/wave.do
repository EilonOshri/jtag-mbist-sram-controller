onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {TESTBENCH & STATUS}
add wave -noupdate /tb_jtag_mbist_top/error_count
add wave -noupdate /tb_jtag_mbist_top/inject_fault
add wave -noupdate /tb_jtag_mbist_top/clk
add wave -noupdate /tb_jtag_mbist_top/rst_n
add wave -noupdate /tb_jtag_mbist_top/tck
add wave -noupdate -divider {JTAG TAP INTERFACE}
add wave -noupdate /tb_jtag_mbist_top/tms
add wave -noupdate /tb_jtag_mbist_top/tdi
add wave -noupdate /tb_jtag_mbist_top/tdo
add wave -noupdate /tb_jtag_mbist_top/dut/u_jtag_tap/state_shiftdr
add wave -noupdate /tb_jtag_mbist_top/dut/u_jtag_tap/state_shiftir
add wave -noupdate -radix hexadecimal /tb_jtag_mbist_top/dut/u_jtag_tap/mbist_status_in
add wave -noupdate /tb_jtag_mbist_top/dut/u_jtag_tap/mbist_start_pulse
add wave -noupdate -divider {CDC SYNCHRONIZER}
add wave -noupdate /tb_jtag_mbist_top/dut/u_sync_start_pulse/pulse_in
add wave -noupdate /tb_jtag_mbist_top/dut/u_sync_start_pulse/pulse_out
add wave -noupdate -divider {MBIST & SRAM ENGINE}
add wave -noupdate /tb_jtag_mbist_top/dut/u_mbist_ctrl/start
add wave -noupdate /tb_jtag_mbist_top/dut/u_mbist_ctrl/fail
add wave -noupdate /tb_jtag_mbist_top/dut/u_mbist_ctrl/done
add wave -noupdate /tb_jtag_mbist_top/dut/u_mbist_ctrl/current_state
add wave -noupdate -radix hexadecimal /tb_jtag_mbist_top/dut/u_mbist_ctrl/rfail_addr
add wave -noupdate -radix hexadecimal /tb_jtag_mbist_top/dut/u_mbist_ctrl/addr_cnt
add wave -noupdate -radix hexadecimal /tb_jtag_mbist_top/dut/u_mbist_ctrl/mem_rdata
add wave -noupdate -radix hexadecimal /tb_jtag_mbist_top/dut/u_mbist_ctrl/mem_wdata
add wave -noupdate /tb_jtag_mbist_top/dut/u_mbist_ctrl/mem_we_n
add wave -noupdate /tb_jtag_mbist_top/dut/u_mbist_ctrl/mem_ce_n
add wave -noupdate /tb_jtag_mbist_top/dut/u_jtag_tap/ir_latched
add wave -noupdate /tb_jtag_mbist_top/dut/u_jtag_tap/mbist_sel
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {65286000 ps} 0 Blue default} {{Cursor 2} {74565000 ps} 0 Blue default}
quietly wave cursor active 2
configure wave -namecolwidth 174
configure wave -valuecolwidth 60
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {64710165 ps} {75974497 ps}
