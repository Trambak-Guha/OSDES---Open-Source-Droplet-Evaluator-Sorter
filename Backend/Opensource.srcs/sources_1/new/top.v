`timescale 1ns / 1ps

module top #(
    parameter CLK_FREQ  = 104_000_000, 
    parameter BAUD_RATE = 2_000_000
)(
    input  wire clk, uart_rx, 
    input  wire vauxp7, vauxn7,     
    input  wire vauxp15, vauxn15,   
    input  wire [1:0] sw,          
    output wire uart_tx, electrode_out, 
    output wire [3:0] leds,
    output wire [2:0] dso_probe    
);

    wire clk_104mhz, locked;
    clk_wiz_0 u_pll (.clk_in1(clk), .clk_out1(clk_104mhz), .reset(1'b0), .locked(locked));
    wire rst_n = locked; 

    // --- UART CONFIGURATION REGISTERS ---
    wire [7:0] filter_alpha; 
    wire filter_reg; 
    wire signed [15:0] threshold, threshold_ch2; 
    wire [15:0] p_w_min, p_w_max; 
    wire signed [15:0] p_h_min, p_h_max;
    wire [15:0] s_a1_min, s_a1_max;
    wire [15:0] s_a2_min, s_a2_max;
    wire actuator_armed;
    
    // --- THE NEW CONTROL WIRES ---
    wire tfads_strict_mode;
    wire primary_pmt_select;
    wire [1:0] metric_flag; 
    
    wire [15:0] delay_us, pulse_width_us, ac_half_period_ticks; 
    wire [1:0] tx_mode; 
    wire fft_trigger;
    wire [7:0] ch1_gain, ch2_gain; 
    wire ch1_en, ch2_en;

    uart_packet_parser u_parser (
        .clk(clk_104mhz), .rst_n(rst_n), .rx_serial(uart_rx),
        .filter_alpha(filter_alpha), .filter_reg(filter_reg), 
        .threshold(threshold), .threshold_ch2(threshold_ch2),
        .p_w_min(p_w_min), .p_w_max(p_w_max), .p_h_min(p_h_min), .p_h_max(p_h_max),
        .s_a1_min(s_a1_min), .s_a1_max(s_a1_max), .s_a2_min(s_a2_min), .s_a2_max(s_a2_max),
        .delay_us(delay_us), .pulse_width_us(pulse_width_us), 
        .ac_half_period_ticks(ac_half_period_ticks), 
        .ch1_gain(ch1_gain), .ch2_gain(ch2_gain), 
        .ch1_en(ch1_en), .ch2_en(ch2_en), 
        
        .actuator_armed(actuator_armed),
        .tfads_strict_mode(tfads_strict_mode),       
        .primary_pmt_select(primary_pmt_select),     
        .metric_flag(metric_flag), 
        
        .tx_mode(tx_mode), .fft_trigger(fft_trigger)
    );

    reg [257:0] prev_config = 0;
    reg cfg_valid = 0;
    always @(posedge clk_104mhz) begin
        prev_config <= {p_w_min, p_w_max, p_h_min, p_h_max, s_a1_min, s_a1_max, s_a2_min, s_a2_max, threshold, delay_us, pulse_width_us, filter_alpha, ch1_gain, ch2_gain, actuator_armed, tfads_strict_mode, primary_pmt_select, metric_flag};
        cfg_valid <= ({p_w_min, p_w_max, p_h_min, p_h_max, s_a1_min, s_a1_max, s_a2_min, s_a2_max, threshold, delay_us, pulse_width_us, filter_alpha, ch1_gain, ch2_gain, actuator_armed, tfads_strict_mode, primary_pmt_select, metric_flag} != prev_config); 
    end

    reg [1:0] tx_mode_prev = 0;
    reg flush_fifos = 0;
    always @(posedge clk_104mhz) begin
        tx_mode_prev <= tx_mode;
        flush_fifos <= (tx_mode != tx_mode_prev) | cfg_valid; 
    end

    // =========================================================
    // --- TRUE 1 MSPS AXI4-STREAM ADC INGESTION ---
    // =========================================================
    wire [15:0] axi_tdata;
    wire [4:0]  axi_tid;
    wire        axi_tvalid;
    
    xadc_wiz_0 u_xadc_axi_stream (
        .s_axis_aclk   (clk_104mhz),
        .m_axis_aclk   (clk_104mhz),
        .m_axis_resetn (rst_n),
        .vp_in         (1'b0),     
        .vn_in         (1'b0),     
        .vauxp7        (vauxp7),
        .vauxn7        (vauxn7),
        .vauxp15       (vauxp15),
        .vauxn15       (vauxn15),
        .channel_out   (), .eoc_out(), .alarm_out(), .eos_out(), .busy_out(),
        .m_axis_tdata  (axi_tdata),
        .m_axis_tvalid (axi_tvalid),
        .m_axis_tid    (axi_tid),
        .m_axis_tready (1'b1) 
    );

    reg signed [15:0] ch1_raw_aligned = 0;
    reg signed [15:0] ch2_raw_aligned = 0;
    reg dual_sample_valid = 0;

    always @(posedge clk_104mhz) begin
        dual_sample_valid <= 0;
        if (axi_tvalid) begin
            if (axi_tid == 5'h17) begin
                ch1_raw_aligned <= {4'b0, axi_tdata[15:4]};
            end else if (axi_tid == 5'h1F) begin 
                ch2_raw_aligned <= {4'b0, axi_tdata[15:4]};
                dual_sample_valid <= 1'b1; 
            end
        end
    end

    // =========================================================
    // --- DSP FAST LANE (DUAL PIPELINE) ---
    // =========================================================
    wire signed [15:0] ch1_centered, ch1_clean;
    wire signed [15:0] ch2_centered, ch2_clean;

    dc_removal_1mhz u_dc_ch1 (.clk(clk_104mhz), .rst_n(rst_n), .sample_en(dual_sample_valid), .data_in(ch1_raw_aligned), .data_out(ch1_centered));
    dc_removal_1mhz u_dc_ch2 (.clk(clk_104mhz), .rst_n(rst_n), .sample_en(dual_sample_valid), .data_in(ch2_raw_aligned), .data_out(ch2_centered));
    lpf_1mhz u_lpf_ch1 (.clk(clk_104mhz), .rst_n(rst_n), .sample_en(dual_sample_valid), .data_in(ch1_centered), .alpha(filter_alpha), .data_out(ch1_clean));
    lpf_1mhz u_lpf_ch2 (.clk(clk_104mhz), .rst_n(rst_n), .sample_en(dual_sample_valid), .data_in(ch2_centered), .alpha(filter_alpha), .data_out(ch2_clean));

    wire signed [15:0] ch1_filtered = (filter_reg) ? ch1_clean : ch1_centered;
    wire signed [15:0] ch2_filtered = (filter_reg) ? ch2_clean : ch2_centered;

    wire signed [23:0] ch1_scaled_comb = ch1_filtered * $signed({1'b0, ch1_gain});
    wire signed [23:0] ch2_scaled_comb = ch2_filtered * $signed({1'b0, ch2_gain});
    
    reg signed [15:0] wave_final_ch1 = 0;
    reg signed [15:0] wave_final_ch2 = 0;
    
    always @(posedge clk_104mhz) begin
        wave_final_ch1 <= ch1_scaled_comb[15:0];
        wave_final_ch2 <= ch2_scaled_comb[15:0];
    end

    // =========================================================
    // --- AREA INTEGRATOR & HIERARCHICAL GATES ---
    // =========================================================
    wire trigger_eval;
    wire [15:0] width_ch1, width_ch2;
    wire signed [15:0] peak_ch1, peak_ch2;
    wire [31:0] area_ch1, area_ch2;

    pulse_integrator_1mhz u_integrator (
        .clk(clk_104mhz), .rst_n(rst_n), .sample_en(dual_sample_valid),
        .wave_in_ch1(wave_final_ch1), .wave_in_ch2(wave_final_ch2),
        .ch1_en(ch1_en), .ch2_en(ch2_en), 
        
        .tfads_strict_mode(tfads_strict_mode),       
        .primary_pmt_select(primary_pmt_select),     
        
        .threshold_ch1(threshold), .threshold_ch2(threshold_ch2),
        .trigger_eval(trigger_eval), 
        .final_width_ch1(width_ch1), .final_width_ch2(width_ch2),
        .final_peak_ch1(peak_ch1), .final_peak_ch2(peak_ch2),
        .final_area_ch1(area_ch1), .final_area_ch2(area_ch2)
    );

    wire trigger_sort; wire [31:0] hardware_tally; 
    
    sorter_core_1mhz u_sorter (
        .clk(clk_104mhz), .rst_n(rst_n), .trigger_eval(trigger_eval),
        .width_ch1(width_ch1), .width_ch2(width_ch2),
        .peak_ch1(peak_ch1), .peak_ch2(peak_ch2),
        .area_ch1(area_ch1), .area_ch2(area_ch2),
        .ch1_en(ch1_en), .ch2_en(ch2_en), .metric_flag(metric_flag),
        .p_w_min(p_w_min), .p_w_max(p_w_max), .p_h_min(p_h_min), .p_h_max(p_h_max),
        .s_a1_min(s_a1_min), .s_a1_max(s_a1_max), .s_a2_min(s_a2_min), .s_a2_max(s_a2_max),
        .actuator_armed(actuator_armed), .trigger_sort(trigger_sort)
    );

    actuator_core_1mhz u_actuator (
        .clk(clk_104mhz), .rst_n(rst_n), .sample_en(dual_sample_valid), .cfg_valid(cfg_valid),
        .trigger_in(trigger_sort), .delay_us(delay_us), .pulse_width_us(pulse_width_us), 
        .ac_half_period_ticks(ac_half_period_ticks), .electrode_out(electrode_out), .hardware_tally(hardware_tally)
    );

    // =========================================================
    // --- DUAL-CHANNEL INTERLEAVED TIME DOMAIN ---
    // =========================================================
    localparam S_ARMED = 0, S_WAIT_TRIGGER = 1, S_HEADER = 2, S_CAP_CH1 = 3, S_CAP_CH2 = 4, S_DRAINING = 5;
    reg [2:0] osc_state = S_ARMED;
    reg [11:0] capture_cnt = 0; 
    
    reg time_wr_en; reg [7:0] time_din;
    wire signed [15:0] scaled_ch1 = (wave_final_ch1 >>> 4); 
    wire signed [15:0] scaled_ch2 = (wave_final_ch2 >>> 4); 
    wire time_empty, time_rd_en; wire [7:0] time_dout;

    wire ch1_is_high = (wave_final_ch1 > threshold) & ch1_en;
    wire ch2_is_high = (wave_final_ch2 > threshold_ch2) & ch2_en;
    
    reg prev_ch1_high, prev_ch2_high;
    always @(posedge clk_104mhz) begin
        if (dual_sample_valid) begin
            prev_ch1_high <= ch1_is_high;
            prev_ch2_high <= ch2_is_high;
        end
    end
    
    wire osc_trigger = dual_sample_valid && ((ch1_is_high && !prev_ch1_high) || (ch2_is_high && !prev_ch2_high));

    // --- CONTINUOUS ROLLING MODE ---
    // The hardware trigger has been explicitly bypassed. 
    // The system now forces a capture every 200,000 clock cycles (~1.9ms) 
    // regardless of whether a signal crosses the threshold.
    reg [23:0] auto_trigger_cnt = 0;

    always @(posedge clk_104mhz or negedge rst_n) begin
        if (!rst_n) begin 
            osc_state <= S_ARMED; capture_cnt <= 0; time_wr_en <= 0; auto_trigger_cnt <= 0; 
        end else begin
            time_wr_en <= 0; 

            if (osc_state == S_WAIT_TRIGGER) auto_trigger_cnt <= auto_trigger_cnt + 1;
            else auto_trigger_cnt <= 0;

            case (osc_state)
                S_ARMED: if (time_empty && tx_mode == 0) osc_state <= S_WAIT_TRIGGER;
                S_WAIT_TRIGGER: begin
                    if (tx_mode != 0) osc_state <= S_ARMED; 
                    // ---> FIX IS HERE: osc_trigger removed, forcing continuous asynchronous capture
                    else if (auto_trigger_cnt > 24'd200_000) begin 
                        osc_state <= S_HEADER; capture_cnt <= 0; 
                    end
                end
                S_HEADER: begin time_din <= 8'hFF; time_wr_en <= 1; osc_state <= S_CAP_CH1; end
                S_CAP_CH1: begin
                    if (dual_sample_valid) begin
                        if (scaled_ch1 >= 16'sd126) time_din <= 8'hFE; else if (scaled_ch1 <= -16'sd128) time_din <= 8'h00; else time_din <= scaled_ch1[7:0] + 8'd128; 
                        time_wr_en <= 1; osc_state <= S_CAP_CH2; 
                    end
                end
                S_CAP_CH2: begin
                    if (scaled_ch2 >= 16'sd126) time_din <= 8'hFE; else if (scaled_ch2 <= -16'sd128) time_din <= 8'h00; else time_din <= scaled_ch2[7:0] + 8'd128; 
                    time_wr_en <= 1;
                    if (capture_cnt == 1999) osc_state <= S_DRAINING;
                    else begin capture_cnt <= capture_cnt + 1; osc_state <= S_CAP_CH1; end
                end
                S_DRAINING: if (time_empty) osc_state <= S_ARMED;
                default: osc_state <= S_ARMED;
            endcase
        end
    end

    fifo_buffer_8b #(.DEPTH(4096)) u_fifo_time (
        .clk(clk_104mhz), .rst_n(rst_n), .clear(flush_fifos), .wr_en(time_wr_en), .din(time_din),
        .rd_en(time_rd_en), .dout(time_dout), .empty(time_empty), .full()
    );

    wire fft_wr_en; wire [7:0] fft_din; wire fft_full; 
    fft_core_1mhz u_fft (
        .clk(clk_104mhz), .rst_n(rst_n), .sample_en(dual_sample_valid), 
        .wave_in(wave_final_ch1), .uart_trigger(fft_trigger), .fifo_full(fft_full), 
        .tx_start_fft(fft_wr_en), .tx_data_fft(fft_din)
    );

    wire fft_empty, fft_rd_en; wire [7:0] fft_dout;
    fifo_buffer_8b #(.DEPTH(4096)) u_fifo_fft (
        .clk(clk_104mhz), .rst_n(rst_n), .clear(flush_fifos), .wr_en(fft_wr_en), .din(fft_din),
        .rd_en(fft_rd_en), .dout(fft_dout), .empty(fft_empty), .full(fft_full) 
    );

    wire scat_wr_logger; wire [7:0] scat_din_logger; wire [12:0] scat_count; 
    
    pulse_logger_1mhz u_logger (
        .clk(clk_104mhz), .rst_n(rst_n), .trigger_log(trigger_eval), 
        .width_ch1(width_ch1), .width_ch2(width_ch2), 
        .peak_ch1(peak_ch1), .peak_ch2(peak_ch2), 
        .area_ch1(area_ch1), .area_ch2(area_ch2),
        .fifo_count(scat_count), .fifo_wr_en(scat_wr_logger), .fifo_din(scat_din_logger)
    );

    reg [3:0] logger_idle_cnt = 0;
    always @(posedge clk_104mhz) begin
        if (scat_wr_logger) logger_idle_cnt <= 0;
        else if (logger_idle_cnt < 15) logger_idle_cnt <= logger_idle_cnt + 1;
    end

    reg [23:0] tally_timer = 0; reg [2:0] tally_state = 0; reg tally_wr_en = 0; reg [7:0] tally_din = 0;
    always @(posedge clk_104mhz or negedge rst_n) begin
        if (!rst_n) begin tally_timer <= 0; tally_state <= 0; tally_wr_en <= 0; end 
        else begin
            tally_wr_en <= 0; 
            if (tally_state == 0) begin
                if (tally_timer >= 24'd10_400_000) begin
                    if (logger_idle_cnt == 15 && scat_count < 13'd4000) begin tally_state <= 1; tally_timer <= 0; end
                end else tally_timer <= tally_timer + 1;
            end else begin
                case (tally_state)
                    1: begin tally_din <= 8'hCC; tally_wr_en <= 1; tally_state <= 2; end
                    2: begin tally_din <= hardware_tally[31:24]; tally_wr_en <= 1; tally_state <= 3; end
                    3: begin tally_din <= hardware_tally[23:16]; tally_wr_en <= 1; tally_state <= 4; end
                    4: begin tally_din <= hardware_tally[15:8]; tally_wr_en <= 1; tally_state <= 5; end
                    5: begin tally_din <= hardware_tally[7:0]; tally_wr_en <= 1; tally_state <= 0; end
                endcase
            end
        end
    end

    wire final_scat_wr_en = scat_wr_logger | tally_wr_en;
    wire [7:0] final_scat_din = tally_wr_en ? tally_din : scat_din_logger;
    wire scat_empty, scat_rd_en, scat_full; wire [7:0] scat_dout;

    fifo_buffer_8b #(.DEPTH(4096)) u_fifo_scat (
        .clk(clk_104mhz), .rst_n(rst_n), .clear(flush_fifos), .wr_en(final_scat_wr_en), .din(final_scat_din),
        .rd_en(scat_rd_en), .dout(scat_dout), .empty(scat_empty), .full(scat_full), .current_count(scat_count)        
    );

    wire uart_busy; wire tx_start_arb; wire [7:0] tx_data_arb;
    telemetry_arbiter u_arbiter (
        .clk(clk_104mhz), .rst_n(rst_n), .tx_mode(tx_mode), .uart_busy(uart_busy),
        .time_empty(time_empty), .time_dout(time_dout), .time_rd_en(time_rd_en),
        .fft_empty(fft_empty),   .fft_dout(fft_dout),   .fft_rd_en(fft_rd_en),
        .scat_empty(scat_empty), .scat_dout(scat_dout), .scat_rd_en(scat_rd_en),
        .tx_start(tx_start_arb), .tx_data(tx_data_arb)
    );

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx_phy (
        .clk(clk_104mhz), .rst_n(rst_n), .start(tx_start_arb), .data_in(tx_data_arb), 
        .tx_active(uart_busy), .tx_serial(uart_tx), .tx_done()
    );

    reg [19:0] led_timer = 0;
    always @(posedge clk_104mhz) begin
        if (electrode_out) led_timer <= 20'd1_000_000; else if (led_timer > 0) led_timer <= led_timer - 1;
    end
    assign leds[0] = (led_timer > 0); assign leds[1] = locked; assign leds[2] = trigger_sort; assign leds[3] = scat_empty; 
    
    reg delay_stopwatch = 0;
    always @(posedge clk_104mhz) begin
        if (trigger_sort) delay_stopwatch <= 1'b1; else if (electrode_out) delay_stopwatch <= 1'b0; 
    end
    reg dso_armed = 0;
    always @(posedge clk_104mhz or negedge rst_n) begin
        if (!rst_n) dso_armed <= 0; else if (cfg_valid) dso_armed <= 1'b1; 
    end
    reg diagnostic_signal;
    always @(*) begin
        case (sw)
            2'b00: diagnostic_signal = (wave_final_ch1 > threshold) & dso_armed;
            2'b01: diagnostic_signal = ((wave_final_ch1 > threshold) | electrode_out) & dso_armed;
            2'b10: diagnostic_signal = electrode_out & dso_armed; 
            2'b11: diagnostic_signal = delay_stopwatch & dso_armed;
        endcase
    end
    assign dso_probe[0] = diagnostic_signal; assign dso_probe[1] = 1'b0; assign dso_probe[2] = 1'b0; 
endmodule