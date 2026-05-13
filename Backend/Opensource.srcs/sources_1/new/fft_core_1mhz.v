`timescale 1ns / 1ps

module fft_core_1mhz (
    input  wire clk,
    input  wire rst_n,
    input  wire sample_en,
    input  wire signed [15:0] wave_in,
    input  wire uart_trigger,      
    input  wire fifo_full,         
    output reg  tx_start_fft,
    output reg  [7:0] tx_data_fft
);

    (* ram_style = "block" *) reg signed [15:0] time_ram [0:8191]; 
    (* ram_style = "block" *) reg [31:0] freq_ram [0:4095];         
    
    reg [12:0] time_addr_w, time_addr_r;
    reg time_we, freq_we;
    reg signed [15:0] time_data_in, time_data_out;
    reg [11:0] freq_addr_w, freq_addr_r;
    reg [31:0] freq_data_in, freq_data_out;

    reg [12:0] idx = 0;
    wire [15:0] win_coeff;
    reg signed [31:0] mult_reg;
    reg [12:0] idx_d1; 
    reg sample_en_d1;        
    
    window_rom u_window (.clk(clk), .addr(idx), .data(win_coeff));

    always @(posedge clk) begin 
        mult_reg <= wave_in * $signed({1'b0, win_coeff});
        idx_d1 <= idx; sample_en_d1 <= sample_en; 
    end

    always @(posedge clk) begin 
        if (time_we) time_ram[time_addr_w] <= time_data_in;
        time_data_out <= time_ram[time_addr_r]; 
    end
    always @(posedge clk) begin 
        if (freq_we) freq_ram[freq_addr_w] <= freq_data_in; 
        freq_data_out <= freq_ram[freq_addr_r]; 
    end

    reg [31:0] fft_feeder_reg;
    reg fft_feeder_valid, fft_in_last;
    wire fft_in_ready, out_valid, out_last; 
    wire [31:0] out_data; 
    reg cfg_valid = 0; wire cfg_ready;
    reg ip_reset_n = 0; reg [7:0] rst_cnt = 0;
    reg capture_done, reset_capture_pulse;

    // ==========================================
    // --- XILINX IP INSTANTIATION ---
    // ==========================================
    xfft_0 u_xfft_inst (
        .aclk(clk), 
        .aresetn(ip_reset_n),
        .s_axis_config_tdata(16'd1), // 1 = Forward FFT (Block Floating Point handles scaling)
        .s_axis_config_tvalid(cfg_valid), 
        .s_axis_config_tready(cfg_ready),
        .s_axis_data_tdata(fft_feeder_reg), 
        .s_axis_data_tvalid(fft_feeder_valid), 
        .s_axis_data_tready(fft_in_ready), 
        .s_axis_data_tlast(fft_in_last),
        .m_axis_data_tdata(out_data), 
        .m_axis_data_tvalid(out_valid), 
        .m_axis_data_tlast(out_last), 
        .m_axis_data_tready(1'b1),        // Prevent Data Stalling
        .m_axis_status_tready(1'b1)       // <--- THE FIX: Prevent Status Stalling
    );
    // ==========================================
    
    localparam S_BOOT=0, S_RESET=1, S_CONFIG=2, S_COLLECT=3, S_FEED=4, S_WAIT=5;
    reg [3:0] state = S_BOOT;
    reg [13:0] feed_idx = 0; 
    wire tx_active_flag; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_BOOT; time_we <= 0; ip_reset_n <= 0; cfg_valid <= 0; reset_capture_pulse <= 0; idx <= 0;
        end else begin
            time_we <= 0; reset_capture_pulse <= 0;
            case (state)
                S_BOOT: begin ip_reset_n <= 0; rst_cnt <= 0; state <= S_RESET; idx <= 0; end
                S_RESET: begin
                    if (rst_cnt == 100) begin ip_reset_n <= 1; state <= S_CONFIG; end 
                    else rst_cnt <= rst_cnt + 1;
                end
                S_CONFIG: begin 
                    if (rst_cnt == 120) begin 
                        cfg_valid <= 1;
                        if (cfg_ready) begin cfg_valid <= 0; time_addr_w <= 0; idx <= 0; state <= S_COLLECT; end
                    end else rst_cnt <= rst_cnt + 1;
                end
                S_COLLECT: begin 
                    if (sample_en) begin if (idx == 8191) idx <= 0; else idx <= idx + 1; end
                    if (sample_en_d1) begin
                        time_addr_w <= idx_d1; time_data_in <= mult_reg[31:16]; time_we <= 1;
                        if (idx_d1 == 8191) begin state <= S_FEED; feed_idx <= 0; time_addr_r <= 0; end
                    end
                end
                S_FEED: begin 
                    if (!fft_feeder_valid && feed_idx < 8192) begin
                        fft_feeder_reg <= {16'd0, time_data_out}; fft_feeder_valid <= 1; fft_in_last <= (feed_idx == 8191);
                        if (feed_idx < 8191) time_addr_r <= feed_idx + 1;
                        feed_idx <= feed_idx + 1; 
                    end
                    if (fft_in_ready && fft_feeder_valid) begin 
                        fft_feeder_valid <= 0;
                        if (fft_in_last) state <= S_WAIT; 
                    end
                end
                S_WAIT: begin
                    if (capture_done && !tx_active_flag) begin reset_capture_pulse <= 1; state <= S_COLLECT; end
                end
            endcase
        end
    end

    reg [31:0] out_data_reg;
    reg out_valid_d1 = 0, out_valid_d2 = 0, pipe1_valid = 0, pipe2_valid = 0;
    wire signed [15:0] real_raw = out_data_reg[15:0];
    wire signed [15:0] imag_raw = out_data_reg[31:16];
    wire [15:0] abs_r = (real_raw[15]) ? -$signed(real_raw) : real_raw;
    wire [15:0] abs_i = (imag_raw[15]) ? -$signed(imag_raw) : imag_raw;
    reg [31:0] pipe1_r, pipe1_i, pipe2_r_sq, pipe2_i_sq;
    reg [12:0] out_idx = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            capture_done <= 0; out_idx <= 0; freq_we <= 0; out_valid_d1 <= 0; out_valid_d2 <= 0; pipe1_valid <= 0; pipe2_valid <= 0;
            pipe1_r <= 0; pipe1_i <= 0; pipe2_r_sq <= 0; pipe2_i_sq <= 0; out_data_reg <= 0;
        end else begin
            freq_we <= 0;
            if (reset_capture_pulse) begin 
                capture_done <= 0; out_idx <= 0; out_valid_d1 <= 0; out_valid_d2 <= 0; pipe1_valid <= 0; pipe2_valid <= 0;
            end else begin
                out_valid_d1 <= out_valid; out_valid_d2 <= out_valid_d1;
                pipe1_valid <= out_valid_d1; pipe2_valid <= pipe1_valid;
                
                if (out_valid) out_data_reg <= out_data[31:0];
                
                if (out_valid_d1) begin
                    pipe1_r <= (abs_r >>> 2); pipe1_i <= (abs_i >>> 2); out_idx <= out_idx + 1;
                end
                
                if (pipe1_valid) begin
                    pipe2_r_sq <= pipe1_r * pipe1_r; pipe2_i_sq <= pipe1_i * pipe1_i;
                end
                
                if (pipe2_valid && out_idx > 2 && out_idx <= 4098) begin
                    freq_addr_w <= out_idx[11:0] - 3; 
                    if (out_idx == 3) freq_data_in <= 0; else freq_data_in <= pipe2_r_sq + pipe2_i_sq; 
                    freq_we <= 1;
                end
                
                if (out_last) capture_done <= 1;
            end
        end
    end

    localparam T_IDLE=0, T_READ=1, T_LATCH=2, T_WAIT=3;
    reg [2:0] tx_state = T_IDLE; reg [12:0] send_idx = 0; reg [1:0] byte_sel = 0; reg trigger_pending = 0;
    assign tx_active_flag = (tx_state != T_IDLE); 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin tx_state <= T_IDLE; tx_start_fft <= 0; freq_addr_r <= 0; trigger_pending <= 0; end 
        else begin
            tx_start_fft <= 0;
            if (uart_trigger) trigger_pending <= 1;

            case (tx_state)
                T_IDLE: begin
                    if (trigger_pending) begin
                        trigger_pending <= 0; tx_data_fft <= 8'hAA; tx_start_fft <= 1;
                        send_idx <= 0; byte_sel <= 0; freq_addr_r <= 0; tx_state <= T_READ;
                    end
                end
                T_READ: tx_state <= T_LATCH; 
                T_LATCH: begin
                    if (!fifo_full) begin
                        if (byte_sel == 0)      begin tx_data_fft <= freq_data_out[7:0];   tx_start_fft <= 1; byte_sel <= 1; tx_state <= T_WAIT; end
                        else if (byte_sel == 1) begin tx_data_fft <= freq_data_out[15:8];  tx_start_fft <= 1; byte_sel <= 2; tx_state <= T_WAIT; end
                        else if (byte_sel == 2) begin tx_data_fft <= freq_data_out[23:16]; tx_start_fft <= 1; byte_sel <= 3; tx_state <= T_WAIT; end
                        else begin 
                            tx_data_fft <= freq_data_out[31:24]; tx_start_fft <= 1; byte_sel <= 0; 
                            if (send_idx == 4095) tx_state <= T_IDLE;
                            else begin send_idx <= send_idx + 1; freq_addr_r <= send_idx + 1; tx_state <= T_READ; end 
                        end
                    end
                end
                T_WAIT: tx_state <= T_LATCH; 
            endcase
        end
    end
endmodule