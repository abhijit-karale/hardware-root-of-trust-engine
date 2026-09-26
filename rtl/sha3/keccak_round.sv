`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: keccak_round
// Description: Combinational single round of Keccak-f[1600] permutation.
//              Implements the five step mappings:
//              - Theta: Column parity computation and mixing.
//              - Rho:   Fixed coordinate-dependent bit rotation.
//              - Pi:    Coordinate permutation.
//              - Chi:   Non-linear row mapping.
//              - Iota:  Round constant injection into lane (0,0).
//////////////////////////////////////////////////////////////////////////////////

module keccak_round (
    input  logic [63:0] state_in [0:4][0:4],
    input  logic [63:0] round_const,
    output logic [63:0] state_out [0:4][0:4]
);

    // 64-bit circular left rotation function
    function automatic logic [63:0] rol64(input logic [63:0] val, input int unsigned shift);
        rol64 = (val << shift) | (val >> (64 - shift));
    endfunction

    // 1. Theta Step
    logic [63:0] c [0:4];
    logic [63:0] d [0:4];
    logic [63:0] a_theta [0:4][0:4];

    always_comb begin
        for (int x = 0; x < 5; x++) begin
            c[x] = state_in[x][0] ^ state_in[x][1] ^ state_in[x][2] ^ state_in[x][3] ^ state_in[x][4];
        end

        for (int x = 0; x < 5; x++) begin
            d[x] = c[(x + 4) % 5] ^ rol64(c[(x + 1) % 5], 1);
        end

        for (int x = 0; x < 5; x++) begin
            for (int y = 0; y < 5; y++) begin
                a_theta[x][y] = state_in[x][y] ^ d[x];
            end
        end
    end

    // 2. Rho and Pi Steps
    logic [63:0] b [0:4][0:4];

    // Rotation offsets per FIPS 202 Table 2:
    // (0,0): 0,  (1,0): 1,  (2,0): 62, (3,0): 28, (4,0): 27
    // (0,1): 36, (1,1): 44, (2,1): 6,  (3,1): 55, (4,1): 20
    // (0,2): 3,  (1,2): 10, (2,2): 43, (3,2): 25, (4,2): 39
    // (0,3): 41, (1,3): 45, (2,3): 15, (3,3): 21, (4,3): 8
    // (0,4): 18, (1,4): 2,  (2,4): 61, (3,4): 56, (4,4): 14
    always_comb begin
        b[0][0] = rol64(a_theta[0][0],  0);
        b[0][2] = rol64(a_theta[1][0],  1);
        b[0][4] = rol64(a_theta[2][0], 62);
        b[0][1] = rol64(a_theta[3][0], 28);
        b[0][3] = rol64(a_theta[4][0], 27);

        b[1][3] = rol64(a_theta[0][1], 36);
        b[1][0] = rol64(a_theta[1][1], 44);
        b[1][2] = rol64(a_theta[2][1],  6);
        b[1][4] = rol64(a_theta[3][1], 55);
        b[1][1] = rol64(a_theta[4][1], 20);

        b[2][1] = rol64(a_theta[0][2],  3);
        b[2][3] = rol64(a_theta[1][2], 10);
        b[2][0] = rol64(a_theta[2][2], 43);
        b[2][2] = rol64(a_theta[3][2], 25);
        b[2][4] = rol64(a_theta[4][2], 39);

        b[3][4] = rol64(a_theta[0][3], 41);
        b[3][1] = rol64(a_theta[1][3], 45);
        b[3][3] = rol64(a_theta[2][3], 15);
        b[3][0] = rol64(a_theta[3][3], 21);
        b[3][2] = rol64(a_theta[4][3],  8);

        b[4][2] = rol64(a_theta[0][4], 18);
        b[4][4] = rol64(a_theta[1][4],  2);
        b[4][1] = rol64(a_theta[2][4], 61);
        b[4][3] = rol64(a_theta[3][4], 56);
        b[4][0] = rol64(a_theta[4][4], 14);
    end

    // 3. Chi and Iota Steps
    always_comb begin
        for (int x = 0; x < 5; x++) begin
            for (int y = 0; y < 5; y++) begin
                // Chi non-linear mapping
                state_out[x][y] = b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y]);
            end
        end

        // Iota: inject round constant into lane (0,0)
        state_out[0][0] = state_out[0][0] ^ round_const;
    end

endmodule
