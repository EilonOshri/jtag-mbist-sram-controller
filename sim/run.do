# ==============================================================================
# File: run.do
# Description: Automated simulation and waveform setup script for ModelSim
# ==============================================================================

# 1. Clean up and create a fresh working directory
if [file exists work] { vdel -lib work -all }
vlib work

# 2. Compile RTL design files
vlog ../rtl/cdc_level_sync.v
vlog ../rtl/cdc_pulse_sync.v
vlog ../rtl/jtag_reg.v
vlog ../rtl/jtag_state_machine.v
vlog ../rtl/jtag_tap_top.v
vlog ../rtl/mbist_controller.v
vlog ../rtl/sram_model.v
vlog ../rtl/jtag_mbist_top.v

# 3. Compile Testbench
vlog ../tb/tb_jtag_mbist_top.v

# 4. Load simulation top module
vsim work.tb_jtag_mbist_top

# 5. Configure Waveform Window
# ------------------------------------------------------------------------------
# TESTBENCH & STATUS Signals
add wave -noupdate -divider "TESTBENCH & STATUS"
add wave -noupdate -radix decimal /tb_jtag_mbist_top/error_count
add wave -noupdate /tb_jtag_mbist_top/inject_fault
add wave -noupdate /tb_jtag_mbist_top/clk
add wave -noupdate /tb_jtag_mbist_top/rst_n
add wave -noupdate /tb_jtag_mbist_top/tck

# JTAG TAP INTERFACE Signals
add wave -noupdate -divider "JTAG TAP INTERFACE"
add wave -noupdate /tb_jtag_mbist_top/tms
add wave -noupdate /tb_jtag_mbist_top/tdi
add wave -noupdate /tb_jtag_mbist_top/tdo
add wave -noupdate /tb_jtag_mbist_top/uut/state_shiftdr
add wave -noupdate /tb_jtag_mbist_top/uut/state_shiftir
add wave -noupdate -radix hex /tb_jtag_mbist_top/uut/mbist_status_in
add wave -noupdate /tb_jtag_mbist_top/uut/mbist_start_pulse

# CDC SYNCHRONIZER Signals
add wave -noupdate -divider "CDC SYNCHRONIZER"
add wave -noupdate /tb_jtag_mbist_top/uut/cdc_inst/pulse_in
add wave -noupdate /tb_jtag_mbist_top/uut/cdc_inst/pulse_out

# MBIST & SRAM ENGINE Signals
add wave -noupdate -divider "MBIST & SRAM ENGINE"
add wave -noupdate /tb_jtag_mbist_top/uut/mbist_inst/start
add wave -noupdate /tb_jtag_mbist_top/uut/mbist_inst/fail
add wave -noupdate /tb_jtag_mbist_top/uut/mbist_inst/done
add wave -noupdate /tb_jtag_mbist_top/uut/mbist_inst/current_state
add wave -noupdate -radix hex /tb_jtag_mbist_top/uut/mbist_inst/rfail_addr
add wave -noupdate -radix hex /tb_jtag_mbist_top/uut/mbist_inst/addr_cnt
add wave -noupdate -radix hex /tb_jtag_mbist_top/uut/sram_inst/mem_rdata
add wave -noupdate -radix hex /tb_jtag_mbist_top/uut/sram_inst/mem_wdata
add wave -noupdate /tb_jtag_mbist_top/uut/sram_inst/mem_we_n
add wave -noupdate /tb_jtag_mbist_top/uut/sram_inst/mem_ce_n
add wave -noupdate -radix hex /tb_jtag_mbist_top/uut/ir_latched
add wave -noupdate /tb_jtag_mbist_top/uut/mbist_sel

# Waveform formatting (show only leaf signal names)
configure wave -justifyvalue left
configure wave -signalnamewidth 1

# 6. Run simulation and auto-zoom to fit full execution time
run -all
wave zoom full
