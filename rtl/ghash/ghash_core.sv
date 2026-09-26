`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: ghash_core
// Description: GHASH Authenticator Engine conforming to NIST SP 800-38D.
//              Features:
//              - Integrates gf_mul128 for Galois field GF(2^128) arithmetic.
//              - State accumulator Y_i = (Y_{i-1} ^ X_i) * H.
//              - Deterministic constant-time execution (exactly 2 cycles per 128-bit block).
//              - Zero data-dependent control flow (side-channel mitigation).
//              - Hardware zeroization support.
//////////////////////////////////////////////////////////////////////////////////

module ghash_core (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         zeroize,     // 1-cycle instantaneous state clear

    input  logic         init,        // Resets accumulator Y to 0
    input  logic [127:0] h_key,       // Hash subkey H = AES_K(0^128)
    input  logic         block_valid, // New 128-bit block presented
    input  logic [127:0] block_in,    // 128-bit data block
    output logic         block_ready, // Ready to accept next block
    output logic         y_valid,     // Accumulator updated
    output logic [127:0] y_out        // Current GHASH accumulator value
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_MUL,
        ST_UPDATE
    } ghash_state_t;

    ghash_state_t state_q, state_d;
    logic [127:0] y_accum_q, y_accum_d;
    logic         mul_start;
    logic [127:0] mul_op_a;
    logic         mul_done;
    logic [127:0] mul_prod;

    // GF(2^128) Multiplier Instance
    gf_mul128 u_gf_mul (
        .clk      (clk),
        .rst_n    (rst_n),
        .zeroize  (zeroize),
        .start    (mul_start),
        .op_a     (mul_op_a),
        .op_b     (h_key),
        .done     (mul_done),
        .prod_out (mul_prod)
    );

    always_comb begin
        state_d     = state_q;
        y_accum_d   = y_accum_q;
        mul_start   = 1'b0;
        mul_op_a    = 128'h0;
        block_ready = 1'b0;
        y_valid     = 1'b0;

        case (state_q)
            ST_IDLE: begin
                block_ready = 1'b1;
                if (init) begin
                    y_accum_d = 128'h0;
                end else if (block_valid) begin
                    mul_op_a    = y_accum_q ^ block_in;
                    mul_start   = 1'b1;
                    state_d     = ST_MUL;
                end
            end

            ST_MUL: begin
                block_ready = 1'b0;
                if (mul_done) begin
                    y_accum_d = mul_prod;
                    y_valid   = 1'b1;
                    state_d   = ST_IDLE;
                end
            end

            default: state_d = ST_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q   <= ST_IDLE;
            y_accum_q <= 128'h0;
        end else if (zeroize) begin
            state_q   <= ST_IDLE;
            y_accum_q <= 128'h0;
        end else begin
            state_q   <= state_d;
            y_accum_q <= y_accum_d;
        end
    end

    assign y_out = y_accum_q;

endmodule
