`timescale 1ns / 1ps

module tb_SRAM;

    // Parameters
    parameter ADDR_WIDTH = 8;
    parameter DATA_WIDTH = 8;

    // Testbench Signals
    reg                   clk;
    reg                   ce_n;
    reg                   we_n;
    reg  [ADDR_WIDTH-1:0] addr;
    reg  [DATA_WIDTH-1:0] wdata;
    wire [DATA_WIDTH-1:0] rdata;

    // Instantiate DUT (Device Under Test)
    SRAM #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk   (clk),
        .ce_n  (ce_n),
        .we_n  (we_n),
        .addr  (addr),
        .wdata (wdata),
        .rdata (rdata)
    );

    // Clock Generator: 50 MHz (Period = 20ns)
    always #10 clk = ~clk;

    // --- Helper Task: Write to Memory ---
    task sram_write(input [ADDR_WIDTH-1:0] wr_addr, input [DATA_WIDTH-1:0] wr_data);
        begin
            @(posedge clk);
            ce_n  <= 1'b0;
            we_n  <= 1'b0;
            addr  <= wr_addr;
            wdata <= wr_data;
        end
    endtask

    // --- Helper Task: Read and Check Memory ---
    task sram_read_and_check(input [ADDR_WIDTH-1:0] rd_addr, input [DATA_WIDTH-1:0] expected_data);
        begin
            @(posedge clk);
            ce_n <= 1'b0;
            we_n <= 1'b1;
            addr <= rd_addr;

            // Wait 1 clock cycle for synchronous read latency
            @(posedge clk);
            #1; // Sample shortly after clock edge
            if (rdata === expected_data) begin
                $display("[PASS] Addr: 0x%02h | Read: 0x%02h | Expected: 0x%02h", rd_addr, rdata, expected_data);
            end else begin
                $display("[FAIL] Addr: 0x%02h | Read: 0x%02h | Expected: 0x%02h", rd_addr, rdata, expected_data);
            end
        end
    endtask

    // --- Test Sequence ---
    initial begin
        // 1. Initialize Inputs
        clk   = 0;
        ce_n  = 1;
        we_n  = 1;
        addr  = 0;
        wdata = 0;

        #30;

        // 2. Test Write Sequence
        $display("--- Starting Write Operations ---");
        sram_write(8'h00, 8'hAA); // Write 0xAA to address 0x00
        sram_write(8'h01, 8'h55); // Write 0x55 to address 0x01
        sram_write(8'hFF, 8'hC3); // Write 0xC3 to address 0xFF

        // Disable memory for a cycle (Idle)
        @(posedge clk);
        ce_n <= 1'b1;
        we_n <= 1'b1;
        #20;

        // 3. Test Read & Verify Sequence
        $display("--- Starting Read & Verify Operations ---");
        sram_read_and_check(8'h00, 8'hAA);
        sram_read_and_check(8'h01, 8'h55);
        sram_read_and_check(8'hFF, 8'hC3);

        // 4. Test Chip Disable (ce_n = 1)
        @(posedge clk);
        ce_n <= 1'b1;
        we_n <= 1'b1;
        addr <= 8'h00;
        @(posedge clk);
        #1;
        $display("--- Testing Chip Disable ---");
        $display("[INFO] Memory disabled, rdata holds previous value: 0x%02h", rdata);

        #50;
        $display("--- SRAM Simulation Finished ---");
        $stop;
    end

endmodule
