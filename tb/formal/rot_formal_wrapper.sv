`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: rot_formal_wrapper
// Description: Formal verification testbench wrapper binding SVA properties
//              to rot_top, aes_core, gf_mul128, and keccak_f1600.
//////////////////////////////////////////////////////////////////////////////////

module rot_formal_wrapper (
    input logic        pclk,
    input logic        presetn,
    input logic        rot_zeroize_pin,
    input logic [11:0] paddr,
    input logic        psel,
    input logic        penable,
    input logic        pwrite,
    input logic [31:0] pwdata,
    input logic [3:0]  pstrb
);

    wire        rot_alarm_out;
    wire        rot_irq_out;
    wire        pready;
    wire [31:0] prdata;
    wire        pslverr;

    // Instantiate DUT (Device Under Verification)
    rot_top u_rot_top (
        .pclk            (pclk),
        .presetn         (presetn),
        .rot_zeroize_pin (rot_zeroize_pin),
        .rot_alarm_out   (rot_alarm_out),
        .rot_irq_out     (rot_irq_out),
        .paddr           (paddr),
        .psel            (psel),
        .penable         (penable),
        .pwrite          (pwrite),
        .pwdata          (pwdata),
        .pstrb           (pstrb),
        .pready          (pready),
        .prdata          (prdata),
        .pslverr         (pslverr)
    );

    // Bind SVA Properties to DUT Internal Signals
    rot_formal_props u_formal_props (
        .pclk            (pclk),
        .presetn         (presetn),
        .rot_zeroize_pin (rot_zeroize_pin),
        .rot_alarm_out   (rot_alarm_out),
        .rot_irq_out     (rot_irq_out),
        .paddr           (paddr),
        .psel            (psel),
        .penable         (penable),
        .pwrite          (pwrite),
        .pwdata          (pwdata),
        .pstrb           (pstrb),
        .pready          (pready),
        .prdata          (prdata),
        .pslverr         (pslverr),

        .global_zeroize  (u_rot_top.global_zeroize),
        .key_locked_reg  (u_rot_top.key_locked_reg),
        .key_word_0      (u_rot_top.key_words[0]),
        .key_word_1      (u_rot_top.key_words[1]),
        .key_word_2      (u_rot_top.key_words[2]),
        .key_word_3      (u_rot_top.key_words[3]),
        .key_word_4      (u_rot_top.key_words[4]),
        .key_word_5      (u_rot_top.key_words[5]),
        .key_word_6      (u_rot_top.key_words[6]),
        .key_word_7      (u_rot_top.key_words[7]),

        .aes_data_valid  (u_rot_top.u_aes_core_inst.data_valid),
        .aes_out_valid   (u_rot_top.u_aes_core_inst.data_out_valid),
        .gf_mul_start    (u_rot_top.u_gcm_inst.u_ghash_core.u_gf_mul.start),
        .gf_mul_done     (u_rot_top.u_gcm_inst.u_ghash_core.u_gf_mul.done),
        .keccak_start    (u_rot_top.u_sha3_inst.u_keccak.start),
        .keccak_done     (u_rot_top.u_sha3_inst.u_keccak.done)
    );

    // Formal Environment Assumptions (APB4 Bus Master Conformance)
    always_comb begin
        if (psel && !penable) begin
            // Setup phase
        end
    end

    // Restrict reset sequence
    initial assume (!presetn);
    always @(posedge pclk) begin
        if ($past(!presetn)) assume (presetn);
    end

endmodule
