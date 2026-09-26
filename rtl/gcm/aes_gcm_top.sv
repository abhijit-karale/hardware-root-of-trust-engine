`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: aes_gcm_top
// Description: Complete Production-Grade AES-256-GCM Authenticated Encryption &
//              Decryption Engine conforming strictly to NIST SP 800-38D.
//              Integrates:
//              - AES-256 pipelined core (keystream and subkey generation).
//              - GHASH GF(2^128) accumulator engine.
//              - Counter block generator (inc32 modulo 2^32).
//              - Automatic length block formatting and padding.
//              - Constant-time tag comparison for side-channel mitigation.
//              - Instantaneous hardware zeroization.
//////////////////////////////////////////////////////////////////////////////////

module aes_gcm_top (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         zeroize,        // 1-cycle high-priority key & state wipe

    // Control & Configuration
    input  logic         start_op,       // Pulse to initiate GCM session
    input  logic         enc_dec_n,      // 1: Authenticated Encrypt, 0: Authenticated Decrypt
    input  logic [255:0] cipher_key,     // 256-bit AES Master Key
    input  logic [95:0]  iv_in,          // 96-bit Initialization Vector
    input  logic [63:0]  aad_len_bytes,  // Total AAD byte length
    input  logic [63:0]  data_len_bytes, // Total Plaintext/Ciphertext byte length

    // Streaming Data Ports (128-bit block-level interface)
    input  logic         block_in_valid,
    input  logic         block_is_aad,   // 1: block belongs to AAD, 0: PT/CT
    input  logic [127:0] block_in_data,
    output logic         block_in_ready, // Ready to accept next block

    // Stream Output
    output logic         block_out_valid,
    output logic [127:0] block_out_data, // Ciphertext (if encrypt) or Plaintext (if decrypt)

    // Tag Interface
    input  logic [127:0] tag_in,         // Provided tag for verification (in decrypt mode)
    output logic         tag_valid,      // Tag output or verification result ready
    output logic [127:0] tag_out,        // Computed 128-bit authentication tag
    output logic         tag_match,      // 1: Tag verified correctly (decrypt mode)
    output logic         busy
);

    // GCM FSM States
    typedef enum logic [3:0] {
        GCM_IDLE,
        GCM_KEY_EXP,       // Latch key and expand
        GCM_GEN_H,         // Compute H = AES_K(0^128)
        GCM_WAIT_H,
        GCM_GEN_S0,        // Compute S0 = AES_K(J0)
        GCM_WAIT_S0,
        GCM_PROCESS_AAD,   // Stream AAD into GHASH
        GCM_PROCESS_DATA,  // CTR encrypt/decrypt & stream CT into GHASH
        GCM_PROCESS_LEN,   // Stream length block into GHASH
        GCM_WAIT_GHASH,
        GCM_FINALIZE,      // Compute T = GHASH ^ S0
        GCM_DONE
    } gcm_state_t;

    gcm_state_t state_q, state_d;

    // Internal Registers
    logic [255:0] key_reg;
    logic [95:0]  iv_reg;
    logic [63:0]  aad_bytes_rem_q, aad_bytes_rem_d;
    logic [63:0]  data_bytes_rem_q, data_bytes_rem_d;
    logic [63:0]  total_aad_bytes_q, total_aad_bytes_d;
    logic [63:0]  total_data_bytes_q, total_data_bytes_d;
    logic         enc_mode_q, enc_mode_d;

    logic [127:0] h_subkey_q, h_subkey_d;
    logic [127:0] s0_mask_q, s0_mask_d;
    logic [31:0]  ctr32_q, ctr32_d;
    logic [127:0] tag_out_q, tag_out_d;
    logic         tag_match_q, tag_match_d;

    // AES Core Signals
    logic         aes_key_load;
    logic [255:0] aes_cipher_key;
    logic         aes_key_ready;
    logic         aes_data_valid;
    logic [1:0]   aes_mode;
    logic [127:0] aes_data_in;
    logic         aes_ready;
    logic         aes_data_out_valid;
    logic [127:0] aes_data_out;

    aes_core u_aes_core (
        .clk            (clk),
        .rst_n          (rst_n),
        .zeroize        (zeroize),
        .key_load_req   (aes_key_load),
        .cipher_key     (aes_cipher_key),
        .key_ready      (aes_key_ready),
        .data_valid     (aes_data_valid),
        .mode           (2'b00), // AES raw block encryption (ECB mode)
        .enc_dec_n      (1'b1),  // Always forward encryption in GCM
        .data_in        (aes_data_in),
        .iv_in          (128'h0),
        .ready          (aes_ready),
        .data_out_valid (aes_data_out_valid),
        .data_out       (aes_data_out)
    );

    // GHASH Core Signals
    logic         ghash_init;
    logic [127:0] ghash_h_key;
    logic         ghash_block_valid;
    logic [127:0] ghash_block_in;
    logic         ghash_block_ready;
    logic         ghash_y_valid;
    logic [127:0] ghash_y_out;

    ghash_core u_ghash_core (
        .clk         (clk),
        .rst_n       (rst_n),
        .zeroize     (zeroize),
        .init        (ghash_init),
        .h_key       (h_subkey_q),
        .block_valid (ghash_block_valid),
        .block_in    (ghash_block_in),
        .block_ready (ghash_block_ready),
        .y_valid     (ghash_y_valid),
        .y_out       (ghash_y_out)
    );

    // Keystream / CTR block fifo / pipeline match register
    logic [127:0] pt_hold_reg;
    logic [127:0] ct_to_ghash;

    // FSM Combinational Logic
    always_comb begin
        state_d            = state_q;
        aad_bytes_rem_d    = aad_bytes_rem_q;
        data_bytes_rem_d   = data_bytes_rem_q;
        total_aad_bytes_d  = total_aad_bytes_q;
        total_data_bytes_d = total_data_bytes_q;
        enc_mode_d         = enc_mode_q;
        h_subkey_d         = h_subkey_q;
        s0_mask_d          = s0_mask_q;
        ctr32_d            = ctr32_q;
        tag_out_d          = tag_out_q;
        tag_match_d        = tag_match_q;

        aes_key_load       = 1'b0;
        aes_cipher_key     = cipher_key;
        aes_data_valid     = 1'b0;
        aes_data_in        = 128'h0;

        ghash_init         = 1'b0;
        ghash_block_valid  = 1'b0;
        ghash_block_in     = 128'h0;

        block_in_ready     = 1'b0;
        block_out_valid    = 1'b0;
        block_out_data     = 128'h0;
        tag_valid          = 1'b0;
        busy               = 1'b1;

        case (state_q)
            GCM_IDLE: begin
                busy = 1'b0;
                if (start_op) begin
                    enc_mode_d         = enc_dec_n;
                    total_aad_bytes_d  = aad_len_bytes;
                    total_data_bytes_d = data_len_bytes;
                    aad_bytes_rem_d    = aad_len_bytes;
                    data_bytes_rem_d   = data_len_bytes;
                    ctr32_d            = 32'd1; // J0 uses counter=1

                    aes_key_load       = 1'b1;
                    ghash_init         = 1'b1;
                    state_d            = GCM_KEY_EXP;
                end
            end

            GCM_KEY_EXP: begin
                if (aes_key_ready) begin
                    // Request H = AES_K(0^128)
                    aes_data_valid = 1'b1;
                    aes_data_in    = 128'h0;
                    state_d        = GCM_WAIT_H;
                end
            end

            GCM_WAIT_H: begin
                if (aes_data_out_valid) begin
                    h_subkey_d = aes_data_out;
                    // Now compute S0 = AES_K(J0) where J0 = {iv, 31'b0, 1'b1}
                    aes_data_valid = 1'b1;
                    aes_data_in    = {iv_in, 32'd1};
                    state_d        = GCM_WAIT_S0;
                end
            end

            GCM_WAIT_S0: begin
                if (aes_data_out_valid) begin
                    s0_mask_d = aes_data_out;
                    ctr32_d   = 32'd2; // CTR for data blocks starts at J0 + 1 (i.e. counter=2)

                    if (total_aad_bytes_q > 0) begin
                        state_d = GCM_PROCESS_AAD;
                    end else if (total_data_bytes_q > 0) begin
                        state_d = GCM_PROCESS_DATA;
                    end else begin
                        state_d = GCM_PROCESS_LEN;
                    end
                end
            end

            GCM_PROCESS_AAD: begin
                block_in_ready = ghash_block_ready;
                if (block_in_valid && ghash_block_ready && block_is_aad) begin
                    ghash_block_valid = 1'b1;
                    ghash_block_in    = block_in_data;

                    if (aad_bytes_rem_q <= 16) begin
                        aad_bytes_rem_d = 64'd0;
                        if (total_data_bytes_q > 0) begin
                            state_d = GCM_PROCESS_DATA;
                        end else begin
                            state_d = GCM_PROCESS_LEN;
                        end
                    end else begin
                        aad_bytes_rem_d = aad_bytes_rem_q - 16;
                    end
                end
            end

            GCM_PROCESS_DATA: begin
                // In CTR mode:
                // Launch AES_K({iv, ctr32}) to produce keystream
                // When keystream arrives from AES pipeline:
                // If Encrypt: CT = PT ^ Keystream; block_out_data = CT; feed CT to GHASH
                // If Decrypt: PT = CT ^ Keystream; block_out_data = PT; feed CT (input) to GHASH
                if (data_bytes_rem_q > 0) begin
                    block_in_ready = aes_ready && ghash_block_ready;
                    if (block_in_valid && aes_ready && ghash_block_ready && !block_is_aad) begin
                        aes_data_valid = 1'b1;
                        aes_data_in    = {iv_in, ctr32_q};
                        ctr32_d        = ctr32_q + 1'b1;

                        if (enc_mode_q) begin
                            // Encrypt: block_in_data is Plaintext
                            // Note: We use synchronous pipeline handshake
                        end
                    end

                    if (aes_data_out_valid) begin
                        block_out_valid = 1'b1;
                        if (enc_mode_q) begin
                            block_out_data    = block_in_data ^ aes_data_out;
                            ghash_block_valid = 1'b1;
                            for (int i = 0; i < 16; i++) begin
                                if (data_bytes_rem_q >= 16 || i < data_bytes_rem_q) begin
                                    ghash_block_in[127 - 8*i -: 8] = block_in_data[127 - 8*i -: 8] ^ aes_data_out[127 - 8*i -: 8];
                                end else begin
                                    ghash_block_in[127 - 8*i -: 8] = 8'h00;
                                end
                            end
                        end else begin
                            block_out_data    = block_in_data ^ aes_data_out;
                            ghash_block_valid = 1'b1;
                            for (int i = 0; i < 16; i++) begin
                                if (data_bytes_rem_q >= 16 || i < data_bytes_rem_q) begin
                                    ghash_block_in[127 - 8*i -: 8] = block_in_data[127 - 8*i -: 8];
                                end else begin
                                    ghash_block_in[127 - 8*i -: 8] = 8'h00;
                                end
                            end
                        end

                        if (data_bytes_rem_q <= 16) begin
                            data_bytes_rem_d = 64'd0;
                            state_d          = GCM_PROCESS_LEN;
                        end else begin
                            data_bytes_rem_d = data_bytes_rem_q - 16;
                        end
                    end
                end else begin
                    state_d = GCM_PROCESS_LEN;
                end
            end

            GCM_PROCESS_LEN: begin
                // Length block: [len(A)]_64 || [len(C)]_64 in bits!
                if (ghash_block_ready) begin
                    ghash_block_valid = 1'b1;
                    ghash_block_in    = {total_aad_bytes_q[60:0], 3'b000, total_data_bytes_q[60:0], 3'b000};
                    state_d           = GCM_WAIT_GHASH;
                end
            end

            GCM_WAIT_GHASH: begin
                if (ghash_y_valid) begin
                    state_d = GCM_FINALIZE;
                end
            end

            GCM_FINALIZE: begin
                // Final tag T = GHASH(H, A, C) ^ S0
                tag_out_d = ghash_y_out ^ s0_mask_q;

                // Constant-time tag verification (compares all 128 bits without early-out)
                tag_match_d = ( (ghash_y_out ^ s0_mask_q) == tag_in );
                state_d     = GCM_DONE;
            end

            GCM_DONE: begin
                busy      = 1'b0;
                tag_valid = 1'b1;
                state_d   = GCM_IDLE;
            end

            default: state_d = GCM_IDLE;
        endcase
    end

    // Sequential State Registers with Hardware Zeroization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q            <= GCM_IDLE;
            aad_bytes_rem_q    <= 64'd0;
            data_bytes_rem_q   <= 64'd0;
            total_aad_bytes_q  <= 64'd0;
            total_data_bytes_q <= 64'd0;
            enc_mode_q         <= 1'b1;
            h_subkey_q         <= 128'h0;
            s0_mask_q          <= 128'h0;
            ctr32_q            <= 32'd0;
            tag_out_q          <= 128'h0;
            tag_match_q        <= 1'b0;
        end else if (zeroize) begin
            // 1-Cycle Instantaneous Wipe of All Sensitive RoT State
            state_q            <= GCM_IDLE;
            aad_bytes_rem_q    <= 64'd0;
            data_bytes_rem_q   <= 64'd0;
            total_aad_bytes_q  <= 64'd0;
            total_data_bytes_q <= 64'd0;
            enc_mode_q         <= 1'b1;
            h_subkey_q         <= 128'h0;
            s0_mask_q          <= 128'h0;
            ctr32_q            <= 32'd0;
            tag_out_q          <= 128'h0;
            tag_match_q        <= 1'b0;
        end else begin
            state_q            <= state_d;
            aad_bytes_rem_q    <= aad_bytes_rem_d;
            data_bytes_rem_q   <= data_bytes_rem_d;
            total_aad_bytes_q  <= total_aad_bytes_d;
            total_data_bytes_q <= total_data_bytes_d;
            enc_mode_q         <= enc_mode_d;
            h_subkey_q         <= h_subkey_d;
            s0_mask_q          <= s0_mask_d;
            ctr32_q            <= ctr32_d;
            tag_out_q          <= tag_out_d;
            tag_match_q        <= tag_match_d;
        end
    end

    assign tag_out   = tag_out_q;
    assign tag_match = tag_match_q;

endmodule
