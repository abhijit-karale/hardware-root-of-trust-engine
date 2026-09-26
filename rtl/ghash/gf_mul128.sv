`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: gf_mul128
// Description: Galois Field GF(2^128) Multiplier for NIST SP 800-38D (GHASH).
//              Features:
//              - Pipelined 2-stage execution for 200 MHz timing closure in SkyWater 130nm.
//              - Bit-reversed carry-less polynomial multiplication over GF(2).
//              - Closed-form 2-step modular reduction mod f(x) = x^128 + x^7 + x^2 + x + 1.
//              - Strictly constant-time execution: exactly 2 clock cycles per multiplication.
//              - Instantaneous hardware zeroization.
//////////////////////////////////////////////////////////////////////////////////

module gf_mul128 (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         zeroize,
    input  logic         start,
    input  logic [127:0] op_a,      // NIST SP 800-38D format
    input  logic [127:0] op_b,      // NIST SP 800-38D format
    output logic         done,
    output logic [127:0] prod_out   // NIST SP 800-38D format
);

    // Bit reversal function (maps NIST bit-0 to standard polynomial x^0)
    function automatic logic [127:0] bit_rev(input logic [127:0] in_vec);
        integer b;
        for (b = 0; b < 128; b++) begin
            bit_rev[b] = in_vec[127 - b];
        end
    endfunction

    // Stage 1: Carry-less Multiplication
    logic [127:0] a_rev, b_rev;
    logic [254:0] poly_prod_comb;
    logic [254:0] poly_prod_reg;
    logic         valid_stage1;

    assign a_rev = bit_rev(op_a);
    assign b_rev = bit_rev(op_b);

    // Combinational carry-less polynomial multiplier (GF(2) polynomial multiplication)
    always_comb begin
        poly_prod_comb = 255'h0;
        for (int i = 0; i < 128; i++) begin
            if (b_rev[i]) begin
                poly_prod_comb ^= ({{127{1'b0}}, a_rev} << i);
            end
        end
    end

    // Pipeline Register 1
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            poly_prod_reg <= 255'h0;
            valid_stage1  <= 1'b0;
        end else if (zeroize) begin
            poly_prod_reg <= 255'h0;
            valid_stage1  <= 1'b0;
        end else begin
            if (start) begin
                poly_prod_reg <= poly_prod_comb;
                valid_stage1  <= 1'b1;
            end else begin
                valid_stage1  <= 1'b0;
            end
        end
    end

    // Stage 2: Modular Reduction modulo f(x) = x^128 + x^7 + x^2 + x + 1
    // f(x) reduction polynomial mask: 8'h87
    logic [126:0] upper_part;
    logic [127:0] lower_part;
    logic [134:0] rem1;
    logic [6:0]   upper2;
    logic [127:0] red_poly;
    logic [127:0] result_reg;
    logic         done_reg;

    always_comb begin
        upper_part = poly_prod_reg[254:128];
        lower_part = poly_prod_reg[127:0];

        // Step 1: Fold bits 128..254 into lower bits using x^128 = x^7 + x^2 + x + 1
        rem1 = {{7{1'b0}}, lower_part} ^
               ({{1{1'b0}}, upper_part, 7'h0}) ^
               ({{6{1'b0}}, upper_part, 2'h0}) ^
               ({{7{1'b0}}, upper_part, 1'b0}) ^
               ({{8{1'b0}}, upper_part});

        // Step 2: Fold overflow bits 128..134 once more
        upper2 = rem1[134:128];
        red_poly = rem1[127:0] ^
                   {114'h0, upper2, 7'h0} ^
                   {119'h0, upper2, 2'h0} ^
                   {120'h0, upper2, 1'b0} ^
                   {121'h0, upper2};
    end

    // Pipeline Register 2 (Output)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_reg <= 128'h0;
            done_reg   <= 1'b0;
        end else if (zeroize) begin
            result_reg <= 128'h0;
            done_reg   <= 1'b0;
        end else begin
            if (valid_stage1) begin
                result_reg <= bit_rev(red_poly);
                done_reg   <= 1'b1;
            end else begin
                done_reg   <= 1'b0;
            end
        end
    end

    assign done     = done_reg;
    assign prod_out = result_reg;

endmodule
