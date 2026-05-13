`timescale 1ns / 1ps

module pulse_integrator_1mhz (
    input  wire clk,
    input  wire rst_n,
    input  wire sample_en,               
    input  wire signed [15:0] wave_in_ch1, 
    input  wire signed [15:0] wave_in_ch2, 
    input  wire ch1_en,
    input  wire ch2_en,
    
    input  wire tfads_strict_mode,
    input  wire primary_pmt_select,
    
    input  wire signed [15:0] threshold_ch1,
    input  wire signed [15:0] threshold_ch2,

    output reg trigger_eval,             
    output reg [15:0] final_width_ch1,       
    output reg [15:0] final_width_ch2,       
    output reg signed [15:0] final_peak_ch1, 
    output reg signed [15:0] final_peak_ch2,
    output reg [31:0] final_area_ch1,    
    output reg [31:0] final_area_ch2     
);

    reg [15:0] width_ch1 = 0;
    reg [15:0] width_ch2 = 0;
    reg signed [15:0] peak_tracker_ch1 = 0;
    reg signed [15:0] peak_tracker_ch2 = 0;
    reg [31:0] area_tracker_ch1 = 0;
    reg [31:0] area_tracker_ch2 = 0;

    wire ch1_active = (wave_in_ch1 > threshold_ch1) & ch1_en;
    wire ch2_active = (wave_in_ch2 > threshold_ch2) & ch2_en;

    wire master_active = primary_pmt_select ? ch2_active : ch1_active;
    wire global_active = tfads_strict_mode ? master_active : (ch1_active | ch2_active);

    reg prev_global_active = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_global_active <= 0; trigger_eval <= 0; 
            width_ch1 <= 0; width_ch2 <= 0;
            peak_tracker_ch1 <= 0; peak_tracker_ch2 <= 0;
            area_tracker_ch1 <= 0; area_tracker_ch2 <= 0;
            final_width_ch1 <= 0; final_width_ch2 <= 0; 
            final_peak_ch1 <= 0; final_peak_ch2 <= 0;
            final_area_ch1 <= 0; final_area_ch2 <= 0;
        end else begin
            trigger_eval <= 0; 
            if (sample_en) begin
                prev_global_active <= global_active;
                
                if (global_active) begin
                    if (tfads_strict_mode) begin
                        // MASTER MODE: Both widths identical, unconditional areas
                        width_ch1 <= width_ch1 + 1;
                        width_ch2 <= width_ch2 + 1;
                        
                        if (wave_in_ch1 > 0) area_tracker_ch1 <= area_tracker_ch1 + wave_in_ch1;
                        if (wave_in_ch2 > 0) area_tracker_ch2 <= area_tracker_ch2 + wave_in_ch2;
                        
                        if (wave_in_ch1 > peak_tracker_ch1) peak_tracker_ch1 <= wave_in_ch1;
                        if (wave_in_ch2 > peak_tracker_ch2) peak_tracker_ch2 <= wave_in_ch2;
                    end else begin
                        // NORMAL MODE: Independent stopwatches & areas
                        if (ch1_active) begin
                            width_ch1 <= width_ch1 + 1;
                            area_tracker_ch1 <= area_tracker_ch1 + wave_in_ch1;
                            if (wave_in_ch1 > peak_tracker_ch1) peak_tracker_ch1 <= wave_in_ch1;
                        end
                        if (ch2_active) begin
                            width_ch2 <= width_ch2 + 1;
                            area_tracker_ch2 <= area_tracker_ch2 + wave_in_ch2;
                            if (wave_in_ch2 > peak_tracker_ch2) peak_tracker_ch2 <= wave_in_ch2;
                        end
                    end
                    
                end else if (!global_active && prev_global_active) begin
                    final_width_ch1 <= width_ch1;
                    final_width_ch2 <= width_ch2;
                    final_peak_ch1 <= peak_tracker_ch1;
                    final_peak_ch2 <= peak_tracker_ch2;
                    final_area_ch1 <= area_tracker_ch1;
                    final_area_ch2 <= area_tracker_ch2;
                    trigger_eval <= 1'b1;
                    
                    width_ch1 <= 0; width_ch2 <= 0;
                    peak_tracker_ch1 <= 0; peak_tracker_ch2 <= 0;
                    area_tracker_ch1 <= 0; area_tracker_ch2 <= 0;
                end
            end
        end
    end
endmodule