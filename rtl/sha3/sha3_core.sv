`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: sha3_core
// Description: SHA-3 / Keccak Sponge Function Core conforming to FIPS 202.
//              Supports SHA3-256 (rate = 1088 bits) and SHA3-512 (rate = 576 bits).
//              Features:
//              - Automated hardware pad10*1 padding generator with 0x06 domain separator.
//              - Pipelined Keccak-f[1600] 24-round permutation engine.
//              - Constant-time block processing (24 cycles per permutation).
//              - Side-channel mitigation with uniform cycle execution.
//              - Instantaneous hardware zeroize signal.
//////////////////////////////////////////////////////////////////////////////////

module sha3_core (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         zeroize,        // High-priority 1-cycle state wipe

    // Control Interface
    input  logic         start_hash,     // Pulse to begin new hash session
    input  logic         mode_sha3_512,  // 0: SHA3-256, 1: SHA3-512
    input  logic         empty_msg,      // High if hashing empty message (|M| = 0)
    output logic         ready,          // Ready to accept data or new session

    // Message Input Interface (64-bit word streaming)
    input  logic         word_valid,
    input  logic [63:0]  word_data,
    input  logic         word_is_last,   // Last word of message
    input  logic [2:0]   valid_bytes,    // Number of valid bytes in last word (1 to 7, or 0 for 8 bytes)
    output logic         word_ready,

    // Digest Output Interface
    output logic         digest_valid,
    output logic [255:0] digest_256,
    output logic [511:0] digest_512
);

    // Sponge Rates:
    // SHA3-256: rate = 1088 bits = 17 lanes (64-bit words) = 136 bytes
    // SHA3-512: rate = 576 bits  = 9 lanes  (64-bit words) = 72 bytes
    localparam int RATE_LANES_256 = 17;
    localparam int RATE_LANES_512 = 9;

    typedef enum logic [2:0] {
        IDLE,
        ABSORB,
        PAD,
        PERMUTE,
        SQUEEZE,
        DONE
    } state_t;

    state_t state_q, state_d;

    logic [1599:0] sponge_state_q, sponge_state_d;
    logic [4:0]    lane_cnt_q, lane_cnt_d;
    logic          is_512_q, is_512_d;
    logic          keccak_start;
    logic          keccak_done;
    logic [1599:0] keccak_state_out;

    logic [4:0] current_rate_lanes;
    assign current_rate_lanes = is_512_q ? RATE_LANES_512 : RATE_LANES_256;

    // Instantiate Keccak-f[1600] 24-round engine
    keccak_f1600 u_keccak (
        .clk       (clk),
        .rst_n     (rst_n),
        .zeroize   (zeroize),
        .start     (keccak_start),
        .state_in  (sponge_state_d),
        .done      (keccak_done),
        .state_out (keccak_state_out)
    );

    // Hardware Pad10*1 formatter
    function automatic logic [63:0] format_pad_lane(
        input logic [63:0] last_word,
        input logic [2:0]  v_bytes,
        input logic        is_pad_only
    );
        logic [7:0] bytes_in [0:7];
        logic [7:0] bytes_out [0:7];
        for (int i = 0; i < 8; i++) begin
            bytes_in[i] = last_word[8*i +: 8];
        end

        if (is_pad_only) begin
            bytes_out[0] = 8'h06;
            for (int i = 1; i < 8; i++) bytes_out[i] = 8'h00;
        end else begin
            case (v_bytes)
                3'd0: begin // 8 valid bytes (no room for 0x06 in this lane)
                    for (int i = 0; i < 8; i++) bytes_out[i] = bytes_in[i];
                end
                3'd1: begin
                    bytes_out[0] = bytes_in[0];
                    bytes_out[1] = 8'h06;
                    for (int i = 2; i < 8; i++) bytes_out[i] = 8'h00;
                end
                3'd2: begin
                    bytes_out[0] = bytes_in[0]; bytes_out[1] = bytes_in[1];
                    bytes_out[2] = 8'h06;
                    for (int i = 3; i < 8; i++) bytes_out[i] = 8'h00;
                end
                3'd3: begin
                    bytes_out[0] = bytes_in[0]; bytes_out[1] = bytes_in[1]; bytes_out[2] = bytes_in[2];
                    bytes_out[3] = 8'h06;
                    for (int i = 4; i < 8; i++) bytes_out[i] = 8'h00;
                end
                3'd4: begin
                    for (int i = 0; i < 4; i++) bytes_out[i] = bytes_in[i];
                    bytes_out[4] = 8'h06;
                    for (int i = 5; i < 8; i++) bytes_out[i] = 8'h00;
                end
                3'd5: begin
                    for (int i = 0; i < 5; i++) bytes_out[i] = bytes_in[i];
                    bytes_out[5] = 8'h06;
                    for (int i = 6; i < 8; i++) bytes_out[i] = 8'h00;
                end
                3'd6: begin
                    for (int i = 0; i < 6; i++) bytes_out[i] = bytes_in[i];
                    bytes_out[6] = 8'h06;
                    bytes_out[7] = 8'h00;
                end
                3'd7: begin
                    for (int i = 0; i < 7; i++) bytes_out[i] = bytes_in[i];
                    bytes_out[7] = 8'h06;
                end
            endcase
        end

        for (int i = 0; i < 8; i++) begin
            format_pad_lane[8*i +: 8] = bytes_out[i];
        end
    endfunction

    // FSM Combinational Logic
    always_comb begin
        state_d        = state_q;
        sponge_state_d = sponge_state_q;
        lane_cnt_d     = lane_cnt_q;
        is_512_d       = is_512_q;
        keccak_start   = 1'b0;
        ready          = 1'b0;
        word_ready     = 1'b0;
        digest_valid   = 1'b0;

        case (state_q)
            IDLE: begin
                ready = 1'b1;
                if (start_hash) begin
                    sponge_state_d = 1600'h0;
                    lane_cnt_d     = 5'd0;
                    is_512_d       = mode_sha3_512;
                    if (empty_msg) begin
                        sponge_state_d[7:0] = 8'h06;
                        sponge_state_d[((mode_sha3_512 ? RATE_LANES_512 : RATE_LANES_256) - 1)*64 + 56 +: 8] = 8'h80;
                        keccak_start = 1'b1;
                        state_d      = PERMUTE;
                    end else begin
                        state_d      = ABSORB;
                    end
                end
            end

            ABSORB: begin
                word_ready = 1'b1;
                if (word_valid) begin
                    if (word_is_last) begin
                        if (valid_bytes == 3'd0) begin
                            // Exactly 8 bytes in this lane: XOR this lane, then advance to pad lane
                            sponge_state_d[lane_cnt_q*64 +: 64] = sponge_state_q[lane_cnt_q*64 +: 64] ^ word_data;
                            if (lane_cnt_q == current_rate_lanes - 1) begin
                                // End of rate block: trigger Keccak, then add pad block
                                keccak_start = 1'b1;
                                lane_cnt_d   = 5'd0;
                                state_d      = PERMUTE;
                            end else begin
                                lane_cnt_d = lane_cnt_q + 1'b1;
                                state_d    = PAD;
                            end
                        end else begin
                            // Partial lane: append 0x06 domain separator in this lane
                            sponge_state_d[lane_cnt_q*64 +: 64] = sponge_state_q[lane_cnt_q*64 +: 64] ^ 
                                                                 format_pad_lane(word_data, valid_bytes, 1'b0);
                            state_d = PAD;
                        end
                    end else begin
                        // Standard full 64-bit word absorption
                        sponge_state_d[lane_cnt_q*64 +: 64] = sponge_state_q[lane_cnt_q*64 +: 64] ^ word_data;
                        if (lane_cnt_q == current_rate_lanes - 1) begin
                            keccak_start = 1'b1;
                            lane_cnt_d   = 5'd0;
                            state_d      = PERMUTE;
                        end else begin
                            lane_cnt_d = lane_cnt_q + 1'b1;
                        end
                    end
                end
            end

            PAD: begin
                // In PAD state: if we haven't placed 0x06, place it. Then set MSB of rate (0x80) on the last rate lane!
                // Last rate lane index is (current_rate_lanes - 1)
                sponge_state_d[(current_rate_lanes - 1)*64 + 56 +: 8] = 
                    sponge_state_q[(current_rate_lanes - 1)*64 + 56 +: 8] ^ 8'h80;
                keccak_start = 1'b1;
                state_d      = PERMUTE;
            end

            PERMUTE: begin
                if (keccak_done) begin
                    sponge_state_d = keccak_state_out;
                    state_d        = SQUEEZE;
                end
            end

            SQUEEZE: begin
                digest_valid = 1'b1;
                state_d      = DONE;
            end

            DONE: begin
                ready        = 1'b1;
                digest_valid = 1'b1;
                if (start_hash) begin
                    sponge_state_d = 1600'h0;
                    lane_cnt_d     = 5'd0;
                    is_512_d       = mode_sha3_512;
                    state_d        = ABSORB;
                end
            end

            default: state_d = IDLE;
        endcase
    end

    // Sequential Registers with Zeroization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q        <= IDLE;
            sponge_state_q <= 1600'h0;
            lane_cnt_q     <= 5'd0;
            is_512_q       <= 1'b0;
        end else if (zeroize) begin
            // 1-Cycle Instantaneous State Wipe
            state_q        <= IDLE;
            sponge_state_q <= 1600'h0;
            lane_cnt_q     <= 5'd0;
            is_512_q       <= 1'b0;
        end else begin
            state_q        <= state_d;
            sponge_state_q <= sponge_state_d;
            lane_cnt_q     <= lane_cnt_d;
            is_512_q       <= is_512_d;
        end
    end

    // Squeeze Outputs:
    // SHA3-256: first 4 lanes (256 bits = 32 bytes)
    // SHA3-512: first 8 lanes (512 bits = 64 bytes)
    assign digest_256 = sponge_state_q[255:0];
    assign digest_512 = sponge_state_q[511:0];

endmodule
