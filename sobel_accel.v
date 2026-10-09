`timescale 1ns / 1ps

// =========================================================================
// Sobel Edge Detection Hardware Accelerator
// Computes 64x64 Sobel convolution on dual-port Block RAM buffers
// =========================================================================
module sobel_accel #(
    parameter integer IMAGE_WIDTH  = 64,
    parameter integer IMAGE_HEIGHT = 64
)(
    input  wire        clk,
    input  wire        rst,

    // Control from CPU
    input  wire        start,
    output reg         busy,
    output reg         done,

    // Input DPRAM (Port B, read)
    output reg  [11:0] in_addr,
    input  wire [7:0]  in_data,

    // Output DPRAM (Port B, write)
    output reg         out_we,
    output reg  [11:0] out_addr,
    output reg  [7:0]  out_data
);

    localparam [1:0] S_IDLE   = 2'd0;
    localparam [1:0] S_BORDER = 2'd1;
    localparam [1:0] S_FETCH  = 2'd2;
    localparam [1:0] S_FINISH = 2'd3;

    reg [1:0]  state;
    reg [5:0]  curr_row;
    reg [5:0]  curr_col;
    reg [3:0]  fetch_step;

    reg [7:0] p00, p01, p02;
    reg [7:0] p10, p11, p12;
    reg [7:0] p20, p21, p22;

    wire [7:0] sobel_edge;

    sobel sobel_core (
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .edge_pixel(sobel_edge)
    );

    wire [11:0] curr_pixel_addr = (curr_row * IMAGE_WIDTH) + curr_col;
    wire is_border = (curr_row == 0 || curr_row == (IMAGE_HEIGHT - 1) ||
                      curr_col == 0 || curr_col == (IMAGE_WIDTH - 1));

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            busy       <= 1'b0;
            done       <= 1'b0;
            curr_row   <= 6'd0;
            curr_col   <= 6'd0;
            fetch_step <= 4'd0;
            in_addr    <= 12'd0;
            out_we     <= 1'b0;
            out_addr   <= 12'd0;
            out_data   <= 8'd0;
        end else begin
            out_we <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy     <= 1'b1;
                        done     <= 1'b0;
                        curr_row <= 6'd0;
                        curr_col <= 6'd0;
                        state    <= S_BORDER;
                    end
                end

                S_BORDER: begin
                    if (is_border) begin
                        out_we   <= 1'b1;
                        out_addr <= curr_pixel_addr;
                        out_data <= 8'd0;

                        if (curr_col == IMAGE_WIDTH - 1) begin
                            curr_col <= 6'd0;
                            if (curr_row == IMAGE_HEIGHT - 1) begin
                                state <= S_FINISH;
                            end else begin
                                curr_row <= curr_row + 6'd1;
                            end
                        end else begin
                            curr_col <= curr_col + 6'd1;
                        end
                    end else begin
                        fetch_step <= 4'd0;
                        state      <= S_FETCH;
                    end
                end

                S_FETCH: begin
                    case (fetch_step)
                        4'd0: begin
                            in_addr    <= ((curr_row - 1) * IMAGE_WIDTH) + (curr_col - 1); // p00
                            fetch_step <= 4'd1;
                        end
                        4'd1: begin
                            in_addr    <= ((curr_row - 1) * IMAGE_WIDTH) + (curr_col);     // p01
                            fetch_step <= 4'd2;
                        end
                        4'd2: begin
                            p00        <= in_data;
                            in_addr    <= ((curr_row - 1) * IMAGE_WIDTH) + (curr_col + 1); // p02
                            fetch_step <= 4'd3;
                        end
                        4'd3: begin
                            p01        <= in_data;
                            in_addr    <= ((curr_row    ) * IMAGE_WIDTH) + (curr_col - 1); // p10
                            fetch_step <= 4'd4;
                        end
                        4'd4: begin
                            p02        <= in_data;
                            in_addr    <= ((curr_row    ) * IMAGE_WIDTH) + (curr_col);     // p11
                            fetch_step <= 4'd5;
                        end
                        4'd5: begin
                            p10        <= in_data;
                            in_addr    <= ((curr_row    ) * IMAGE_WIDTH) + (curr_col + 1); // p12
                            fetch_step <= 4'd6;
                        end
                        4'd6: begin
                            p11        <= in_data;
                            in_addr    <= ((curr_row + 1) * IMAGE_WIDTH) + (curr_col - 1); // p20
                            fetch_step <= 4'd7;
                        end
                        4'd7: begin
                            p12        <= in_data;
                            in_addr    <= ((curr_row + 1) * IMAGE_WIDTH) + (curr_col);     // p21
                            fetch_step <= 4'd8;
                        end
                        4'd8: begin
                            p20        <= in_data;
                            in_addr    <= ((curr_row + 1) * IMAGE_WIDTH) + (curr_col + 1); // p22
                            fetch_step <= 4'd9;
                        end
                        4'd9: begin
                            p21        <= in_data;
                            fetch_step <= 4'd10;
                        end
                        4'd10: begin
                            p22        <= in_data;
                            fetch_step <= 4'd11;
                        end
                        4'd11: begin
                            out_we   <= 1'b1;
                            out_addr <= curr_pixel_addr;
                            out_data <= sobel_edge;

                            if (curr_col == IMAGE_WIDTH - 1) begin
                                curr_col <= 6'd0;
                                if (curr_row == IMAGE_HEIGHT - 1) begin
                                    state <= S_FINISH;
                                end else begin
                                    curr_row <= curr_row + 6'd1;
                                    state    <= S_BORDER;
                                end
                            end else begin
                                curr_col <= curr_col + 6'd1;
                                state    <= S_BORDER;
                            end
                        end
                        default: state <= S_BORDER;
                    endcase
                end

                S_FINISH: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
