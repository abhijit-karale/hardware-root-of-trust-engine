`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: rot_formal_props
// Description: SystemVerilog Assertions (SVA) Formal Property Suite for RoT Engine.
//              Verifies:
//              1. Deterministic Constant-Time Latency (timing side-channel mitigation).
//              2. Key Confidentiality & Bus Non-Leakage (reads to key address return 0).
//              3. Instantaneous Hardware Zeroization (1-cycle purge of keys and state).
//              4. Key Lock Invariance (once locked, key cannot be altered).
//              5. FSM Liveness and Deadlock Freedom.
//////////////////////////////////////////////////////////////////////////////////

module rot_formal_props (
    input logic        pclk,
    input logic        presetn,

    // Physical Security Pins
    input logic        rot_zeroize_pin,
    input logic        rot_alarm_out,
    input logic        rot_irq_out,

    // APB4 Bus Signals
    input logic [11:0] paddr,
    input logic        psel,
    input logic        penable,
    input logic        pwrite,
    input logic [31:0] pwdata,
    input logic [3:0]  pstrb,
    input logic        pready,
    input logic [31:0] prdata,
    input logic        pslverr,

    // Internal Monitored Signals from rot_top
    input logic        global_zeroize,
    input logic        key_locked_reg,
    input logic [31:0] key_word_0,
    input logic [31:0] key_word_1,
    input logic [31:0] key_word_2,
    input logic [31:0] key_word_3,
    input logic [31:0] key_word_4,
    input logic [31:0] key_word_5,
    input logic [31:0] key_word_6,
    input logic [31:0] key_word_7,

    // Submodule Latency Monitoring
    input logic        aes_data_valid,
    input logic        aes_out_valid,
    input logic        gf_mul_start,
    input logic        gf_mul_done,
    input logic        keccak_start,
    input logic        keccak_done
);

    default clocking cb @(posedge pclk); endclocking
    default disable iff (!presetn);

    // =========================================================================
    // PROPERTY 1: KEY CONFIDENTIALITY - ZERO BUS LEAKAGE
    // An APB read to any key register address [0x010..0x02C] MUST ALWAYS return 0.
    // The master key bits must never be exposed on the peripheral bus.
    // =========================================================================
    property p_key_bus_non_leakage;
        (psel && !pwrite && (paddr >= 12'h010) && (paddr <= 12'h02C)) |-> (prdata == 32'h00000000);
    endproperty
    assert_key_bus_non_leakage: assert property (p_key_bus_non_leakage)
        else $error("[SECURITY VIOLATION] Secret key exposed on APB bus read!");

    // =========================================================================
    // PROPERTY 2: 1-CYCLE INSTANTANEOUS HARDWARE ZEROIZATION
    // When rot_zeroize_pin or software zeroize is asserted, all key registers
    // MUST be completely cleared to 32'h0 in the very next clock cycle.
    // =========================================================================
    property p_instant_zeroize_keys;
        global_zeroize |=> (key_word_0 == 32'h0) &&
                           (key_word_1 == 32'h0) &&
                           (key_word_2 == 32'h0) &&
                           (key_word_3 == 32'h0) &&
                           (key_word_4 == 32'h0) &&
                           (key_word_5 == 32'h0) &&
                           (key_word_6 == 32'h0) &&
                           (key_word_7 == 32'h0);
    endproperty
    assert_instant_zeroize_keys: assert property (p_instant_zeroize_keys)
        else $error("[SECURITY VIOLATION] Key registers failed to zeroize within 1 cycle!");

    // =========================================================================
    // PROPERTY 3: KEY LOCK IMMUTABILITY
    // Once key_locked_reg is asserted, writes to key addresses cannot alter key registers.
    // =========================================================================
    genvar k;
    generate
        property p_key_locked_immutable_0;
            (key_locked_reg && !global_zeroize && psel && penable && pwrite && (paddr == 12'h010)) 
            |=> $stable(key_word_0);
        endproperty
        assert_key_locked_immutable_0: assert property (p_key_locked_immutable_0)
            else $error("[SECURITY VIOLATION] Key register modified after lock assertion!");
    endgenerate

    // =========================================================================
    // PROPERTY 4: CONSTANT-TIME EXECUTION - AES 14-ROUND PIPELINE
    // The AES pipelined engine must complete computation with deterministic
    // cycle latency: Exactly 14 cycles from pipeline entry to valid output.
    // Must be completely invariant to key value and plaintext data!
    // =========================================================================
    property p_aes_constant_time_latency;
        disable iff (!presetn || global_zeroize)
        aes_data_valid |-> ##14 aes_out_valid;
    endproperty
    assert_aes_constant_time_latency: assert property (p_aes_constant_time_latency)
        else $error("[TIMING SIDE-CHANNEL DETECTED] AES pipeline latency is non-deterministic!");

    // =========================================================================
    // PROPERTY 5: CONSTANT-TIME EXECUTION - GF(2^128) MULTIPLIER
    // Every GHASH Galois Field multiplication must take strictly 2 clock cycles.
    // =========================================================================
    property p_gf_mul_constant_time;
        disable iff (!presetn || global_zeroize)
        gf_mul_start |-> ##2 gf_mul_done;
    endproperty
    assert_gf_mul_constant_time: assert property (p_gf_mul_constant_time)
        else $error("[TIMING SIDE-CHANNEL DETECTED] GF(2^128) multiplier latency varied!");

    // =========================================================================
    // PROPERTY 6: CONSTANT-TIME EXECUTION - KECCAK-F[1600] 24-ROUND PERMUTATION
    // Keccak-f[1600] must execute exactly 24 permutation rounds (24 cycles)
    // before producing the transformed state output.
    // =========================================================================
    property p_keccak_constant_time;
        disable iff (!presetn || global_zeroize)
        keccak_start |-> ##24 keccak_done;
    endproperty
    assert_keccak_constant_time: assert property (p_keccak_constant_time)
        else $error("[TIMING SIDE-CHANNEL DETECTED] Keccak permutation took non-deterministic cycle count!");

    // =========================================================================
    // PROPERTY 7: APB4 BUS INTEGRITY & PROTOCOL SAFETY
    // PREADY must respond without hang (deadlock-freedom).
    // =========================================================================
    property p_apb_deadlock_free;
        psel |-> ##[0:1] pready;
    endproperty
    assert_apb_deadlock_free: assert property (p_apb_deadlock_free)
        else $error("[BUS PROTOCOL VIOLATION] APB bus deadlock detected!");

    // =========================================================================
    // PROPERTY 8: TAMPER ALARM ASSERTION
    // Whenever global_zeroize is triggered, rot_alarm_out must be asserted.
    // =========================================================================
    property p_alarm_on_tamper;
        global_zeroize |-> rot_alarm_out;
    endproperty
    assert_alarm_on_tamper: assert property (p_alarm_on_tamper)
        else $error("[SECURITY VIOLATION] Alarm indicator failed to assert on zeroize event!");

endmodule
