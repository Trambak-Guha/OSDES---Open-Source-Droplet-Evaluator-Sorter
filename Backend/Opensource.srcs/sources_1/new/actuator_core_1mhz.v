`timescale 1ns / 1ps

module actuator_core_1mhz (
    input  wire clk,
    input  wire rst_n,
    input  wire sample_en,
    input  wire cfg_valid,
    input  wire trigger_in,
    input  wire [15:0] delay_us,
    input  wire [15:0] pulse_width_us,
    input  wire [15:0] ac_half_period_ticks, 

    output reg  electrode_out,
    output reg  [31:0] hardware_tally
);

    // --- TIMING FIX: REGISTERED MULTIPLIERS ---
    // By changing these from 'wires' to clocked 'regs', Vivado uses the 
    // internal DSP pipeline registers, instantly closing timing.
    reg [31:0] delay_ticks = 0;
    reg [31:0] pulse_ticks = 0;
    
    always @(posedge clk) begin
        delay_ticks <= delay_us * 104;
        pulse_ticks <= pulse_width_us * 104;
    end

    reg [1:0] state;
    reg [31:0] timer;
    reg [15:0] ac_timer;
    reg ac_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0;
            timer <= 0;
            ac_timer <= 0;
            ac_state <= 0;
            electrode_out <= 0;
            hardware_tally <= 0;
        end else begin
            if (cfg_valid) begin
                hardware_tally <= 0; 
            end

            case (state)
                0: begin
                    electrode_out <= 0;
                    if (trigger_in) begin
                        state <= 1;
                        timer <= 0;
                        hardware_tally <= hardware_tally + 1; 
                    end
                end
                1: begin // DELAY PHASE
                    if (timer >= delay_ticks) begin
                        state <= 2;
                        timer <= 0;
                        ac_timer <= 0;
                        ac_state <= 1;
                        electrode_out <= 1;
                    end else begin
                        timer <= timer + 1;
                    end
                end
                2: begin // AC BURST PHASE
                    if (timer >= pulse_ticks) begin
                        state <= 0;
                        electrode_out <= 0;
                    end else begin
                        timer <= timer + 1;
                        
                        if (ac_timer >= ac_half_period_ticks) begin
                            ac_timer <= 0;
                            ac_state <= ~ac_state;
                            electrode_out <= ~ac_state;
                        end else begin
                            ac_timer <= ac_timer + 1;
                            electrode_out <= ac_state;
                        end
                    end
                end
            endcase
        end
    end
endmodule