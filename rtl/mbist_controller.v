module MBIST #(
    parameter ADDR_WIDTH = 8,                           // 256 words memory depth
    parameter DATA_WIDTH = 8                            // 8-bit word data width
)(
    input  wire                  clk,                   // System clock input
    input  wire                  rst_n,                 // Asynchronous active-low reset
    input  wire                  start,                 // Start BIST execution pulse
    input  wire [DATA_WIDTH-1:0] mem_rdata,             // Data read from SRAM
    output wire                  done,                  // High when test completes
    output wire                  pass,                  // High if test passed
    output wire                  fail,                  // High if test failed
    output wire [ADDR_WIDTH-1:0] mem_addr,              // Memory address driven by BIST
    output wire [DATA_WIDTH-1:0] mem_wdata,             // Memory data pattern driven by BIST
    output wire                  mem_we_n,              // Active-low write enable to SRAM
    output wire                  mem_ce_n,              // Active-low chip enable to SRAM
    output reg  [ADDR_WIDTH-1:0] rfail_addr             // Register storing first failing address
);

    // FSM State Encoding
    localparam STATE_WIDTH = 3;                         // 3 bits needed for 8 states

    localparam [STATE_WIDTH-1:0] IDLE          = 3'd0,  // Wait for start trigger
                                 STAGE_1_W0    = 3'd1,  // Up sweep: Write 0
                                 STAGE_2_R0_W1 = 3'd2,  // Up sweep: Read 0, Write 1
                                 STAGE_3_R1_W0 = 3'd3,  // Up sweep: Read 1, Write 0
                                 STAGE_4_R0_W1 = 3'd4,  // Down sweep: Read 0, Write 1
                                 STAGE_5_R1_W0 = 3'd5,  // Down sweep: Read 1, Write 0
                                 STAGE_6_R0    = 3'd6,  // Down sweep: Read 0
                                 DONE          = 3'd7;  // Finished: Assert status

    // Internal State Registers
    reg [STATE_WIDTH-1:0] current_state;    
    reg [STATE_WIDTH-1:0] next_state;          

    // Internal Address Counter
    reg [ADDR_WIDTH-1:0]  addr_cnt;                  

    // Sub-operation Phase (for Read-then-Write stages)
    reg                   op_phase;                  

    // Internal Fault Tracking Register
    reg                   fail_flag;                 

    // Maximum and Minimum Address Boundaries
    localparam [ADDR_WIDTH-1:0] MAX_ADDR = {ADDR_WIDTH{1'b1}}; // Highest memory address (255)
    localparam [ADDR_WIDTH-1:0] MIN_ADDR = {ADDR_WIDTH{1'b0}}; // Lowest memory address (0)





always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= IDLE;
    end else begin
        current_state <= next_state;
    end
end







  
always @(*) begin
    next_state = current_state; // ערך ברירת מחדל למניעת Latch

    case (current_state)
        IDLE: begin
          if (start == 1'b1) begin
            next_state = STAGE_1_W0;
          end
          else begin
            next_state = IDLE;
          end
        end

        STAGE_1_W0: begin
          if (addr_cnt != MAX_ADDR) begin
            next_state = STAGE_1_W0;
          end
          else begin
            next_state = STAGE_2_R0_W1;
          end
        end

        STAGE_2_R0_W1: begin
            // שלב משולב (קריאה op_phase=0 ואז כתיבה op_phase=1)
            // מתי מסיימים את כל הכתובות ועוברים ל-STAGE_3_R1_W0?
        end

        STAGE_3_R1_W0: begin
            // שלב משולב עולה נוסף
            // מתי עוברים ל-STAGE_4_R0_W1?
        end

        STAGE_4_R0_W1: begin
            // שלב משולב יורד (מ-MAX_ADDR חזרה ל-MIN_ADDR)
            // מתי עוברים ל-STAGE_5_R1_W0?
        end

        STAGE_5_R1_W0: begin
            // שלב משולב יורד נוסף
            // מתי עוברים ל-STAGE_6_R0?
        end

        STAGE_6_R0: begin
            // שלב קריאה בלבד יורד (ללא כתיבה)
            // מתי מסיימים ועוברים ל-DONE?
        end

        DONE: begin
            // מתי חוזרים ל-IDLE? (למשל כאשר start יורד ל-0)
        end

        default: next_state = IDLE;
    endcase
end






















  

endmodule
