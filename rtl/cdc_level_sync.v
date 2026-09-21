module cdc_level_sync (
    input  wire clk_dst,
    input  wire rst_dst_n,
    input  wire sig_in,
    output wire sig_out
);

    (* ASYNC_REG = "TRUE" *) reg sync_stage1;
    (* ASYNC_REG = "TRUE" *) reg sync_stage2;

    always @(posedge clk_dst or negedge rst_dst_n) begin
        if (!rst_dst_n) begin
            sync_stage1 <= 1'b0;
            sync_stage2 <= 1'b0;
        end else begin
            sync_stage1 <= sig_in;
            sync_stage2 <= sync_stage1;
        end
    end

    assign sig_out = sync_stage2;

endmodule
