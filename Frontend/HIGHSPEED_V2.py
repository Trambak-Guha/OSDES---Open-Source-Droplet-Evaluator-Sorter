# -*- coding: utf-8 -*-
import serial
import serial.tools.list_ports
import struct
import threading
import time
import queue
from collections import deque
import tkinter as tk
from tkinter import ttk, messagebox
import numpy as np
import matplotlib
matplotlib.use("TkAgg")
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.figure import Figure
import matplotlib.patches as patches  
from matplotlib.colors import LogNorm

# Try to import PIL for image loading
try:
    from PIL import Image, ImageTk
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

BAUD_RATE = 2000000
N_FREQ = 4096            
FS = 1000000.0           
DC_OFFSET = 128          
VIEW_WINDOW = 2000       
MAX_SCATTER_PTS = 200000  

class FPGAViewerApp:
    def __init__(self, root):
        self.root = root
        self.root.title("OSDES - Open Source Droplet Evaluator and Sorter")
        self.root.geometry("1500x900") 
        self.root.configure(bg='#1e1e1e')

        self.ser = None
        self.running = False
        self.read_thread = None
        self.current_mode = "TIME"
        self.is_frozen = False
        self.is_armed = False # --- NEW: Decouples gating from live sorting ---

        self.time_queue = queue.Queue()
        self.fft_queue = queue.Queue()
        self.scatter_queue = queue.Queue() 
        self.tally_queue = queue.Queue() 
        self.sync_buffer = bytearray()
        
        self.scatter_history = deque(maxlen=MAX_SCATTER_PTS)
        
        self.alpha_val = 200
        self.threshold_ch1_mv = 49  
        self.threshold_ch2_mv = 49  
        
        self.gate_x_min = 1.0  
        self.gate_x_max = 40.0  
        self.gate_y_min = 1.0  
        self.gate_y_max = 40.0  
        
        self.is_gating_active = False
        self.delay_us = 10      
        self.pulse_width_us = 50 
        self.ac_freq_khz = 50  
        
        self.scatter_xmax = 50.0  
        self.scatter_ymax = 50.0 
        self.fft_xmax = 100.0     

        self.dragging_threshold = None 
        self.dragging_gate = None  

        self.bins_x_grid = 100
        self.bins_y_grid = 100

        self.style_ui()
        self.build_layout()
        self.update_plot()

    def style_ui(self):
        style = ttk.Style()
        style.theme_use('clam')
        style.configure("TFrame", background='#1e1e1e')
        style.configure("TLabelframe", background='#252526', foreground='#00aaff', borderwidth=1)
        style.configure("TLabelframe.Label", background='#252526', foreground='#00aaff', font=("Segoe UI", 10, "bold"))
        style.configure("TLabel", background='#252526', foreground='white', font=("Segoe UI", 9))
        style.configure("TButton", background="#333333", foreground="white", borderwidth=1, font=("Segoe UI", 9))
        style.map("TButton", background=[("active", "#444444")])
        style.configure("TEntry", fieldbackground="#333333", foreground="white", borderwidth=0)
        style.configure("TRadiobutton", background='#252526', foreground='white', font=("Segoe UI", 9))
        
        # --- NEW: CUSTOM STYLES FOR CH1 AND CH2 LABEL FRAMES ---
        style.configure("CH1.TLabelframe", background='#252526', borderwidth=1)
        style.configure("CH1.TLabelframe.Label", background='#252526', foreground='#ffff00', font=("Segoe UI", 10, "bold"))
        
        style.configure("CH2.TLabelframe", background='#252526', borderwidth=1)
        style.configure("CH2.TLabelframe.Label", background='#252526', foreground='#00ffff', font=("Segoe UI", 10, "bold"))

    def build_layout(self):
        # --- SPLIT WINDOW (FIXED LAYOUT, NO SCROLLING) ---
        self.left_panel = ttk.Frame(self.root, width=420)
        self.left_panel.pack(side=tk.LEFT, fill=tk.Y, padx=(10, 5), pady=10)
        self.left_panel.pack_propagate(False) 
        
        self.right_panel = ttk.Frame(self.root)
        self.right_panel.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True, padx=(5,10), pady=10)

        self.build_left_controls()
        self.build_right_plot()

    def build_left_controls(self):
        self.logo_frame = tk.Frame(self.left_panel, bg='#1e1e1e', height=160)
        self.logo_frame.pack(fill=tk.X, pady=(0, 10))
        self.logo_frame.pack_propagate(False)
        
        try:
            if HAS_PIL:
                try:
                    img_left = Image.open('logo2.png')
                except FileNotFoundError:
                    img_left = Image.open('logo.png') 
                img_left.thumbnail((200, 160), Image.Resampling.LANCZOS)
                self.logo_img_left = ImageTk.PhotoImage(img_left)
                
                img_right = Image.open('logo.png')
                img_right.thumbnail((200, 160), Image.Resampling.LANCZOS)
                self.logo_img_right = ImageTk.PhotoImage(img_right)
                
                tk.Label(self.logo_frame, image=self.logo_img_left, bg='#1e1e1e').pack(side=tk.LEFT, expand=True)
                tk.Label(self.logo_frame, image=self.logo_img_right, bg='#1e1e1e').pack(side=tk.RIGHT, expand=True)
            else:
                raise ImportError
        except Exception:
            tk.Label(self.logo_frame, text="[ LOGO 2 ]", bg='#252526', fg='#00aaff', font=("Segoe UI", 10, "bold")).pack(side=tk.LEFT, expand=True, fill=tk.BOTH, padx=2)
            tk.Label(self.logo_frame, text="[ LOGO 1 ]", bg='#252526', fg='#00aaff', font=("Segoe UI", 10, "bold")).pack(side=tk.RIGHT, expand=True, fill=tk.BOTH, padx=2)

        # 1. CONNECTION
        conn_frame = ttk.LabelFrame(self.left_panel, text=" System Connection ", padding=5)
        conn_frame.pack(fill=tk.X, pady=3)
        
        row1 = ttk.Frame(conn_frame)
        row1.pack(fill=tk.X)
        self.port_combo = ttk.Combobox(row1, width=12)
        self.port_combo.pack(side=tk.LEFT, padx=(0,5))
        self.refresh_ports()
        ttk.Button(row1, text="Refresh", command=self.refresh_ports, width=8).pack(side=tk.LEFT, padx=2)
        self.btn_connect = tk.Button(row1, text="Connect", bg="#0066cc", fg="white", borderwidth=0, command=self.toggle_connection, width=10)
        self.btn_connect.pack(side=tk.RIGHT)

        # 2. PIPELINE MODE
        mode_frame = ttk.LabelFrame(self.left_panel, text=" Window View ", padding=5)
        mode_frame.pack(fill=tk.X, pady=3)
        
        m_row = ttk.Frame(mode_frame)
        m_row.pack(fill=tk.X)
        ttk.Button(m_row, text="TIME DOMAIN", command=lambda: self.switch_mode('t', "TIME")).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=2)
        ttk.Button(m_row, text="FFT", command=lambda: self.switch_mode('f', "FFT")).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=2)
        ttk.Button(m_row, text="SCATTER", command=lambda: self.switch_mode('s', "SCATTER")).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=2)
        
        self.btn_freeze = tk.Button(m_row, text="FREEZE", bg="#444", fg="white", borderwidth=0, command=self.toggle_freeze, width=8)
        self.btn_freeze.pack(side=tk.LEFT, padx=2)

        # 3. DSP & METRICS
        dsp_frame = ttk.LabelFrame(self.left_panel, text=" DSP & Scatter Metrics ", padding=5)
        dsp_frame.pack(fill=tk.X, pady=3)
        
        d_row1 = ttk.Frame(dsp_frame)
        d_row1.pack(fill=tk.X, pady=2)
        ttk.Label(d_row1, text="2D Metric:").pack(side=tk.LEFT)
        self.dual_plot_var = tk.StringVar(value="Area")
        
        ttk.Radiobutton(d_row1, text="Area", variable=self.dual_plot_var, value="Area", command=self.on_metric_change).pack(side=tk.LEFT, padx=5)
        ttk.Radiobutton(d_row1, text="Height", variable=self.dual_plot_var, value="Height", command=self.on_metric_change).pack(side=tk.LEFT, padx=5)
        ttk.Radiobutton(d_row1, text="Width", variable=self.dual_plot_var, value="Width", command=self.on_metric_change).pack(side=tk.LEFT, padx=5)
        
        d_row2 = ttk.Frame(dsp_frame)
        d_row2.pack(fill=tk.X, pady=(5,2))
        ttk.Label(d_row2, text="Hardware LPF:").pack(side=tk.LEFT)
        
        self.btn_filt_on = tk.Button(d_row2, text="ON", bg="#444", fg="white", borderwidth=0, width=5, command=lambda: self.toggle_filter(True))
        self.btn_filt_on.pack(side=tk.LEFT, padx=5)
        self.btn_filt_off = tk.Button(d_row2, text="OFF", bg="#aa0000", fg="white", borderwidth=0, width=5, command=lambda: self.toggle_filter(False))
        self.btn_filt_off.pack(side=tk.LEFT)
        
        ttk.Label(d_row2, text=" Alpha:").pack(side=tk.LEFT, padx=(10,2))
        self.ent_alpha = ttk.Entry(d_row2, width=5)
        self.ent_alpha.insert(0, str(self.alpha_val)) 
        self.ent_alpha.pack(side=tk.LEFT)

        d_row3 = ttk.Frame(dsp_frame)
        d_row3.pack(fill=tk.X, pady=(5,2))
        ttk.Label(d_row3, text="FFT Max (kHz):").pack(side=tk.LEFT)
        self.ent_fft_max = ttk.Entry(d_row3, width=6)
        self.ent_fft_max.insert(0, str(int(self.fft_xmax)))
        self.ent_fft_max.pack(side=tk.LEFT, padx=5)
        ttk.Button(d_row3, text="Zoom", width=6, command=self.update_zoom).pack(side=tk.LEFT)

        # 4. OPTICS CH1 
        opt1_frame = ttk.LabelFrame(self.left_panel, text=" Channel 1 ", padding=5, style="CH1.TLabelframe")
        opt1_frame.pack(fill=tk.X, pady=3)
        
        o1_row = ttk.Frame(opt1_frame)
        o1_row.pack(fill=tk.X)
        self.var_ch1_en = tk.BooleanVar(value=True)
        self.btn_ch1_en = tk.Button(o1_row, text="Trigger: ON", bg="#228B22", fg="white", borderwidth=0, width=10, command=self.toggle_ch1)
        self.btn_ch1_en.pack(side=tk.LEFT, padx=2)
        
        self.var_ch1_prim = tk.BooleanVar(value=False)
        self.btn_ch1_prim = tk.Button(o1_row, text="Primary: OFF", bg="#444", fg="white", borderwidth=0, width=12, command=self.toggle_ch1_prim)
        self.btn_ch1_prim.pack(side=tk.LEFT, padx=2)
        
        ttk.Label(o1_row, text="Gain:").pack(side=tk.LEFT, padx=(10,2))
        self.ent_ch1_gain = ttk.Entry(o1_row, width=4)
        self.ent_ch1_gain.insert(0, "1")
        self.ent_ch1_gain.pack(side=tk.LEFT)
        
        self.lbl_thresh1_val = ttk.Label(opt1_frame, text=f"Threshold (Y-Axis): {self.threshold_ch1_mv} mV", foreground="#ffff00", font=("Consolas", 9))
        self.lbl_thresh1_val.pack(anchor=tk.W, pady=(3,0))

        # 5. OPTICS CH2 
        opt2_frame = ttk.LabelFrame(self.left_panel, text=" Channel 2 ", padding=5, style="CH2.TLabelframe")
        opt2_frame.pack(fill=tk.X, pady=3)
        
        o2_row = ttk.Frame(opt2_frame)
        o2_row.pack(fill=tk.X)
        self.var_ch2_en = tk.BooleanVar(value=True)
        self.btn_ch2_en = tk.Button(o2_row, text="Trigger: ON", bg="#228B22", fg="white", borderwidth=0, width=10, command=self.toggle_ch2)
        self.btn_ch2_en.pack(side=tk.LEFT, padx=2)
        
        self.var_ch2_prim = tk.BooleanVar(value=False)
        self.btn_ch2_prim = tk.Button(o2_row, text="Primary: OFF", bg="#444", fg="white", borderwidth=0, width=12, command=self.toggle_ch2_prim)
        self.btn_ch2_prim.pack(side=tk.LEFT, padx=2)
        
        ttk.Label(o2_row, text="Gain:").pack(side=tk.LEFT, padx=(10,2))
        self.ent_ch2_gain = ttk.Entry(o2_row, width=4)
        self.ent_ch2_gain.insert(0, "1")
        self.ent_ch2_gain.pack(side=tk.LEFT)
        
        self.lbl_thresh2_val = ttk.Label(opt2_frame, text=f"Threshold (Y-Axis): {self.threshold_ch2_mv} mV", foreground="#00ffff", font=("Consolas", 9))
        self.lbl_thresh2_val.pack(anchor=tk.W, pady=(3,0))

        # 6. ACTUATOR
        act_frame = ttk.LabelFrame(self.left_panel, text=" Dielectrophoretic Actuator ", padding=5)
        act_frame.pack(fill=tk.X, pady=3)
        
        grid_act = ttk.Frame(act_frame)
        grid_act.pack(fill=tk.X)
        
        ttk.Label(grid_act, text="Delay (µs):").grid(row=0, column=0, sticky=tk.W, pady=1)
        self.ent_delay = ttk.Entry(grid_act, width=8)
        self.ent_delay.insert(0, str(self.delay_us))
        self.ent_delay.grid(row=0, column=1, padx=5, pady=1)
        self.lbl_delay_conv = ttk.Label(grid_act, text="(0 kHz)", foreground="#aaaaaa")
        self.lbl_delay_conv.grid(row=0, column=2, sticky=tk.W)
        
        ttk.Label(grid_act, text="Pulse (µs):").grid(row=1, column=0, sticky=tk.W, pady=1)
        self.ent_pulse = ttk.Entry(grid_act, width=8)
        self.ent_pulse.insert(0, str(self.pulse_width_us))
        self.ent_pulse.grid(row=1, column=1, padx=5, pady=1)
        self.lbl_pulse_conv = ttk.Label(grid_act, text="(0 kHz)", foreground="#aaaaaa")
        self.lbl_pulse_conv.grid(row=1, column=2, sticky=tk.W)
        
        ttk.Label(grid_act, text="AC (kHz):").grid(row=2, column=0, sticky=tk.W, pady=1)
        self.ent_ac_freq = ttk.Entry(grid_act, width=8)
        self.ent_ac_freq.insert(0, str(self.ac_freq_khz))
        self.ent_ac_freq.grid(row=2, column=1, padx=5, pady=1)
        self.lbl_ac_conv = ttk.Label(grid_act, text="(0 µs)", foreground="#aaaaaa")
        self.lbl_ac_conv.grid(row=2, column=2, sticky=tk.W)

        self.ent_delay.bind('<KeyRelease>', self.update_conversions)
        self.ent_pulse.bind('<KeyRelease>', self.update_conversions)
        self.ent_ac_freq.bind('<KeyRelease>', self.update_conversions)
        self.update_conversions()

        # 7. GATES & SCALES
        gate_frame = ttk.LabelFrame(self.left_panel, text=" Optical Gates & Display Scale ", padding=5)
        gate_frame.pack(fill=tk.X, pady=3)
        
        g_row1 = ttk.Frame(gate_frame)
        g_row1.pack(fill=tk.X, pady=2)
        ttk.Label(g_row1, text="X Gate:").pack(side=tk.LEFT)
        self.ent_gate_x_min = ttk.Entry(g_row1, width=6)
        self.ent_gate_x_min.insert(0, str(self.gate_x_min))
        self.ent_gate_x_min.pack(side=tk.LEFT, padx=2)
        ttk.Label(g_row1, text="to").pack(side=tk.LEFT)
        self.ent_gate_x_max = ttk.Entry(g_row1, width=6)
        self.ent_gate_x_max.insert(0, str(self.gate_x_max))
        self.ent_gate_x_max.pack(side=tk.LEFT, padx=2)
        
        g_row2 = ttk.Frame(gate_frame)
        g_row2.pack(fill=tk.X, pady=2)
        ttk.Label(g_row2, text="Y Gate:").pack(side=tk.LEFT)
        self.ent_gate_y_min = ttk.Entry(g_row2, width=6)
        self.ent_gate_y_min.insert(0, str(self.gate_y_min))
        self.ent_gate_y_min.pack(side=tk.LEFT, padx=2)
        ttk.Label(g_row2, text="to").pack(side=tk.LEFT)
        self.ent_gate_y_max = ttk.Entry(g_row2, width=6)
        self.ent_gate_y_max.insert(0, str(self.gate_y_max))
        self.ent_gate_y_max.pack(side=tk.LEFT, padx=2)

        g_row3 = ttk.Frame(gate_frame)
        g_row3.pack(fill=tk.X, pady=(5,2))
        ttk.Label(g_row3, text="Plot Max X:").pack(side=tk.LEFT)
        self.ent_scat_x = ttk.Entry(g_row3, width=6)
        self.ent_scat_x.insert(0, str(self.scatter_xmax))
        self.ent_scat_x.pack(side=tk.LEFT, padx=2)
        ttk.Label(g_row3, text=" Y:").pack(side=tk.LEFT)
        self.ent_scat_y = ttk.Entry(g_row3, width=6)
        self.ent_scat_y.insert(0, str(self.scatter_ymax))
        self.ent_scat_y.pack(side=tk.LEFT, padx=2)
        ttk.Button(g_row3, text="Apply", width=6, command=self.update_scatter_scale).pack(side=tk.RIGHT)

        # 8. MASTER SYNC
        btn_frame = ttk.Frame(self.left_panel)
        btn_frame.pack(fill=tk.X, pady=(10, 0))
        
        self.btn_sync = tk.Button(btn_frame, text="SYNC TO FPGA HARDWARE", bg="#cc5500", fg="white", font=("Segoe UI", 11, "bold"), borderwidth=0, height=2, command=self.arm_and_sync)
        self.btn_sync.pack(fill=tk.X)
        
        ttk.Button(btn_frame, text="Clear Scatter Data", command=self.clear_scatter_plot).pack(fill=tk.X, pady=(5,0))

    def build_right_plot(self):
        header_frame = ttk.Frame(self.right_panel)
        header_frame.pack(side=tk.TOP, fill=tk.X, pady=(0, 5))
        
        self.lbl_last_pulse = ttk.Label(header_frame, text="System: Disconnected", foreground="#00ffff", font=("Consolas", 14), background="#1e1e1e")
        self.lbl_last_pulse.pack(side=tk.LEFT)
        
        self.hw_hits_var = tk.StringVar(value="Hardware Sorts: 0")
        self.lbl_hw_hits = ttk.Label(header_frame, textvariable=self.hw_hits_var, foreground="#00ff00", font=("Consolas", 18, "bold"), background="#1e1e1e")
        self.lbl_hw_hits.pack(side=tk.RIGHT)

        footer_frame = tk.Frame(self.right_panel, bg='#1e1e1e')
        footer_frame.pack(side=tk.BOTTOM, fill=tk.X, pady=(5, 0))
        tk.Label(footer_frame, text="- DEVELOPED BY ", bg='#1e1e1e', fg='#666666', font=("Segoe UI", 10, "bold", "italic")).pack(side=tk.RIGHT)

        plot_frame = tk.Frame(self.right_panel, bg='black', bd=0, highlightthickness=0, relief=tk.FLAT)
        plot_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

        self.fig = Figure(figsize=(9, 6), dpi=100)
        self.fig.patch.set_facecolor('black')
        self.ax = self.fig.add_subplot(111)
        self.ax.set_facecolor('black')
        self.canvas = FigureCanvasTkAgg(self.fig, master=plot_frame)
        self.canvas.get_tk_widget().pack(fill=tk.BOTH, expand=True)
        self.canvas.mpl_connect('button_press_event', self.on_click)
        self.canvas.mpl_connect('button_release_event', self.on_release)
        self.canvas.mpl_connect('motion_notify_event', self.on_drag)

    def arm_and_sync(self):
        self.is_armed = True
        self.send_32byte_packet()

    def toggle_freeze(self):
        self.is_frozen = not self.is_frozen
        if self.is_frozen:
            self.btn_freeze.config(bg="#aa0000", text="UNFREEZE")
        else:
            self.btn_freeze.config(bg="#444", text="FREEZE")

    def on_metric_change(self):
        metric = self.dual_plot_var.get()
        if metric == "Area":
            self.scatter_xmax = 50.0
            self.scatter_ymax = 50.0
            self.gate_x_max = 40.0
            self.gate_y_max = 40.0
        elif metric == "Height":
            self.scatter_xmax = 1.0   
            self.scatter_ymax = 1.0
            self.gate_x_max = 0.8
            self.gate_y_max = 0.8
        elif metric == "Width":
            self.scatter_xmax = 10.0  
            self.scatter_ymax = 10.0
            self.gate_x_max = 8.0
            self.gate_y_max = 8.0

        self.gate_x_min = 0.0
        self.gate_y_min = 0.0

        self.ent_scat_x.delete(0, tk.END)
        self.ent_scat_x.insert(0, str(self.scatter_xmax))
        self.ent_scat_y.delete(0, tk.END)
        self.ent_scat_y.insert(0, str(self.scatter_ymax))
        
        self.ent_gate_x_min.delete(0, tk.END)
        self.ent_gate_x_min.insert(0, "0.0")
        self.ent_gate_x_max.delete(0, tk.END)
        self.ent_gate_x_max.insert(0, str(self.gate_x_max))
        
        self.ent_gate_y_min.delete(0, tk.END)
        self.ent_gate_y_min.insert(0, "0.0")
        self.ent_gate_y_max.delete(0, tk.END)
        self.ent_gate_y_max.insert(0, str(self.gate_y_max))

        self.is_armed = False
        
        self.setup_plot_axes()
        self.send_32byte_packet()

    def toggle_ch1_prim(self):
        state = not self.var_ch1_prim.get()
        self.var_ch1_prim.set(state)
        if state:
            self.btn_ch1_prim.config(text="Primary: ON", bg="#228B22")
            self.var_ch2_prim.set(False)
            self.btn_ch2_prim.config(text="Primary: OFF", bg="#444")
            if hasattr(self, 'thresh_line_ch2'): self.thresh_line_ch2.set_color('#444444')
            if hasattr(self, 'lbl_thresh2_val'): self.lbl_thresh2_val.config(foreground='#444444')
            if hasattr(self, 'thresh_line_ch1'): self.thresh_line_ch1.set_color('#ffff00')
            if hasattr(self, 'lbl_thresh1_val'): self.lbl_thresh1_val.config(foreground='#ffff00')
        else:
            self.btn_ch1_prim.config(text="Primary: OFF", bg="#444")
            if not self.var_ch2_prim.get(): 
                if hasattr(self, 'thresh_line_ch2'): self.thresh_line_ch2.set_color('#00ffff')
                if hasattr(self, 'lbl_thresh2_val'): self.lbl_thresh2_val.config(foreground='#00ffff')
                if hasattr(self, 'thresh_line_ch1'): self.thresh_line_ch1.set_color('#ffff00')
                if hasattr(self, 'lbl_thresh1_val'): self.lbl_thresh1_val.config(foreground='#ffff00')
        self.canvas.draw_idle()
        self.send_32byte_packet()

    def toggle_ch2_prim(self):
        state = not self.var_ch2_prim.get()
        self.var_ch2_prim.set(state)
        if state:
            self.btn_ch2_prim.config(text="Primary: ON", bg="#228B22")
            self.var_ch1_prim.set(False)
            self.btn_ch1_prim.config(text="Primary: OFF", bg="#444")
            if hasattr(self, 'thresh_line_ch1'): self.thresh_line_ch1.set_color('#444444')
            if hasattr(self, 'lbl_thresh1_val'): self.lbl_thresh1_val.config(foreground='#444444')
            if hasattr(self, 'thresh_line_ch2'): self.thresh_line_ch2.set_color('#00ffff')
            if hasattr(self, 'lbl_thresh2_val'): self.lbl_thresh2_val.config(foreground='#00ffff')
        else:
            self.btn_ch2_prim.config(text="Primary: OFF", bg="#444")
            if not self.var_ch1_prim.get(): 
                if hasattr(self, 'thresh_line_ch1'): self.thresh_line_ch1.set_color('#ffff00')
                if hasattr(self, 'lbl_thresh1_val'): self.lbl_thresh1_val.config(foreground='#ffff00')
                if hasattr(self, 'thresh_line_ch2'): self.thresh_line_ch2.set_color('#00ffff')
                if hasattr(self, 'lbl_thresh2_val'): self.lbl_thresh2_val.config(foreground='#00ffff')
        self.canvas.draw_idle()
        self.send_32byte_packet()

    def toggle_filter(self, turn_on):
        if turn_on:
            self.btn_filt_on.config(bg="#228B22")
            self.btn_filt_off.config(bg="#444")
            self.send_command('1')
        else:
            self.btn_filt_on.config(bg="#444")
            self.btn_filt_off.config(bg="#aa0000")
            self.send_command('0')

    def toggle_ch1(self):
        state = not self.var_ch1_en.get()
        self.var_ch1_en.set(state)
        if state: self.btn_ch1_en.config(text="Trigger: ON", bg="#228B22")
        else:     self.btn_ch1_en.config(text="Trigger: OFF", bg="#aa0000")
        self.send_32byte_packet()

    def toggle_ch2(self):
        state = not self.var_ch2_en.get()
        self.var_ch2_en.set(state)
        if state: self.btn_ch2_en.config(text="Trigger: ON", bg="#228B22")
        else:     self.btn_ch2_en.config(text="Trigger: OFF", bg="#aa0000")
        self.send_32byte_packet()

    def update_conversions(self, event=None):
        try:
            val = float(self.ent_delay.get())
            if val > 0: self.lbl_delay_conv.config(text=f"({1000.0/val:.1f} kHz)")
            else: self.lbl_delay_conv.config(text="(--- kHz)")
        except ValueError: self.lbl_delay_conv.config(text="(--- kHz)")

        try:
            val = float(self.ent_pulse.get())
            if val > 0: self.lbl_pulse_conv.config(text=f"({1000.0/val:.1f} kHz)")
            else: self.lbl_pulse_conv.config(text="(--- kHz)")
        except ValueError: self.lbl_pulse_conv.config(text="(--- kHz)")

        try:
            val = float(self.ent_ac_freq.get())
            if val > 0: self.lbl_ac_conv.config(text=f"({1000.0/val:.1f} us)")
            else: self.lbl_ac_conv.config(text="(--- us)")
        except ValueError: self.lbl_ac_conv.config(text="(--- us)")

    def clear_scatter_plot(self):
        if self.ser and self.ser.is_open:
            time.sleep(0.01) 
            self.ser.reset_input_buffer()
        with self.scatter_queue.mutex: self.scatter_queue.queue.clear()
        with self.tally_queue.mutex: self.tally_queue.queue.clear()
        self.sync_buffer.clear()
        self.scatter_history.clear()
        if hasattr(self, 'scatter_pts'):
            self.scatter_pts.set_offsets(np.empty((0, 2)))
            self.scatter_pts.set_array(np.array([]))
            
        self.is_armed = False 
        self.hw_hits_var.set("Hardware Sorts: 0")
        self.is_gating_active = False
        self.send_mute_packet()
        if self.current_mode == "SCATTER": self.canvas.draw_idle()

    def update_scatter_scale(self):
        try:
            w = float(self.ent_scat_x.get())
            h = float(self.ent_scat_y.get())
            self.scatter_xmax = max(0.001, w)
            self.scatter_ymax = max(0.001, h)
            if self.current_mode == "SCATTER":
                self.ax.set_xlim(0, self.scatter_xmax)
                self.ax.set_ylim(0, self.scatter_ymax)
                self.redraw_scatter_data()
                self.canvas.draw_idle()
        except ValueError: pass

    def update_zoom(self):
        try:
            val = float(self.ent_fft_max.get())
            self.fft_xmax = max(1.0, min(500.0, val)) 
            if self.current_mode == "FFT": self.setup_plot_axes()
        except ValueError: pass

    def send_command(self, cmd_char):
        if self.ser and self.ser.is_open:
            try: self.ser.write(cmd_char.encode('utf-8'))
            except: pass
            
    def send_mute_packet(self):
        if not (self.ser and self.ser.is_open): return
        try:
            thresh_adc_ch1 = int(self.threshold_ch1_mv * 4.095)
            thresh_adc_ch2 = int(self.threshold_ch2_mv * 4.095)
            try: ac_freq = int(self.ent_ac_freq.get())
            except ValueError: ac_freq = 50 
            ac_half_period_ticks = int(104000000 / (2 * ac_freq * 1000))
            
            strict_mode = 1 if (self.var_ch1_prim.get() or self.var_ch2_prim.get()) else 0
            primary_pmt = 1 if self.var_ch2_prim.get() else 0
            
            metric = self.dual_plot_var.get()
            metric_flag = 0 
            if metric == "Height": metric_flag = 1
            elif metric == "Width": metric_flag = 2

            sys_flags = 0 | (strict_mode << 1) | (primary_pmt << 2) | (metric_flag << 3)

            payload_bytes = bytearray(struct.pack('>BhHHhhHHHBBBBhHHHHB', 
                                                  int(self.ent_alpha.get()), thresh_adc_ch1, 
                                                  0, 65535, 0, 32767,   
                                                  int(self.ent_delay.get()), int(self.ent_pulse.get()),
                                                  ac_half_period_ticks, 1, 1, 0, 0, thresh_adc_ch2,
                                                  0, 65535, 0, 65535, sys_flags))
            for i in range(len(payload_bytes)):
                if payload_bytes[i] == 0xAA: payload_bytes[i] = 0xAB 
            
            self.ser.write(b'\xAA' + payload_bytes)
            time.sleep(0.005)
            self.ser.write(b'\xAA' + payload_bytes)
            
            self.lbl_last_pulse.config(text="System: DISARMED (Press SYNC to Arm)", foreground="#ffaa00")
        except ValueError: pass

    def send_32byte_packet(self):
        if not (self.ser and self.ser.is_open): return
        try:
            self.alpha_val = int(self.ent_alpha.get())
            self.delay_us = int(self.ent_delay.get())
            self.pulse_width_us = int(self.ent_pulse.get())
            
            self.gate_x_min = float(self.ent_gate_x_min.get())
            self.gate_x_max = float(self.ent_gate_x_max.get())
            self.gate_y_min = float(self.ent_gate_y_min.get())
            self.gate_y_max = float(self.ent_gate_y_max.get())
            
            mode_11 = self.var_ch1_en.get() and self.var_ch2_en.get()
            
            metric = self.dual_plot_var.get()
            
            if mode_11:
                if metric == "Area":
                    hw_s_a1_min = max(0, min(65535, int(round(self.gate_x_min * 256.0))))
                    hw_s_a1_max = max(0, min(65535, int(round(self.gate_x_max * 256.0))))
                    hw_s_a2_min = max(0, min(65535, int(round(self.gate_y_min * 256.0))))
                    hw_s_a2_max = max(0, min(65535, int(round(self.gate_y_max * 256.0))))
                elif metric == "Height":
                    hw_s_a1_min = max(0, min(65535, int(round(self.gate_x_min * 4096.0))))
                    hw_s_a1_max = max(0, min(65535, int(round(self.gate_x_max * 4096.0))))
                    hw_s_a2_min = max(0, min(65535, int(round(self.gate_y_min * 4096.0))))
                    hw_s_a2_max = max(0, min(65535, int(round(self.gate_y_max * 4096.0))))
                elif metric == "Width":
                    hw_s_a1_min = max(0, min(65535, int(round(self.gate_x_min * 1000.0))))
                    hw_s_a1_max = max(0, min(65535, int(round(self.gate_x_max * 1000.0))))
                    hw_s_a2_min = max(0, min(65535, int(round(self.gate_y_min * 1000.0))))
                    hw_s_a2_max = max(0, min(65535, int(round(self.gate_y_max * 1000.0))))
                
                hw_p_w_min, hw_p_w_max = 0, 65535
                hw_p_h_min, hw_p_h_max = -32768, 32767
            else:
                hw_p_w_min = max(0, min(65535, int(round(self.gate_x_min * 1000.0))))
                hw_p_w_max = max(0, min(65535, int(round(self.gate_x_max * 1000.0))))
                hw_p_h_min = max(-32768, min(32767, int(round(self.gate_y_min * 4096.0))))
                hw_p_h_max = max(-32768, min(32767, int(round(self.gate_y_max * 4096.0))))
                
                hw_s_a1_min, hw_s_a1_max = 0, 65535
                hw_s_a2_min, hw_s_a2_max = 0, 65535
            
            thresh_adc_ch1 = int(self.threshold_ch1_mv * 4.095)
            thresh_adc_ch2 = int(self.threshold_ch2_mv * 4.095)
            
            self.ac_freq_khz = int(self.ent_ac_freq.get())
            ac_half_period_ticks = int(104000000 / (2 * self.ac_freq_khz * 1000))
            
            ch1_gain = max(1, min(255, int(self.ent_ch1_gain.get())))
            ch2_gain = max(1, min(255, int(self.ent_ch2_gain.get())))
            ch1_en = 1 if self.var_ch1_en.get() else 0
            ch2_en = 1 if self.var_ch2_en.get() else 0
            
            armed = 1 if self.is_armed else 0
            strict_mode = 1 if (self.var_ch1_prim.get() or self.var_ch2_prim.get()) else 0
            primary_pmt = 1 if self.var_ch2_prim.get() else 0
            
            metric_flag = 0 
            if metric == "Height": metric_flag = 1
            elif metric == "Width": metric_flag = 2

            sys_flags = armed | (strict_mode << 1) | (primary_pmt << 2) | (metric_flag << 3)

            payload_bytes = bytearray(struct.pack('>BhHHhhHHHBBBBhHHHHB', 
                self.alpha_val, thresh_adc_ch1, 
                hw_p_w_min, hw_p_w_max, hw_p_h_min, hw_p_h_max, 
                self.delay_us, self.pulse_width_us, ac_half_period_ticks,
                ch1_gain, ch2_gain, ch1_en, ch2_en, thresh_adc_ch2,
                hw_s_a1_min, hw_s_a1_max, hw_s_a2_min, hw_s_a2_max, sys_flags
            ))
            
            for i in range(len(payload_bytes)):
                if payload_bytes[i] == 0xAA: payload_bytes[i] = 0xAB 
            
            self.ser.write(b'\xAA' + payload_bytes)
            time.sleep(0.005) 
            self.ser.write(b'\xAA' + payload_bytes)
            
            self.ser.reset_input_buffer() 
            
            with self.scatter_queue.mutex: self.scatter_queue.queue.clear()
            with self.tally_queue.mutex: self.tally_queue.queue.clear()
            self.sync_buffer.clear()
            
            self.scatter_history.clear()
            if hasattr(self, 'scatter_pts'):
                self.scatter_pts.set_offsets(np.empty((0, 2)))
                self.scatter_pts.set_array(np.array([]))
            
            self.is_gating_active = True
            
            if self.is_armed:
                self.lbl_last_pulse.config(text="System: ARMED & Synced", foreground="#00ff00")
                self.hw_hits_var.set("Hardware Sorts: 0")
            else:
                self.lbl_last_pulse.config(text="System: DISARMED (Press SYNC to Arm)", foreground="#ffaa00")
            
            if self.current_mode == "SCATTER" and hasattr(self, 'gate_rect'):
                self.gate_rect.set_xy((self.gate_x_min, self.gate_y_min))
                self.gate_rect.set_width(self.gate_x_max - self.gate_x_min)
                self.gate_rect.set_height(self.gate_y_max - self.gate_y_min)
                self.gate_line_l.set_xdata([self.gate_x_min, self.gate_x_min])
                self.gate_line_r.set_xdata([self.gate_x_max, self.gate_x_max])
                self.gate_line_b.set_ydata([self.gate_y_min, self.gate_y_min])
                self.gate_line_t.set_ydata([self.gate_y_max, self.gate_y_max])
                self.canvas.draw_idle()
                
            self.setup_plot_axes()
        except ValueError: pass

    def refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        self.port_combo["values"] = ports
        if ports: self.port_combo.current(0)

    def toggle_connection(self):
        if not self.running:
            try:
                self.ser = serial.Serial(self.port_combo.get(), BAUD_RATE, timeout=0.1)
                self.ser.reset_input_buffer()
                self.sync_buffer.clear()
                self.running = True
                self.read_thread = threading.Thread(target=self.read_loop, daemon=True)
                self.read_thread.start()
                self.btn_connect.config(text="Disconnect", bg="#aa0000")
                self.switch_mode('t', "TIME") 
                self.send_mute_packet() 
            except Exception as e: messagebox.showerror("Error", str(e))
        else:
            self.running = False
            if self.ser: self.ser.close()
            self.btn_connect.config(text="Connect", bg="#0066cc")

    def switch_mode(self, cmd_char, mode_name):
        if self.ser and self.ser.is_open:
            self.current_mode = mode_name
            self.ser.write(cmd_char.encode('utf-8'))
            time.sleep(0.05) 
            self.ser.reset_input_buffer() 
            self.sync_buffer.clear()
            
            if mode_name == "TIME":
                with self.time_queue.mutex: self.time_queue.queue.clear()
            elif mode_name == "FFT":
                with self.fft_queue.mutex: self.fft_queue.queue.clear()
            
            self.setup_plot_axes()

            if mode_name == "FFT": self.auto_trigger_fft()

    def auto_trigger_fft(self):
        if self.running and self.current_mode == "FFT":
            try: self.ser.write(b'f')
            except: pass
            self.root.after(250, self.auto_trigger_fft)

    def on_click(self, event):
        if event.inaxes != self.ax: return
        if self.current_mode == "TIME":
            if hasattr(self, 'thresh_line_ch1') and abs(event.ydata - self.thresh_line_ch1.get_ydata()[0]) < 0.05:
                if not self.var_ch2_prim.get(): self.dragging_threshold = 'ch1'
            elif hasattr(self, 'thresh_line_ch2') and abs(event.ydata - self.thresh_line_ch2.get_ydata()[0]) < 0.05:
                if not self.var_ch1_prim.get(): self.dragging_threshold = 'ch2'
        elif self.current_mode == "SCATTER":
            if event.xdata is None or event.ydata is None: return
            x_tol = self.scatter_xmax * 0.03
            y_tol = self.scatter_ymax * 0.03
            d_l = abs(event.xdata - self.gate_x_min)
            d_r = abs(event.xdata - self.gate_x_max)
            d_b = abs(event.ydata - self.gate_y_min)
            d_t = abs(event.ydata - self.gate_y_max)
            norm_l = d_l / x_tol; norm_r = d_r / x_tol
            norm_b = d_b / y_tol; norm_t = d_t / y_tol
            min_norm = min(norm_l, norm_r, norm_b, norm_t)
            if min_norm <= 1.0: 
                if min_norm == norm_l: self.dragging_gate = 'left'
                elif min_norm == norm_r: self.dragging_gate = 'right'
                elif min_norm == norm_b: self.dragging_gate = 'bottom'
                elif min_norm == norm_t: self.dragging_gate = 'top'

    def on_release(self, event):
        sync_required = False
        if getattr(self, 'dragging_threshold', None) is not None:
            self.dragging_threshold = None
            sync_required = True
        if getattr(self, 'dragging_gate', None):
            self.dragging_gate = None
            sync_required = True
            
        if sync_required: 
            self.is_armed = False # --- FIX: Mouse release disarms system ---
            self.send_32byte_packet()

    def on_drag(self, event):
        if event.inaxes != self.ax: return
        if event.xdata is None or event.ydata is None: return
        if self.current_mode == "TIME" and getattr(self, 'dragging_threshold', None) is not None:
            new_y = max(0.005, min(0.5, event.ydata)) 
            if self.dragging_threshold == 'ch1':
                self.thresh_line_ch1.set_ydata([new_y, new_y])
                self.threshold_ch1_mv = int(new_y * 1000.0)
                self.lbl_thresh1_val.config(text=f"Threshold (Y-Axis): {self.threshold_ch1_mv} mV")
            elif self.dragging_threshold == 'ch2':
                self.thresh_line_ch2.set_ydata([new_y, new_y])
                self.threshold_ch2_mv = int(new_y * 1000.0)
                self.lbl_thresh2_val.config(text=f"Threshold (Y-Axis): {self.threshold_ch2_mv} mV")
            self.canvas.draw_idle()
            
        elif self.current_mode == "SCATTER" and getattr(self, 'dragging_gate', None):
            if self.dragging_gate == 'left':
                self.gate_x_min = max(0.001, min(event.xdata, self.gate_x_max - 0.001))
                self.gate_line_l.set_xdata([self.gate_x_min, self.gate_x_min])
            elif self.dragging_gate == 'right':
                self.gate_x_max = max(self.gate_x_min + 0.001, min(event.xdata, self.scatter_xmax))
                self.gate_line_r.set_xdata([self.gate_x_max, self.gate_x_max])
            elif self.dragging_gate == 'bottom':
                self.gate_y_min = max(0.0, min(event.ydata, self.gate_y_max - 0.001))
                self.gate_line_b.set_ydata([self.gate_y_min, self.gate_y_min])
            elif self.dragging_gate == 'top':
                self.gate_y_max = max(self.gate_y_min + 0.001, min(event.ydata, self.scatter_ymax))
                self.gate_line_t.set_ydata([self.gate_y_max, self.gate_y_max])
                
            self.gate_rect.set_xy((self.gate_x_min, self.gate_y_min))
            self.gate_rect.set_width(self.gate_x_max - self.gate_x_min)
            self.gate_rect.set_height(self.gate_y_max - self.gate_y_min)
            self.canvas.draw_idle()
            
            self.ent_gate_x_min.delete(0, tk.END); self.ent_gate_x_min.insert(0, f"{self.gate_x_min:.3f}")
            self.ent_gate_x_max.delete(0, tk.END); self.ent_gate_x_max.insert(0, f"{self.gate_x_max:.3f}")
            self.ent_gate_y_min.delete(0, tk.END); self.ent_gate_y_min.insert(0, f"{self.gate_y_min:.3f}")
            self.ent_gate_y_max.delete(0, tk.END); self.ent_gate_y_max.insert(0, f"{self.gate_y_max:.3f}")

    def setup_plot_axes(self):
        self.fig.clf() 
        self.ax = self.fig.add_subplot(111)
        
        self.ax.grid(True, color='#444', linestyle='--')
        self.ax.set_facecolor('black')
        self.ax.tick_params(colors='white')
        
        for spine in self.ax.spines.values():
            spine.set_color('#555555')
        
        if hasattr(self, 'cbar'):
            delattr(self, 'cbar')
            
        if self.current_mode == "TIME":
            self.ax.set_title("1 MSPS DUAL-CHANNEL OSCILLOSCOPE", color='white') 
            self.ax.set_xlabel("Samples (1 µs per sample)", color='white') 
            self.ax.set_ylabel("Amplitude (V)", color='white') 
            self.ax.set_ylim(-0.6, 0.6) 
            self.ax.set_xlim(0, VIEW_WINDOW)
            
            self.line_ch1, = self.ax.plot(np.arange(VIEW_WINDOW), np.zeros(VIEW_WINDOW), color="#ffff00", label="CH1 ", linewidth=1.5)
            self.line_ch2, = self.ax.plot(np.arange(VIEW_WINDOW), np.zeros(VIEW_WINDOW), color="#00ffff", label="CH2 ", linewidth=1.5, alpha=0.8)
            self.ax.legend(loc="upper right", facecolor='black', labelcolor='white')
            
            c1_color = '#444444' if self.var_ch2_prim.get() else '#ffff00'
            c2_color = '#444444' if self.var_ch1_prim.get() else '#00ffff'

            self.thresh_line_ch1 = self.ax.axhline(y=(self.threshold_ch1_mv / 1000.0), color=c1_color, linestyle='--', linewidth=2, picker=True)
            self.thresh_line_ch2 = self.ax.axhline(y=(self.threshold_ch2_mv / 1000.0), color=c2_color, linestyle='--', linewidth=2, picker=True)
            
        elif self.current_mode == "FFT":
            self.ax.set_title("1 MSPS REAL-TIME FFT SPECTRUM (CH1)", color='white')
            self.ax.set_xlabel("Frequency (kHz)", color='white')
            self.ax.set_ylabel("Magnitude (dB)", color='white')
            self.ax.set_xlim(0, self.fft_xmax) 
            self.ax.set_ylim(0, 150) 
            self.line, = self.ax.plot(np.linspace(0, FS/2000, N_FREQ), np.zeros(N_FREQ), color="#ff3333")
            
        elif self.current_mode == "SCATTER":
            mode_11 = self.var_ch1_en.get() and self.var_ch2_en.get()
            mode_01 = self.var_ch1_en.get() and not self.var_ch2_en.get()
            mode_10 = not self.var_ch1_en.get() and self.var_ch2_en.get()
            
            if mode_11:
                metric = self.dual_plot_var.get()
                if metric == "Area":
                    self.ax.set_title("2D OSDES: CH1 Area vs CH2 Area", color='white') 
                    self.ax.set_xlabel("CH1 Peak Area (V·µs)", color='#ffff00', fontweight='bold')
                    self.ax.set_ylabel("CH2 Peak Area (V·µs)", color='#00ffff', fontweight='bold')
                elif metric == "Height":
                    self.ax.set_title("2D OSDES: CH1 Height vs CH2 Height", color='white') 
                    self.ax.set_xlabel("CH1 Peak Amplitude (V)", color='#ffff00', fontweight='bold')
                    self.ax.set_ylabel("CH2 Peak Amplitude (V)", color='#00ffff', fontweight='bold')
                elif metric == "Width":
                    self.ax.set_title("2D OSDES: CH1 Width vs CH2 Width", color='white') 
                    self.ax.set_xlabel("CH1 Width (ms)", color='#ffff00', fontweight='bold')
                    self.ax.set_ylabel("CH2 Width (ms)", color='#00ffff', fontweight='bold')
            elif mode_01:
                self.ax.set_title("1D OSDES MONO-CHANNEL (Width vs CH1 Peak Height)", color='white') 
                self.ax.set_xlabel("Droplet Width (ms)", color='#ffffff', fontweight='bold')
                self.ax.set_ylabel("CH1 Peak Amplitude (V)", color='#ffff00', fontweight='bold')
            elif mode_10:
                self.ax.set_title("1D OSDES MONO-CHANNEL (Width vs CH2 Peak Height)", color='white') 
                self.ax.set_xlabel("Droplet Width (ms)", color='#ffffff', fontweight='bold')
                self.ax.set_ylabel("CH2 Peak Amplitude (V)", color='#00ffff', fontweight='bold')
            else:
                self.ax.set_title("SYSTEM MUTED (Enable a Channel to Plot Data)", color='red') 
                self.ax.set_xlabel("X-Axis", color='white')
                self.ax.set_ylabel("Y-Axis", color='white')

            self.ax.set_xlim(0, self.scatter_xmax)
            self.ax.set_ylim(0, self.scatter_ymax)
            
            self.scatter_pts = self.ax.scatter([], [], c=[], norm=LogNorm(vmin=0.5, vmax=100), cmap='magma', s=15, alpha=0.9, edgecolors='none')
            
            rect_w = self.gate_x_max - self.gate_x_min
            rect_h = self.gate_y_max - self.gate_y_min
            self.gate_rect = patches.Rectangle((self.gate_x_min, self.gate_y_min), rect_w, rect_h, linewidth=2, edgecolor='red', facecolor='red', alpha=0.15, linestyle='-')
            self.ax.add_patch(self.gate_rect)
            
            self.gate_line_l = self.ax.axvline(x=self.gate_x_min, color='red', linestyle='--', linewidth=1.5, alpha=0.8)
            self.gate_line_r = self.ax.axvline(x=self.gate_x_max, color='red', linestyle='--', linewidth=1.5, alpha=0.8)
            self.gate_line_b = self.ax.axhline(y=self.gate_y_min, color='red', linestyle='--', linewidth=1.5, alpha=0.8)
            self.gate_line_t = self.ax.axhline(y=self.gate_y_max, color='red', linestyle='--', linewidth=1.5, alpha=0.8)
            
            self.cbar = self.fig.colorbar(self.scatter_pts, ax=self.ax, orientation='vertical')
            self.cbar.set_label('Droplet Density (Count per Grid)', color='white', fontname='Arial', size=10)
            self.cbar.ax.yaxis.set_tick_params(color='white')
            for t in self.cbar.ax.yaxis.get_ticklabels(): t.set_color('white')
            
        self.fig.tight_layout()
        
        if self.current_mode == "SCATTER":
            self.redraw_scatter_data()
            
        self.canvas.draw()

    def redraw_scatter_data(self):
        if not hasattr(self, 'scatter_pts') or len(self.scatter_history) < 10:
            return
            
        history_arr = np.array(self.scatter_history)
        x_data = history_arr[:, 0]
        y_data = history_arr[:, 1]
        
        H, _, _ = np.histogram2d(x_data, y_data, 
                                 bins=[self.bins_x_grid, self.bins_y_grid], 
                                 range=[[0, self.scatter_xmax], [0, self.scatter_ymax]])
        
        norm_x = np.clip((x_data - 0) / (self.scatter_xmax - 0), 0, 1)
        norm_y = np.clip((y_data - 0) / (self.scatter_ymax - 0), 0, 1)
        
        bin_idx_x = np.floor(norm_x * (self.bins_x_grid - 1)).astype(int)
        bin_idx_y = np.floor(norm_y * (self.bins_y_grid - 1)).astype(int)
        
        colors_density = np.clip(H[bin_idx_x, bin_idx_y], 1, MAX_SCATTER_PTS)
        
        sort_idx = np.argsort(colors_density)
        sorted_history = history_arr[sort_idx]
        sorted_colors = colors_density[sort_idx]
        
        self.scatter_pts.set_offsets(sorted_history)
        self.scatter_pts.set_array(sorted_colors)
        self.scatter_pts.set_clim(0.5, max(10, np.max(sorted_colors)))

    def read_loop(self):
        while self.running:
            try:
                in_wait = self.ser.in_waiting
                if in_wait == 0:
                    time.sleep(0.002)
                    continue
                
                self.sync_buffer.extend(self.ser.read(in_wait))
                
                if self.current_mode == "TIME":
                    while len(self.sync_buffer) >= 4001:
                        idx = self.sync_buffer.find(b'\xFF')
                        if idx == -1:
                            self.sync_buffer.clear()
                            break
                        if len(self.sync_buffer) >= idx + 4001:
                            payload = self.sync_buffer[idx+1 : idx+4001]
                            self.time_queue.put(payload)
                            self.sync_buffer = self.sync_buffer[idx+4001:]
                        else:
                            self.sync_buffer = self.sync_buffer[idx:]
                            break
                            
                elif self.current_mode == "FFT":
                    while len(self.sync_buffer) >= 16385:
                        idx = self.sync_buffer.find(b'\xAA')
                        if idx == -1:
                            self.sync_buffer.clear()
                            break
                        if len(self.sync_buffer) >= idx + 16385:
                            payload = self.sync_buffer[idx+1 : idx+16385]
                            self.fft_queue.put(struct.unpack(f'<{N_FREQ}I', payload))
                            self.sync_buffer = self.sync_buffer[idx+16385:]
                        else:
                            self.sync_buffer = self.sync_buffer[idx:]
                            break
                            
                elif self.current_mode == "SCATTER":
                    while len(self.sync_buffer) >= 5:
                        header = self.sync_buffer[0]
                        if header == 0xBB:
                            if len(self.sync_buffer) >= 14:
                                if self.sync_buffer[13] == 0xEE:
                                    payload = self.sync_buffer[1:13]
                                    w1, w2, p1, p2, a1, a2 = struct.unpack('>HHhhHH', payload)
                                    self.scatter_queue.put((w1, w2, p1, p2, a1, a2))
                                    self.sync_buffer = self.sync_buffer[14:]
                                else:
                                    self.sync_buffer = self.sync_buffer[1:]
                            else:
                                break 
                        elif header == 0xCC:
                            if len(self.sync_buffer) >= 5:
                                payload = self.sync_buffer[1:5]
                                hw_count = struct.unpack('>I', payload)[0]
                                self.tally_queue.put(hw_count)
                                self.sync_buffer = self.sync_buffer[5:]
                            else:
                                break
                        else:
                            self.sync_buffer = self.sync_buffer[1:]
            except Exception as e: pass

    def update_plot(self):
        if self.running:
            if self.current_mode == "TIME":
                if not self.is_frozen:
                    payload = None
                    while not self.time_queue.empty():
                        try: payload = self.time_queue.get_nowait()
                        except queue.Empty: break
                    
                    if payload is not None:
                        raw_np = np.frombuffer(payload, dtype=np.uint8)
                        ch1_raw = raw_np[0::2] 
                        ch2_raw = raw_np[1::2] 
                        
                        self.last_view_ch1 = (ch1_raw.astype(float) - DC_OFFSET) / 256.0 
                        self.last_view_ch2 = (ch2_raw.astype(float) - DC_OFFSET) / 256.0 
                
                if hasattr(self, 'last_view_ch1'):
                    if self.var_ch1_en.get():
                        self.line_ch1.set_data(np.arange(VIEW_WINDOW), self.last_view_ch1)
                        disp_p1 = np.max(self.last_view_ch1)
                    else:
                        self.line_ch1.set_data(np.arange(VIEW_WINDOW), np.zeros(VIEW_WINDOW))
                        disp_p1 = 0.0

                    if self.var_ch2_en.get():
                        self.line_ch2.set_data(np.arange(VIEW_WINDOW), self.last_view_ch2)
                        disp_p2 = np.max(self.last_view_ch2)
                    else:
                        self.line_ch2.set_data(np.arange(VIEW_WINDOW), np.zeros(VIEW_WINDOW))
                        disp_p2 = 0.0
                        
                    self.lbl_last_pulse.config(text=f"Live Peaks: CH1 {disp_p1:.3f}V | CH2 {disp_p2:.3f}V")
                    self.canvas.draw_idle()
                        
            elif self.current_mode == "FFT":
                data = None
                while not self.fft_queue.empty():
                    try: data = self.fft_queue.get_nowait()
                    except queue.Empty: break
                if data:
                    linear_pwr = np.array(data, dtype=np.float64)
                    linear_pwr[0] = 0 
                    db = 10 * np.log10(linear_pwr + 1.0)
                    freq_x = np.linspace(0, FS/2000, N_FREQ) 
                    self.line.set_data(freq_x, db)
                    max_db = np.max(db)
                    if max_db > 10: self.ax.set_ylim(0, max_db * 1.2) 
                    else: self.ax.set_ylim(0, 100)
                    self.canvas.draw_idle()
            
            elif self.current_mode == "SCATTER":
                latest_tally = None
                while not self.tally_queue.empty():
                    try: latest_tally = self.tally_queue.get_nowait()
                    except queue.Empty: break
                
                if latest_tally is not None:
                    self.hw_hits_var.set(f"Hardware Sorts: {latest_tally}")
                
                mode_11 = self.var_ch1_en.get() and self.var_ch2_en.get()
                mode_01 = self.var_ch1_en.get() and not self.var_ch2_en.get()
                mode_10 = not self.var_ch1_en.get() and self.var_ch2_en.get()

                new_pts = []
                while not self.scatter_queue.empty():
                    try: 
                        w1, w2, p1, p2, a1, a2 = self.scatter_queue.get_nowait()
                        
                        if mode_11:
                            metric = self.dual_plot_var.get()
                            if metric == "Area":
                                x_val = a1 / 256.0  
                                y_val = a2 / 256.0  
                                self.lbl_last_pulse.config(text=f"Last: Area CH1 {x_val:.1f} | CH2 {y_val:.1f}")
                            elif metric == "Height":
                                x_val = p1 / 4096.0  
                                y_val = p2 / 4096.0  
                                self.lbl_last_pulse.config(text=f"Last: Height CH1 {x_val:.3f}V | CH2 {y_val:.3f}V")
                            elif metric == "Width":
                                x_val = w1 / 1000.0  
                                y_val = w2 / 1000.0  
                                self.lbl_last_pulse.config(text=f"Last: Width CH1 {x_val:.3f}ms | CH2 {y_val:.3f}ms")
                        elif mode_01:
                            x_val = w1 / 1000.0  
                            y_val = p1 / 4096.0  
                            self.lbl_last_pulse.config(text=f"Last Droplet: W1 {x_val:.3f} ms | P1 {y_val:.3f} V")
                        elif mode_10:
                            x_val = w2 / 1000.0  
                            y_val = p2 / 4096.0  
                            self.lbl_last_pulse.config(text=f"Last Droplet: W2 {x_val:.3f} ms | P2 {y_val:.3f} V")
                        else:
                            x_val = 0; y_val = 0

                        new_pts.append([x_val, y_val])
                    except queue.Empty: break
                
                if new_pts:
                    self.scatter_history.extend(new_pts)
                    self.redraw_scatter_data()
                    self.canvas.draw_idle() 
            
        self.root.after(30, self.update_plot)

if __name__ == "__main__":
    root = tk.Tk()
    app = FPGAViewerApp(root)
    root.protocol("WM_DELETE_WINDOW", lambda: (app.toggle_connection(), root.destroy()))
    root.mainloop()