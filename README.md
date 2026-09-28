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
![System Architecture & Block Diagram](docs/adr/block%20diagram%20-.png)

## 2. Architecture & Block Diagram

![System Architecture & Block Diagram](block%20diagram%20-.png)

### Color Coding
* **Pink Module (JTAG TAP):** IEEE 1149.1 TAP Controller interfacing external test pins (`tck`, `tms`, `tdi`, `trst_n`, `tdo`).
* **Green Module (CDC Synchronizer):** Bidirectional pulse synchronizer safely passing trigger and done pulses across clock boundaries (`mbist_start_cmd_tck` → `mbist_start_pulse_clk`, `done` → `mbist_done_pulse_tck`).
* **Grey Module (Status Capture Registers):** `TCK`-domain shadow registers capturing `fail` and `rfail_addr[7:0]` to pack into `mbist_status[31:0]`.
* **Yellow Module (MBIST):** Test pattern generator and comparator running at functional system clock frequency (`clk`).
* **Purple Module (MUX):** DFT multiplexers controlled by `test_mode` for SRAM bus switching and functional read isolation (`func_rdata[7:0]`).
* **Blue Module (SRAM):** Embedded memory model under test with dedicated hardware fault injection hook (`inject_fault`).

### Module Descriptions
* **`jtag_mbist_top` (Top-Level Wrapper):** Integrates the TAP controller, MBIST controller, CDC pulse synchronizers, isolation multiplexers, and SRAM behavioral model.
* **`jtag_tap_top` (JTAG TAP):** Implements the IEEE 1149.1 TAP FSM, Instruction Register (IR), and Data Registers (DR) for MBIST control/status.
* **`mbist_controller` (MBIST):** FSM executing the March C- algorithm to test SRAM; generates R/W cycles and checks for memory faults.
* **`cdc_pulse_sync` (CDC Synchronizer):** Safe toggle to pulse synchronizer passing single cycle events across unrelated clock domains (`tck` ↔ `clk`).
* **`sram_model` (SRAM):** Parameterized synchronous single port SRAM behavioral model with fault injection input.

---

## 3. Design Details

### Clock Domain Crossing (CDC) & Status Register

| Domain | Clock Signal | Associated Logic Blocks | Function |
|---|---|---|---|
| **Test Domain** | `tck` | `u_jtag_tap`, TCK Shadow Regs | Scans in instructions/data, latches final pass/fail results |
| **System Domain** | `clk` | `u_mbist_ctrl`, `u_sram`, FSM | Executes MBIST algorithms at functional system clock frequency |

#### Synchronization Mechanism
1. **Start Trigger:** Setting `ctrl[0] = 1` in the MBIST Control DR asserts `mbist_start_cmd_tck` during `Update-DR`. This single-cycle pulse in `TCK` is synchronized into `CLK` as `mbist_start_pulse_clk`.
2. **Test Run:** `mbist_start_reg` latches high, asserting `test_mode = 1` to route SRAM buses to `mbist_controller`.
3. **Completion & Latch:** The rising edge of `mbist_done` triggers a pulse back to the `TCK` domain (`mbist_done_pulse_tck`), safely latching `fail` and `rfail_addr` into shadow flip-flops.

#### JTAG MBIST Status Register Bit Mapping (32-bit `mbist_status`)

| Bit Range | Field Name | Description |
|---|---|---|
| `[31:10]` | `RESERVED` | Zero-padded bits |
| `[9:2]` | `RFAIL_ADDR[7:0]` | Address of the first detected memory failure |
| `[1]` | `FAIL` | MBIST test outcome (`1` = fail, `0` = pass) |
| `[0]` | `DONE` | Test completion flag (`1` = finished) |

---
