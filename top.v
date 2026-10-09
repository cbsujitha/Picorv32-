`timescale 1ns / 1ps

// ============================================================================
// top.v -- PicoRV32 SoC with Integrated Sobel Edge Detection Accelerator
// Real Digital Boolean Board (Xilinx Spartan-7 XC7S50-CSGA324-1)
//
// Address Map:
//   0x0000_0000 - 0x0000_07FF : Boot ROM (2 KB) -- preloaded with Sobel firmware
//   0x1000_0000 - 0x1000_1FFF : App RAM  (8 KB)
//   0x2000_0000               : UART DATA (read: RX, write: TX)
//   0x2000_0004               : UART STATUS (bit0 = tx_busy, bit1 = rx_valid)
//   0x3000_0000               : LED Register (16-bit)
//   0x4000_0000               : Sobel Accelerator CSR (bit0: START/BUSY, bit1: DONE)
//   0x4000_1000 - 0x4000_1FFF : Sobel Input Image Buffer  (4096 bytes)
//   0x4000_2000 - 0x4000_2FFF : Sobel Output Image Buffer (4096 bytes)
// ============================================================================

module top (
    input  wire        clk,        // 100 MHz on-board oscillator, pin F14
    input  wire        btn_rst,    // Push-button reset, ACTIVE-HIGH, pin J2
    output wire [15:0] led,        // 16 on-board LEDs
    input  wire        UART_rxd,   // From host PC USB-UART into FPGA (pin V12)
    output wire        UART_txd    // From FPGA out to host PC USB-UART (pin U11)
);

    // ------------------------------------------------------------------
    // Reset synchronizer (btn_rst active-high -> resetn active-low)
    // ------------------------------------------------------------------
    reg [1:0] rst_sync = 2'b11;
    always @(posedge clk) begin
        rst_sync <= {rst_sync[0], btn_rst};
    end
    wire resetn = ~rst_sync[1];

    // ------------------------------------------------------------------
    // PicoRV32 native memory interface
    // ------------------------------------------------------------------
    wire        mem_valid;
    wire        mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata;

    picorv32 #(
        .ENABLE_COUNTERS (0),
        .ENABLE_MUL      (0),
        .ENABLE_DIV      (0),
        .BARREL_SHIFTER  (0),
        .COMPRESSED_ISA  (0),
        .PROGADDR_RESET  (32'h0000_0000)   // Boots into Boot ROM
    ) cpu (
        .clk       (clk),
        .resetn    (resetn),
        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),
        .irq       (32'b0)
    );

    // ------------------------------------------------------------------
    // Address decode
    // ------------------------------------------------------------------
    wire rom_sel       = (mem_addr[31:28] == 4'h0);
    wire app_sel       = (mem_addr[31:28] == 4'h1);
    wire uart_sel      = (mem_addr[31:28] == 4'h2);
    wire led_sel       = (mem_addr[31:28] == 4'h3);
    wire sobel_sel     = (mem_addr[31:28] == 4'h4);

    wire sobel_csr_sel = sobel_sel && (mem_addr[15:12] == 4'h0);
    wire sobel_in_sel  = sobel_sel && (mem_addr[15:12] == 4'h1);
    wire sobel_out_sel = sobel_sel && (mem_addr[15:12] == 4'h2);

    // ------------------------------------------------------------------
    // Boot ROM (2 KB): Preloaded with Sobel firmware (bootloader.hex)
    // ------------------------------------------------------------------
    localparam ROM_WORDS = 512;
    reg [31:0] bootrom [0:ROM_WORDS-1];
    initial $readmemh("bootloader.hex", bootrom);

    // ------------------------------------------------------------------
    // Application RAM (8 KB)
    // ------------------------------------------------------------------
    localparam APP_WORDS = 2048;
    reg [31:0] appram [0:APP_WORDS-1];
    integer ii;
    initial for (ii = 0; ii < APP_WORDS; ii = ii + 1) appram[ii] = 32'h0;

    // ------------------------------------------------------------------
    // LED register
    // ------------------------------------------------------------------
    reg [15:0] led_reg = 16'h0000;
    assign led = led_reg;

    // ------------------------------------------------------------------
    // UART peripheral: 115200 baud @ 100 MHz clock (868 divider)
    // ------------------------------------------------------------------
    localparam integer CLKS_PER_BIT = 868;

    // ---- Transmit ----
    reg        tx_busy = 1'b0;
    reg [15:0] tx_clkcnt;
    reg [3:0]  tx_bitidx;
    reg [9:0]  tx_shiftreg;
    reg        uart_txd_reg = 1'b1;
    assign UART_txd = uart_txd_reg;

    wire tx_start = uart_sel && mem_valid && !mem_ready &&
                    (mem_addr[3:2] == 2'b00) && (|mem_wstrb) && !tx_busy;

    always @(posedge clk) begin
        if (!resetn) begin
            tx_busy      <= 1'b0;
            uart_txd_reg <= 1'b1;
        end else if (tx_start) begin
            tx_shiftreg  <= {1'b1, mem_wdata[7:0], 1'b0};
            tx_bitidx    <= 4'd0;
            tx_clkcnt    <= 16'd0;
            tx_busy      <= 1'b1;
            uart_txd_reg <= 1'b0;
        end else if (tx_busy) begin
            if (tx_clkcnt == CLKS_PER_BIT - 1) begin
                tx_clkcnt <= 16'd0;
                if (tx_bitidx == 4'd9) begin
                    tx_busy <= 1'b0;
                end else begin
                    tx_bitidx    <= tx_bitidx + 4'd1;
                    tx_shiftreg  <= {1'b1, tx_shiftreg[9:1]};
                    uart_txd_reg <= tx_shiftreg[1];
                end
            end else begin
                tx_clkcnt <= tx_clkcnt + 16'd1;
            end
        end
    end

    // ---- Receive ----
    reg [1:0] rxd_sync = 2'b11;
    always @(posedge clk) rxd_sync <= {rxd_sync[0], UART_rxd};
    wire rxd = rxd_sync[1];

    reg        rx_busy = 1'b0;
    reg        rx_aligned = 1'b0;
    reg [15:0] rx_clkcnt;
    reg [3:0]  rx_bitidx;
    reg [7:0]  rx_shiftreg;
    reg        rx_valid = 1'b0;
    reg [7:0]  rx_data;

    wire rx_read_ack = uart_sel && mem_valid && !mem_ready &&
                       (mem_addr[3:2] == 2'b00) && (mem_wstrb == 4'b0000);

    always @(posedge clk) begin
        if (!resetn) begin
            rx_busy  <= 1'b0;
            rx_valid <= 1'b0;
        end else begin
            if (rx_valid && rx_read_ack)
                rx_valid <= 1'b0;

            if (!rx_busy) begin
                if (!rxd) begin
                    rx_busy    <= 1'b1;
                    rx_aligned <= 1'b0;
                    rx_clkcnt  <= CLKS_PER_BIT / 2;
                    rx_bitidx  <= 4'd0;
                end
            end else begin
                if (rx_clkcnt == CLKS_PER_BIT - 1) begin
                    rx_clkcnt <= 16'd0;
                    if (!rx_aligned) begin
                        rx_aligned <= 1'b1;
                    end else if (rx_bitidx == 4'd8) begin
                        rx_busy  <= 1'b0;
                        rx_data  <= rx_shiftreg;
                        rx_valid <= 1'b1;
                    end else begin
                        rx_shiftreg <= {rxd, rx_shiftreg[7:1]};
                        rx_bitidx   <= rx_bitidx + 4'd1;
                    end
                end else begin
                    rx_clkcnt <= rx_clkcnt + 16'd1;
                end
            end
        end
    end

    // ==================================================================
    // Sobel Hardware Accelerator Subsystem
    // ==================================================================
    reg  sobel_start = 1'b0;
    wire sobel_busy;
    wire sobel_done;

    // Dual-Port RAM connections:
    // Input Image Buffer (4096 bytes)
    wire        in_dpram_we_a   = sobel_in_sel && mem_valid && !mem_ready && (|mem_wstrb);
    wire [31:0] in_dpram_dout_a;
    wire [11:0] accel_in_addr;
    wire [7:0]  accel_in_data;

    sobel_dpram_4096 input_dpram (
        .clk    (clk),
        // Port A (CPU)
        .we_a   (in_dpram_we_a),
        .wstrb_a(mem_wstrb),
        .addr_a (mem_addr[11:2]),
        .din_a  (mem_wdata),
        .dout_a (in_dpram_dout_a),
        // Port B (Accelerator)
        .we_b   (1'b0),
        .addr_b (accel_in_addr),
        .din_b  (8'd0),
        .dout_b (accel_in_data)
    );

    // Output Edge Buffer (4096 bytes)
    wire [31:0] out_dpram_dout_a;
    wire        accel_out_we;
    wire [11:0] accel_out_addr;
    wire [7:0]  accel_out_data;

    sobel_dpram_4096 output_dpram (
        .clk    (clk),
        // Port A (CPU)
        .we_a   (1'b0),
        .wstrb_a(4'b0000),
        .addr_a (mem_addr[11:2]),
        .din_a  (32'd0),
        .dout_a (out_dpram_dout_a),
        // Port B (Accelerator)
        .we_b   (accel_out_we),
        .addr_b (accel_out_addr),
        .din_b  (accel_out_data),
        .dout_b ()
    );

    // Sobel Accelerator Core
    sobel_accel #(
        .IMAGE_WIDTH (64),
        .IMAGE_HEIGHT(64)
    ) accelerator (
        .clk     (clk),
        .rst     (~resetn),
        .start   (sobel_start),
        .busy    (sobel_busy),
        .done    (sobel_done),
        .in_addr (accel_in_addr),
        .in_data (accel_in_data),
        .out_we  (accel_out_we),
        .out_addr(accel_out_addr),
        .out_data(accel_out_data)
    );

    // ------------------------------------------------------------------
    // Combinational read data multiplexer (routes single-cycle BRAM outputs)
    // ------------------------------------------------------------------
    always @(*) begin
        mem_rdata = 32'h0;
        if (rom_sel) begin
            mem_rdata = bootrom[mem_addr[10:2]];
        end
        else if (app_sel) begin
            mem_rdata = appram[mem_addr[12:2]];
        end
        else if (uart_sel) begin
            if (mem_addr[3:2] == 2'b00)
                mem_rdata = {24'h0, rx_data};
            else
                mem_rdata = {30'h0, rx_valid, tx_busy};
        end
        else if (led_sel) begin
            mem_rdata = {16'h0000, led_reg};
        end
        else if (sobel_csr_sel) begin
            mem_rdata = {30'h0, sobel_done, sobel_busy};
        end
        else if (sobel_in_sel) begin
            mem_rdata = in_dpram_dout_a;
        end
        else if (sobel_out_sel) begin
            mem_rdata = out_dpram_dout_a;
        end
    end

    // ------------------------------------------------------------------
    // Synchronous memory bus handshake & write operations
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        mem_ready   <= 1'b0;
        sobel_start <= 1'b0;

        if (mem_valid && !mem_ready) begin
            mem_ready <= 1'b1;

            if (rom_sel) begin
                if (mem_wstrb[0]) bootrom[mem_addr[10:2]][7:0]   <= mem_wdata[7:0];
                if (mem_wstrb[1]) bootrom[mem_addr[10:2]][15:8]  <= mem_wdata[15:8];
                if (mem_wstrb[2]) bootrom[mem_addr[10:2]][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) bootrom[mem_addr[10:2]][31:24] <= mem_wdata[31:24];
            end
            else if (app_sel) begin
                if (mem_wstrb[0]) appram[mem_addr[12:2]][7:0]   <= mem_wdata[7:0];
                if (mem_wstrb[1]) appram[mem_addr[12:2]][15:8]  <= mem_wdata[15:8];
                if (mem_wstrb[2]) appram[mem_addr[12:2]][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) appram[mem_addr[12:2]][31:24] <= mem_wdata[31:24];
            end
            else if (led_sel) begin
                if (mem_wstrb[0]) led_reg[7:0]  <= mem_wdata[7:0];
                if (mem_wstrb[1]) led_reg[15:8] <= mem_wdata[15:8];
            end
            else if (sobel_csr_sel) begin
                if (|mem_wstrb && mem_wdata[0]) begin
                    sobel_start <= 1'b1;
                end
            end
        end
    end

endmodule
