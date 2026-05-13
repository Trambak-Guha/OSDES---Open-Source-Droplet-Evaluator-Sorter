## Clock Signal (Bank 35)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## UART (Bank 16)
set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports uart_tx]
set_property -dict { PACKAGE_PIN A9    IOSTANDARD LVCMOS33 } [get_ports uart_rx]

## LEDs (Bank 35 & 14)
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports {leds[0]}]
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports {leds[1]}]
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports {leds[2]}]
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports {leds[3]}]

## RESET BUTTON
#set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports rst]

## ========================================================
## DUAL SIMULTANEOUS ANALOG INPUTS (Bank 35)
## ========================================================
# CH1: TRANSMITTANCE -> Arty Header A3 (VAUX7)
set_property -dict { PACKAGE_PIN B1    IOSTANDARD LVCMOS33 } [get_ports vauxp7]
set_property -dict { PACKAGE_PIN A1    IOSTANDARD LVCMOS33 } [get_ports vauxn7]

# CH2: FLUORESCENCE -> Arty Header A4 (VAUX15)
set_property -dict { PACKAGE_PIN B3    IOSTANDARD LVCMOS33 } [get_ports vauxp15]
set_property -dict { PACKAGE_PIN B2    IOSTANDARD LVCMOS33 } [get_ports vauxn15]

## ========================================================
## DIAGNOSTIC SWITCHES & OUTPUTS
## ========================================================
set_property -dict { PACKAGE_PIN A8    IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN C11   IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN F3    IOSTANDARD LVCMOS33 } [get_ports electrode_out]
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports {dso_probe[0]}]
set_property -dict { PACKAGE_PIN D3    IOSTANDARD LVCMOS33 } [get_ports {dso_probe[1]}]
set_property -dict { PACKAGE_PIN F4    IOSTANDARD LVCMOS33 } [get_ports {dso_probe[2]}]