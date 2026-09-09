`timescale 1ns / 1ps

module tb_mbist;

    // Parameters
    localparam ADDR_WIDTH = 8;
    localparam DATA_WIDTH = 8;
    localparam CLK_PERIOD = 10; // 100 MHz clock

    // Testbench Signals
    reg                   clk;
    reg                   rst_n;
    reg                   start;
    reg                   inject_fault;
    wire                  done;
    wire                  fail;
    wire [ADDR_WIDTH-1:0] mem_addr;
    wire [DATA_WIDTH-1:0] mem_wdata;
    wire [DATA_WIDTH-1:0] mem_rdata;
    wire                  mem_we_n;
    wire                  mem_ce_n;
    wire [ADDR_WIDTH-1:0] rfail_addr;

    // Instantiate MBIST Controller
    MBIST #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_mbist (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .mem_rdata  (mem_rdata),
        .done       (done),
        .fail       (fail),
        .mem_addr   (mem_addr),
        .mem_wdata  (mem_wdata),
        .mem_we_n   (mem_we_n),
        .mem_ce_n   (mem_ce_n),
        .rfail_addr (rfail_addr)
    );

    // Instantiate SRAM Model with Hardware Fault Injection
    sram_model #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_sram (
        .clk          (clk),
        .ce_n         (mem_ce_n),
        .we_n         (mem_we_n),
        .addr         (mem_addr),
        .wdata        (mem_wdata),
        .inject_fault (inject_fault),
        .rdata        (mem_rdata)
    );

    // Clock Generation (Runs continuously)
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Main Verification Flow
    initial begin
        // Signal Initialization
        clk          = 0;
        rst_n        = 0;
        start        = 0;
        inject_fault = 0;

        $display("------------------------------------------------------------");
        $display("Starting MBIST Simulation Verification (March C- Algorithm)...");
        $display("------------------------------------------------------------");

        // Apply Reset
        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        // ==========================================================
        // Testcase 1: Good Memory Run (Golden Run, Expect PASS)
        // ==========================================================
        $display("[TC1] Running March C- on Fault-Free SRAM...");
        inject_fault = 0;
        start        = 1; // Assert and hold start active

        // Wait until MBIST completes
        @(posedge done);
        #(CLK_PERIOD * 10); // Hold in DONE state for clear visibility in waveforms

        if (fail === 1'b0) begin
            $display("[TC1 RESULT] SUCCESS: Memory test PASSED (done=1, fail=0)");
        end 
        else begin
            $display("[TC1 RESULT] FAILED: Expected fail=0, got fail=1 (rfail_addr = 0x%0h)", rfail_addr);
        end

        // Deassert start to allow FSM to return to IDLE
        start = 0;
        #(CLK_PERIOD * 10);

        // ==========================================================
        // Testcase 2: Hardware Stuck-at-1 Fault Run (Expect FAIL)
        // ==========================================================
        $display("------------------------------------------------------------");
        $display("[TC2] Running March C- with Hardware Stuck-at-1 Fault active at 0x2A...");
        
        inject_fault = 1; // Enable persistent hardware fault at address 0x2A
        start        = 1; // Assert and hold start active

        // Wait until MBIST completes
        @(posedge done);
        #(CLK_PERIOD * 10); // Hold in DONE state for clear visibility in waveforms

        if (fail === 1'b1 && rfail_addr === 8'h2A) begin
            $display("[TC2 RESULT] SUCCESS: Fault detected at correct address 0x%0h!", rfail_addr);
        end 
        else begin
            $display("[TC2 RESULT] FAILED: fail=%0b, rfail_addr=0x%0h (Expected addr: 0x2A)", fail, rfail_addr);
        end

        // Deassert start to allow FSM to return to IDLE
        start = 0;
        #(CLK_PERIOD * 10);

        $display("------------------------------------------------------------");
        $display("Verification Complete. Clock continues running for waveform analysis.");
        $display("------------------------------------------------------------");
    end

endmodule
