`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: aes_round
// Description: Fully synthesizable AES encryption round module.
//              Implements SubBytes (16 S-boxes), ShiftRows, MixColumns
//              (with bypass for the 14th/final round), and AddRoundKey.
//              Optimized for 200 MHz timing closure in SkyWater 130nm.
//////////////////////////////////////////////////////////////////////////////////

module aes_round (
    input  logic [127:0] state_in,
    input  logic [127:0] round_key,
    input  logic         is_final_round,
    output logic [127:0] state_out
);

    // Byte unpacking: byte 0 is state_in[127:120], byte 15 is state_in[7:0]
    logic [7:0] state_bytes [0:15];
    logic [7:0] sb_bytes    [0:15];
    logic [7:0] sr_bytes    [0:15];
    logic [7:0] mc_bytes    [0:15];

    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : gen_unpack
            assign state_bytes[i] = state_in[127 - 8*i : 120 - 8*i];
        end
    endgenerate

    // 1. SubBytes: 16 parallel S-Box instances
    generate
        for (i = 0; i < 16; i++) begin : gen_sbox
            aes_sbox u_sbox (
                .in_byte  (state_bytes[i]),
                .out_byte (sb_bytes[i])
            );
        end
    endgenerate

    // 2. ShiftRows
    // State layout (Column-Major):
    // Col 0: sb[0],  sb[1],  sb[2],  sb[3]
    // Col 1: sb[4],  sb[5],  sb[6],  sb[7]
    // Col 2: sb[8],  sb[9],  sb[10], sb[11]
    // Col 3: sb[12], sb[13], sb[14], sb[15]
    always_comb begin
        // Row 0: shift 0
        sr_bytes[0]  = sb_bytes[0];
        sr_bytes[4]  = sb_bytes[4];
        sr_bytes[8]  = sb_bytes[8];
        sr_bytes[12] = sb_bytes[12];

        // Row 1: shift left 1
        sr_bytes[1]  = sb_bytes[5];
        sr_bytes[5]  = sb_bytes[9];
        sr_bytes[9]  = sb_bytes[13];
        sr_bytes[13] = sb_bytes[1];

        // Row 2: shift left 2
        sr_bytes[2]  = sb_bytes[10];
        sr_bytes[6]  = sb_bytes[14];
        sr_bytes[10] = sb_bytes[2];
        sr_bytes[14] = sb_bytes[6];

        // Row 3: shift left 3
        sr_bytes[3]  = sb_bytes[15];
        sr_bytes[7]  = sb_bytes[3];
        sr_bytes[11] = sb_bytes[7];
        sr_bytes[15] = sb_bytes[11];
    end

    // 3. MixColumns
    function automatic logic [7:0] xtime(input logic [7:0] b);
        xtime = b[7] ? ((b << 1) ^ 8'h1b) : (b << 1);
    endfunction

    genvar c;
    generate
        for (c = 0; c < 4; c++) begin : gen_mix_columns
            wire [7:0] s0 = sr_bytes[4*c + 0];
            wire [7:0] s1 = sr_bytes[4*c + 1];
            wire [7:0] s2 = sr_bytes[4*c + 2];
            wire [7:0] s3 = sr_bytes[4*c + 3];

            wire [7:0] mc0 = xtime(s0) ^ (xtime(s1) ^ s1) ^ s2 ^ s3;
            wire [7:0] mc1 = s0 ^ xtime(s1) ^ (xtime(s2) ^ s2) ^ s3;
            wire [7:0] mc2 = s0 ^ s1 ^ xtime(s2) ^ (xtime(s3) ^ s3);
            wire [7:0] mc3 = (xtime(s0) ^ s0) ^ s1 ^ s2 ^ xtime(s3);

            assign mc_bytes[4*c + 0] = is_final_round ? s0 : mc0;
            assign mc_bytes[4*c + 1] = is_final_round ? s1 : mc1;
            assign mc_bytes[4*c + 2] = is_final_round ? s2 : mc2;
            assign mc_bytes[4*c + 3] = is_final_round ? s3 : mc3;
        end
    endgenerate

    // 4. AddRoundKey
    logic [127:0] mc_packed;
    generate
        for (i = 0; i < 16; i++) begin : gen_pack
            assign mc_packed[127 - 8*i : 120 - 8*i] = mc_bytes[i];
        end
    endgenerate

    assign state_out = mc_packed ^ round_key;

endmodule
