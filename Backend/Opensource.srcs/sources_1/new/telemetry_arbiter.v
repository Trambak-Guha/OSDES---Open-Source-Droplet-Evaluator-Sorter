`timescale 1ns / 1ps

module telemetry_arbiter (
    input  wire clk,
    input  wire rst_n,
    
    input  wire [1:0] tx_mode,
    input  wire uart_busy,
    
    input  wire time_empty,
    input  wire [7:0] time_dout,
    output reg  time_rd_en,
    
    input  wire fft_empty,
    input  wire [7:0] fft_dout,
    output reg  fft_rd_en,
    
    input  wire scat_empty,
    input  wire [7:0] scat_dout,
    output reg  scat_rd_en,
    
    output reg  tx_start,
    output reg  [7:0] tx_data
);

    reg [2:0] state = 0;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0;
            time_rd_en <= 0; fft_rd_en <= 0; scat_rd_en <= 0;
            tx_start <= 0; tx_data <= 0;
        end else begin
            time_rd_en <= 0; fft_rd_en <= 0; scat_rd_en <= 0;
            tx_start <= 0;
            
            case (state)
                0: begin
                    if (!uart_busy) begin
                        if (tx_mode == 0 && !time_empty) begin
                            time_rd_en <= 1; state <= 1;
                        end else if (tx_mode == 1 && !fft_empty) begin
                            fft_rd_en <= 1; state <= 1;
                        end else if (tx_mode == 2 && !scat_empty) begin
                            scat_rd_en <= 1; state <= 1;
                        end
                    end
                end
                
                1: state <= 2; // Wait 1 cycle for BRAM latency
                
                2: begin
                    if      (tx_mode == 0) tx_data <= time_dout;
                    else if (tx_mode == 1) tx_data <= fft_dout;
                    else if (tx_mode == 2) tx_data <= scat_dout;
                    
                    tx_start <= 1;
                    state <= 3;
                end
                
                3: state <= 4; // Give UART exactly 1 cycle to assert busy
                
                4: begin
                    if (!uart_busy) state <= 0; // Wait patiently for UART to finish
                end
                
                default: state <= 0;
            endcase
        end
    end
endmodule