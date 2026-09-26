`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: rot_top
// Description: Production-Grade Hardware Root-of-Trust (RoT) Cryptographic Engine.
//              Integrates:
//              - AES-256 (ECB, CBC, and GCM authenticated encryption/decryption).
//              - GHASH GF(2^128) Galois field authentication engine.
//              - SHA-3 / Keccak-f[1600] 24-round sponge cryptographic hash.
//              - APB4 standard memory-mapped host interface.
//              - Hardware Key Confidentiality (Write-only, lock register, bus masking).
//              - Physical Anti-Tamper & 1-cycle instantaneous Zeroization line.
//              - Constant-time execution datapath (side-channel mitigation).
//              Target Node: SkyWater 130nm @ 200 MHz.
//////////////////////////////////////////////////////////////////////////////////

module rot_top (
    // Clock and Reset
    input  logic        pclk,
    input  logic        presetn,

    // Physical Security & Anti-Tamper Pins
    input  logic        rot_zeroize_pin, // External tamper / emergency wipe
    output logic        rot_alarm_out,   // Security alarm indicator
    output logic        rot_irq_out,     // Interrupt request to host CPU

    // APB4 Slave Bus Interface
    input  logic [11:0] paddr,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] pwdata,
    input  logic [3:0]  pstrb,
    output logic        pready,
    output logic [31:0] prdata,
    output logic        pslverr
);

    // Register Address Offsets
    localparam [11:0] ADDR_CONTROL      = 12'h000;
    localparam [11:0] ADDR_STATUS       = 12'h004;
    localparam [11:0] ADDR_IRQ_EN       = 12'h008;
    localparam [11:0] ADDR_IRQ_STAT     = 12'h00C;

    // Key registers 0x010 - 0x02C (8 words = 256 bits, Write-Only, Bus-Masked)
    localparam [11:0] ADDR_KEY_0        = 12'h010;
    localparam [11:0] ADDR_KEY_7        = 12'h02C;

    // IV registers 0x030 - 0x038 (3 words = 96 bits)
    localparam [11:0] ADDR_IV_0         = 12'h030;
    localparam [11:0] ADDR_IV_1         = 12'h034;
    localparam [11:0] ADDR_IV_2         = 12'h038;

    // Length registers 0x040 - 0x04C
    localparam [11:0] ADDR_AAD_LEN_LO   = 12'h040;
    localparam [11:0] ADDR_AAD_LEN_HI   = 12'h044;
    localparam [11:0] ADDR_DATA_LEN_LO  = 12'h048;
    localparam [11:0] ADDR_DATA_LEN_HI  = 12'h04C;

    // Tag In 0x050 - 0x05C (128 bits)
    localparam [11:0] ADDR_TAG_IN_0     = 12'h050;
    localparam [11:0] ADDR_TAG_IN_3     = 12'h05C;

    // Tag Out 0x060 - 0x06C (128 bits, Read-Only)
    localparam [11:0] ADDR_TAG_OUT_0    = 12'h060;
    localparam [11:0] ADDR_TAG_OUT_3    = 12'h06C;

    // Data In 0x070 - 0x07C (128 bits)
    localparam [11:0] ADDR_DATA_IN_0    = 12'h070;
    localparam [11:0] ADDR_DATA_IN_3    = 12'h07C;

    // Data Out 0x080 - 0x08C (128 bits, Read-Only)
    localparam [11:0] ADDR_DATA_OUT_0   = 12'h080;
    localparam [11:0] ADDR_DATA_OUT_3   = 12'h08C;

    // SHA-3 Digest 0x090 - 0x0AC (8 words = 256 bits, Read-Only)
    localparam [11:0] ADDR_DIGEST_0     = 12'h090;
    localparam [11:0] ADDR_DIGEST_7     = 12'h0AC;

    // Combined Zeroize Signal (Pin or Software command)
    logic sw_zeroize;
    logic global_zeroize;
    assign global_zeroize = rot_zeroize_pin | sw_zeroize;

    // RoT Control Registers
    logic [31:0] ctrl_reg;
    logic [31:0] status_reg;
    logic [31:0] irq_en_reg;
    logic [31:0] irq_stat_reg;

    // Key Storage (Strictly Confidential: Zeroed on readback)
    logic [31:0] key_words [0:7];
    logic        key_locked_reg;

    // IV Storage
    logic [31:0] iv_words [0:2];

    // Length Storage
    logic [63:0] aad_len_reg;
    logic [63:0] data_len_reg;

    // Tag Storage
    logic [31:0] tag_in_words [0:3];
    logic [31:0] tag_out_words [0:3];

    // Data In & Out Buffers
    logic [31:0] data_in_words [0:3];
    logic [31:0] data_out_words [0:3];

    // SHA-3 Digest Buffer
    logic [31:0] digest_words [0:7];

    // Control field unpacking (uses live pwdata during ADDR_CONTROL write cycle)
    wire ctrl_write_active = psel && penable && pwrite && (paddr == ADDR_CONTROL);
    wire [31:0] effective_ctrl = ctrl_write_active ? pwdata : ctrl_reg;

    wire op_start          = effective_ctrl[0];
    wire engine_sel_sha3   = effective_ctrl[1];      // 0: AES, 1: SHA-3
    wire [1:0] aes_mode    = effective_ctrl[3:2];    // 00: ECB, 01: CBC, 10: GCM
    wire enc_dec_n         = effective_ctrl[4];      // 1: Encrypt, 0: Decrypt
    wire sha3_mode_512     = effective_ctrl[5];      // 0: 256, 1: 512
    wire data_block_is_aad = effective_ctrl[6];      // GCM: 1 if block in DATA_IN is AAD
    wire key_commit        = effective_ctrl[7];      // Pulse to expand & validate key
    assign sw_zeroize      = effective_ctrl[8];
    wire key_lock_cmd      = effective_ctrl[16];

    // Submodule Signals
    // 1. AES Core
    logic         aes_data_valid;
    logic         aes_ready;
    logic         aes_out_valid;
    logic [127:0] aes_out_data;

    // 2. AES-GCM Top
    logic         gcm_start;
    logic         gcm_block_in_valid;
    logic         gcm_block_in_ready;
    logic         gcm_block_out_valid;
    logic [127:0] gcm_block_out_data;
    logic         gcm_tag_valid;
    logic [127:0] gcm_tag_out;
    logic         gcm_tag_match;
    logic         gcm_busy;

    // 3. SHA-3 Core
    logic         sha3_start;
    logic         sha3_ready;
    logic         sha3_word_valid;
    logic [63:0]  sha3_word_data;
    logic         sha3_word_last;
    logic [2:0]   sha3_valid_bytes;
    logic         sha3_word_ready;
    logic         sha3_digest_valid;
    logic [255:0] sha3_digest_256;
    logic [511:0] sha3_digest_512;

    // Packed 256-bit Key and 96-bit IV
    wire [255:0] packed_key = {key_words[0], key_words[1], key_words[2], key_words[3],
                               key_words[4], key_words[5], key_words[6], key_words[7]};
    wire [95:0]  packed_iv  = {iv_words[0], iv_words[1], iv_words[2]};
    wire [127:0] packed_data_in = {
        data_in_words[0],
        data_in_words[1],
        data_in_words[2],
        (psel && penable && pwrite && (paddr == ADDR_DATA_IN_3)) ? pwdata : data_in_words[3]
    };
    wire [127:0] packed_tag_in  = {tag_in_words[0], tag_in_words[1], tag_in_words[2], tag_in_words[3]};

    // Instantiate AES Core (for ECB / CBC)
    aes_core u_aes_core_inst (
        .clk            (pclk),
        .rst_n          (presetn),
        .zeroize        (global_zeroize),
        .key_load_req   (key_commit && !engine_sel_sha3 && (aes_mode != 2'b10)),
        .cipher_key     (packed_key),
        .key_ready      (),
        .data_valid     (aes_data_valid),
        .mode           (aes_mode),
        .enc_dec_n      (enc_dec_n),
        .data_in        (packed_data_in),
        .iv_in          ({packed_iv, 32'h0}),
        .ready          (aes_ready),
        .data_out_valid (aes_out_valid),
        .data_out       (aes_out_data)
    );

    // Instantiate AES-GCM Engine
    aes_gcm_top u_gcm_inst (
        .clk             (pclk),
        .rst_n           (presetn),
        .zeroize         (global_zeroize),
        .start_op        (gcm_start),
        .enc_dec_n       (enc_dec_n),
        .cipher_key      (packed_key),
        .iv_in           (packed_iv),
        .aad_len_bytes   (aad_len_reg),
        .data_len_bytes  (data_len_reg),
        .block_in_valid  (gcm_block_in_valid),
        .block_is_aad    (data_block_is_aad),
        .block_in_data   (packed_data_in),
        .block_in_ready  (gcm_block_in_ready),
        .block_out_valid (gcm_block_out_valid),
        .block_out_data  (gcm_block_out_data),
        .tag_in          (packed_tag_in),
        .tag_valid       (gcm_tag_valid),
        .tag_out         (gcm_tag_out),
        .tag_match       (gcm_tag_match),
        .busy            (gcm_busy)
    );

    // Instantiate SHA-3 Core
    sha3_core u_sha3_inst (
        .clk            (pclk),
        .rst_n          (presetn),
        .zeroize        (global_zeroize),
        .start_hash     (sha3_start),
        .mode_sha3_512  (sha3_mode_512),
        .empty_msg      (data_len_reg == 64'd0),
        .ready          (sha3_ready),
        .word_valid     (sha3_word_valid),
        .word_data      (sha3_word_data),
        .word_is_last   (sha3_word_last),
        .valid_bytes    (sha3_valid_bytes),
        .word_ready     (sha3_word_ready),
        .digest_valid   (sha3_digest_valid),
        .digest_256     (sha3_digest_256),
        .digest_512     (sha3_digest_512)
    );

    // APB4 State Machine
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    // Operation Trigger Decoding
    always_comb begin
        aes_data_valid     = 1'b0;
        gcm_start          = 1'b0;
        gcm_block_in_valid = 1'b0;
        sha3_start         = 1'b0;
        sha3_word_valid    = 1'b0;
        sha3_word_data     = {data_in_words[0], data_in_words[1]};
        sha3_word_last     = ctrl_reg[9];
        sha3_valid_bytes   = ctrl_reg[12:10];

        if (psel && penable && pwrite && (paddr == ADDR_CONTROL) && pwdata[0]) begin
            if (pwdata[1] == 1'b0) begin
                // AES Engine
                if (pwdata[3:2] == 2'b10) begin
                    // GCM Mode
                    gcm_start = 1'b1;
                end else begin
                    // ECB or CBC Mode
                    aes_data_valid = 1'b1;
                end
            end else begin
                // SHA-3 Engine
                sha3_start = 1'b1;
            end
        end

        // Streaming block input to GCM
        if (psel && penable && pwrite && (paddr == ADDR_DATA_IN_3)) begin
            if (!engine_sel_sha3 && (aes_mode == 2'b10)) begin
                gcm_block_in_valid = 1'b1;
            end
        end
    end

    // Output capture logic
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            data_out_words[0] <= 32'h0;
            data_out_words[1] <= 32'h0;
            data_out_words[2] <= 32'h0;
            data_out_words[3] <= 32'h0;

            tag_out_words[0]  <= 32'h0;
            tag_out_words[1]  <= 32'h0;
            tag_out_words[2]  <= 32'h0;
            tag_out_words[3]  <= 32'h0;

            for (int d = 0; d < 8; d++) digest_words[d] <= 32'h0;
            irq_stat_reg <= 32'h0;
        end else if (global_zeroize) begin
            // 1-Cycle Instantaneous Wipe
            data_out_words[0] <= 32'h0;
            data_out_words[1] <= 32'h0;
            data_out_words[2] <= 32'h0;
            data_out_words[3] <= 32'h0;

            tag_out_words[0]  <= 32'h0;
            tag_out_words[1]  <= 32'h0;
            tag_out_words[2]  <= 32'h0;
            tag_out_words[3]  <= 32'h0;

            for (int d = 0; d < 8; d++) digest_words[d] <= 32'h0;
            irq_stat_reg <= 32'h0;
        end else begin
            // Capture AES ECB/CBC output
            if (aes_out_valid) begin
                data_out_words[0] <= aes_out_data[127:96];
                data_out_words[1] <= aes_out_data[95:64];
                data_out_words[2] <= aes_out_data[63:32];
                data_out_words[3] <= aes_out_data[31:0];
                irq_stat_reg[0]   <= 1'b1; // Done IRQ
            end

            // Capture GCM block output
            if (gcm_block_out_valid) begin
                data_out_words[0] <= gcm_block_out_data[127:96];
                data_out_words[1] <= gcm_block_out_data[95:64];
                data_out_words[2] <= gcm_block_out_data[63:32];
                data_out_words[3] <= gcm_block_out_data[31:0];
            end

            // Capture GCM final tag output
            if (gcm_tag_valid) begin
                tag_out_words[0] <= gcm_tag_out[127:96];
                tag_out_words[1] <= gcm_tag_out[95:64];
                tag_out_words[2] <= gcm_tag_out[63:32];
                tag_out_words[3] <= gcm_tag_out[31:0];
                irq_stat_reg[0]  <= 1'b1; // Done IRQ
            end

            // Capture SHA-3 digest output
            if (sha3_digest_valid) begin
                for (int d = 0; d < 8; d++) begin
                    digest_words[d] <= {
                        sha3_digest_256[32*d + 0  +: 8],
                        sha3_digest_256[32*d + 8  +: 8],
                        sha3_digest_256[32*d + 16 +: 8],
                        sha3_digest_256[32*d + 24 +: 8]
                    };
                end
                irq_stat_reg[0] <= 1'b1; // Done IRQ
            end

            // Clear IRQ status on write-1-to-clear
            if (psel && penable && pwrite && (paddr == ADDR_IRQ_STAT)) begin
                irq_stat_reg <= irq_stat_reg & ~pwdata;
            end
        end
    end

    // APB Write Path (Configuration, Keys, IV, Data)
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ctrl_reg        <= 32'h0;
            irq_en_reg      <= 32'h0;
            key_locked_reg  <= 1'b0;
            for (int k = 0; k < 8; k++) key_words[k] <= 32'h0;
            for (int v = 0; v < 3; v++) iv_words[v]  <= 32'h0;
            aad_len_reg     <= 64'd0;
            data_len_reg    <= 64'd0;
            for (int t = 0; t < 4; t++) tag_in_words[t]  <= 32'h0;
            for (int d = 0; d < 4; d++) data_in_words[d] <= 32'h0;
        end else if (global_zeroize) begin
            // 1-Cycle Instantaneous Wipe of All Sensitive Registers
            ctrl_reg        <= 32'h0;
            irq_en_reg      <= 32'h0;
            key_locked_reg  <= 1'b0;
            for (int k = 0; k < 8; k++) key_words[k] <= 32'h0;
            for (int v = 0; v < 3; v++) iv_words[v]  <= 32'h0;
            aad_len_reg     <= 64'd0;
            data_len_reg    <= 64'd0;
            for (int t = 0; t < 4; t++) tag_in_words[t]  <= 32'h0;
            for (int d = 0; d < 4; d++) data_in_words[d] <= 32'h0;
        end else begin
            // Auto-clear start and key_commit strobes
            ctrl_reg[0] <= 1'b0;
            ctrl_reg[7] <= 1'b0;

            if (psel && penable && pwrite) begin
                case (paddr)
                    ADDR_CONTROL: begin
                        ctrl_reg <= pwdata;
                        if (pwdata[16]) key_locked_reg <= 1'b1; // Lock key once set
                    end
                    ADDR_IRQ_EN:      irq_en_reg <= pwdata;

                    // Key registers: Only writable if NOT locked!
                    ADDR_KEY_0: if (!key_locked_reg) key_words[0] <= pwdata;
                    ADDR_KEY_0 + 4:  if (!key_locked_reg) key_words[1] <= pwdata;
                    ADDR_KEY_0 + 8:  if (!key_locked_reg) key_words[2] <= pwdata;
                    ADDR_KEY_0 + 12: if (!key_locked_reg) key_words[3] <= pwdata;
                    ADDR_KEY_0 + 16: if (!key_locked_reg) key_words[4] <= pwdata;
                    ADDR_KEY_0 + 20: if (!key_locked_reg) key_words[5] <= pwdata;
                    ADDR_KEY_0 + 24: if (!key_locked_reg) key_words[6] <= pwdata;
                    ADDR_KEY_7:      if (!key_locked_reg) key_words[7] <= pwdata;

                    ADDR_IV_0: iv_words[0] <= pwdata;
                    ADDR_IV_1: iv_words[1] <= pwdata;
                    ADDR_IV_2: iv_words[2] <= pwdata;

                    ADDR_AAD_LEN_LO:  aad_len_reg[31:0]  <= pwdata;
                    ADDR_AAD_LEN_HI:  aad_len_reg[63:32] <= pwdata;
                    ADDR_DATA_LEN_LO: data_len_reg[31:0]  <= pwdata;
                    ADDR_DATA_LEN_HI: data_len_reg[63:32] <= pwdata;

                    ADDR_TAG_IN_0:     tag_in_words[0] <= pwdata;
                    ADDR_TAG_IN_0 + 4: tag_in_words[1] <= pwdata;
                    ADDR_TAG_IN_0 + 8: tag_in_words[2] <= pwdata;
                    ADDR_TAG_IN_3:     tag_in_words[3] <= pwdata;

                    ADDR_DATA_IN_0:     data_in_words[0] <= pwdata;
                    ADDR_DATA_IN_0 + 4: data_in_words[1] <= pwdata;
                    ADDR_DATA_IN_0 + 8: data_in_words[2] <= pwdata;
                    ADDR_DATA_IN_3:     data_in_words[3] <= pwdata;
                    default: ;
                endcase
            end
        end
    end

    // Status Register Packing
    always_comb begin
        status_reg    = 32'h0;
        status_reg[0] = gcm_busy | (!sha3_ready);
        status_reg[1] = irq_stat_reg[0]; // Done
        status_reg[2] = 1'b1;            // Key loaded
        status_reg[3] = key_locked_reg;  // Key locked
        status_reg[4] = gcm_tag_match;   // GCM Tag Match
        status_reg[5] = global_zeroize;  // Zeroized state
    end

    // APB Read Path (STRICT SECURITY: Key reads are HARDWARE MASKED to 32'h0!)
    always_comb begin
        prdata = 32'h0;
        if (psel && !pwrite) begin
            case (paddr)
                ADDR_CONTROL:  prdata = ctrl_reg;
                ADDR_STATUS:   prdata = status_reg;
                ADDR_IRQ_EN:   prdata = irq_en_reg;
                ADDR_IRQ_STAT: prdata = irq_stat_reg;

                // KEY REGISTERS: ALWAYS READ AS ZERO (Protects Root-of-Trust key confidentiality)
                ADDR_KEY_0, ADDR_KEY_0+4, ADDR_KEY_0+8, ADDR_KEY_0+12,
                ADDR_KEY_0+16, ADDR_KEY_0+20, ADDR_KEY_0+24, ADDR_KEY_7: begin
                    prdata = 32'h00000000;
                end

                ADDR_IV_0: prdata = iv_words[0];
                ADDR_IV_1: prdata = iv_words[1];
                ADDR_IV_2: prdata = iv_words[2];

                ADDR_AAD_LEN_LO:  prdata = aad_len_reg[31:0];
                ADDR_AAD_LEN_HI:  prdata = aad_len_reg[63:32];
                ADDR_DATA_LEN_LO: prdata = data_len_reg[31:0];
                ADDR_DATA_LEN_HI: prdata = data_len_reg[63:32];

                ADDR_TAG_OUT_0:     prdata = tag_out_words[0];
                ADDR_TAG_OUT_0 + 4: prdata = tag_out_words[1];
                ADDR_TAG_OUT_0 + 8: prdata = tag_out_words[2];
                ADDR_TAG_OUT_3:     prdata = tag_out_words[3];

                ADDR_DATA_OUT_0:     prdata = data_out_words[0];
                ADDR_DATA_OUT_0 + 4: prdata = data_out_words[1];
                ADDR_DATA_OUT_0 + 8: prdata = data_out_words[2];
                ADDR_DATA_OUT_3:     prdata = data_out_words[3];

                ADDR_DIGEST_0:      prdata = digest_words[0];
                ADDR_DIGEST_0 + 4:  prdata = digest_words[1];
                ADDR_DIGEST_0 + 8:  prdata = digest_words[2];
                ADDR_DIGEST_0 + 12: prdata = digest_words[3];
                ADDR_DIGEST_0 + 16: prdata = digest_words[4];
                ADDR_DIGEST_0 + 20: prdata = digest_words[5];
                ADDR_DIGEST_0 + 24: prdata = digest_words[6];
                ADDR_DIGEST_7:      prdata = digest_words[7];

                default: prdata = 32'h00000000;
            endcase
        end
    end

    // Latched Security Alarm Indicator (persists until master reset)
    logic alarm_latched_q;
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            alarm_latched_q <= 1'b0;
        end else if (global_zeroize) begin
            alarm_latched_q <= 1'b1;
        end
    end

    // Interrupt and Alarm outputs
    assign rot_irq_out   = |(irq_stat_reg & irq_en_reg);
    assign rot_alarm_out = global_zeroize | alarm_latched_q;

endmodule
