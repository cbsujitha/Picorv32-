`timescale 1ns / 1ps

module sobel (
    input  wire [7:0] p00, p01, p02,
    input  wire [7:0] p10, p11, p12,
    input  wire [7:0] p20, p21, p22,
    output wire [7:0] edge_pixel
);

    wire signed [11:0] gx;
    wire signed [11:0] gy;
    wire [11:0] abs_gx;
    wire [11:0] abs_gy;
    wire [11:0] sum;

    // Horizontal gradient: Gx
    assign gx = ($signed({4'd0, p02}) + $signed({3'd0, p12, 1'b0}) + $signed({4'd0, p22})) -
                ($signed({4'd0, p00}) + $signed({3'd0, p10, 1'b0}) + $signed({4'd0, p20}));

    // Vertical gradient: Gy
    assign gy = ($signed({4'd0, p20}) + $signed({3'd0, p21, 1'b0}) + $signed({4'd0, p22})) -
                ($signed({4'd0, p00}) + $signed({3'd0, p01, 1'b0}) + $signed({4'd0, p02}));

    assign abs_gx = (gx < 0) ? -gx : gx;
    assign abs_gy = (gy < 0) ? -gy : gy;
    assign sum    = abs_gx + abs_gy;

    // Saturate at 255
    assign edge_pixel = (sum > 12'd255) ? 8'd255 : sum[7:0];

endmodule
