# JTAG IEEE 1149.1 Integrated MBIST Architecture

## 1. Introduction

### What is this project?
This project implements a complete, synthesizable **Memory Built-In Self-Test (MBIST)** subsystem integrated with a standard **IEEE 1149.1 (JTAG) TAP Controller**. Designed for Design-for-Testability (DFT) applications, it enables non-intrusive, serial-driven in-system and manufacturing testing of on-chip embedded SRAM blocks via standard JTAG boundary-scan pins (`TCK`, `TMS`, `TDI`, `TDO`, `TRST_n`).

Written in Verilog, the architecture handles critical mixed-clock digital design challenges, specifically robust **Clock Domain Crossing (CDC)** between the asynchronous/slower Test Clock (`TCK`) domain and the high-speed functional System Clock (`CLK`) domain. The top-level module (`jtag_mbist_top`) arbitrates SRAM access between normal functional operation and BIST execution, capturing pass/fail diagnostic flags and first-failing address telemetry into JTAG Data Registers for real-time serial extraction.

### Key Features
* **IEEE 1149.1 Compliant TAP Controller**: Serial instruction register (`IR_LEN = 4`) and dedicated MBIST Data Register (`MBIST_DR_LEN = 32`) interface.
* **Deterministic Dual-Domain CDC Synchronization**: Pulse-synchronizers (`cdc_pulse_sync`) for hazard-free control and completion transfer across `TCK` and `CLK` domains.
* **Non-Intrusive Functional Multiplexing**: Hardware MUX isolation layer seamlessly swaps memory control between functional buses and the BIST engine based on `test_mode`.
* **Telemetry & Failure Diagnosis**: Sticky latching registers capture `mbist_done`, `mbist_fail`, and the first failing address (`mbist_rfail_addr`) into the 32-bit JTAG status word.
* **Fault Injection**: Built-in verification hook (`inject_fault`) within `sram_model` to validate error detection mechanisms and diagnostic telemetry during simulation.

---
