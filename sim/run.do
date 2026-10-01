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
do wave.do

# Waveform formatting (show only leaf signal names)
configure wave -justifyvalue left
configure wave -signalnamewidth 1

# 6. Run simulation and auto-zoom to fit full execution time
run -all
wave zoom full
