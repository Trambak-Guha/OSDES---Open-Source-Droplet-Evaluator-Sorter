`timescale 1ns / 1ps

module uart_packet_parser (
    input  wire clk, rst_n, rx_serial,        
    output reg [7:0] filter_alpha,  
    output reg filter_reg,          
    output reg signed [15:0] threshold, 
    output reg signed [15:0] threshold_ch2,
    
    output reg [15:0] p_w_min, p_w_max,
    output reg signed [15:0] p_h_min, p_h_max,
    
    output reg [15:0] s_a1_min, s_a1_max,
    output reg [15:0] s_a2_min, s_a2_max,
    
    output reg [15:0] delay_us, pulse_width_us, ac_half_period_ticks, 
    output reg [7:0] ch1_gain, ch2_gain,
    output reg ch1_en, ch2_en,
    
    // --- THE SYSTEM FLAGS ---
    output reg actuator_armed, 
    output reg tfads_strict_mode,
    output reg primary_pmt_select,
    output reg [1:0] metric_flag, // <--- ADDED MUX FLAG
    
    output reg [1:0] tx_mode,
    output reg fft_trigger 
);

    wire rx_done; wire [7:0] rx_byte;
    uart_rx #(.CLK_FREQ(104_000_000), .BAUD_RATE(2_000_000)) u_rx_phy (
        .clk(clk), .rst_n(rst_n), .rx_serial(rx_serial), .rx_done(rx_done), .rx_byte(rx_byte)
    );

    localparam HEADER_BYTE = 8'hAA; 
    reg [5:0] byte_cnt = 0;      
    reg [7:0] shadow_buf [0:31]; 
    reg [16:0] timeout_cnt = 0; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_cnt <= 0; tx_mode <= 0; fft_trigger <= 0; timeout_cnt <= 0;
            filter_alpha <= 8'd200; filter_reg <= 0; threshold <= 16'd200;      
            threshold_ch2 <= 16'd200;
            
            p_w_min <= 16'd2; p_w_max <= 16'd5000; p_h_min <= 0; p_h_max <= 16'h7FFF;
            s_a1_min <= 0; s_a1_max <= 16'hFFFF; s_a2_min <= 0; s_a2_max <= 16'hFFFF;
            
            delay_us <= 16'd1000; pulse_width_us <= 16'd50; ac_half_period_ticks <= 16'd1040; 
            ch1_gain <= 8'd1; ch2_gain <= 8'd1; ch1_en <= 1'b1; ch2_en <= 1'b1;
            
            actuator_armed <= 1'b0; 
            tfads_strict_mode <= 1'b0;
            primary_pmt_select <= 1'b0;
            metric_flag <= 2'b00;
        end else begin
            fft_trigger <= 0; 
            
            if (rx_done) timeout_cnt <= 0;
            else if (timeout_cnt < 100000) timeout_cnt <= timeout_cnt + 1;
            
            if (timeout_cnt == 100000 && byte_cnt != 0) byte_cnt <= 0;
            
            if (rx_done) begin
                if (rx_byte == HEADER_BYTE) byte_cnt <= 1; 
                else if (byte_cnt == 0) begin
                    if (rx_byte == 8'h74) tx_mode <= 0; 
                    else if (rx_byte == 8'h66) begin tx_mode <= 1; fft_trigger <= 1; end 
                    else if (rx_byte == 8'h73) tx_mode <= 2; 
                    else if (rx_byte == 8'h31) filter_reg <= 1; 
                    else if (rx_byte == 8'h30) filter_reg <= 0; 
                end else begin
                    shadow_buf[byte_cnt - 1] <= rx_byte;
                    if (byte_cnt == 32) byte_cnt <= 0; 
                    else byte_cnt <= byte_cnt + 1;
                end
            end
            
            if (byte_cnt == 32 && rx_done && rx_byte != HEADER_BYTE) begin
                filter_alpha         <= shadow_buf[0]; 
                threshold            <= {shadow_buf[1],  shadow_buf[2]};
                p_w_min              <= {shadow_buf[3],  shadow_buf[4]};
                p_w_max              <= {shadow_buf[5],  shadow_buf[6]};
                p_h_min              <= {shadow_buf[7],  shadow_buf[8]};
                p_h_max              <= {shadow_buf[9],  shadow_buf[10]};
                delay_us             <= {shadow_buf[11], shadow_buf[12]};
                pulse_width_us       <= {shadow_buf[13], shadow_buf[14]}; 
                ac_half_period_ticks <= {shadow_buf[15], shadow_buf[16]}; 
                ch1_gain             <= shadow_buf[17];
                ch2_gain             <= shadow_buf[18];
                ch1_en               <= shadow_buf[19][0]; 
                ch2_en               <= shadow_buf[20][0]; 
                threshold_ch2        <= {shadow_buf[21], shadow_buf[22]};
                s_a1_min             <= {shadow_buf[23], shadow_buf[24]};
                s_a1_max             <= {shadow_buf[25], shadow_buf[26]};
                s_a2_min             <= {shadow_buf[27], shadow_buf[28]};
                s_a2_max             <= {shadow_buf[29], shadow_buf[30]};
                
                actuator_armed       <= shadow_buf[31][0];
                tfads_strict_mode    <= shadow_buf[31][1];
                primary_pmt_select   <= shadow_buf[31][2];
                metric_flag          <= shadow_buf[31][4:3]; // <--- UNPACKED HERE
            end
        end
    end
endmodule


// =========================================================
// --- UART RECEIVER PHYSICAL LAYER ---
// =========================================================
module uart_rx #(
    parameter CLK_FREQ  = 104_000_000, 
    parameter BAUD_RATE = 2_000_000   
)(
    input  wire clk, rst_n, rx_serial,
    output reg  rx_done, output reg  [7:0] rx_byte
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; 
    localparam IDLE=0, START=1, DATA=2, STOP=3, CLEANUP=4;
    reg [2:0] state = IDLE; reg [15:0] clk_count = 0; reg [2:0] bit_index = 0;
    reg rx_d1, rx_d2; wire rx_in = rx_d2;

    always @(posedge clk) begin rx_d1 <= rx_serial; rx_d2 <= rx_d1; end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; rx_done <= 0; clk_count <= 0; bit_index <= 0; rx_byte <= 0;
        end else begin
            rx_done <= 0; 
            case (state)
                IDLE: begin clk_count <= 0; bit_index <= 0; if (rx_in == 0) state <= START; end
                START: begin
                    if (clk_count == (CLKS_PER_BIT / 2)) begin
                        if (rx_in == 0) begin clk_count <= 0; state <= DATA; end else state <= IDLE; 
                    end else clk_count <= clk_count + 1;
                end
                DATA: begin
                    if (clk_count < CLKS_PER_BIT - 1) clk_count <= clk_count + 1;
                    else begin
                        clk_count <= 0; rx_byte[bit_index] <= rx_in; 
                        if (bit_index < 7) bit_index <= bit_index + 1; else state <= STOP;
                    end
                end
                STOP: begin
                    if (clk_count < CLKS_PER_BIT - 1) clk_count <= clk_count + 1;
                    else begin rx_done <= 1; state <= CLEANUP; end
                end
                CLEANUP: state <= IDLE; 
            endcase
        end
    end
endmodule