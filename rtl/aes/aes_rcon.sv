`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: aes_rcon
// Description: AES Round Constant (Rcon) lookup generator.
//              Provides the 32-bit round constant word {rc, 24'h000000}
//              used in the KeyExpansion step.
//////////////////////////////////////////////////////////////////////////////////

module aes_rcon (
    input  logic [3:0]  rcon_idx, // Index 1 to 10
    output logic [31:0] rcon_word
);

    always_comb begin
        case (rcon_idx)
            4'd1:  rcon_word = 32'h01000000;
            4'd2:  rcon_word = 32'h02000000;
            4'd3:  rcon_word = 32'h04000000;
            4'd4:  rcon_word = 32'h08000000;
            4'd5:  rcon_word = 32'h10000000;
            4'd6:  rcon_word = 32'h20000000;
            4'd7:  rcon_word = 32'h40000000;
            4'd8:  rcon_word = 32'h80000000;
            4'd9:  rcon_word = 32'h1b000000;
            4'd10: rcon_word = 32'h36000000;
            default: rcon_word = 32'h00000000;
        endcase
    end

endmodule
