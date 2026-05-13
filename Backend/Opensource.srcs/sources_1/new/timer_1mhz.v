`timescale 1ns / 1ps

module timer_1mhz #(
    parameter integer CLK_FREQ = 104_000_000
)(
    input  wire clk,
    input  wire rst_n,
    output reg  sample_tick
);
    // 104 MHz / 1 MHz = 104 cycles per sample
    localparam integer CNT_MAX = CLK_FREQ / 1_000_000; 
    
    reg [7:0] cnt; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0;
            sample_tick <= 0;
        end else begin
            // 1. Advance the master timer
            if (cnt >= (CNT_MAX - 1)) begin
                cnt <= 0;
            end else begin
                cnt <= cnt + 1;
            end
            
            // 2. THE FIX: The UG480 Pulse Width Expansion
            // Hold CONVST high for 5 cycles (48 ns) to safely clear the 
            // 1 ADCCLK (38.4 ns) minimum hardware threshold.
            if (cnt < 5) begin
                sample_tick <= 1;
            end else begin
                sample_tick <= 0;
            end
        end
    end
endmodule