module jtag_tap_top #(
    parameter IR_LEN = 4,
    parameter MBIST_DR_LEN = 32
) (
    // JTAG External Interface
    input  wire                      tck,
    input  wire                      tms,
    input  wire                      trst_n,
    input  wire                      tdi,
    output reg                       tdo,

    // Internal MBIST Interface
    input  wire [MBIST_DR_LEN-1:0]   mbist_status_in,      // Fail flag + Failing Addr from MBIST
    output wire [MBIST_DR_LEN-1:0]   mbist_ctrl_out,       // Start command / Config to MBIST
    output wire                      mbist_start_pulse     // Trigger pulse when Update-DR happens
);

    // Standard Opcodes
    localparam [IR_LEN-1:0] OP_BYPASS    = {IR_LEN{1'b1}}; // 4'b1111
    localparam [IR_LEN-1:0] OP_RUN_MBIST = 4'b0010;

    // FSM State Decodes
    wire state_tlr;
    wire state_capturedr;
    wire state_captureir;
    wire state_shiftdr;
    wire state_shiftir;
    wire state_updatedr;
    wire state_updateir;

    // 1. Instantiate the TAP Controller FSM
    jtag_state_machine tap_fsm (
        .tck             (tck),
        .tms             (tms),
        .trst            (trst_n),
        .state_tlr       (state_tlr),
        .state_capturedr (state_capturedr),
        .state_captureir (state_captureir),
        .state_shiftdr   (state_shiftdr),
        .state_shiftir   (state_shiftir),
        .state_updatedr  (state_updatedr),
        .state_updateir  (state_updateir)
    );

    // 2. Instruction Register (IR) Logic
    reg [IR_LEN-1:0] ir_shift_reg;
    reg [IR_LEN-1:0] ir_latched;

    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            ir_shift_reg <= {{(IR_LEN-1){1'b0}}, 1'b1}; // 0001 pattern on reset
            ir_latched   <= OP_BYPASS;
        end else if (state_tlr) begin
            ir_shift_reg <= {{(IR_LEN-1){1'b0}}, 1'b1};
            ir_latched   <= OP_BYPASS;
        end else if (state_captureir) begin
            ir_shift_reg <= {{(IR_LEN-1){1'b0}}, 1'b1}; // Fixed capture value
        end else if (state_shiftir) begin
            ir_shift_reg <= {tdi, ir_shift_reg[IR_LEN-1:1]};
        end else if (state_updateir) begin
            ir_latched   <= ir_shift_reg;
        end
    end

    wire tdo_ir = ir_shift_reg[0];

    // 3. Bypass Register (1-bit DR)
    wire tdo_bypass;
    jtag_reg #(
        .IR_LEN    (IR_LEN),
        .DR_LEN    (1),
        .IR_OPCODE (OP_BYPASS)
    ) bypass_dr (
        .tck             (tck),
        .trst            (trst_n),
        .tdi             (tdi),
        .tdo             (tdo_bypass),
        .state_tlr       (state_tlr),
        .state_capturedr (state_capturedr),
        .state_shiftdr   (state_shiftdr),
        .state_updatedr  (state_updatedr),
        .ir_reg          (ir_latched),
        .dr_dataIn       (1'b0),
        .dr_dataOut      (),
        .dr_dataOutReady ()
    );

    // 4. MBIST Data Register
    wire tdo_mbist;
    jtag_reg #(
        .IR_LEN    (IR_LEN),
        .DR_LEN    (MBIST_DR_LEN),
        .IR_OPCODE (OP_RUN_MBIST)
    ) mbist_dr (
        .tck             (tck),
        .trst            (trst_n),
        .tdi             (tdi),
        .tdo             (tdo_mbist),
        .state_tlr       (state_tlr),
        .state_capturedr (state_capturedr),
        .state_shiftdr   (state_shiftdr),
        .state_updatedr  (state_updatedr),
        .ir_reg          (ir_latched),
        .dr_dataIn       (mbist_status_in),
        .dr_dataOut      (mbist_ctrl_out),
        .dr_dataOutReady (mbist_start_pulse)
    );

    // 5. Multiplex TDO & Output on Falling Edge of TCK
    reg tdo_mux;
    always @(*) begin
        if (state_shiftir) begin
            tdo_mux = tdo_ir;
        end else begin
            case (ir_latched)
                OP_RUN_MBIST: tdo_mux = tdo_mbist;
                default:      tdo_mux = tdo_bypass;
            endcase
        end
    end

    always @(negedge tck or negedge trst_n) begin
        if (!trst_n) begin
            tdo <= 1'b0;
        end else begin
            tdo <= tdo_mux;
        end
    end

endmodule