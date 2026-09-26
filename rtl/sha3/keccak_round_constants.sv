`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: keccak_round_constants
// Description: Round constants RC[0..23] for Keccak-f[1600] per FIPS 202.
//////////////////////////////////////////////////////////////////////////////////

module keccak_round_constants (
    input  logic [4:0]  round_idx, // 0 to 23
    output logic [63:0] round_const
);

    always_comb begin
        case (round_idx)
            5'd0:  round_const = 64'h0000000000000001;
            5'd1:  round_const = 64'h0000000000008082;
            5'd2:  round_const = 64'h800000000000808a;
            5'd3:  round_const = 64'h8000000080008000;
            5'd4:  round_const = 64'h000000000000808b;
            5'd5:  round_const = 64'h0000000080000001;
            5'd6:  round_const = 64'h8000000080008081;
            5'd7:  round_const = 64'h8000000000008009;
            5'd8:  round_const = 64'h000000000000008a;
            5'd9:  round_const = 64'h0000000000000088;
            5'd10: round_const = 64'h0000000080008009;
            5'd11: round_const = 64'h000000008000000a;
            5'd12: round_const = 64'h000000008000808b;
            5'd13: round_const = 64'h800000000000008b;
            5'd14: round_const = 64'h8000000000008089;
            5'd15: round_const = 64'h8000000000008003;
            5'd16: round_const = 64'h8000000000008002;
            5'd17: round_const = 64'h8000000000000080;
            5'd18: round_const = 64'h000000000000800a;
            5'd19: round_const = 64'h800000008000000a;
            5'd20: round_const = 64'h8000000080008081;
            5'd21: round_const = 64'h8000000000008080;
            5'd22: round_const = 64'h0000000080000001;
            5'd23: round_const = 64'h8000000080008008;
            default: round_const = 64'h0000000000000000;
        endcase
    end

endmodule
