`timescale 1ns / 1ps

// =========================================================================
// 4096-Byte True Dual-Port Block RAM
// Port A: 32-bit CPU interface (1024 words, byte write enables)
// Port B: 8-bit Sobel Accelerator interface (4096 bytes)
// =========================================================================
module sobel_dpram_4096 (
    input  wire        clk,

    // Port A (PicoRV32 CPU 32-bit access)
    input  wire        we_a,
    input  wire [3:0]  wstrb_a,
    input  wire [9:0]  addr_a,      // word address 0..1023
    input  wire [31:0] din_a,
    output reg  [31:0] dout_a,

    // Port B (Sobel Accelerator 8-bit access)
    input  wire        we_b,
    input  wire [11:0] addr_b,      // byte address 0..4095
    input  wire [7:0]  din_b,
    output reg  [7:0]  dout_b
);

    // Four 1024 x 8-bit byte slices (infers 1 RAMB36E1 or 2 RAMB18E1s)
    (* ram_style = "block" *) reg [7:0] ram0 [0:1023];
    (* ram_style = "block" *) reg [7:0] ram1 [0:1023];
    (* ram_style = "block" *) reg [7:0] ram2 [0:1023];
    (* ram_style = "block" *) reg [7:0] ram3 [0:1023];

    // Port A synchronous read/write
    always @(posedge clk) begin
        if (we_a) begin
            if (wstrb_a[0]) ram0[addr_a] <= din_a[7:0];
            if (wstrb_a[1]) ram1[addr_a] <= din_a[15:8];
            if (wstrb_a[2]) ram2[addr_a] <= din_a[23:16];
            if (wstrb_a[3]) ram3[addr_a] <= din_a[31:24];
        end
        dout_a <= {ram3[addr_a], ram2[addr_a], ram1[addr_a], ram0[addr_a]};
    end

    // Port B synchronous read/write
    wire [9:0] word_addr_b = addr_b[11:2];
    wire [1:0] byte_sel_b  = addr_b[1:0];

    reg [7:0] b_dout0, b_dout1, b_dout2, b_dout3;
    reg [1:0] byte_sel_d;

    always @(posedge clk) begin
        if (we_b) begin
            case (byte_sel_b)
                2'd0: ram0[word_addr_b] <= din_b;
                2'd1: ram1[word_addr_b] <= din_b;
                2'd2: ram2[word_addr_b] <= din_b;
                2'd3: ram3[word_addr_b] <= din_b;
            endcase
        end
        b_dout0    <= ram0[word_addr_b];
        b_dout1    <= ram1[word_addr_b];
        b_dout2    <= ram2[word_addr_b];
        b_dout3    <= ram3[word_addr_b];
        byte_sel_d <= byte_sel_b;
    end

    always @(*) begin
        case (byte_sel_d)
            2'd0: dout_b = b_dout0;
            2'd1: dout_b = b_dout1;
            2'd2: dout_b = b_dout2;
            2'd3: dout_b = b_dout3;
        endcase
    end

endmodule
