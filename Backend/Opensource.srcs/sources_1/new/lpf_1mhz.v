`timescale 1ns / 1ps

module lpf_1mhz (
    input  wire clk,                  // 104 MHz System Clock
    input  wire rst_n,
    input  wire sample_en,            // 1 MHz Pulse
    input  wire signed [15:0] data_in,// Centered signed data
    input  wire [7:0] alpha,          // From UART GUI (0 to 255)
    output reg  signed [15:0] data_out
);

    // 4th-Order filter requires 4 accumulators
    reg signed [31:0] acc1, acc2, acc3, acc4;
    
    wire signed [31:0] in_scaled = $signed(data_in) <<< 8;
    wire signed [9:0]  alpha_signed = $signed({2'b00, alpha}); // Cast to positive signed

    // Pipeline Registers
    reg [3:0] state;
    reg signed [32:0] diff;
    reg signed [41:0] mult;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc1 <= 0; acc2 <= 0; acc3 <= 0; acc4 <= 0;
            data_out <= 0;
            state <= 0; diff <= 0; mult <= 0;
        end else begin
            // 9-STAGE PIPELINED 4TH-ORDER IIR FILTER
            // Executes in ~86ns (9 cycles at 104 MHz), well within the 1000ns budget
            case (state)
                0: begin 
                    if (sample_en) begin
                        diff <= in_scaled - acc1;     // Stage 1: Subtract
                        state <= 1;
                    end
                end
                1: begin mult <= diff * alpha_signed; state <= 2; end // Stage 1: Multiply
                2: begin 
                    acc1 <= acc1 + (mult >>> 8);                      // Stage 1: Accumulate
                    diff <= (acc1 + (mult >>> 8)) - acc2;             // Stage 2: Subtract
                    state <= 3; 
                end
                3: begin mult <= diff * alpha_signed; state <= 4; end // Stage 2: Multiply
                4: begin 
                    acc2 <= acc2 + (mult >>> 8);                      // Stage 2: Accumulate
                    diff <= (acc2 + (mult >>> 8)) - acc3;             // Stage 3: Subtract
                    state <= 5; 
                end
                5: begin mult <= diff * alpha_signed; state <= 6; end // Stage 3: Multiply
                6: begin 
                    acc3 <= acc3 + (mult >>> 8);                      // Stage 3: Accumulate
                    diff <= (acc3 + (mult >>> 8)) - acc4;             // Stage 4: Subtract
                    state <= 7; 
                end
                7: begin mult <= diff * alpha_signed; state <= 8; end // Stage 4: Multiply
                8: begin 
                    acc4 <= acc4 + (mult >>> 8);                      // Stage 4: Accumulate
                    data_out <= (acc4 + (mult >>> 8)) >>> 8; 
                    state <= 0; // Return to idle
                end
                default: state <= 0;
            endcase
        end
    end
endmodule