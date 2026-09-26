`ifndef NIST_VECTORS_SVH
`define NIST_VECTORS_SVH

// =============================================================================
// NIST FIPS 197, NIST SP 800-38D, and FIPS 202 Official Test Vectors
// =============================================================================

// FIPS 197 Appendix C.3: AES-256 ECB
localparam [255:0] FIPS197_KEY_C3 = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
localparam [127:0] FIPS197_PT_C3  = 128'h00112233445566778899aabbccddeeff;
localparam [127:0] FIPS197_CT_C3  = 128'h8ea2b7ca516745bfeafc49904b496089;

// NIST SP 800-38D Test Case 13 (AES-256 GCM)
// Key: 256'h0, IV: 96'h0, PT: empty, AAD: empty
localparam [255:0] NIST_GCM_CASE13_KEY = 256'h0;
localparam [95:0]  NIST_GCM_CASE13_IV  = 96'h0;
localparam [127:0] NIST_GCM_CASE13_TAG = 128'h530f8afbc74536b9a963b4f1c4cb738b;

// NIST SP 800-38D Test Case 14 (AES-256 GCM)
// Key: 256'h0, IV: 96'h0, PT: 1 block of 16 zeros
localparam [255:0] NIST_GCM_CASE14_KEY = 256'h0;
localparam [95:0]  NIST_GCM_CASE14_IV  = 96'h0;
localparam [127:0] NIST_GCM_CASE14_PT  = 128'h0;
localparam [127:0] NIST_GCM_CASE14_CT  = 128'hcea7403d4d606b6e074ec5d3baf39d18;
localparam [127:0] NIST_GCM_CASE14_TAG = 128'hd0d1c8a799996bf0265b98b5d48ab919;

// NIST SP 800-38D Test Case 16 (AES-256 GCM with AAD)
localparam [255:0] NIST_GCM_CASE16_KEY = 256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308;
localparam [95:0]  NIST_GCM_CASE16_IV  = 96'hcafebabefacedbaddecaf888;
localparam [127:0] NIST_GCM_CASE16_TAG = 128'h76fc6ece0f4e1768cddf8853bb2d551b;

// FIPS 202 SHA3-256 Test Vectors
// Empty Message: SHA3-256("")
localparam [255:0] FIPS202_SHA3_EMPTY = 256'ha7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a;
// "abc" Message: SHA3-256("abc")
localparam [255:0] FIPS202_SHA3_ABC   = 256'h3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532;

`endif
