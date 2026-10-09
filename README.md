# PicoRV32 RISC-V SoC with Sobel Edge Detection Hardware Accelerator

[![Target FPGA](https://img.shields.io/badge/FPGA-AMD%20Spartan--7%20XC7S50-blue.svg)](https://www.realdigital.org/hardware/boolean)
[![Core](https://img.shields.io/badge/Core-PicoRV32%20(RV32I)-brightgreen.svg)](https://github.com/YosysHQ/picorv32)
[![EDA Tool](https://img.shields.io/badge/EDA-AMD%20Vivado%202025.2-orange.svg)]()
[![Verification](https://img.shields.io/badge/Verification-100%25%20Bit--Exact%20Match-success.svg)]()

A complete hardware/software co-design implementing real-time **Sobel Edge Detection** on an **AMD Xilinx Spartan-7 FPGA (RealDigital Boolean Board)**. 

The architecture integrates a 32-bit **PicoRV32 RISC-V CPU** that manages PC-to-FPGA image streaming over UART, coordinates memory buffers, and dispatches execution to a dedicated **pipelined 3×3 Sobel hardware accelerator** instantiated on True Dual-Port Block RAM.

---

## 📸 System Demonstration

| Original 64×64 Input Logo | Hardware Sobel Output (FPGA) |
|:---:|:---:|
| `custom_input_64x64.bmp` | `custom_sobel_output.bmp` |
| Solid contours, gradients, and text | Sharp, high-contrast extracted boundary edges |

---

## 🚀 Key Features & Performance

- **Processor Core:** 32-bit PicoRV32 (RV32I base integer ISA) running @ 100 MHz.
- **Hardware Accelerator:** Pipelined 3×3 2D spatial convolution kernel computing horizontal ($G_x$) and vertical ($G_y$) gradients with Manhattan norm saturation ($|G_x| + |G_y| \le 255$).
- **Accelerator Latency:** Fully processes a 64×64 frame (4,096 pixels) in **42,536 clock cycles (~0.42 ms @ 100 MHz)**.
- **Communication:** Full-duplex UART at 115,200 baud, 8N1.
- **Memory Architecture:** True Dual-Port Block RAM (Port A: 32-bit CPU bus with byte-write enables; Port B: 8-bit streaming hardware accelerator interface).
- **Verification:** **100.00% bit-exact match (0 mismatches across all 4,096 pixels)** compared against software reference algorithms.
- **Ultra-low Resource Utilization:** Consumes only **5.33%** of the Boolean Board's Block RAM and **7.84%** of Slice LUTs.

---

## 🏗️ System Architecture
<img width="337" height="557" alt="image (2)" src="https://github.com/user-attachments/assets/16c46e3e-9932-4c85-8529-3ae04aefa428" />

## input
<img width="352" height="267" alt="image" src="https://github.com/user-attachments/assets/7344dc0d-1af5-46bb-9e11-0afb81f940b5" />

## output
<img width="260" height="312" alt="image" src="https://github.com/user-attachments/assets/366c9dc6-e36a-4c56-97ae-138efc9f6d26" />

## applications



