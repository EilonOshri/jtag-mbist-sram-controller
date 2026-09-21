module cdc_pulse_sync (
    // Source Clock Domain (JTAG TCK)
    input  wire clk_src,     // Source clock
    input  wire rst_src_n,   // Source reset (active-low)
    input  wire pulse_in,    // Single-cycle pulse in source clock domain

    // Destination Clock Domain (System CLK)
    input  wire clk_dst,     // Destination clock
    input  wire rst_dst_n,   // Destination reset (active-low)
    output wire pulse_out    // Reconstructed single-cycle pulse in destination clock domain
);

    //-------------------------------------------------------------------------
    // Step 1: Pulse-to-Toggle Conversion (Source Domain)
    // Converts each incoming pulse into a logic level transition (0->1 or 1->0).
    // This holds the signal indefinitely so it cannot be missed by the destination clock.
    //-------------------------------------------------------------------------
    reg toggle_src;

    always @(posedge clk_src or negedge rst_src_n) begin
        if (!rst_src_n) begin
            toggle_src <= 1'b0;
        end else if (pulse_in) begin
            toggle_src <= ~toggle_src;
        end
    end

    //-------------------------------------------------------------------------
    // Step 2: 2-Stage Flip-Flop Synchronizer (Destination Domain)
    // Resolves metastability issues across clock domain boundaries.
    // ASYNC_REG attribute ensures back-to-back placement during synthesis/P&R.
    //-------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg sync_stage1;
    (* ASYNC_REG = "TRUE" *) reg sync_stage2;

    always @(posedge clk_dst or negedge rst_dst_n) begin
        if (!rst_dst_n) begin
            sync_stage1 <= 1'b0;
            sync_stage2 <= 1'b0;
        end else begin
            sync_stage1 <= toggle_src;
            sync_stage2 <= sync_stage1;
        end
    end

    //-------------------------------------------------------------------------
    // Step 3: Edge Detection / Pulse Reconstruction (Destination Domain)
    // Delays the synchronized toggle signal by one extra clock cycle.
    //-------------------------------------------------------------------------
    reg sync_stage3;

    always @(posedge clk_dst or negedge rst_dst_n) begin
        if (!rst_dst_n) begin
            sync_stage3 <= 1'b0;
        end else begin
            sync_stage3 <= sync_stage2;
        end
    end

    // An XOR operation detects any transition (rising or falling edge),
    // producing a clean 1-cycle pulse aligned to clk_dst.
    assign pulse_out = sync_stage2 ^ sync_stage3;

endmodule
