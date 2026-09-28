# JTAG IEEE 1149.1 TAP Controller & SRAM MBIST

## 1. Introduction

### What is this project?
This project is an educational, simulation-level Design-for-Testability (DFT) system. It demonstrates the architecture and verification of an **IEEE 1149.1 standard JTAG TAP Controller** integrated with an on-chip **Memory Built-In Self-Test (MBIST) Controller** to test a simulated single-port SRAM model.

Written in Verilog, the design tackles critical Clock Domain Crossing (CDC) challenges between the asynchronous test clock (`tck`) and core clock (`clk`). It employs dedicated `cdc_pulse_sync` modules to safely pass single-cycle start and completion pulses without metastability, alongside `tck`-domain shadow registers that latch the test outcome and failing address until the next dispatch.

### Key Features
* **IEEE 1149.1 TAP Controller Model:** Standard 5 wire JTAG interface supporting instruction and data register scan sequences.
* **Dual Clock Domain Architecture (CDC):** Asynchronous separation between `TCK` and `CLK` domains using single cycle pulse synchronizers (`cdc_pulse_sync`) for start and completion handshakes.
* **Status Shadow Register:** Latches test results (`done`, `fail`, `rfail_addr`) safely in the `TCK` domain upon completion, retaining them until the next test run.
* **Functional Memory Isolation:** Multiplexes SRAM access between normal operation and test mode (`test_mode`), clamping functional read data (`func_rdata`) during BIST runs.
* **Fault Injection Simulation:** Built in verification input (`inject_fault`) within the SRAM model to trigger failure scenarios and verify detection logic.

---

## 2. Architecture & Block Diagram
![System Architecture & Block Diagram](block%20diagram%20-.png)
