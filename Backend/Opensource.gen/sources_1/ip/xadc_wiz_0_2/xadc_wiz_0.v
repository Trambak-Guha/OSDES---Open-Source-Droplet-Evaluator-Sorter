
// file: xadc_wiz_0.v
// (c) Copyright 2009 - 2023 AMD, Inc. All rights reserved.
// 
// This file contains confidential and proprietary information
// of AMD, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
// 
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// AMD, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) AMD shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or AMD had been advised of the
// possibility of the same.
// 
// CRITICAL APPLICATIONS
// AMD products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of AMD products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
// 
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
`timescale 1ns / 1 ps

(* CORE_GENERATION_INFO = "xadc_wiz_0,xadc_wiz_v3_3_12,{component_name=xadc_wiz_0,enable_axi=false,enable_axi4stream=true,dclk_frequency=104,enable_busy=true,enable_convst=false,enable_convstclk=false,enable_dclk=true,enable_drp=false,enable_eoc=true,enable_eos=true,enable_vbram_alaram=false,enable_vccddro_alaram=false,enable_Vccint_Alaram=true,enable_Vccaux_alaram=true,enable_vccpaux_alaram=false,enable_vccpint_alaram=false,ot_alaram=true,user_temp_alaram=true,timing_mode=continuous,channel_averaging=None,sequencer_mode=on,startup_channel_selection=simultaneous_sampling}" *)


module xadc_wiz_0
   (
  // axi4stream master signals 
    input s_axis_aclk,
    input m_axis_aclk,
    input m_axis_resetn,
    output [15 : 0] m_axis_tdata,
    output m_axis_tvalid,
    output [4 : 0] m_axis_tid,
    input m_axis_tready,
    input vauxp7,                                              
    input vauxn7,                                              
    input vauxp15,                                             
    input vauxn15,                                             
    output [4:0] channel_out,
    output busy_out,        
    output eoc_out, 
    output eos_out,
    output ot_out, 
    output vccaux_alarm_out,
    output vccint_alarm_out,
    output user_temp_alarm_out,
    output alarm_out ,                                          
    input vp_in,                                               
    input vn_in
);

          wire [7:0]  alm_int;
          assign alarm_out = alm_int[7];
          assign vccaux_alarm_out = alm_int[2];
          assign vccint_alarm_out = alm_int[1];
          assign user_temp_alarm_out = alm_int[0];

    xadc_wiz_0_axi_xadc 
    inst 
    (
    .s_axis_aclk     (s_axis_aclk),
    .m_axis_aclk     (m_axis_aclk),
    .m_axis_resetn   (m_axis_resetn),
              
    .m_axis_tdata    (m_axis_tdata),
    .m_axis_tvalid   (m_axis_tvalid),
    .m_axis_tid      (m_axis_tid),
    .m_axis_tready   (m_axis_tready),
    .vauxp7 (vauxp7),
    .vauxn7 (vauxn7),
    .vauxp15 (vauxp15),
    .vauxn15 (vauxn15),
    .channel_out(channel_out),
    .busy_out(busy_out), 
    .eoc_out(eoc_out), 
    .eos_out(eos_out),
    .ot_out(ot_out),
    .alarm_out  (alm_int),
    .vp_in (vp_in),
    .vn_in (vn_in)

          );


endmodule
