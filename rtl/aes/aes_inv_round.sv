`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: aes_inv_round
// Description: Fully synthesizable AES decryption (inverse) round module.
//              Implements InvShiftRows, InvSubBytes (16 inverse S-boxes),
//              AddRoundKey, and InvMixColumns (bypassed on final inverse round).
//////////////////////////////////////////////////////////////////////////////////

module aes_inv_round (
    input  logic [127:0] state_in,
    input  logic [127:0] round_key,
    input  logic         is_final_round, // Bypasses InvMixColumns
    output logic [127:0] state_out
);

    logic [7:0] state_bytes [0:15];
    logic [7:0] isr_bytes   [0:15];
    logic [7:0] isb_bytes   [0:15];
    logic [7:0] ark_bytes   [0:15];
    logic [7:0] imc_bytes   [0:15];

    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : gen_unpack
            assign state_bytes[i] = state_in[127 - 8*i : 120 - 8*i];
        end
    endgenerate

    // 1. InvShiftRows
    always_comb begin
        // Row 0: shift 0
        isr_bytes[0]  = state_bytes[0];
        isr_bytes[4]  = state_bytes[4];
        isr_bytes[8]  = state_bytes[8];
        isr_bytes[12] = state_bytes[12];

        // Row 1: cyclic right shift 1 (left shift 3)
        isr_bytes[1]  = state_bytes[13];
        isr_bytes[5]  = state_bytes[1];
        isr_bytes[9]  = state_bytes[5];
        isr_bytes[13] = state_bytes[9];

        // Row 2: cyclic right shift 2 (left shift 2)
        isr_bytes[2]  = state_bytes[10];
        isr_bytes[6]  = state_bytes[14];
        isr_bytes[10] = state_bytes[2];
        isr_bytes[14] = state_bytes[6];

        // Row 3: cyclic right shift 3 (left shift 1)
        isr_bytes[3]  = state_bytes[7];
        isr_bytes[7]  = state_bytes[11];
        isr_bytes[11] = state_bytes[15];
        isr_bytes[15] = state_bytes[3];
    end

    // 2. InvSubBytes
    generate
        for (i = 0; i < 16; i++) begin : gen_inv_sbox
            aes_inv_sbox u_inv_sbox (
                .in_byte  (isr_bytes[i]),
                .out_byte (isb_bytes[i])
            );
        end
    endgenerate

    // 3. AddRoundKey
    generate
        for (i = 0; i < 16; i++) begin : gen_ark
            assign ark_bytes[i] = isb_bytes[i] ^ round_key[127 - 8*i : 120 - 8*i];
        end
    endgenerate

    // 4. InvMixColumns: Multiplications by {0e}, {0b}, {0d}, {09}
    function automatic logic [7:0] xtime(input logic [7:0] b);
        xtime = b[7] ? ((b << 1) ^ 8'h1b) : (b << 1);
    endfunction

    function automatic logic [7:0] mul_09(input logic [7:0] b);
        mul_09 = xtime(xtime(xtime(b))) ^ b;
    endfunction

    function automatic logic [7:0] mul_0b(input logic [7:0] b);
        mul_0b = xtime(xtime(xtime(b))) ^ xtime(b) ^ b;
    endfunction

    function automatic logic [7:0] mul_0d(input logic [7:0] b);
        mul_0d = xtime(xtime(xtime(b))) ^ xtime(xtime(b)) ^ b;
    endfunction

    function automatic logic [7:0] mul_0e(input logic [7:0] b);
        mul_0e = xtime(xtime(xtime(b))) ^ xtime(xtime(b)) ^ xtime(b);
    endfunction

    genvar c;
    generate
        for (c = 0; c < 4; c++) begin : gen_inv_mix_cols
            wire [7:0] s0 = ark_bytes[4*c + 0];
            wire [7:0] s1 = ark_bytes[4*c + 1];
            wire [7:0] s2 = ark_bytes[4*c + 2];
            wire [7:0] s3 = ark_bytes[4*c + 3];

            wire [7:0] imc0 = mul_0e(s0) ^ mul_0b(s1) ^ mul_0d(s2) ^ mul_09(s3);
            wire [7:0] imc1 = mul_09(s0) ^ mul_0e(s1) ^ mul_0b(s2) ^ mul_0d(s3);
            wire [7:0] imc2 = mul_0d(s0) ^ mul_09(s1) ^ mul_0e(s2) ^ mul_0b(s3);
            wire [7:0] imc3 = mul_0b(s0) ^ mul_0d(s1) ^ mul_09(s2) ^ mul_0e(s3);

            assign imc_bytes[4*c + 0] = is_final_round ? s0 : imc0;
            assign imc_bytes[4*c + 1] = is_final_round ? s1 : imc1;
            assign imc_bytes[4*c + 2] = is_final_round ? s2 : imc2;
            assign imc_bytes[4*c + 3] = is_final_round ? s3 : imc3;
        end
    endgenerate

    generate
        for (i = 0; i < 16; i++) begin : gen_pack_out
            assign state_out[127 - 8*i : 120 - 8*i] = imc_bytes[i];
        end
    endgenerate

endmodule
