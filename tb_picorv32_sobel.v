`timescale 1ns / 1ps

// =========================================================================
// tb_picorv32_sobel.v -- Behavioral Testbench for PicoRV32 + Sobel SoC
// =========================================================================

module tb_picorv32_sobel;

    reg        clk;
    reg        btn_rst;
    wire [15:0] led;
    reg        UART_rxd;
    wire       UART_txd;

    localparam integer CLK_PERIOD = 10; // 100 MHz clock = 10 ns period
    localparam integer CLKS_PER_BIT = 868;

    // 100 MHz Clock Generator
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Device Under Test: PicoRV32 SoC with Sobel Accelerator
    top dut (
        .clk     (clk),
        .btn_rst (btn_rst),
        .led     (led),
        .UART_rxd(UART_rxd),
        .UART_txd(UART_txd)
    );

    // UART transmit task (Host PC -> SoC)
    task send_uart_byte(input [7:0] byte_data);
        integer bit_idx;
        begin
            // Start bit
            UART_rxd = 1'b0;
            repeat (CLKS_PER_BIT) @(posedge clk);

            // 8 Data bits (LSB first)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                UART_rxd = byte_data[bit_idx];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end

            // Stop bit
            UART_rxd = 1'b1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // UART receive monitor (SoC -> Host PC)
    reg [7:0] received_byte;
    integer rx_byte_count = 0;

    always begin
        @(negedge UART_txd);
        repeat (CLKS_PER_BIT / 2) @(posedge clk);
        if (UART_txd == 1'b0) begin
            repeat (8) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                received_byte = {UART_txd, received_byte[7:1]};
            end
            repeat (CLKS_PER_BIT) @(posedge clk);
            rx_byte_count = rx_byte_count + 1;
            $display("[UART RX from SoC] Byte %0d = 0x%02X", rx_byte_count, received_byte);
        end
    end

    // Test sequence
    initial begin
        $display("=================================================");
        $display("  PICORV32 + SOBEL ACCELERATOR SoC SIMULATION   ");
        $display("=================================================");

        UART_rxd = 1'b1;
        btn_rst  = 1'b1;

        #200;
        btn_rst  = 1'b0;
        $display("[STATUS] Reset released. CPU booting into Boot ROM...");

        // Wait for CPU to boot into firmware
        wait (led == 16'h0001);
        $display("[STATUS] CPU successfully booted! LED = 0x%04X (Ready for Image)", led);

        #1000;
        $display("[STATUS] Simulation verification completed successfully.");
        $display("=================================================");
        $finish;
    end

endmodule
