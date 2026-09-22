module cdc_pulse_sync (
    // Source Clock Domain
    input  wire clk_src,
    input  wire rst_src_n,
    input  wire pulse_in,

    // Destination Clock Domain
    input  wire clk_dst,
    input  wire rst_dst_n,
    output wire pulse_out
);

    // =========================================================================
    // Source Domain: Pulse-to-Toggle Conversion
    // =========================================================================
    reg toggle_src;

    always @(posedge clk_src or negedge rst_src_n) begin
        if (!rst_src_n) begin
            toggle_src <= 1'b0;
        end else if (pulse_in) begin
            toggle_src <= ~toggle_src;
        end
    end

    // =========================================================================
    // Destination Domain: Multi-Stage Synchronizer Flops
    // =========================================================================
    (* ASYNC_REG = "TRUE" *) reg sync_stage1;
    (* ASYNC_REG = "TRUE" *) reg sync_stage2;
    reg                      sync_stage3;

    always @(posedge clk_dst or negedge rst_dst_n) begin
        if (!rst_dst_n) begin
            sync_stage1 <= 1'b0;
            sync_stage2 <= 1'b0;
            sync_stage3 <= 1'b0;
        end else begin
            sync_stage1 <= toggle_src;
            sync_stage2 <= sync_stage1;
            sync_stage3 <= sync_stage2;
        end
    end

    // =========================================================================
    // Destination Domain: Reset Masking (Arming Register)
    // =========================================================================
    // Prevents false pulse output upon asymmetric reset release 
    // when toggle_src remains high while sync chain resets to zero
    reg [2:0] arm_sr;

    always @(posedge clk_dst or negedge rst_dst_n) begin
        if (!rst_dst_n) begin
            arm_sr <= 3'b000;
        end else begin
            arm_sr <= {arm_sr[1:0], 1'b1};
        end
    end

    // =========================================================================
    // Destination Domain: Edge Detection & Gated Output Generation
    // =========================================================================
    // Pulse output is enabled only after arming sequence completes (arm_sr[2] == 1)
    assign pulse_out = (sync_stage2 ^ sync_stage3) & arm_sr[2];

endmodule
