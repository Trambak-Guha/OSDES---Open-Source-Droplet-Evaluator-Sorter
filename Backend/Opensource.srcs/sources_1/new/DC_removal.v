`timescale 1ns / 1ps

module dc_removal_1mhz (
    input  wire clk,
    input  wire rst_n,
    input  wire sample_en,
    input  wire signed [15:0] data_in,
    output reg signed [15:0] data_out
);
    reg signed [47:0] dc_accumulator;
    
    // Time constant: 65,536 samples (65.5 ms at 1 MSPS)
    wire signed [15:0] dc_val = dc_accumulator >>> 16;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            dc_accumulator <= 0;
            data_out <= 0;
        end else if (sample_en) begin
            dc_accumulator <= dc_accumulator + data_in - dc_val;
            data_out <= data_in - dc_val;
        end
    end
endmodule