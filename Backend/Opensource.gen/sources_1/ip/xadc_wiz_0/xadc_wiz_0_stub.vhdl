-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2025.1 (win64) Build 6140274 Thu May 22 00:12:29 MDT 2025
-- Date        : Wed Mar 25 15:58:19 2026
-- Host        : LIMSDBEBone running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub -rename_top xadc_wiz_0 -prefix
--               xadc_wiz_0_ xadc_wiz_0_stub.vhdl
-- Design      : xadc_wiz_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7a35tcsg324-1
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity xadc_wiz_0 is
  Port ( 
    daddr_in : in STD_LOGIC_VECTOR ( 6 downto 0 );
    dclk_in : in STD_LOGIC;
    den_in : in STD_LOGIC;
    di_in : in STD_LOGIC_VECTOR ( 15 downto 0 );
    dwe_in : in STD_LOGIC;
    reset_in : in STD_LOGIC;
    vauxp0 : in STD_LOGIC;
    vauxn0 : in STD_LOGIC;
    busy_out : out STD_LOGIC;
    channel_out : out STD_LOGIC_VECTOR ( 4 downto 0 );
    do_out : out STD_LOGIC_VECTOR ( 15 downto 0 );
    drdy_out : out STD_LOGIC;
    eoc_out : out STD_LOGIC;
    eos_out : out STD_LOGIC;
    ot_out : out STD_LOGIC;
    vccaux_alarm_out : out STD_LOGIC;
    vccint_alarm_out : out STD_LOGIC;
    user_temp_alarm_out : out STD_LOGIC;
    alarm_out : out STD_LOGIC;
    muxaddr_out : out STD_LOGIC_VECTOR ( 4 downto 0 );
    vp_in : in STD_LOGIC;
    vn_in : in STD_LOGIC
  );

  attribute CORE_GENERATION_INFO : string;
  attribute CORE_GENERATION_INFO of xadc_wiz_0 : entity is "xadc_wiz_0,xadc_wiz_v3_3_12,{component_name=xadc_wiz_0,enable_axi=false,enable_axi4stream=false,dclk_frequency=104,enable_busy=true,enable_convst=false,enable_convstclk=false,enable_dclk=true,enable_drp=true,enable_eoc=true,enable_eos=true,enable_vbram_alaram=false,enable_vccddro_alaram=false,enable_Vccint_Alaram=true,enable_Vccaux_alaram=true,enable_vccpaux_alaram=false,enable_vccpint_alaram=false,ot_alaram=true,user_temp_alaram=true,timing_mode=continuous,channel_averaging=None,sequencer_mode=off,startup_channel_selection=single_channel}";
end xadc_wiz_0;

architecture stub of xadc_wiz_0 is
  attribute syn_black_box : boolean;
  attribute black_box_pad_pin : string;
  attribute syn_black_box of stub : architecture is true;
  attribute black_box_pad_pin of stub : architecture is "daddr_in[6:0],dclk_in,den_in,di_in[15:0],dwe_in,reset_in,vauxp0,vauxn0,busy_out,channel_out[4:0],do_out[15:0],drdy_out,eoc_out,eos_out,ot_out,vccaux_alarm_out,vccint_alarm_out,user_temp_alarm_out,alarm_out,muxaddr_out[4:0],vp_in,vn_in";
begin
end;
