module jtag_mbist_top #(
    parameter ADDR_WIDTH   = 8,   // Memory address bus width (2^8 = 256 words)
    parameter DATA_WIDTH   = 8,   // Memory data bus width (8 bit word)
    parameter IR_LEN       = 4,   // JTAG Instruction Register length in bits
    parameter MBIST_DR_LEN = 32   // JTAG MBIST Data Register length in bits
)(
    // System Clock and Reset
    input  wire                  clk,        
    input  wire                  rst_n,    
  
    // IEEE 1149.1 JTAG Pins
    input  wire                  tck,        // Test Clock input
    input  wire                  tms,        // Test Mode Select input
    input  wire                  trst_n,     // Test Reset input (active-low)
    input  wire                  tdi,        // Test Data In serial input
    output wire                  tdo,        // Test Data Out serial output

    // Functional Memory Interface (Normal Operation Mode)
    input  wire                  func_ce_n,  // Functional chip enable (active-low)
    input  wire                  func_we_n,  // Functional write enable (active-low)
    input  wire [ADDR_WIDTH-1:0] func_addr,  // Functional memory address bus
    input  wire [DATA_WIDTH-1:0] func_wdata, // Functional memory write data bus
    output wire [DATA_WIDTH-1:0] func_rdata  // Functional memory read data bus
);

    // JTAG TAP Controller Interface Signals
    wire [MBIST_DR_LEN-1:0] mbist_status;      // Status vector sent to JTAG Capture-DR
    wire [MBIST_DR_LEN-1:0] mbist_ctrl;        // Control vector received from JTAG Update-DR
    wire                    mbist_start_pulse; // 1 cycle trigger pulse generated in Update-DR

    // MBIST Controller Control & Status Signals
    reg                     mbist_start_reg;   // Registered start signal to sustain execution
    wire                    mbist_start;       // Combined start signal to MBIST FSM
    wire                    mbist_done;        // Test completion flag from MBIST
    wire                    mbist_fail;        // Failure flag from MBIST
    wire [ADDR_WIDTH-1:0]   mbist_rfail_addr;  // Address of first detected fault

    // MBIST Memory Access Bus
    wire                    mbist_ce_n;        // MBIST memory chip enable
    wire                    mbist_we_n;        // MBIST memory write enable
    wire [ADDR_WIDTH-1:0]   mbist_addr;        // MBIST memory address output
    wire [DATA_WIDTH-1:0]   mbist_wdata;       // MBIST memory write data pattern
    wire [DATA_WIDTH-1:0]   sram_rdata;        // Read data directly from SRAM output

    // Multiplexed SRAM Inputs
    wire                    sram_ce_n;         // Final chip enable driven to SRAM
    wire                    sram_we_n;         // Final write enable driven to SRAM
    wire [ADDR_WIDTH-1:0]   sram_addr;         // Final address driven to SRAM
    wire [DATA_WIDTH-1:0]   sram_wdata;        // Final write data driven to SRAM

    // Test Mode Indicator
    wire                    test_mode;         // High when MBIST is running or holding status
  
////////////////////////////////////
// 1. JTAG TAP Controller Subsystem
///////////////////////////////////
  
    jtag_tap_top #(
        .IR_LEN       (IR_LEN),
        .MBIST_DR_LEN (MBIST_DR_LEN)
    ) u_jtag_tap (
        .tck               (tck),               // Connect external TCK
        .tms               (tms),               // Connect external TMS
        .trst_n            (trst_n),            // Connect external TRSTn
        .tdi               (tdi),               // Connect external TDI
        .tdo               (tdo),               // Connect external TDO
        .mbist_status_in   (mbist_status),      // Status input sampled in Capture-DR
        .mbist_ctrl_out    (mbist_ctrl),        // Control output latched in Update-DR
        .mbist_start_pulse (mbist_start_pulse)  // Pulse asserted on Update-DR transition
    );

    // Pack MBIST results into the 32 bit status register: [31:10] Padding, [9:2] Fail Addr, [1] Fail, [0] Done
    assign mbist_status = {
      {(MBIST_DR_LEN - 2 - ADDR_WIDTH){1'b0}}, // [31:10] Padding (22 bits)
        mbist_rfail_addr,                       // Store first failing address [9:2] (8 bits)
        mbist_fail,                             // Store fail status flag [1] (1 bit)
        mbist_done                              // Store completion status flag [0] (1 bit)
    };

    // Auto-clearing start register: asserts on Update-DR pulse, deasserts on completion
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mbist_start_reg <= 1'b0;             // Clear start register on system reset
        end
        else if (mbist_start_pulse) begin
            mbist_start_reg <= 1'b1;             // Set start register upon JTAG Update-DR pulse
        end
        else if (mbist_done || !mbist_ctrl[0]) begin
            mbist_start_reg <= 1'b0;             // Reset start register once test finishes
        end
    end

    // Assert start if register is set or bit[0] of control register is high
    assign mbist_start = mbist_start_reg | mbist_ctrl[0];

    // Engage test mode while test is active or when retaining completion state
    assign test_mode   = mbist_start | mbist_done;

    /////////////////////////////////
    // 2. MBIST Controller Subsystem
    ////////////////////////////////
  
    MBIST #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_mbist_ctrl (
        .clk        (clk),              // Connect system clock
        .rst_n      (rst_n),            // Connect system reset
        .start      (mbist_start),      // Execution start control
        .mem_rdata  (sram_rdata),       // SRAM data bus input for verification
        .done       (mbist_done),       // Output assertion when March C- finishes
        .fail       (mbist_fail),       // Output sticky flag on data mismatch
        .mem_addr   (mbist_addr),       // Memory address driven by BIST counter
        .mem_wdata  (mbist_wdata),      // Test data patterns driven by BIST
        .mem_we_n   (mbist_we_n),       // Write enable generated by BIST FSM
        .mem_ce_n   (mbist_ce_n),       // Chip enable generated by BIST FSM
        .rfail_addr (mbist_rfail_addr)  // Register capturing failing address
    );

    ///////////////////////////////////////////////////////////
    // 3. DFT Memory MUXes (Functional vs. Test Mode Selection)
    //////////////////////////////////////////////////////////
  
    assign sram_ce_n   = test_mode ? mbist_ce_n   : func_ce_n;  // Select CE between BIST and functional
    assign sram_we_n   = test_mode ? mbist_we_n   : func_we_n;  // Select WE between BIST and functional
    assign sram_addr   = test_mode ? mbist_addr   : func_addr;  // Select Addr between BIST and functional
    assign sram_wdata  = test_mode ? mbist_wdata  : func_wdata; // Select WData between BIST and functional

    // Expose memory read data to the external functional interface
    assign func_rdata  = sram_rdata;

    //////////////////////////////
    // 4. Target SRAM Memory Block
    /////////////////////////////
  
    sram_model #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_sram (
        .clk   (clk),         // Connect system clock
        .ce_n  (sram_ce_n),   // Driven by DFT MUX output
        .we_n  (sram_we_n),   // Driven by DFT MUX output
        .addr  (sram_addr),   // Driven by DFT MUX output
        .wdata (sram_wdata),  // Driven by DFT MUX output
        .rdata (sram_rdata)   // Output fed to MBIST and functional read port
    );

endmodule
