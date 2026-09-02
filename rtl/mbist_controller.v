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
    
    case (current_state)
        
         // Wait for start trigger to begin BIST execution
        IDLE: begin
          if (start == 1'b1) begin
            next_state = STAGE_1_W0;
          end
          else begin
            next_state = IDLE;
          end
        end

        // Stage 1: Up sweep, write 0 across all addresses
        STAGE_1_W0: begin
          if (addr_cnt != MAX_ADDR) begin
            next_state = STAGE_1_W0;
          end
          else begin
            next_state = STAGE_2_R0_W1;
          end
        end

        // Stage 2: Up sweep, read 0 then write 1 at each address
        STAGE_2_R0_W1: begin
            if ((addr_cnt == MAX_ADDR) && (op_phase == 1)) begin
                next_state = STAGE_3_R1_W0;
            end
            else begin
                next_state = STAGE_2_R0_W1;
            end
        end

        // Stage 3: Up sweep, read 1 then write 0 at each address
        STAGE_3_R1_W0: begin
            if ((addr_cnt == MAX_ADDR) && (op_phase == 1)) begin
                next_state = STAGE_4_R0_W1;
            end
            else begin
                next_state =  STAGE_3_R1_W0;
            end           
        end

        // Stage 4: Down sweep, read 0 then write 1 at each address
        STAGE_4_R0_W1: begin
            if ((addr_cnt == MIN_ADDR) && (op_phase == 1)) begin
                next_state = STAGE_5_R1_W0;
            end
            else begin
                next_state =  STAGE_4_R0_W1;
            end      
        end

        // Stage 5: Down sweep, read 1 then write 0 at each address
        STAGE_5_R1_W0: begin
            if ((addr_cnt == MIN_ADDR) && (op_phase == 1)) begin
                next_state = STAGE_6_R0;
            end
            else begin
                next_state =  STAGE_5_R1_W0;
            end   
        end

        // Stage 6: Down sweep, read 0 verification across all addresses
        STAGE_6_R0: begin
            if (addr_cnt == MIN_ADDR) begin
                next_state = DONE;
            end
            else begin
                next_state = STAGE_6_R0;
            end
        end

        // Hold completion status until start is deasserted
        DONE: begin
            if (start == 0) begin
                next_state = IDLE;
            end
            else begin
                next_state = DONE;
            end
        end

default: begin
            next_state = IDLE;
        end
    endcase
end






















  

endmodule
