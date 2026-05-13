`timescale 1ns / 1ps

module pulse_logger_1mhz (
    input  wire clk,
    input  wire rst_n,
    input  wire trigger_log,
    input  wire [15:0] width_ch1,
    input  wire [15:0] width_ch2,
    input  wire signed [15:0] peak_ch1,
    input  wire signed [15:0] peak_ch2,
    input  wire [31:0] area_ch1,
    input  wire [31:0] area_ch2,
    input  wire [12:0] fifo_count, 
    
    output reg fifo_wr_en,
    output reg [7:0] fifo_din
);

    reg [3:0] log_state = 0;

    wire [15:0] scaled_area_ch1 = (area_ch1 > 32'd16777215) ? 16'hFFFF : area_ch1[23:8];
    wire [15:0] scaled_area_ch2 = (area_ch2 > 32'd16777215) ? 16'hFFFF : area_ch2[23:8];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            log_state <= 0; fifo_wr_en <= 0; fifo_din <= 0;
        end else begin
            fifo_wr_en <= 0; 
            if (log_state == 0) begin
                if (trigger_log && fifo_count < 13'd4000) log_state <= 1;
            end else begin
                case (log_state)
                    1: begin fifo_din <= 8'hBB; fifo_wr_en <= 1; log_state <= 2; end
                    2: begin fifo_din <= width_ch1[15:8]; fifo_wr_en <= 1; log_state <= 3; end
                    3: begin fifo_din <= width_ch1[7:0];  fifo_wr_en <= 1; log_state <= 4; end
                    4: begin fifo_din <= width_ch2[15:8]; fifo_wr_en <= 1; log_state <= 5; end
                    5: begin fifo_din <= width_ch2[7:0];  fifo_wr_en <= 1; log_state <= 6; end
                    6: begin fifo_din <= peak_ch1[15:8]; fifo_wr_en <= 1; log_state <= 7; end
                    7: begin fifo_din <= peak_ch1[7:0];  fifo_wr_en <= 1; log_state <= 8; end
                    8: begin fifo_din <= peak_ch2[15:8]; fifo_wr_en <= 1; log_state <= 9; end
                    9: begin fifo_din <= peak_ch2[7:0];  fifo_wr_en <= 1; log_state <= 10; end
                    10: begin fifo_din <= scaled_area_ch1[15:8]; fifo_wr_en <= 1; log_state <= 11; end
                    11: begin fifo_din <= scaled_area_ch1[7:0];  fifo_wr_en <= 1; log_state <= 12; end
                    12: begin fifo_din <= scaled_area_ch2[15:8]; fifo_wr_en <= 1; log_state <= 13; end
                    13: begin fifo_din <= scaled_area_ch2[7:0];  fifo_wr_en <= 1; log_state <= 14; end
                    14: begin fifo_din <= 8'hEE; fifo_wr_en <= 1; log_state <= 0; end
                    default: log_state <= 0;
                endcase
            end
        end
    end
endmodule