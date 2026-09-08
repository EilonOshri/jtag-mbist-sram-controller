`timescale 1ns / 1ps

module tb_jtag_mbist_top;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam ADDR_WIDTH   = 8;
    localparam DATA_WIDTH   = 8;
    localparam IR_LEN       = 4;
    localparam MBIST_DR_LEN = 32;

    // JTAG Opcodes
    localparam [IR_LEN-1:0] OP_RUN_MBIST = 4'b0010;
    localparam [IR_LEN-1:0] OP_BYPASS    = 4'b1111;

    // Clock Periods
    localparam CLK_PERIOD = 10; // System Clock: 100 MHz (10ns)
    localparam TCK_PERIOD = 40; // JTAG TCK:      25 MHz  (40ns - Asynchronous / Slower)

    // =========================================================================
    // DUT Signals
    // =========================================================================
    // Clocks and Resets
    reg  clk;
    reg  rst_n;
    reg  tck;
    reg  tms;
    reg  trst_n;
    reg  tdi;
    wire tdo;

    // Functional Interface
    reg                   func_ce_n;
    reg                   func_we_n;
    reg  [ADDR_WIDTH-1:0] func_addr;
    reg  [DATA_WIDTH-1:0] func_wdata;
    wire [DATA_WIDTH-1:0] func_rdata;

    // Testbench Variables
    reg [MBIST_DR_LEN-1:0] captured_status;

    // =========================================================================
    // Device Under Test (DUT) Instantiation
    // =========================================================================
    jtag_mbist_top #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .IR_LEN       (IR_LEN),
        .MBIST_DR_LEN (MBIST_DR_LEN)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .tck        (tck),
        .tms        (tms),
        .trst_n     (trst_n),
        .tdi        (tdi),
        .tdo        (tdo),
        .func_ce_n  (func_ce_n),
        .func_we_n  (func_we_n),
        .func_addr  (func_addr),
        .func_wdata (func_wdata),
        .func_rdata (func_rdata)
    );

    // =========================================================================
    // Clock Generators
    // =========================================================================
    // System Clock (100 MHz)
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // JTAG Test Clock (25 MHz)
    initial tck = 1'b0;
    always #(TCK_PERIOD / 2) tck = ~tck;

    // =========================================================================
    // JTAG Driver Tasks (TAP Master Emulation)
    // =========================================================================

    // Task 1: Reset the TAP FSM to Test-Logic-Reset (TLR) using 5 consecutive TMS=1
    task tap_reset();
        integer i;
        begin
            tms = 1'b1;
            tdi = 1'b0;
            for (i = 0; i < 5; i = i + 1) begin
                @(posedge tck);
            end
            // Move from Test-Logic-Reset to Run-Test/Idle
            #(TCK_PERIOD * 0.2);
            tms = 1'b0;
            @(posedge tck);
            #(TCK_PERIOD * 0.2);
        end
    endtask

    // Task 2: Shift an Instruction into the IR (Shift-IR -> Update-IR -> Run-Test/Idle)
    task shift_ir(input [IR_LEN-1:0] opcode);
        integer i;
        begin
            // Navigate: Run-Test/Idle -> Select-DR-Scan (TMS=1) -> Select-IR-Scan (TMS=1)
            #(TCK_PERIOD * 0.2); tms = 1'b1; @(posedge tck);
            #(TCK_PERIOD * 0.2); tms = 1'b1; @(posedge tck);
            
            // Navigate: Select-IR-Scan -> Capture-IR (TMS=0) -> Shift-IR (TMS=0)
            #(TCK_PERIOD * 0.2); tms = 1'b0; @(posedge tck);
            #(TCK_PERIOD * 0.2); tms = 1'b0; @(posedge tck);

            // Shift Opcode bits (LSB first). On the last bit, assert TMS=1 to go to Exit1-IR
            for (i = 0; i < IR_LEN; i = i + 1) begin
                #(TCK_PERIOD * 0.2);
                tdi = opcode[i];
                if (i == IR_LEN - 1)
                    tms = 1'b1; // Last bit moves to Exit1-IR
                else
                    tms = 1'b0;
                @(posedge tck);
            end

            // Navigate: Exit1-IR -> Update-IR (TMS=1)
            #(TCK_PERIOD * 0.2); tms = 1'b1; @(posedge tck);

            // Navigate: Update-IR -> Run-Test/Idle (TMS=0)
            #(TCK_PERIOD * 0.2); tms = 1'b0; @(posedge tck);
            tdi = 1'b0;
        end
    endtask

    // Task 3: Shift Data into DR and Capture Data out from TDO
    task shift_dr(
        input  [MBIST_DR_LEN-1:0] din,
        output [MBIST_DR_LEN-1:0] dout
    );
        integer i;
        begin
            // Navigate: Run-Test/Idle -> Select-DR-Scan (TMS=1)
            #(TCK_PERIOD * 0.2); tms = 1'b1; @(posedge tck);

            // Navigate: Select-DR-Scan -> Capture-DR (TMS=0) -> Shift-DR (TMS=0)
            #(TCK_PERIOD * 0.2); tms = 1'b0; @(posedge tck);
            #(TCK_PERIOD * 0.2); tms = 1'b0; @(posedge tck);

            // Shift DR bits (LSB first). Sample TDO on negedge / stable region
            for (i = 0; i < MBIST_DR_LEN; i = i + 1) begin
                #(TCK_PERIOD * 0.2);
                tdi = din[i];
                if (i == MBIST_DR_LEN - 1)
                    tms = 1'b1; // Last bit moves to Exit1-DR
                else
                    tms = 1'b0;

                // Sample TDO on falling edge of TCK (IEEE 1149.1 TDO changes on negedge TCK)
                @(negedge tck);
                dout[i] = tdo;
                @(posedge tck);
            end

            // Navigate: Exit1-DR -> Update-DR (TMS=1)
            #(TCK_PERIOD * 0.2); tms = 1'b1; @(posedge tck);

            // Navigate: Update-DR -> Run-Test/Idle (TMS=0)
            #(TCK_PERIOD * 0.2); tms = 1'b0; @(posedge tck);
            tdi = 1'b0;
        end
    endtask

    // =========================================================================
    // Main Test Execution Flow
    // =========================================================================
    initial begin
        $display("=================================================================");
        $display("       STARTING JTAG-MBIST SYSTEM-LEVEL VERIFICATION            ");
        $display("=================================================================");

        // 1. Initial State & Hardware Reset
        rst_n       = 1'b0;
        trst_n      = 1'b0;
        tms         = 1'b1;
        tdi         = 1'b0;
        func_ce_n   = 1'b1;
        func_we_n   = 1'b1;
        func_addr   = {ADDR_WIDTH{1'b0}};
        func_wdata  = {DATA_WIDTH{1'b0}};

        #(CLK_PERIOD * 5);
        rst_n  = 1'b1;
        trst_n = 1'b1;
        #(CLK_PERIOD * 5);

        // Put TAP controller into Run-Test/Idle state
        tap_reset();
        $display("[STATUS] System & TAP Controller Reset completed successfully.");

        // =====================================================================
        // TEST 1: Golden Run (Clean Memory -> Expected PASS)
        // =====================================================================
        $display("\n--- [TEST 1] Starting MBIST on Clean Memory (Expecting PASS) ---");

        // Load RUN_MBIST opcode into JTAG IR
        shift_ir(OP_RUN_MBIST);
        $display("[JTAG] Loaded OP_RUN_MBIST (4'b0010) into IR.");

        // Trigger MBIST execution by shifting 32'h00000001 (bit 0 = start) into MBIST DR
        shift_dr(32'h0000_0001, captured_status);
        $display("[JTAG] Shifted Start pulse via Update-DR. MBIST is now running...");

        // Wait for MBIST to complete (March C- requires approx ~2000-3000 clock cycles)
        wait(dut.mbist_done == 1'b1);
        $display("[MBIST] Execution completed! mbist_done asserted.");
        #(CLK_PERIOD * 10);

        // Shift out the MBIST 32-bit Status Register through TDO
        shift_dr(32'h0000_0000, captured_status);

        $display("[JTAG TDO Output] Captured Status Word: 32'h%08X", captured_status);
        $display("  -> Done Flag      : %b", captured_status[0]);
        $display("  -> Fail Flag      : %b", captured_status[1]);
        $display("  -> Failing Address: 0x%02X", captured_status[9:2]);

        // Self-Checking Verification
        if (captured_status[0] == 1'b1 && captured_status[1] == 1'b0) begin
            $display("[TEST 1 PASSED] Memory is fully functional! Zero faults found.");
        end else begin
            $display("[TEST 1 FAILED] Expected Pass, but received Fail!");
            $stop;
        end

        // Return to Idle and let the system settle
        tap_reset();
        #(CLK_PERIOD * 20);

        // =====================================================================
        // TEST 2: Fault Injection Run (Inject Fault -> Expected FAIL)
        // =====================================================================
        $display("\n--- [TEST 2] Injecting Fault into SRAM (Expecting FAIL) ---");

        // Inject a stuck bit at Address 8'h2A using hierarchical backdoor access
        // (Simulating a physical manufacturing defect in cell 0x2A)
        dut.u_sram.mem[8'h2A] = 8'hAA; 
        $display("[FAULT INJECTION] Corrupted memory address 0x2A with value 0xAA.");

        // Re-arm and launch MBIST via JTAG
        shift_ir(OP_RUN_MBIST);
        shift_dr(32'h0000_0001, captured_status);
        $display("[JTAG] Launched MBIST verification run...");

        // Wait for MBIST to complete
        wait(dut.mbist_done == 1'b1);
        $display("[MBIST] Execution completed! Reading diagnostic status...");
        #(CLK_PERIOD * 10);

        // Read out status through JTAG TDO
        shift_dr(32'h0000_0000, captured_status);

        $display("[JTAG TDO Output] Captured Status Word: 32'h%08X", captured_status);
        $display("  -> Done Flag      : %b", captured_status[0]);
        $display("  -> Fail Flag      : %b", captured_status[1]);
        $display("  -> Failing Address: 0x%02X", captured_status[9:2]);

        // Self-Checking Verification
        if (captured_status[0] == 1'b1 && captured_status[1] == 1'b1 && captured_status[9:2] == 8'h2A) begin
            $display("[TEST 2 PASSED] MBIST successfully caught defect at address 0x%02X!", captured_status[9:2]);
        end else begin
            $display("[TEST 2 FAILED] Fault was not detected accurately!");
            $stop;
        end

        $display("\n=================================================================");
        $display("   ALL SYSTEM-LEVEL TESTS COMPLETED SUCCESSFULLY (100%% PASS)   ");
        $display("=================================================================\n");
        $finish;
    end

endmodule
