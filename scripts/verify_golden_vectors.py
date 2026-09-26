#!/usr/bin/env python3
"""
================================================================================
Company: Hardware Root-of-Trust (RoT) Silicon Lab
Engineer: Abhijit Karale
Script: verify_golden_vectors.py
Description: Standalone cryptographic reference script validating all
             test vectors for AES-256, GHASH GF(2^128), AES-GCM, and SHA3-256.
================================================================================
"""

import sys
import ctypes

def banner(title):
    print("\n" + "="*80)
    print(f" {title}")
    print("="*80)

# ------------------------------------------------------------------------------
# 1. NIST FIPS 197 S-BOX GENERATION & TEST
# ------------------------------------------------------------------------------
def sbox_gen():
    def gf_mul(a, b):
        p = 0
        for _ in range(8):
            if b & 1: p ^= a
            hi = a & 0x80
            a = (a << 1) & 0xff
            if hi: a ^= 0x1b
            b >>= 1
        return p

    def gf_inv(a):
        if a == 0: return 0
        res, base, exp = 1, a, 254
        while exp > 0:
            if exp & 1: res = gf_mul(res, base)
            base = gf_mul(base, base)
            exp >>= 1
        return res

    def rotl8(x, s):
        return ((x << s) | (x >> (8 - s))) & 0xff

    return [gf_inv(x) ^ rotl8(gf_inv(x), 1) ^ rotl8(gf_inv(x), 2) ^ rotl8(gf_inv(x), 3) ^ rotl8(gf_inv(x), 4) ^ 0x63 for x in range(256)]

sbox = sbox_gen()
inv_sbox = [0]*256
for i, s in enumerate(sbox): inv_sbox[s] = i

# ------------------------------------------------------------------------------
# 2. AES-256 ENCRYPTION
# ------------------------------------------------------------------------------
def sub_word(w): return [sbox[b] for b in w]
def rot_word(w): return w[1:] + w[:1]

rcon = [
    [0x00, 0x00, 0x00, 0x00],
    [0x01, 0x00, 0x00, 0x00],
    [0x02, 0x00, 0x00, 0x00],
    [0x04, 0x00, 0x00, 0x00],
    [0x08, 0x00, 0x00, 0x00],
    [0x10, 0x00, 0x00, 0x00],
    [0x20, 0x00, 0x00, 0x00],
    [0x40, 0x00, 0x00, 0x00]
]

def key_expansion_256(key_bytes):
    w = []
    for i in range(8):
        w.append(list(key_bytes[4*i:4*i+4]))
    for i in range(8, 60):
        temp = list(w[i-1])
        if i % 8 == 0:
            temp = [a ^ b for a, b in zip(sub_word(rot_word(temp)), rcon[i//8])]
        elif i % 8 == 4:
            temp = sub_word(temp)
        w.append([a ^ b for a, b in zip(w[i-8], temp)])
    round_keys = []
    for r in range(15):
        rk = []
        for c in range(4):
            rk.extend(w[4*r + c])
        round_keys.append(bytes(rk))
    return round_keys

def xtime(a):
    return (((a << 1) ^ 0x1b) & 0xff) if (a & 0x80) else ((a << 1) & 0xff)

def mix_single_column(c):
    return [
        xtime(c[0]) ^ xtime(c[1]) ^ c[1] ^ c[2] ^ c[3],
        c[0] ^ xtime(c[1]) ^ xtime(c[2]) ^ c[2] ^ c[3],
        c[0] ^ c[1] ^ xtime(c[2]) ^ xtime(c[3]) ^ c[3],
        xtime(c[0]) ^ c[0] ^ c[1] ^ c[2] ^ xtime(c[3])
    ]

def aes_round(state, rk):
    sb = [sbox[b] for b in state]
    s = [0]*16
    s[0]  = sb[0];  s[4]  = sb[4];  s[8]  = sb[8];  s[12] = sb[12]
    s[1]  = sb[5];  s[5]  = sb[9];  s[9]  = sb[13]; s[13] = sb[1]
    s[2]  = sb[10]; s[6]  = sb[14]; s[10] = sb[2];  s[14] = sb[6]
    s[3]  = sb[15]; s[7]  = sb[3];  s[11] = sb[7];  s[15] = sb[11]
    mc = [0]*16
    for c in range(4):
        col = mix_single_column([s[4*c], s[4*c+1], s[4*c+2], s[4*c+3]])
        mc[4*c] = col[0]; mc[4*c+1] = col[1]; mc[4*c+2] = col[2]; mc[4*c+3] = col[3]
    return [b ^ k for b, k in zip(mc, rk)]

def aes_last_round(state, rk):
    sb = [sbox[b] for b in state]
    s = [0]*16
    s[0]  = sb[0];  s[4]  = sb[4];  s[8]  = sb[8];  s[12] = sb[12]
    s[1]  = sb[5];  s[5]  = sb[9];  s[9]  = sb[13]; s[13] = sb[1]
    s[2]  = sb[10]; s[6]  = sb[14]; s[10] = sb[2];  s[14] = sb[6]
    s[3]  = sb[15]; s[7]  = sb[3];  s[11] = sb[7];  s[15] = sb[11]
    return [b ^ k for b, k in zip(s, rk)]

def aes_encrypt_block(pt, rks):
    state = [p ^ k for p, k in zip(pt, rks[0])]
    for r in range(1, 14):
        state = aes_round(state, rks[r])
    state = aes_last_round(state, rks[14])
    return bytes(state)

# ------------------------------------------------------------------------------
# 3. GHASH GF(2^128) MULTIPLICATION
# ------------------------------------------------------------------------------
def bit_rev128(n):
    return int(f'{n:0128b}'[::-1], 2)

def gf_mul(X, Y):
    # Pure bit-reversed hardware polynomial multiply + 2-step modular reduction
    a = bit_rev128(X)
    b = bit_rev128(Y)
    prod = 0
    for i in range(128):
        if (b >> i) & 1:
            prod ^= (a << i)
    upper = prod >> 128
    lower = prod & ((1 << 128) - 1)
    rem1 = lower ^ (upper << 7) ^ (upper << 2) ^ (upper << 1) ^ upper
    upper2 = rem1 >> 128
    rem2 = (rem1 & ((1 << 128) - 1)) ^ (upper2 << 7) ^ (upper2 << 2) ^ (upper2 << 1) ^ upper2
    return bit_rev128(rem2)

def ghash(H, data_bytes):
    assert len(data_bytes) % 16 == 0
    Y = 0
    for i in range(0, len(data_bytes), 16):
        block = int.from_bytes(data_bytes[i:i+16], 'big')
        Y = gf_mul(Y ^ block, H)
    return Y

# ------------------------------------------------------------------------------
# 4. AES-GCM FULL AUTHENTICATED ENCRYPTION
# ------------------------------------------------------------------------------
def pad16(b):
    rem = len(b) % 16
    return b if rem == 0 else b + bytes(16 - rem)

def aes_gcm_encrypt(key_bytes, iv_bytes, pt_bytes, aad_bytes):
    rks = key_expansion_256(key_bytes)
    # H = AES_K(0^128)
    H_bytes = aes_encrypt_block(bytes(16), rks)
    H = int.from_bytes(H_bytes, 'big')

    # J0 = IV || 0^31 || 1
    J0 = iv_bytes + bytes([0, 0, 0, 1])
    S0_bytes = aes_encrypt_block(J0, rks)
    S0 = int.from_bytes(S0_bytes, 'big')

    # CTR Keystream
    ct = bytearray()
    ctr = int.from_bytes(J0, 'big')
    for i in range(0, len(pt_bytes), 16):
        ctr = (ctr & ~0xffffffff) | (((ctr & 0xffffffff) + 1) & 0xffffffff)
        ks = aes_encrypt_block(ctr.to_bytes(16, 'big'), rks)
        chunk = pt_bytes[i:i+16]
        ct.extend(bytes(p ^ k for p, k in zip(chunk, ks[:len(chunk)])))

    # GHASH over pad(AAD) || pad(CT) || len(AAD)_64 || len(CT)_64
    ghash_in = pad16(aad_bytes) + pad16(bytes(ct)) + \
               (len(aad_bytes)*8).to_bytes(8, 'big') + \
               (len(pt_bytes)*8).to_bytes(8, 'big')

    S = ghash(H, ghash_in)
    tag = S ^ S0
    return bytes(ct), tag.to_bytes(16, 'big')

# ------------------------------------------------------------------------------
# 5. KECCAK-F[1600] AND SHA3-256
# ------------------------------------------------------------------------------
RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
]
R = [
    [ 0, 36,  3, 41, 18],
    [ 1, 44, 10, 45,  2],
    [62,  6, 43, 15, 61],
    [28, 55, 25, 21, 56],
    [27, 20, 39,  8, 14]
]
def rol64(x, s): return ((x << s) | (x >> (64 - s))) & 0xffffffffffffffff
def keccak_round(A, ir):
    C = [A[x][0] ^ A[x][1] ^ A[x][2] ^ A[x][3] ^ A[x][4] for x in range(5)]
    D = [C[(x+4)%5] ^ rol64(C[(x+1)%5], 1) for x in range(5)]
    A_prime = [[A[x][y] ^ D[x] for y in range(5)] for x in range(5)]
    B = [[0]*5 for _ in range(5)]
    for x in range(5):
        for y in range(5):
            B[y][(2*x + 3*y)%5] = rol64(A_prime[x][y], R[x][y])
    A_out = [[B[x][y] ^ ((~B[(x+1)%5][y]) & B[(x+2)%5][y]) for y in range(5)] for x in range(5)]
    A_out[0][0] ^= RC[ir]
    return A_out

def sha3_256(msg):
    rate_bytes = 136
    pad = bytearray(msg)
    pad.append(0x06)
    while len(pad) % rate_bytes != (rate_bytes - 1): pad.append(0x00)
    pad.append(0x80)
    state = [[0]*5 for _ in range(5)]
    for block_idx in range(0, len(pad), rate_bytes):
        block = pad[block_idx:block_idx+rate_bytes]
        for i in range(17):
            lane = int.from_bytes(block[8*i:8*i+8], 'little')
            state[i%5][i//5] ^= lane
        for ir in range(24): state = keccak_round(state, ir)
    digest = bytearray()
    for i in range(4):
        digest.extend(state[i%5][i//5].to_bytes(8, 'little'))
    return digest.hex()

def main():
    banner("1. NIST FIPS 197 APPENDIX C.3 AES-256 ECB VERIFICATION")
    k_c3 = bytes.fromhex('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f')
    p_c3 = bytes.fromhex('00112233445566778899aabbccddeeff')
    expected_c3 = '8ea2b7ca516745bfeafc49904b496089'
    rks = key_expansion_256(k_c3)
    ct_c3 = aes_encrypt_block(p_c3, rks).hex()
    print(f"Key:         {k_c3.hex()}")
    print(f"Plaintext:   {p_c3.hex()}")
    print(f"Ciphertext:  {ct_c3}")
    print(f"Expected:    {expected_c3}")
    assert ct_c3 == expected_c3, "FIPS 197 C.3 mismatch!"
    print("[PASS] FIPS 197 C.3 Verified 100% Correct.")

    banner("2. NIST SP 800-38D AES-256-GCM TEST CASES 13, 14, 16")
    # Case 13
    ct13, tag13 = aes_gcm_encrypt(bytes(32), bytes(12), b'', b'')
    print("Case 13 (Empty PT/AAD):")
    print(f"  Tag:      {tag13.hex()}")
    print(f"  Expected: 530f8afbc74536b9a963b4f1c4cb738b")
    assert tag13.hex() == '530f8afbc74536b9a963b4f1c4cb738b'
    print("  [PASS] Case 13 Matched.")

    # Case 14
    ct14, tag14 = aes_gcm_encrypt(bytes(32), bytes(12), bytes(16), b'')
    print("\nCase 14 (16 Zero Bytes PT):")
    print(f"  CT:       {ct14.hex()}")
    print(f"  Tag:      {tag14.hex()}")
    print(f"  Expected: cea7403d4d606b6e074ec5d3baf39d18 / d0d1c8a799996bf0265b98b5d48ab919")
    assert ct14.hex() == 'cea7403d4d606b6e074ec5d3baf39d18'
    assert tag14.hex() == 'd0d1c8a799996bf0265b98b5d48ab919'
    print("  [PASS] Case 14 Matched.")

    # Case 16
    k16 = bytes.fromhex('feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308')
    iv16 = bytes.fromhex('cafebabefacedbaddecaf888')
    aad16 = bytes.fromhex('feedfacedeadbeeffeedfacedeadbeefabaddad2')
    pt16 = bytes.fromhex('d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39')
    ct16, tag16 = aes_gcm_encrypt(k16, iv16, pt16, aad16)
    print("\nCase 16 (60-byte PT, 20-byte AAD):")
    print(f"  CT:       {ct16.hex()[:32]}... ({len(ct16)} bytes)")
    print(f"  Tag:      {tag16.hex()}")
    print(f"  Expected: 76fc6ece0f4e1768cddf8853bb2d551b")
    assert tag16.hex() == '76fc6ece0f4e1768cddf8853bb2d551b'
    print("  [PASS] Case 16 Matched.")

    banner("3. FIPS 202 SHA3-256 STANDARD TEST VECTORS")
    d_empty = sha3_256(b'')
    print(f"SHA3-256(''):    {d_empty}")
    assert d_empty == 'a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a'
    print("  [PASS] SHA3-256('') Matched.")

    d_abc = sha3_256(b'abc')
    print(f"SHA3-256('abc'): {d_abc}")
    assert d_abc == '3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532'
    print("  [PASS] SHA3-256('abc') Matched.")

    banner("ALL CRYPTOGRAPHIC REFERENCE VECTORS VERIFIED 100% BIT-FOR-BIT!")

if __name__ == '__main__':
    main()
