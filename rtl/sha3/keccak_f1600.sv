`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: keccak_f1600
// Description: Keccak-f[1600] 24-round permutation engine per FIPS 202.
//              Features:
//              - Strict constant-time execution: exactly 24 clock cycles per block.
//              - 1 round per clock cycle (1600-bit state registered).
//              - Eliminates timing side channels.
//              - Instantaneous 1-cycle hardware zeroization.
//////////////////////////////////////////////////////////////////////////////////

module keccak_f1600 (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          zeroize,
    input  logic          start,
    input  logic [1599:0] state_in,
    output logic          done,
    output logic [1599:0] state_out
);

    typedef enum logic [1:0] {
        IDLE,
        PERMUTE,
        DONE
    } state_t;

    state_t state_q, state_d;
    logic [4:0]  round_cnt_q, round_cnt_d;
    logic [63:0] lanes_q [0:4][0:4];
    logic [63:0] lanes_d [0:4][0:4];

    // Unpack 1600-bit state_in into 5x5 lanes
    // In FIPS 202: lane (x, y) corresponds to lane index (x + 5*y)
    // Little-endian mapping: bit 0 of lane 0 is state_in[0]
    logic [63:0] state_in_lanes [0:4][0:4];
    genvar x, y;
    generate
        for (y = 0; y < 5; y++) begin : gen_unpack_y
            for (x = 0; x < 5; x++) begin : gen_unpack_x
                assign state_in_lanes[x][y] = state_in[(x + 5*y)*64 +: 64];
            end
        end
    endgenerate

    // Round Constant Generator
    logic [63:0] round_const;
    keccak_round_constants u_rc (
        .round_idx   (round_cnt_q),
        .round_const (round_const)
    );

    // Keccak Round Combinational Module
    logic [63:0] round_out_lanes [0:4][0:4];
    keccak_round u_round (
        .state_in    (lanes_q),
        .round_const (round_const),
        .state_out   (round_out_lanes)
    );

    // FSM Combinational
    always_comb begin
        state_d     = state_q;
        round_cnt_d = round_cnt_q;
        lanes_d     = lanes_q;
        done        = 1'b0;

        case (state_q)
            IDLE: begin
                if (start) begin
                    lanes_d     = state_in_lanes;
                    round_cnt_d = 5'd0;
                    state_d     = PERMUTE;
                end
            end

            PERMUTE: begin
                lanes_d = round_out_lanes;
                if (round_cnt_q == 5'd23) begin
                    state_d = DONE;
                end else begin
                    round_cnt_d = round_cnt_q + 1'b1;
                end
            end

            DONE: begin
                done    = 1'b1;
                state_d = IDLE;
            end

            default: state_d = IDLE;
        endcase
    end

    // Sequential Registers with Zeroization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q     <= IDLE;
            round_cnt_q <= 5'd0;
            for (int yi = 0; yi < 5; yi++) begin
                for (int xi = 0; xi < 5; xi++) begin
                    lanes_q[xi][yi] <= 64'h0;
                end
            end
        end else if (zeroize) begin
            // Instant 1-cycle state purge
            state_q     <= IDLE;
            round_cnt_q <= 5'd0;
            for (int yi = 0; yi < 5; yi++) begin
                for (int xi = 0; xi < 5; xi++) begin
                    lanes_q[xi][yi] <= 64'h0;
                end
            end
        end else begin
            state_q     <= state_d;
            round_cnt_q <= round_cnt_d;
            lanes_q     <= lanes_d;
        end
    end

    // Pack 5x5 lanes back into 1600-bit state_out
    generate
        for (y = 0; y < 5; y++) begin : gen_pack_y
            for (x = 0; x < 5; x++) begin : gen_pack_x
                assign state_out[(x + 5*y)*64 +: 64] = lanes_q[x][y];
            end
        end
    endgenerate

endmodule
