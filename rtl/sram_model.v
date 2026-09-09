module sram_model #(
    parameter ADDR_WIDTH = 8,   // 256 Words
    parameter DATA_WIDTH = 8    // 8 bit word width
)(
    input  wire                  clk,
    input  wire                  ce_n,         // Chip Enable (Active Low)
    input  wire                  we_n,         // Write Enable ('0' = Write, '1' = Read)
    input  wire [ADDR_WIDTH-1:0] addr,         // Address
    input  wire [DATA_WIDTH-1:0] wdata,        // Write Data
    input  wire                  inject_fault, // Fault Injection Enable (Stuck at '1' at 0x2A)
    output reg  [DATA_WIDTH-1:0] rdata         // Read Data
);

    // 2D register array modeling the SRAM
    reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH) - 1];

    // Synchronous Write Operation
    always @(posedge clk) begin
        if (!ce_n && !we_n) begin
            mem[addr] <= wdata;
        end
    end

    // Combinational Read Operation (0 cycle latency) with Fault Injection
    always @(*) begin
        if (ce_n || !we_n) begin
            rdata = {DATA_WIDTH{1'b0}};
        end 
        else begin
            if (inject_fault && (addr == 8'h2A)) begin
                rdata = {DATA_WIDTH{1'b1}}; // Force all 1s (0xFF)
            end 
            else begin
                rdata = mem[addr];          // Normal memory read
            end
        end
    end

endmodule
