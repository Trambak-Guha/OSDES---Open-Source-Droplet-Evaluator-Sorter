// =====================================================================
// UART TX PHYSICAL LAYER (2,000,000 Baud)
// Mathematical Clock Division: 104 MHz / 2 MHz = 52 cycles per bit exactly.
// =====================================================================
module uart_tx #(
    parameter CLK_FREQ  = 104_000_000, 
    parameter BAUD_RATE = 2_000_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,          // 1-cycle pulse to trigger transmission
    input  wire [7:0] data_in,
    
    output reg  tx_active,      // The "Busy" flag (CRITICAL for arbitration)
    output reg  tx_serial,      // The physical TX pin to the PC
    output reg  tx_done
);

    // 104M / 2M = 52. Zero fractional error.
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; 
    localparam IDLE=0, START_BIT=1, DATA_BITS=2, STOP_BIT=3;

    reg [1:0] state = IDLE;
    reg [15:0] clk_count = 0;
    reg [2:0] bit_index = 0;
    reg [7:0] tx_data = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            tx_serial <= 1; // UART protocol specifies idle lines are held HIGH
            tx_active <= 0; 
            tx_done <= 0;
        end else begin
            tx_done <= 0; // Default pulse

            case (state)
                IDLE: begin
                    tx_serial <= 1;
                    if (start) begin
                        tx_active <= 1;
                        tx_data <= data_in; 
                        clk_count <= 0;
                        state <= START_BIT; 
                    end else begin
                        tx_active <= 0;
                    end
                end
                
                START_BIT: begin
                    tx_serial <= 0; // Drive LOW to signal start of frame
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin 
                        clk_count <= 0;
                        bit_index <= 0; 
                        state <= DATA_BITS; 
                    end
                end
                
                DATA_BITS: begin
                    tx_serial <= tx_data[bit_index]; // Send LSB first
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            state <= STOP_BIT;
                        end
                    end
                end
                
                STOP_BIT: begin
                    tx_serial <= 1; // Drive HIGH for Stop Bit
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin 
                        state <= IDLE;
                        tx_done <= 1;  
                        tx_active <= 0; // Drop busy flag, allowing Arbiter to send next byte
                    end
                end
            endcase
        end
    end
endmodule