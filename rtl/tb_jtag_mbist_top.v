`timescale 1ns / 1ps

module tb_jtag_mbist_top;

    // =========================================================================
    // Parameters & Clock Configurations
    // =========================================================================
    localparam ADDR_WIDTH   = 8;
    localparam DATA_WIDTH   = 8;
    localparam IR_LEN       = 4;
    localparam MBIST_DR_LEN = 32;

    // JTAG Instruction Opcodes
    localparam [IR_LEN-1:0] OP_RUN_MBIST = 4'b0010;
    localparam [IR_LEN-1:0] OP_BYPASS    = 4'b1111;
    localparam [IR_LEN-1:0] OP_UNKNOWN   = 4'b0101; // Test default bypass behavior

    // System Clock: 100 MHz (Period = 10ns)
    // JTAG Clock:   20 MHz  (Period = 50ns, async CDC verification)
    localparam CLK_PERIOD = 10;
    localparam TCK_PERIOD = 50;

    // =========================================================================
    // Signals
    // =========================================================================
    reg                     clk;
    reg                     rst_n;

    reg                     tck;
    reg                     tms;
    reg                     trst_n;
    reg                     tdi;
    wire                    tdo;

    reg                     inject_fault;

    reg                     func_ce_n;
    reg                     func_we_n;
    reg  [ADDR_WIDTH-1:0]   func_addr;
    reg  [DATA_WIDTH-1:0]   func_wdata;
    wire [DATA_WIDTH-1:0]   func_rdata;

    // Test tracking
    integer error_count = 0;
    reg [IR_LEN-1:0]       ir_capture;
    reg [MBIST_DR_LEN-1:0] dr_capture;

    // =========================================================================
    // Device Under Test (DUT)
    // =========================================================================
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

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    initial begin
        tck = 1'b0;
        forever #(TCK_PERIOD / 2) tck = ~tck;
    end

    // =========================================================================
    // JTAG Driver Tasks (IEEE 1149.1 Compliant Navigation)
    // =========================================================================

    // Test-Logic-Reset: 5 consecutive TCK cycles with TMS=1
    task jtag_reset_tlr;
        integer i;
        begin
            @(negedge tck);
            tms = 1'b1;
            tdi = 1'b0;
            for (i = 0; i < 6; i = i + 1) begin
                @(negedge tck);
            end
            // Transition to Run-Test/Idle
            tms = 1'b0;
            @(negedge tck);
        end
    endtask

    // Instruction Register (IR) Scan: LSB-first
    task jtag_shift_ir;
        input  [IR_LEN-1:0] ir_in;
        output [IR_LEN-1:0] ir_out;
        integer i;
        begin
            // Idle -> Select-DR-Scan -> Select-IR-Scan
            @(negedge tck) tms = 1'b1;
            @(negedge tck) tms = 1'b1;
            // Select-IR-Scan -> Capture-IR -> Shift-IR
            @(negedge tck) tms = 1'b0;
            @(negedge tck) tms = 1'b0;

            // Shift IR
            for (i = 0; i < IR_LEN; i = i + 1) begin
                @(negedge tck);
                tdi = ir_in[i];
                tms = (i == IR_LEN - 1) ? 1'b1 : 1'b0; // Exit1-IR on MSB
                @(posedge tck);
                #1;
                ir_out[i] = tdo;
            end

            // Exit1-IR -> Update-IR -> Run-Test/Idle
            @(negedge tck) tms = 1'b1;
            @(negedge tck) tms = 1'b0;
        end
    endtask

    // Data Register (DR) Scan: LSB-first
    task jtag_shift_dr;
        input  [MBIST_DR_LEN-1:0] dr_in;
        output [MBIST_DR_LEN-1:0] dr_out;
        integer i;
        begin
            // Idle -> Select-DR-Scan -> Capture-DR -> Shift-DR
            @(negedge tck) tms = 1'b1;
            @(negedge tck) tms = 1'b0;
            @(negedge tck) tms = 1'b0;

            // Shift DR
            for (i = 0; i < MBIST_DR_LEN; i = i + 1) begin
                @(negedge tck);
                tdi = dr_in[i];
                tms = (i == MBIST_DR_LEN - 1) ? 1'b1 : 1'b0; // Exit1-DR on MSB
                @(posedge tck);
                #1;
                dr_out[i] = tdo;
            end

            // Exit1-DR -> Update-DR -> Run-Test/Idle
            @(negedge tck) tms = 1'b1;
            @(negedge tck) tms = 1'b0;
        end
    endtask

    // Shift 1-bit Bypass Register
    task jtag_shift_bypass;
        input  reg bit_in;
        output reg bit_out;
        begin
            @(negedge tck) tms = 1'b1; // Select-DR
            @(negedge tck) tms = 1'b0; // Capture-DR
            @(negedge tck) tms = 1'b0; // Shift-DR
            @(negedge tck);
            tdi = bit_in;
            tms = 1'b1; // Exit1-DR
            @(posedge tck);
            #1;
            bit_out = tdo;
            @(negedge tck) tms = 1'b1; // Update-DR
            @(negedge tck) tms = 1'b0; // Run-Test/Idle
        end
    endtask

    // =========================================================================
    // Functional Access Tasks
    // =========================================================================
    task func_write;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        begin
            @(posedge clk);
            func_ce_n  <= 1'b0;
            func_we_n  <= 1'b0;
            func_addr  <= addr;
            func_wdata <= data;
            @(posedge clk);
            func_ce_n  <= 1'b1;
            func_we_n  <= 1'b1;
        end
    endtask

    task func_read_check;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] exp_data;
        begin
            @(posedge clk);
            func_ce_n <= 1'b0;
            func_we_n <= 1'b1;
            func_addr <= addr;
            @(posedge clk);
            #1;
            if (func_rdata !== exp_data) begin
                $display("[FAIL][FUNC] Addr 0x%0h | Expected: 0x%0h, Got: 0x%0h", addr, exp_data, func_rdata);
                error_count = error_count + 1;
            end else begin
                $display("[PASS][FUNC] Addr 0x%0h | Matched Data: 0x%0h", addr, func_rdata);
            end
            func_ce_n <= 1'b1;
        end
    endtask

    // =========================================================================
    // Main Verification Procedure
    // =========================================================================
    integer poll_iter;
    reg bypass_val;

    initial begin
        // Signal Initializations
        rst_n        = 1'b0;
        trst_n       = 1'b0;
        tms          = 1'b1;
        tdi          = 1'b0;
        inject_fault = 1'b0;
        func_ce_n    = 1'b1;
        func_we_n    = 1'b1;
        func_addr    = {ADDR_WIDTH{1'b0}};
        func_wdata   = {DATA_WIDTH{1'b0}};

        // Reset Sequence
        #(CLK_PERIOD * 4);
        rst_n = 1'b1;
        #(TCK_PERIOD * 2);
        trst_n = 1'b1;
        jtag_reset_tlr();
        #(CLK_PERIOD * 5);

        $display("===================================================================");
        $display(" TEST 1: Functional Read/Write Operations (Pre-MBIST)");
        $display("===================================================================");
        func_write(8'h12, 8'h34);
        func_write(8'hAB, 8'hCD);
        func_read_check(8'h12, 8'h34);
        func_read_check(8'hAB, 8'hCD);

        $display("\n===================================================================");
        $display(" TEST 2: JTAG Bypass Mode & Unmapped Opcode Compliance");
        $display("===================================================================");
        // Test standard BYPASS opcode (0xF)
        jtag_shift_ir(OP_BYPASS, ir_capture);
        jtag_shift_bypass(1'b1, bypass_val);
        if (bypass_val !== 1'b0) begin // 1-cycle capture value of bypass is 0
            $display("[WARN] First bypass shift returned non-zero capture: %b", bypass_val);
        end
        jtag_shift_bypass(1'b1, bypass_val);
        if (bypass_val !== 1'b1) begin
            $display("[FAIL][BYPASS] Data did not shift through 1-bit Bypass register!");
            error_count = error_count + 1;
        end else begin
            $display("[PASS][BYPASS] Standard Bypass shifted successfully.");
        end

        // Test unallocated opcode routing to Bypass
        jtag_shift_ir(OP_UNKNOWN, ir_capture);
        jtag_shift_bypass(1'b1, bypass_val);
        jtag_shift_bypass(1'b1, bypass_val);
        if (bypass_val !== 1'b1) begin
            $display("[FAIL][BYPASS] Unallocated opcode did not route to Bypass register!");
            error_count = error_count + 1;
        end else begin
            $display("[PASS][BYPASS] Unallocated opcode properly routed to Bypass.");
        end

        $display("\n===================================================================");
        $display(" TEST 3: JTAG MBIST Execution - Clean SRAM (No Fault)");
        $display("===================================================================");
        // Load MBIST instruction
        jtag_shift_ir(OP_RUN_MBIST, ir_capture);

        // Assert Start command pulse: DR bit[0] = 1
        jtag_shift_dr(32'h0000_0001, dr_capture);

        // Polling loop: DR bit[0] = 0 (Query status without triggering new run)
        poll_iter = 0;
        dr_capture = 32'h0;
        while (dr_capture[0] !== 1'b1 && poll_iter < 3000) begin
            jtag_shift_dr(32'h0000_0000, dr_capture);
            poll_iter = poll_iter + 1;
        end

        $display("Polling completed in %0d JTAG DR reads.", poll_iter);
        $display("Status Register = 0x%08h (Done=%b, Fail=%b, FailAddr=0x%02h)", 
                 dr_capture, dr_capture[0], dr_capture[1], dr_capture[9:2]);

        if (dr_capture[0] === 1'b1 && dr_capture[1] === 1'b0) begin
            $display("[PASS][MBIST] Clean run passed with zero errors.");
        end else begin
            $display("[FAIL][MBIST] Clean run failed! Expected Done=1, Fail=0.");
            error_count = error_count + 1;
        end

        // Polling again to verify results are sticky and not cleared by read
        jtag_shift_dr(32'h0000_0000, dr_capture);
        if (dr_capture[0] !== 1'b1 || dr_capture[1] !== 1'b0) begin
            $display("[FAIL][MBIST] Status was unexpectedly cleared on consecutive read!");
            error_count = error_count + 1;
        end else begin
            $display("[PASS][MBIST] Status retention verified.");
        end

        $display("\n===================================================================");
        $display(" TEST 4: JTAG MBIST Execution - Injected Fault Verification");
        $display("===================================================================");
        inject_fault = 1'b1;

        // Trigger a new run with bit[0] = 1
        jtag_shift_dr(32'h0000_0001, dr_capture);

        poll_iter = 0;
        dr_capture = 32'h0;
        while (dr_capture[0] !== 1'b1 && poll_iter < 3000) begin
            jtag_shift_dr(32'h0000_0000, dr_capture);
            poll_iter = poll_iter + 1;
        end

        $display("Fault Run Finished in %0d JTAG DR reads.", poll_iter);
        $display("Status Register = 0x%08h (Done=%b, Fail=%b, FailAddr=0x%02h)", 
                 dr_capture, dr_capture[0], dr_capture[1], dr_capture[9:2]);

        // Expect: Done=1, Fail=1, First failing address = 0x2A
        if (dr_capture[0] === 1'b1 && dr_capture[1] === 1'b1 && dr_capture[9:2] === 8'h2A) begin
            $display("[PASS][MBIST] Injected fault detected correctly at address 0x2A!");
        end else begin
            $display("[FAIL][MBIST] Fault run failed! Expected Done=1, Fail=1, FailAddr=0x2A.");
            error_count = error_count + 1;
        end

        $display("\n===================================================================");
        $display(" TEST 5: Test-Logic-Reset (TLR) Functional Recovery Verification");
        $display("===================================================================");
        // Force TAP to TLR to verify test registers de-assert
        jtag_reset_tlr();
        inject_fault = 1'b0;

        // Verify SRAM functional read/write operates cleanly after MBIST
        func_write(8'h55, 8'hAA);
        func_read_check(8'h55, 8'hAA);

        // =====================================================================
        // Final Summary
        // =====================================================================
        #(CLK_PERIOD * 20);
        $display("\n===================================================================");
        if (error_count == 0) begin
            $display("                      ALL TESTS PASSED!                            ");
        end else begin
            $display("              TESTBENCH COMPLETED WITH %0d ERRORS!                  ", error_count);
        end
        $display("===================================================================\n");
        $finish;
    end

endmodule
