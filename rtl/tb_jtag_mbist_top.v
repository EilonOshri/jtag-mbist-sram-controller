`timescale 1ns / 1ps

module tb_jtag_mbist_top;

    // Parameters
    localparam ADDR_WIDTH   = 8;
    localparam DATA_WIDTH   = 8;
    localparam IR_LEN       = 4;
    localparam MBIST_DR_LEN = 32;

    // Clock periods
    localparam SYS_CLK_PERIOD = 10;  // 100 MHz System Clock
    localparam TCK_PERIOD     = 100; // 10 MHz JTAG Test Clock

    // JTAG Instructions
    localparam [IR_LEN-1:0] OP_MBIST_RUN = 4'b0011;
    localparam [IR_LEN-1:0] OP_BYPASS    = 4'b1111;

    // Testbench Signals
    reg                     clk;
    reg                     rst_n;
    reg                     tck;
    reg                     tms;
    reg                     trst_n;
    reg                     tdi;
    wire                    tdo;
    reg                     inject_fault;

    // Functional Interface (tied off during BIST test)
    reg                     func_ce_n;
    reg                     func_we_n;
    reg  [ADDR_WIDTH-1:0]   func_addr;
    reg  [DATA_WIDTH-1:0]   func_wdata;
    wire [DATA_WIDTH-1:0]   func_rdata;

    // Shift registers for TB verification
    reg [MBIST_DR_LEN-1:0]  dr_readout;

    // Instantiate Top-Level Design Under Test
    jtag_mbist_top #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .IR_LEN       (IR_LEN),
        .MBIST_DR_LEN (MBIST_DR_LEN)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .tck          (tck),
        .tms          (tms),
        .trst_n       (trst_n),
        .tdi          (tdi),
        .tdo          (tdo),
        .inject_fault (inject_fault),
        .func_ce_n    (func_ce_n),
        .func_we_n    (func_we_n),
        .func_addr    (func_addr),
        .func_wdata   (func_wdata),
        .func_rdata   (func_rdata)
    );

    // Continuous System and JTAG Clock Generation
    always #(SYS_CLK_PERIOD / 2) clk = ~clk;
    always #(TCK_PERIOD / 2)     tck = ~tck;

    // =========================================================================
    // JTAG Tasks (IEEE 1149.1 Standard Navigation)
    // =========================================================================

    // Reset TAP Controller to Test-Logic-Reset, then transition to Run-Test/Idle
    task tap_reset;
        begin
            trst_n = 1'b0;
            tms    = 1'b1;
            tdi    = 1'b0;
            #(TCK_PERIOD * 3);
            trst_n = 1'b1;
            #(TCK_PERIOD * 2);

            // 5 TCK cycles with TMS=1 guarantees TEST_LOGIC_RESET
            repeat (5) @(negedge tck);

            // Move to RUN_TEST_IDLE (TMS: 0)
            @(negedge tck) tms = 1'b0;
            @(negedge tck);
        end
    endtask

    // Shift an Instruction into the IR (assumes start at RUN_TEST_IDLE)
    task shift_ir;
        input [IR_LEN-1:0] opcode;
        integer i;
        begin
            // Move: RUN_TEST_IDLE -> SELECT_DR_SCAN -> SELECT_IR_SCAN
            @(negedge tck) tms = 1'b1;
            @(negedge tck) tms = 1'b1;
            // Move: SELECT_IR_SCAN -> CAPTURE_IR -> SHIFT_IR
            @(negedge tck) tms = 1'b0;
            @(negedge tck) tms = 1'b0;

            // Shift bits [0] up to [IR_LEN-2] with TMS=0
            for (i = 0; i < IR_LEN - 1; i = i + 1) begin
                @(negedge tck);
                tdi = opcode[i];
                tms = 1'b0;
            end

            // Shift last bit [IR_LEN-1] with TMS=1 (Transition to EXIT1_IR)
            @(negedge tck);
            tdi = opcode[IR_LEN-1];
            tms = 1'b1;

            // Move: EXIT1_IR -> UPDATE_IR -> RUN_TEST_IDLE
            @(negedge tck) tms = 1'b1;
            @(negedge tck) tms = 1'b0;
            @(negedge tck);
        end
    endtask

    // Write a 32-bit vector into Data Register (assumes start at RUN_TEST_IDLE)
    task write_dr;
        input [MBIST_DR_LEN-1:0] din;
        integer i;
        begin
            // Move: RUN_TEST_IDLE -> SELECT_DR_SCAN -> CAPTURE_DR -> SHIFT_DR
            @(negedge tck) tms = 1'b1;
            @(negedge tck) tms = 1'b0;
            @(negedge tck) tms = 1'b0;

            // Shift bits [0] to [30] with TMS=0
            for (i = 0; i < MBIST_DR_LEN - 1; i = i + 1) begin
                @(negedge tck);
                tdi = din[i];
                tms = 1'b0;
            end

            // Shift last bit [31] with TMS=1 (Transition to EXIT1_DR)
            @(negedge tck);
            tdi = din[MBIST_DR_LEN-1];
            tms = 1'b1;

            // Move: EXIT1_DR -> UPDATE_DR -> RUN_TEST_IDLE
            @(negedge tck) tms = 1'b1;
            @(negedge tck) tms = 1'b0;
            @(negedge tck);
        end
    endtask

    // Read 32-bit Data Register out via TDO (assumes start at RUN_TEST_IDLE)
    task read_dr;
        output [MBIST_DR_LEN-1:0] dout;
        integer i;
        begin
            // Move: RUN_TEST_IDLE -> SELECT_DR_SCAN -> CAPTURE_DR -> SHIFT_DR
            @(negedge tck) tms = 1'b1;
            @(negedge tck) tms = 1'b0;
            @(negedge tck) tms = 1'b0;

            // Shift out bits [0] to [30]
            for (i = 0; i < MBIST_DR_LEN - 1; i = i + 1) begin
                @(posedge tck);
                dout[i] = tdo;
                @(negedge tck);
                tms = 1'b0;
                tdi = 1'b0;
            end

            // Shift out last bit [31] with TMS=1 (Transition to EXIT1_DR)
            @(posedge tck);
            dout[MBIST_DR_LEN-1] = tdo;
            @(negedge tck);
            tms = 1'b1;
            tdi = 1'b0;

            // Move: EXIT1_DR -> UPDATE_DR -> RUN_TEST_IDLE
            @(negedge tck) tms = 1'b1;
            @(negedge tck) tms = 1'b0;
            @(negedge tck);
        end
    endtask

    // =========================================================================
    // Main Verification Flow
    // =========================================================================
    initial begin
        // Signal Initialization
        clk          = 1'b0;
        rst_n        = 1'b0;
        tck          = 1'b0;
        tms          = 1'b1;
        trst_n       = 1'b0;
        tdi          = 1'b0;
        inject_fault = 1'b0;
        func_ce_n    = 1'b1;
        func_we_n    = 1'b1;
        func_addr    = {ADDR_WIDTH{1'b0}};
        func_wdata   = {DATA_WIDTH{1'b0}};
        dr_readout   = {MBIST_DR_LEN{1'b0}};

        $display("============================================================");
        $display("Starting Top-Level JTAG-MBIST Integration Verification");
        $display("============================================================");

        // System Asynchronous Reset
        #(SYS_CLK_PERIOD * 3);
        rst_n = 1'b1;
        #(SYS_CLK_PERIOD * 2);

        // Reset TAP Controller
        tap_reset();

        // =====================================================================
        // Testcase 1: Golden Run (inject_fault = 0 -> Expect PASS via TDO)
        // =====================================================================
        $display("\n[TC1] Configuring JTAG for MBIST Golden Run (No Fault)...");
        inject_fault = 1'b0;

        // Step 1: Load MBIST_RUN instruction into IR
        shift_ir(OP_MBIST_RUN);

        // Step 2: Trigger MBIST by writing start bit to Data Register (bit[0]=1)
        write_dr(32'h0000_0001);

        // Step 3: Clear start trigger bit so BIST returns to IDLE upon finish
        write_dr(32'h0000_0000);

        // Step 4: Wait for MBIST to execute March C- in RUN_TEST_IDLE state
        $display("[TC1] Waiting for MBIST execution to complete...");
        @(posedge dut.mbist_done);
        #(SYS_CLK_PERIOD * 20);

        // Step 5: Read Status Register through JTAG TDO
        read_dr(dr_readout);

        $display("[TC1] JTAG DR Readout: 0x%08h", dr_readout);
        $display("[TC1] Decoded Status -> done: %0b, fail: %0b, rfail_addr: 0x%02h", 
                 dr_readout[0], dr_readout[1], dr_readout[9:2]);

        if (dr_readout[0] === 1'b1 && dr_readout[1] === 1'b0) begin
            $display("[TC1 RESULT] SUCCESS: Golden Run PASSED via JTAG interface!");
        end else begin
            $display("[TC1 RESULT] FAILED: Expected done=1, fail=0. Got done=%0b, fail=%0b", 
                     dr_readout[0], dr_readout[1]);
        end

        #(TCK_PERIOD * 10);

        // =====================================================================
        // Testcase 2: Fault Injection Run (inject_fault = 1 -> Expect FAIL @ 0x2A)
        // =====================================================================
        $display("\n------------------------------------------------------------");
        $display("[TC2] Configuring JTAG for MBIST Run with Fault Active at 0x2A...");
        inject_fault = 1'b1;

        // Step 1: Ensure MBIST_RUN instruction is loaded
        shift_ir(OP_MBIST_RUN);

        // Step 2: Trigger MBIST by writing start bit to Data Register (bit[0]=1)
        write_dr(32'h0000_0001);

        // Step 3: Clear start trigger bit
        write_dr(32'h0000_0000);

        // Step 4: Wait for MBIST to execute and capture failure
        $display("[TC2] Waiting for MBIST execution to complete...");
        @(posedge dut.mbist_done);
        #(SYS_CLK_PERIOD * 20);

        // Step 5: Read Status Register through JTAG TDO
        read_dr(dr_readout);

        $display("[TC2] JTAG DR Readout: 0x%08h", dr_readout);
        $display("[TC2] Decoded Status -> done: %0b, fail: %0b, rfail_addr: 0x%02h", 
                 dr_readout[0], dr_readout[1], dr_readout[9:2]);

        if (dr_readout[0] === 1'b1 && dr_readout[1] === 1'b1 && dr_readout[9:2] === 8'h2A) begin
            $display("[TC2 RESULT] SUCCESS: Fault caught and reported correctly via JTAG! (Addr: 0x2A)");
        end else begin
            $display("[TC2 RESULT] FAILED: Expected fail=1 and rfail_addr=0x2A. Got fail=%0b, rfail_addr=0x%02h", 
                     dr_readout[1], dr_readout[9:2]);
        end

        $display("============================================================");
        $display("JTAG Top-Level Verification Complete.");
        $display("============================================================");
    end

endmodule
