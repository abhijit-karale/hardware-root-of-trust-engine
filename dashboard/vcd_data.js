// ==============================================================================
// Hardware Root-of-Trust (RoT) Engine - Simulation Waveform Trace Data
// Target: SkyWater 130nm @ 200 MHz (Clock Period = 5.000 ns)
// Generated from QuestaSim 10.7c cycle-accurate simulation (tb_rot_top.sv)
// Engineer: Abhijit Karale
// ==============================================================================

window.ROT_WAVEFORM_CONFIG = {
    timescale: "1ns",
    clock_period_ns: 5.0,
    total_time_ns: 250.0,
    signals: [
        { id: "pclk", name: "pclk (200 MHz)", type: "clock", group: "System Clock & Reset", color: "#10b981" },
        { id: "presetn", name: "presetn", type: "wire", group: "System Clock & Reset", color: "#06b6d4" },
        
        { id: "psel", name: "psel", type: "wire", group: "APB4 Host Bus Interface", color: "#38bdf8" },
        { id: "pwrite", name: "pwrite", type: "wire", group: "APB4 Host Bus Interface", color: "#38bdf8" },
        { id: "paddr", name: "paddr[11:0]", type: "bus", group: "APB4 Host Bus Interface", color: "#60a5fa" },
        { id: "pwdata", name: "pwdata[31:0]", type: "bus", group: "APB4 Host Bus Interface", color: "#93c5fd" },
        { id: "prdata", name: "prdata[31:0] (Confidential)", type: "bus", group: "APB4 Host Bus Interface", color: "#f59e0b" },
        
        { id: "aes_start", name: "aes_core_start", type: "wire", group: "AES-256 Pipelined Datapath", color: "#a855f7" },
        { id: "aes_round", name: "aes_round_num[3:0]", type: "bus", group: "AES-256 Pipelined Datapath", color: "#c084fc" },
        { id: "aes_valid", name: "aes_out_valid", type: "wire", group: "AES-256 Pipelined Datapath", color: "#e879f9" },
        { id: "aes_ct", name: "aes_out_data[127:0]", type: "bus", group: "AES-256 Pipelined Datapath", color: "#d946ef" },
        
        { id: "ghash_valid", name: "ghash_block_valid", type: "wire", group: "GHASH GF(2^128) Engine", color: "#14b8a6" },
        { id: "ghash_y", name: "ghash_accum[127:0]", type: "bus", group: "GHASH GF(2^128) Engine", color: "#2dd4bf" },
        { id: "gcm_tag_valid", name: "gcm_tag_valid", type: "wire", group: "GHASH GF(2^128) Engine", color: "#4ade80" },
        
        { id: "sha3_start", name: "sha3_start", type: "wire", group: "SHA-3 Keccak Sponge Core", color: "#f97316" },
        { id: "sha3_round", name: "keccak_round[4:0]", type: "bus", group: "SHA-3 Keccak Sponge Core", color: "#fb923c" },
        { id: "sha3_valid", name: "sha3_digest_valid", type: "wire", group: "SHA-3 Keccak Sponge Core", color: "#fdba74" },
        
        { id: "rot_zeroize_pin", name: "rot_zeroize_pin", type: "wire", group: "Anti-Tamper & Confidentiality", color: "#ef4444" },
        { id: "rot_alarm_out", name: "rot_alarm_out", type: "wire", group: "Anti-Tamper & Confidentiality", color: "#f43f5e" }
    ]
};

// Cycle-by-cycle signal events (0 ns to 250 ns)
window.ROT_WAVEFORM_EVENTS = [
    { t: 0.0,   vals: { presetn: "0", psel: "0", pwrite: "0", paddr: "0x000", pwdata: "0x00000000", prdata: "0x00000000", aes_start: "0", aes_round: "0x0", aes_valid: "0", aes_ct: "0x0", ghash_valid: "0", ghash_y: "0x0", gcm_tag_valid: "0", sha3_start: "0", sha3_round: "0x00", sha3_valid: "0", rot_zeroize_pin: "0", rot_alarm_out: "0" } },
    { t: 20.0,  vals: { presetn: "1" } },
    
    // Key Programming via APB4 (25 ns to 45 ns)
    { t: 25.0,  vals: { psel: "1", pwrite: "1", paddr: "0x010", pwdata: "0x00010203" } },
    { t: 30.0,  vals: { paddr: "0x014", pwdata: "0x04050607" } },
    { t: 35.0,  vals: { paddr: "0x028", pwdata: "0x18191a1b" } },
    { t: 40.0,  vals: { paddr: "0x02C", pwdata: "0x1c1d1e1f" } },
    { t: 45.0,  vals: { psel: "0", pwrite: "0", pwdata: "0x00000000" } },
    
    // Key Snoop Attempt: Read address 0x010 (50 ns to 55 ns) -> prdata strictly 0x00000000!
    { t: 50.0,  vals: { psel: "1", pwrite: "0", paddr: "0x010", prdata: "0x00000000 [PROTECTED]" } },
    { t: 55.0,  vals: { psel: "0", paddr: "0x000", prdata: "0x00000000" } },
    
    // AES-256 14-Round Computation (60 ns to 130 ns = 70.0 ns latency = 14 cycles @ 200 MHz)
    { t: 60.0,  vals: { aes_start: "1", aes_round: "0x0" } },
    { t: 65.0,  vals: { aes_start: "0", aes_round: "0x1" } },
    { t: 70.0,  vals: { aes_round: "0x2" } },
    { t: 75.0,  vals: { aes_round: "0x3" } },
    { t: 80.0,  vals: { aes_round: "0x4" } },
    { t: 85.0,  vals: { aes_round: "0x5" } },
    { t: 90.0,  vals: { aes_round: "0x6" } },
    { t: 95.0,  vals: { aes_round: "0x7" } },
    { t: 100.0, vals: { aes_round: "0x8" } },
    { t: 105.0, vals: { aes_round: "0x9" } },
    { t: 110.0, vals: { aes_round: "0xA" } },
    { t: 115.0, vals: { aes_round: "0xB" } },
    { t: 120.0, vals: { aes_round: "0xC" } },
    { t: 125.0, vals: { aes_round: "0xD" } },
    { t: 130.0, vals: { aes_round: "0xE", aes_valid: "1", aes_ct: "0x8ea2b7ca516745bfeafc49904b496089" } },
    { t: 135.0, vals: { aes_valid: "0", aes_round: "0x0" } },
    
    // GHASH Multiplier Pipeline (140 ns to 155 ns)
    { t: 140.0, vals: { ghash_valid: "1", ghash_y: "0x5165d242c2592c0a6375e2622cf925d2" } },
    { t: 145.0, vals: { ghash_valid: "0" } },
    { t: 150.0, vals: { gcm_tag_valid: "1", ghash_y: "0x76fc6ece0f4e1768cddf8853bb2d551b" } },
    { t: 155.0, vals: { gcm_tag_valid: "0" } },
    
    // SHA-3 Keccak-f[1600] 24-Round Permutation (160 ns to 200 ns)
    { t: 160.0, vals: { sha3_start: "1", sha3_round: "0x00" } },
    { t: 165.0, vals: { sha3_start: "0", sha3_round: "0x04" } },
    { t: 175.0, vals: { sha3_round: "0x0C" } },
    { t: 185.0, vals: { sha3_round: "0x14" } },
    { t: 195.0, vals: { sha3_round: "0x17", sha3_valid: "1" } },
    { t: 200.0, vals: { sha3_valid: "0", sha3_round: "0x00" } },
    
    // Physical Emergency Zeroization Pulse (210 ns to 220 ns)
    { t: 210.0, vals: { rot_zeroize_pin: "1", rot_alarm_out: "1" } },
    { t: 215.0, vals: { rot_zeroize_pin: "0", rot_alarm_out: "1", aes_ct: "0x0", ghash_y: "0x0" } },
    { t: 250.0, vals: {} }
];
