`timescale 1ns / 1ps

module fifo_buffer_8b #(
    parameter DEPTH = 4096 // Must be a power of 2
)(
    input  wire clk,
    input  wire rst_n,
    input  wire clear,    // *** NEW: Synchronous Flush Command ***
    
    input  wire wr_en,
    input  wire [7:0] din,
    
    input  wire rd_en,
    output reg  [7:0] dout,
    
    output wire empty,
    output wire full,
    output wire [12:0] current_count 
);

    (* ram_style = "block" *) reg [7:0] memory [0:DEPTH-1];
    
    reg [11:0] wr_ptr;
    reg [11:0] rd_ptr;
    reg [12:0] count;

    assign empty = (count == 0);
    assign full  = (count == DEPTH);
    assign current_count = count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0; rd_ptr <= 0; count  <= 0;
        end else if (clear) begin
            wr_ptr <= 0; rd_ptr <= 0; count  <= 0; // *** INSTANT FLUSH ***
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: begin wr_ptr <= wr_ptr + 1; count <= count + 1; end
                2'b01: begin rd_ptr <= rd_ptr + 1; count <= count - 1; end
                2'b11: begin wr_ptr <= wr_ptr + 1; rd_ptr <= rd_ptr + 1; end
                default: ; 
            endcase
        end
    end

    always @(posedge clk) begin
        if (wr_en && !full && !clear) memory[wr_ptr] <= din;
        if (rd_en && !empty && !clear) dout <= memory[rd_ptr]; 
    end
endmodule