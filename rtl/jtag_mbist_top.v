module jtag_mbist_top #(
    parameter ADDR_WIDTH   = 8,   // Memory address bus width (2^8 = 256 words)
    parameter DATA_WIDTH   = 8,   // Memory data bus width (8-bit word)
    parameter IR_LEN       = 4,   // JTAG Instruction Register length in bits
    parameter MBIST_DR_LEN = 32   // JTAG MBIST Data Register length in bits
)(
    // System Clock and Reset
    input  wire                   clk,         
    input  wire                   rst_n,      
  
    // IEEE 1149.1 JTAG Pins
    input  wire                   tck,        // Test Clock input
    input  wire                   tms,        // Test Mode Select input
    input  wire                   trst_n,     // Test Reset input (active-low)
    input  wire                   tdi,        // Test Data In serial input
    output wire                   tdo,        // Test Data Out serial output

    // Fault Injection Control (Verification Hook)
    input  wire                   inject_fault,

    // Functional Memory Interface (Normal Operation Mode)
    input  wire                   func_ce_n,  // Functional chip enable (active-low)
    input  wire                   func_we_n,  // Functional write enable (active-low)
    input  wire [ADDR_WIDTH-1:0]  func_addr,  // Functional memory address bus
    input  wire [DATA_WIDTH-1:0]  func_wdata, // Functional memory write data bus
    output wire [DATA_WIDTH-1:0]  func_rdata  // Functional memory read data bus
);

    // =========================================================================
    // JTAG TAP Controller Subsystem Signals (TCK Domain)
    // =========================================================================
    wire [MBIST_DR_LEN-1:0] mbist_status;          // Status vector driven to JTAG Capture-DR
    wire [MBIST_DR_LEN-1:0] mbist_ctrl;            // Control vector latched in JTAG Update-DR
    wire                    mbist_start_pulse_tck; // 1-cycle pulse generated on Update-DR
    wire                    mbist_done_pulse_tck;  // Synchronized completion pulse in TCK domain
    
    // TCK Domain Shadow Registers (Data-with-Flag pattern)
    reg                     mbist_done_latched;    // Sticky done indicator in TCK
    reg                     mbist_fail_tck;        // Captured fail flag in TCK
    reg  [ADDR_WIDTH-1:0]   mbist_rfail_addr_tck;  // Captured failing address in TCK

    // Qualified trigger pulse: only start when control bit[0] is set
    wire                    mbist_start_cmd_tck;

    // =========================================================================
    // Synchronized CDC Signals (CLK Domain)
    // =========================================================================
    wire                    mbist_start_pulse_clk; // Synchronized start pulse in CLK domain
    reg                     mbist_done_d;          // Flop for CLK-domain rising edge detection
    wire                    mbist_done_rise;       // Single-cycle pulse from MBIST done

    // =========================================================================
    // MBIST Controller Subsystem Signals (CLK Domain)
    // =========================================================================
    reg                     mbist_start_reg;       // Registered start signal
    wire                    mbist_start;           // MBIST FSM trigger
    wire                    mbist_done;            // Completion flag directly from MBIST
    wire                    mbist_fail;            // Failure flag directly from MBIST
    wire [ADDR_WIDTH-1:0]   mbist_rfail_addr;      // First failing address from MBIST

    // MBIST Memory Access Bus
    wire                    mbist_ce_n;
    wire                    mbist_we_n;
    wire [ADDR_WIDTH-1:0]   mbist_addr;
    wire [DATA_WIDTH-1:0]   mbist_wdata;
    wire [DATA_WIDTH-1:0]   sram_rdata;

    // Multiplexed SRAM Interface
    wire                    sram_ce_n;
    wire                    sram_we_n;
    wire [ADDR_WIDTH-1:0]   sram_addr;
    wire [DATA_WIDTH-1:0]   sram_wdata;

    // Test Mode Indicator
    wire                    test_mode;

    // -------------------------------------------------------------------------
    // 1. JTAG TAP Controller Subsystem
    // -------------------------------------------------------------------------
    jtag_tap_top #(
        .IR_LEN       (IR_LEN),
        .MBIST_DR_LEN (MBIST_DR_LEN)
    ) u_jtag_tap (
        .tck               (tck),
        .tms               (tms),
        .trst_n            (trst_n),
        .tdi               (tdi),
        .tdo               (tdo),
        .mbist_status_in   (mbist_status),
        .mbist_ctrl_out    (mbist_ctrl),
        .mbist_start_pulse (mbist_start_pulse_tck)
    );

    // Gate Start pulse: trigger only on explicit command bit (ctrl[0] = 1)
    assign mbist_start_cmd_tck = mbist_start_pulse_tck & mbist_ctrl[0];

    // -------------------------------------------------------------------------
    // 2. Clock Domain Crossing (CDC) Synchronization
    // -------------------------------------------------------------------------
    
    // TCK -> CLK: Synchronize start command pulse
    cdc_pulse_sync u_sync_start_pulse (
        .clk_src   (tck),
        .rst_src_n (trst_n),
        .pulse_in  (mbist_start_cmd_tck),
        .clk_dst   (clk),
        .rst_dst_n (rst_n),
        .pulse_out (mbist_start_pulse_clk)
    );

    // CLK Domain: Convert level mbist_done to a single-cycle pulse
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mbist_done_d <= 1'b0;
        end else begin
            mbist_done_d <= mbist_done;
        end
    end

    assign mbist_done_rise = mbist_done & ~mbist_done_d;

    // CLK -> TCK: Synchronize completion pulse
    cdc_pulse_sync u_sync_done_pulse (
        .clk_src   (clk),
        .rst_src_n (rst_n),
        .pulse_in  (mbist_done_rise),
        .clk_dst   (tck),
        .rst_dst_n (trst_n),
        .pulse_out (mbist_done_pulse_tck)
    );

    // -------------------------------------------------------------------------
    // 3. TCK Result Capture & Status Register Packing
    // -------------------------------------------------------------------------
    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            mbist_done_latched   <= 1'b0;
            mbist_fail_tck       <= 1'b0;
            mbist_rfail_addr_tck <= {ADDR_WIDTH{1'b0}};
        end 
        else if (mbist_start_cmd_tck) begin
            // Reset status on every new explicit test start
            mbist_done_latched   <= 1'b0;
            mbist_fail_tck       <= 1'b0;
            mbist_rfail_addr_tck <= {ADDR_WIDTH{1'b0}};
        end 
        else if (mbist_done_pulse_tck) begin
            // Latch results safely upon synchronized done pulse
            mbist_done_latched   <= 1'b1;
            mbist_fail_tck       <= mbist_fail;
            mbist_rfail_addr_tck <= mbist_rfail_addr;
        end
    end

    // Status Register format: [Padding | Fail Address | Fail Flag | Done Flag]
    assign mbist_status = {
        {(MBIST_DR_LEN - 2 - ADDR_WIDTH){1'b0}},
        mbist_rfail_addr_tck,
        mbist_fail_tck,
        mbist_done_latched
    };

    // -------------------------------------------------------------------------
    // 4. MBIST Execution Control (CLK Domain)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mbist_start_reg <= 1'b0;
        end else if (mbist_start_pulse_clk) begin
            mbist_start_reg <= 1'b1;
        end else if (mbist_done) begin
            mbist_start_reg <= 1'b0;
        end
    end

    assign mbist_start = mbist_start_reg;
    assign test_mode   = mbist_start | mbist_done;

    // -------------------------------------------------------------------------
    // 5. MBIST Controller Subsystem
    // -------------------------------------------------------------------------
    mbist_controller #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_mbist_ctrl (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (mbist_start),
        .mem_rdata  (sram_rdata),
        .done       (mbist_done),
        .fail       (mbist_fail),
        .mem_addr   (mbist_addr),
        .mem_wdata  (mbist_wdata),
        .mem_we_n   (mbist_we_n),
        .mem_ce_n   (mbist_ce_n),
        .rfail_addr (mbist_rfail_addr)
    );

    // -------------------------------------------------------------------------
    // 6. DFT Memory MUXes & Functional Isolation
    // -------------------------------------------------------------------------
    assign sram_ce_n  = test_mode ? mbist_ce_n  : func_ce_n;
    assign sram_we_n  = test_mode ? mbist_we_n  : func_we_n;
    assign sram_addr  = test_mode ? mbist_addr  : func_addr;
    assign sram_wdata = test_mode ? mbist_wdata : func_wdata;

    // Prevent functional side from seeing internal BIST patterns
    assign func_rdata = test_mode ? {DATA_WIDTH{1'b0}} : sram_rdata;

    // -------------------------------------------------------------------------
    // 7. SRAM Model Block
    // -------------------------------------------------------------------------
    sram_model #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_sram (
        .clk          (clk),
        .ce_n         (sram_ce_n),
        .we_n         (sram_we_n),
        .addr         (sram_addr),
        .wdata        (sram_wdata),
        .inject_fault (inject_fault),
        .rdata        (sram_rdata)
    );

endmodule
