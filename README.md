# OSDES: Open-Source Droplet Evaluator-Sorter
<img width="1600" height="963" alt="WhatsApp Image 2026-05-01 at 09 47 20" src="https://github.com/user-attachments/assets/46cdc288-9c87-4673-ad4a-222b5c764c39" />


## Overview
OSDES is an open-source hardware and software pipeline designed for high throughput screening,specifically targeting microfluidic droplet evaluation and sorting.

The system relies on an FPGA-driven backend for real-time digital signal processing and hardware-level decision-making, coupled with a Python-based graphical frontend for live telemetry visualization and data logging.

## System Architecture

The repository is divided into two distinct pipelines:

### 1. `Backend/` (FPGA Hardware Logic)
Developed using Xilinx Vivado, the backend handles high-speed analog signal acquisition, real-time filtering, and sorting logic.
* **Core DSP:** Implements a 4th order low-pass filter (LPF) and mathematical DC offset removal directly in hardware.
<img width="1600" height="855" alt="WhatsApp Image 2026-05-07 at 02 25 11" src="https://github.com/user-attachments/assets/29d2bf89-98c3-48c3-b14c-25bbede0098e" />

* **Spectral Analysis:** Integrated FFT processing core with bin length of 8192.
* **ADC Configuration:** XADC maximized to 1MSPS with an overclocking frequency of 104Hz.
* **Communication:** USB-UART bridge (assigned to pin `D10`) utilizing a custom transmission protocol with specific headers for robust data streaming. Avoids heavy Ethernet stack overhead.
* **Modules:** Includes dedicated modules for pulse integration, telemetry arbitration, and sorter actuation.

### 2. `Frontend/` (Python PC Interface)
The `HIGHSPEED_V2.py` script serves as the control and visualization hub, built using Python, PyQt5, and Matplotlib.
<img width="1600" height="860" alt="WhatsApp Image 2026-05-07 at 02 25 09" src="https://github.com/user-attachments/assets/4005b8f4-eb65-441f-a6bc-ccf67174168f" />


* **Live Visualization:** Thresholded live data plotting, FFT spectra, and real-time time-domain waveforms.
* <img width="1600" height="859" alt="WhatsApp Image 2026-05-02 at 00 33 22" src="https://github.com/user-attachments/assets/84554ed8-294f-4671-8bc8-e04abcc66e02" />

* **Advanced Analytics:** Dynamic scatter density plots and pulse width visualization validated against digital storage oscilloscopes.
* **Signal Processing:** Software-side baseline correction applied to external data.
* **Streamlined UI:** Engineered for high-speed rendering by intentionally omitting performance-heavy pause/freeze functions and adjustable zoom sliders.

## Prerequisites & Setup

**Hardware Requirements:**
* FPGA Development Board (e.g., Arty A7 35T)
* Signal Generator
* Standard USB cable for UART communication

**Software Requirements:**
* **Vivado:** For synthesizing the `Backend` Verilog code.
* **Python 3.x (Anaconda recommended):** For running the `Frontend` GUI. Required libraries: `pyserial`, `numpy`, `matplotlib`, `PyQt5`.

## Author
**Trambak Guha** Laboratory for Integrated Microfluidics Systems ,
Indian Institute of Technology (IIT) Delhi
