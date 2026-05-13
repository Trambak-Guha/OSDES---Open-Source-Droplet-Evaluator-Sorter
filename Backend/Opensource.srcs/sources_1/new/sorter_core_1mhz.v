`timescale 1ns / 1ps

module sorter_core_1mhz (
    input  wire clk,
    input  wire rst_n,
    input  wire trigger_eval,         
    
    input  wire [15:0] width_ch1,
    input  wire [15:0] width_ch2,
    input  wire signed [15:0] peak_ch1,
    input  wire signed [15:0] peak_ch2,
    input  wire [31:0] area_ch1,
    input  wire [31:0] area_ch2,
    
    input  wire ch1_en,
    input  wire ch2_en,
    input  wire [1:0] metric_flag,
    
    input  wire [15:0] p_w_min, p_w_max,
    input  wire signed [15:0] p_h_min, p_h_max,
    
    input  wire [15:0] s_a1_min, s_a1_max,
    input  wire [15:0] s_a2_min, s_a2_max,
    
    input  wire actuator_armed,
    
    output reg trigger_sort
);

    // --- MONO-CHANNEL MULTIPLEXER (Primary Gates) ---
    // If CH1 is muted but CH2 is active, dynamically swap to evaluate CH2 bounds.
    wire use_ch2_mono = (ch2_en && !ch1_en);
    wire [15:0] mono_w = use_ch2_mono ? width_ch2 : width_ch1;
    wire signed [15:0] mono_p = use_ch2_mono ? peak_ch2 : peak_ch1;

    wire pass_primary = (mono_w >= p_w_min) && (mono_w <= p_w_max) &&
                        (mono_p >= p_h_min) && (mono_p <= p_h_max);
    
    // --- DUAL-CHANNEL MULTIPLEXER (Secondary Gates) ---
    reg [15:0] dual_x, dual_y;
    
    always @(*) begin
        case (metric_flag)
            2'b00: begin // AREA
                dual_x = (area_ch1 > 32'd16777215) ? 16'hFFFF : area_ch1[23:8];
                dual_y = (area_ch2 > 32'd16777215) ? 16'hFFFF : area_ch2[23:8];
            end
            2'b01: begin // HEIGHT 
                // Ensure negative noise floors don't roll over to massive unsigned ints
                dual_x = (peak_ch1[15]) ? 16'd0 : peak_ch1[15:0]; 
                dual_y = (peak_ch2[15]) ? 16'd0 : peak_ch2[15:0];
            end
            2'b10: begin // WIDTH
                dual_x = width_ch1;
                dual_y = width_ch2;
            end
            default: begin
                dual_x = 0; dual_y = 0;
            end
        endcase
    end

    wire pass_secondary = (dual_x >= s_a1_min) && (dual_x <= s_a1_max) &&
                          (dual_y >= s_a2_min) && (dual_y <= s_a2_max);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trigger_sort <= 0;
        end else begin
            trigger_sort <= 0; 
            if (trigger_eval) begin
                if (pass_primary && pass_secondary && actuator_armed) begin
                    trigger_sort <= 1'b1;
                end
            end
        end
    end
endmodule