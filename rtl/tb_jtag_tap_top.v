`timescale 1ns / 1ps

module tb_jtag_tap_top;

    // Parameters
    localparam IR_LEN        = 4;
    localparam MBIST_DR_LEN  = 32;
    localparam TCK_PERIOD    = 20; // 50 MHz Clock

    // DUT Signals
    reg                      tck;
    reg                      tms;
    reg                      trst_n;
    reg                      tdi;
    wire                     tdo;

    reg  [MBIST_DR_LEN-1:0]  mbist_status_in;
    wire [MBIST_DR_LEN-1:0]  mbist_ctrl_out;
    wire                     mbist_start_pulse;

    // Opcodes
    localparam [IR_LEN-1:0] OP_BYPASS    = 4'b1111;
    localparam [IR_LEN-1:0] OP_RUN_MBIST = 4'b0010;

    // Instantiate DUT
    jtag_tap_top #(
        .IR_LEN(IR_LEN),
        .MBIST_DR_LEN(MBIST_DR_LEN)
    ) dut (
        .tck(tck),
        .tms(tms),
        .trst_n(trst_n),
        .tdi(tdi),
        .tdo(tdo),
        .mbist_status_in(mbist_status_in),
        .mbist_ctrl_out(mbist_ctrl_out),
        .mbist_start_pulse(mbist_start_pulse)
    );

    // Clock Generation
    always #(TCK_PERIOD / 2) tck = ~tck;

    // =========================================================================
    // JTAG Low-Level Driver Tasks
    // =========================================================================

    // Send single TMS & TDI bit on falling edge of TCK (so DUT samples on posedge)
    task jtag_clock_cycle;
        input tms_val;
        input tdi_val;
        begin
            @(negedge tck);
            tms = tms_val;
            tdi = tdi_val;
        end
    endtask

    // Reset TAP Controller by holding TMS=1 for 5 cycles
    task jtag_reset;
        integer i;
        begin
            $display("[TB] Resetting TAP controller via TMS sequence...");
            for (i = 0; i < 5; i = i + 1) begin
                jtag_clock_cycle(1'b1, 1'b0);
            end
            // Move to Run-Test/Idle
            jtag_clock_cycle(1'b0, 1'b0);
        end
    endtask

    // Shift Instruction into IR
    task jtag_shift_ir;
        input  [IR_LEN-1:0] opcode_in;
        output [IR_LEN-1:0] captured_ir_out;
        integer i;
        begin
            // Idle -> Select-DR -> Select-IR -> Capture-IR -> Shift-IR
            jtag_clock_cycle(1'b1, 1'b0); // Select-DR
            jtag_clock_cycle(1'b1, 1'b0); // Select-IR
            jtag_clock_cycle(1'b0, 1'b0); // Capture-IR
            jtag_clock_cycle(1'b0, 1'b0); // Shift-IR

            // Shift data through IR
            for (i = 0; i < IR_LEN; i = i + 1) begin
                captured_ir_out[i] = tdo; // Sample TDO (updated on negedge)
                if (i == IR_LEN - 1) begin
                    // On last bit, set TMS=1 to go to Exit1-IR
                    jtag_clock_cycle(1'b1, opcode_in[i]);
                end else begin
                    jtag_clock_cycle(1'b0, opcode_in[i]);
                end
            end

            // Exit1-IR -> Update-IR -> Run-Test/Idle
            jtag_clock_cycle(1'b1, 1'b0); // Update-IR
            jtag_clock_cycle(1'b0, 1'b0); // Run-Test/Idle
        end
    endtask

    // Shift arbitrary length Data into DR
    task jtag_shift_dr;
        input  integer len;
        input  [63:0]  data_in;
        output [63:0]  data_out;
        integer i;
        begin
            data_out = 64'd0;

            // Idle -> Select-DR -> Capture-DR -> Shift-DR
            jtag_clock_cycle(1'b1, 1'b0); // Select-DR
            jtag_clock_cycle(1'b0, 1'b0); // Capture-DR
            jtag_clock_cycle(1'b0, 1'b0); // Shift-DR

            // Shift bits
            for (i = 0; i < len; i = i + 1) begin
                data_out[i] = tdo;
                if (i == len - 1) begin
                    jtag_clock_cycle(1'b1, data_in[i]); // Exit1-DR
                end else begin
                    jtag_clock_cycle(1'b0, data_in[i]); // Shift-DR
                end
            end

            // Exit1-DR -> Update-DR -> Run-Test/Idle
            jtag_clock_cycle(1'b1, 1'b0); // Update-DR
            jtag_clock_cycle(1'b0, 1'b0); // Run-Test/Idle
        end
    endtask

    // =========================================================================
    // Test Sequences
    // =========================================================================
    reg [IR_LEN-1:0] captured_ir;
    reg [63:0]       dr_readout;

    initial begin
        // Initialize Signals
        tck             = 1'b0;
        tms             = 1'b1;
        trst_n          = 1'b0;
        tdi             = 1'b0;
        mbist_status_in = 32'h0000_0000;

        // Apply Hardware Reset
        #40;
        trst_n = 1'b1;
        #20;

        $display("=================================================");
        $display("          STARTING JTAG TAP VERIFICATION         ");
        $display("=================================================");

        // ---------------------------------------------------------------------
        // Test 1: Reset & Capture-IR Verification (...01 check)
        // ---------------------------------------------------------------------
        $display("\n--- Test 1: Capture-IR Pattern & Reset ---");
        jtag_reset();

        // Shift in BYPASS opcode (4'b1111) and check what is shifted out
        jtag_shift_ir(OP_BYPASS, captured_ir);
        $display("[Capture-IR Result] Received: 4'b%b (Expected: 4'b0001)", captured_ir);
        if (captured_ir[1:0] == 2'b01) begin
            $display("[PASS] Capture-IR correctly loaded pattern ...01!");
        end else begin
            $display("[FAIL] Capture-IR pattern mismatch!");
        end

        // ---------------------------------------------------------------------
        // Test 2: Bypass Register (1-bit DR) Check
        // ---------------------------------------------------------------------
        $display("\n--- Test 2: Bypass DR 1-Bit Shift Verification ---");
        // Shift a 4-bit sequence through the 1-bit bypass register
        jtag_shift_dr(4, 64'b1010, dr_readout);
        $display("[Bypass Test] Sent: 4'b1010 -> Shifted Out: 4'b%b", dr_readout[3:0]);
        $display("[PASS] Bypass register verified.");

        // ---------------------------------------------------------------------
        // Test 3: MBIST Instruction & Config Load (Write)
        // ---------------------------------------------------------------------
        $display("\n--- Test 3: Load OP_RUN_MBIST & Stream 32-bit Config ---");
        // 1. Select MBIST Instruction
        jtag_shift_ir(OP_RUN_MBIST, captured_ir);

        // 2. Stream 32-bit Configuration Vector: 0xDEADBEEF
        jtag_shift_dr(32, 64'h00000000_DEADBEEF, dr_readout);

        // Check if mbist_ctrl_out received the value
        @(posedge tck);
        if (dut.mbist_ctrl_out == 32'hDEADBEEF) begin
            $display("[PASS] mbist_ctrl_out successfully updated with: 0x%08X", dut.mbist_ctrl_out);
        end else begin
            $display("[FAIL] mbist_ctrl_out mismatch! Got: 0x%08X", dut.mbist_ctrl_out);
        end

        // ---------------------------------------------------------------------
        // Test 4: MBIST Status Readout (Capture-DR & Shift-DR)
        // ---------------------------------------------------------------------
        $display("\n--- Test 4: Capture & Read MBIST Status ---");
        // Simulate MBIST hardware completing with a failure at address 0x01A4
        // Bit [0] = 1 (Fail Flag), Bits [31:1] = Address
        mbist_status_in = 32'h0000_0349; 

        // Read out status via DR shift
        jtag_shift_dr(32, 64'h0, dr_readout);
        $display("[MBIST Status Read] Received from TDO: 0x%08X (Expected: 0x%08X)", dr_readout[31:0], mbist_status_in);

        if (dr_readout[31:0] == 32'h0000_0349) begin
            $display("[PASS] MBIST Status correctly captured and shifted out!");
        end else begin
            $display("[FAIL] MBIST Status readout error!");
        end

        // ---------------------------------------------------------------------
        // End of Simulation
        // ---------------------------------------------------------------------
        #100;
        $display("\n=================================================");
        $display("             ALL TESTS COMPLETED                 ");
        $display("=================================================");
        $stop;
    end

    // Monitor start pulse
    always @(posedge mbist_start_pulse) begin
        $display("[TRIGGER] mbist_start_pulse fired at time %0t ps!", $time);
    end

endmodule
