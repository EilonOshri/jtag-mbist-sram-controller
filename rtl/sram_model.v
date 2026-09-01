module SRAM #(
    parameter ADDR_WIDTH = 8,   // 256 Word
    parameter DATA_WIDTH = 8    // 8-bit word width
)(
    input  wire                  clk,
    input  wire                  ce_n,   // Chip Enable (Active Low)
    input  wire                  we_n,   // Write Enable ('0' = Write, '1' = Read)
    input  wire [ADDR_WIDTH-1:0] addr,   // Address
    input  wire [DATA_WIDTH-1:0] wdata,  // Write Data
    output reg  [DATA_WIDTH-1:0] rdata   // Read Data
);

    // 2D register array modeling the SRAM: [DATA_WIDTH-1:0] defines word width, [0:(1<<ADDR_WIDTH)-1] defines depth (2^ADDR_WIDTH words)
    reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH) - 1];
  
    // Synchronous read and write operations
    always @(posedge clk) begin
        // Check if the memory block is enabled
        if (!ce_n) begin
            if (!we_n) begin
                // Write Operation: Store wdata into the specified memory address
                mem[addr] <= wdata;
            end else begin
                // Read Operation: Fetch data from the specified memory address
                // Output is available on the next clock cycle (1-cycle read latency)
                rdata <= mem[addr];
            end
        end
    end

endmodule
