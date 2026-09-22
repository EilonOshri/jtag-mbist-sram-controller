module jtag_reg #(
    parameter DR_LEN = 32
)(
    input  wire              tck,
    input  wire              trst_n,

    // JTAG TAP FSM States
    input  wire              state_tlr,
    input  wire              state_capturedr,
    input  wire              state_shiftdr,
    input  wire              state_updatedr,

    // Serial scan interface
    input  wire              tdi,
    output wire              tdo,

    // Parallel load/update interface
    input  wire [DR_LEN-1:0] dr_dataIn,
    output reg  [DR_LEN-1:0] dr_dataOut,
    output reg               dr_dataOutReady
);

    reg [DR_LEN-1:0] dr_reg;

    // Shift logic safe for any DR_LEN >= 1 (prevents reversed index [0:1])
    wire [DR_LEN:0]   dr_concat     = {tdi, dr_reg};
    wire [DR_LEN-1:0] dr_shift_next = dr_concat[DR_LEN:1];

    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            dr_reg          <= {DR_LEN{1'b0}};
            dr_dataOut      <= {DR_LEN{1'b0}};
            dr_dataOutReady <= 1'b0;
        end else if (state_tlr) begin
            // Compliant with IEEE 1149.1: Disable test control registers on TLR
            dr_reg          <= dr_dataIn;
            dr_dataOut      <= {DR_LEN{1'b0}};
            dr_dataOutReady <= 1'b0;
        end else if (state_capturedr) begin
            dr_reg          <= dr_dataIn;
            dr_dataOutReady <= 1'b0;
        end else if (state_shiftdr) begin
            dr_reg          <= dr_shift_next;
            dr_dataOutReady <= 1'b0;
        end else if (state_updatedr) begin
            dr_dataOut      <= dr_reg;
            dr_dataOutReady <= 1'b1;
        end else begin
            dr_dataOutReady <= 1'b0;
        end
    end

    // Serial output: LSB is shifted out first
    assign tdo = dr_reg[0];

endmodule
