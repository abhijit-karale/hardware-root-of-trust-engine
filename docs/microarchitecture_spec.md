# Hardware Root-of-Trust (RoT) Engine: Microarchitectural Specification
**Target Tech Node & Clock**: SkyWater 130nm @ 200 MHz (Clock Period $T = 5.000\text{ ns}$)  
**Candidate & Lead Architect**: Abhijit Karale  
**Standards**: NIST FIPS 197 (AES), NIST SP 800-38D (GCM), NIST FIPS 202 (SHA-3 / Keccak)  

---

## 1. System Overview & Architectural Philosophy
The Hardware Root-of-Trust (RoT) cryptographic coprocessor provides unified authenticated encryption, data confidentiality, message integrity, and platform attestation for secure embedded Systems-on-Chip (SoCs).

```
                      +-------------------------------------------------------------+
                      |           SoC Interconnect (32-bit APB4 Master)             |
                      +-------------------------------------------------------------+
                                       |                      ^
                         paddr, pwdata |                      | prdata, pready
                         psel, penable |                      | rot_irq_out
                                       v                      |
+---------------------+      +------------------------------------------------------+
| Physical Anti-Tamper|----->|         APB4 Register Interface & CSR Decode        |
| rot_zeroize_pin     |      +------------------------------------------------------+
+---------------------+            |                  |                  |
                                   | Key & Config     | Streaming Blocks | SHA-3 Words
                                   v                  v                  v
                      +------------------+  +-------------------+  +------------------+
                      | AES-256 Pipelined|  |  GHASH GF(2^128)  |  | Keccak-f[1600]   |
                      | Engine (14-Rnds) |  | Multiplier Core   |  | Permutation Core |
                      | ECB / CBC / CTR  |  | (NIST SP 800-38D) |  | SHA3-256/512     |
                      +------------------+  +-------------------+  +------------------+
                                   |                  |                  |
                                   +--------+---------+                  |
                                            |                            |
                                            v                            v
                                  +-------------------+        +-------------------+
                                  |  AES-GCM Top AEAD |        |  SHA-3 Attestation|
                                  | Keystream & Tag   |        |   256-bit Digest  |
                                  +-------------------+        +-------------------+
```

---

## 2. AES-256 Round Datapath Architecture
AES-256 processes 128-bit blocks through $N_r = 14$ rounds using an on-the-fly or registered round key schedule derived from a 256-bit master cipher key.

### 2.1 State Matrix Layout (Column-Major)
A 128-bit block $S = s_0 s_1 \dots s_{15}$ is mapped to a $4 \times 4$ matrix over $GF(2^8)$:

$$
\begin{bmatrix}
s_0 & s_4 & s_8 & s_{12} \\
s_1 & s_5 & s_9 & s_{13} \\
s_2 & s_6 & s_{10} & s_{14} \\
s_3 & s_7 & s_{11} & s_{15}
\end{bmatrix}
$$

### 2.2 AES Round Datapath Schematic (ASCII)
```
          128-bit Input State (Stage r-1)
                     |
                     v
     +-------------------------------+
     |           SubBytes            |  <-- 16 Parallel S-Boxes (GF(2^8) Inversion + Affine)
     |  [SB0] [SB1] ... [SB14] [SB15]|      Propagation Delay: ~1.20 ns (Sky130)
     +-------------------------------+
                     |
                     v
     +-------------------------------+
     |           ShiftRows           |  <-- Pure Wire Permutation (Zero Gate Delay)
     | Row 0: <<< 0  |  Row 1: <<< 1 |      Row 1: [s1, s5, s9, s13] -> [s5, s9, s13, s1]
     | Row 2: <<< 2  |  Row 3: <<< 3 |      Row 2: [s2, s6, s10, s14]-> [s10, s14, s2, s6]
     +-------------------------------+      Row 3: [s3, s7, s11, s15]-> [s15, s3, s7, s11]
                     |
                     v
            /-----------------\
           /   is_final_round? \--------+
          /                     \       |
         |         NO            |      |
          \                     /       |
           \-------------------/        |
                     |                  |
                     v                  | (Bypass for Round 14)
     +-------------------------------+  |
     |          MixColumns           |  |
     | 4x Column Polynomial Matrix   |  |
     | [2 3 1 1] x [s0 s1 s2 s3]^T   |  |  <-- xtime() logic & 4-way XOR trees
     | Gate Delay: ~0.80 ns (Sky130) |  |
     +-------------------------------+  |
                     |                  |
                     +<-----------------+
                     |
                     v
     +-------------------------------+
     |          AddRoundKey          |  <-- 128-bit Bitwise XOR with Round Key K_r
     |      mc_out ^ round_key[r]    |      Gate Delay: ~0.18 ns (Sky130)
     +-------------------------------+
                     |
                     v
      +-----------------------------+
      |  Pipeline Stage Register r  |  <-- Clocked by posedge pclk
      | (128-bit D-type Flip-Flops) |      Setup Time: 0.12 ns, Hold Time: 0.05 ns
      +-----------------------------+
```

Total critical path through one round: $\approx 1.20 + 0.00 + 0.80 + 0.18 + 0.12 = 2.30\text{ ns}$.  
Clock Period at 200 MHz: $5.000\text{ ns}$ $\implies$ **Timing Margin (Slack) $> +2.50\text{ ns}$!**

---

## 3. AES-256 Key Schedule Pipeline Architecture
The 256-bit key schedule expands the initial 8 words $W_0 \dots W_7$ into 60 words (15 round keys $K_0 \dots K_{14}$, each 128 bits):

```
       Master Key [255:0] (W0..W7)
                 |
                 +----------------------------------------------------> K0 = {W0, W1, W2, W3}
                 |                                                      K1 = {W4, W5, W6, W7}
                 v
   +----------------------------+
   | Step 1: Words W8..W15      |
   | W8  = W0 ^ SubWord(Rot(W7))| <--- Rcon[1] = 32'h01000000
   | W12 = W4 ^ SubWord(W11)    |
   +----------------------------+ ------------------------------------> K2 = {W8,  W9,  W10, W11}
                 |                                                      K3 = {W12, W13, W14, W15}
                 v
   +----------------------------+
   | Step 2: Words W16..W23     | <--- Rcon[2] = 32'h02000000
   +----------------------------+ ------------------------------------> K4 = {W16, W17, W18, W19}
                 |                                                      K5 = {W20, W21, W22, W23}
                 ~
   +----------------------------+
   | Step 7: Words W56..W59     | <--- Rcon[7] = 32'h40000000
   | W56 = W48 ^ SubWord(Rot)   |
   +----------------------------+ ------------------------------------> K14 = {W56, W57, W58, W59}
```

- **Expansion Latency**: Exactly 7 clock cycles upon key commit.
- **Key Register Lock**: Setting bit 16 of `CONTROL` permanently freezes `key_words` against subsequent writes.
- **Key Bus Masking**: APB reads to key registers `0x010..0x02C` return `32'h00000000` under all conditions.

---

## 4. GHASH Galois Field ($GF(2^{128})$) Multiplier Architecture
GHASH performs polynomial multiplication in the finite field $GF(2^{128})$ modulo the irreducible polynomial:
$$f(x) = x^{128} + x^7 + x^2 + x + 1$$

### 4.1 Endianness Mapping & Bit-Reversal
NIST SP 800-38D represents field elements with bit 0 as the coefficient of $x^0$. In hardware vector indexing `[127:0]`, bit 127 is the most significant bit. By applying bit-reversal $A_{\text{rev}}[i] = A[127-i]$, standard carry-less polynomial multiplication over $GF(2)$ can be directly utilized.

### 4.2 Multiplier Datapath Schematic (ASCII)
```
          NIST 128-bit Op A                       NIST 128-bit Op B (H)
                  |                                         |
                  v                                         v
         +-----------------+                       +-----------------+
         |   bit_rev128    |                       |   bit_rev128    |
         +-----------------+                       +-----------------+
                  | a_rev                                   | b_rev
                  +--------------------+--------------------+
                                       |
                                       v
                     +-----------------------------------+
                     |   Carry-Less Poly Multiplier      |  Stage 1:
                     |   GF(2) Product: 255-bit poly     |  Parallel AND/XOR Matrix
                     |   prod = XOR(b_rev[i] ? a<<i : 0) |
                     +-----------------------------------+
                                       |
                                       v
                     +-----------------------------------+
                     |     Pipeline Register Stage 1     |  Cycle 1 Boundary
                     |           poly_prod_reg           |
                     +-----------------------------------+
                                       |
                                       v
         +---------------------------------------------------------------+
         |             Closed-Form 2-Step Modular Reduction              |  Stage 2:
         |  Step 1: rem1 = lower ^ (upper<<7) ^ (upper<<2) ^ (upper<<1)  |  Degree reduction
         |                 ^ upper                                       |  from 254 down
         |  Step 2: rem2 = rem1[127:0] ^ (upper2<<7) ^ (upper2<<2)      |  to < 128 in
         |                 ^ (upper2<<1) ^ upper2                        |  only 2 XOR folds!
         +---------------------------------------------------------------+
                                       |
                                       v
                              +-----------------+
                              |   bit_rev128    |
                              +-----------------+
                                       |
                                       v
                     +-----------------------------------+
                     |     Pipeline Register Stage 2     |  Cycle 2 Boundary
                     |            prod_out               |  Deterministic Done
                     +-----------------------------------+
```

- **Execution Latency**: Strictly **2 clock cycles** per multiplication.
- **Constant-Time Guarantee**: Zero data-dependent branching; bit patterns execute identical combinational XOR trees.

---

## 5. Keccak-f[1600] / SHA-3 Sponge Function Architecture
Keccak-f[1600] operates on a state array of $5 \times 5 \times 64 = 1600$ bits:

### 5.1 State Array Mapping
```
                   x = 0       x = 1       x = 2       x = 3       x = 4
               +-----------+-----------+-----------+-----------+-----------+
      y = 0    | Lane(0,0) | Lane(1,0) | Lane(2,0) | Lane(3,0) | Lane(4,0) |
               +-----------+-----------+-----------+-----------+-----------+
      y = 1    | Lane(0,1) | Lane(1,1) | Lane(2,1) | Lane(3,1) | Lane(4,1) |
               +-----------+-----------+-----------+-----------+-----------+
      y = 2    | Lane(0,2) | Lane(1,2) | Lane(2,2) | Lane(3,2) | Lane(4,2) |
               +-----------+-----------+-----------+-----------+-----------+
      y = 3    | Lane(0,3) | Lane(1,3) | Lane(2,3) | Lane(3,3) | Lane(4,3) |
               +-----------+-----------+-----------+-----------+-----------+
      y = 4    | Lane(0,4) | Lane(1,4) | Lane(2,4) | Lane(3,4) | Lane(4,4) |
               +-----------+-----------+-----------+-----------+-----------+
               <-------------------- 64 bits per lane --------------------->
```

### 5.2 Five Step Mappings per Round
1. **$\theta$ (Theta)**: Column parity mixing  
   $C[x] = \bigoplus_{y=0}^4 A[x,y]$  
   $D[x] = C[x-1] \oplus \text{ROL64}(C[x+1], 1)$  
   $A'[x,y] = A[x,y] \oplus D[x]$
2. **$\rho$ (Rho)**: Circular intra-lane bit rotation with coordinate offsets $r[x,y] \in [0..62]$.
3. **$\pi$ (Pi)**: Inter-lane coordinate transposition $B[y, (2x+3y)\%5] = \text{ROL64}(A'[x,y], r[x,y])$.
4. **$\chi$ (Chi)**: Non-linear boolean gate layer:  
   $A''[x,y] = B[x,y] \oplus ((\sim B[x+1, y]) \ \& \ B[x+2, y])$
5. **$\iota$ (Iota)**: Round constant addition $A'''[0,0] = A''[0,0] \oplus RC[i_r]$.

### 5.3 Sponge Execution Parameters
| Parameter | SHA3-256 | SHA3-512 |
|:---|:---|:---|
| Capacity ($c$) | 512 bits | 1024 bits |
| Rate ($r$) | 1088 bits (17 lanes / 136 bytes) | 576 bits (9 lanes / 72 bytes) |
| Domain Suffix | `0x06` | `0x06` |
| Permutation Latency | Exactly 24 clock cycles | Exactly 24 clock cycles |
| Digest Squeeze | 256 bits (4 lanes) | 512 bits (8 lanes) |

---

## 6. Physical Security, Side-Channel Mitigation & Zeroization
1. **Constant-Time Datapath**:
   - AES-256 pipeline latency is strictly fixed (14 cycles) regardless of data hamming weights.
   - GHASH multiplication is strictly fixed (2 cycles).
   - GCM tag verification compares all 128 bits combinationally without early termination on mismatch.
   - Keccak-f[1600] permutation is strictly fixed (24 cycles).
2. **Hardware Zeroization (`rot_zeroize_pin` & `sw_zeroize`)**:
   - Asynchronous or edge-triggered emergency input.
   - Clears all root keys, round keys, counter registers, pipeline registers, and sponge state to `0` in **1 single clock cycle**.
   - Asserts `rot_alarm_out` to alert system monitoring logic.
3. **Key Lock Register**:
   - Setting bit 16 of `CONTROL` makes key registers immutable until the next hard reset or zeroize event.
   - APB bus read attempts to key registers always return `32'h00000000` to prevent bus snooping attacks.

---

## 7. Memory-Mapped Register Map (APB4 Slave)
Base Address: `0x000` (12-bit address space)

| Offset | Name | R/W | Description |
|:---|:---|:---|:---|
| `0x000` | `CONTROL` | R/W | [0] Start, [1] Engine (0: AES, 1: SHA-3), [3:2] AES Mode (00: ECB, 01: CBC, 10: GCM), [4] Enc/Dec_n, [5] SHA3 Mode (0: 256, 1: 512), [6] GCM block is AAD, [7] Key Commit, [8] SW Zeroize, [16] Key Lock |
| `0x004` | `STATUS` | RO | [0] Busy, [1] Done, [2] Key Ready, [3] Key Locked, [4] Tag Match, [5] Zeroized |
| `0x008` | `IRQ_EN` | R/W | [0] Done Interrupt Enable, [1] Error Interrupt Enable |
| `0x00C` | `IRQ_STAT`| R/W1C| [0] Done Interrupt Flag, [1] Error Interrupt Flag (Write 1 to clear) |
| `0x010 - 0x02C` | `KEY_0 .. KEY_7` | WO | 256-bit Master Key (8 words). **Reads return `32'h00000000`** |
| `0x030 - 0x038` | `IV_0 .. IV_2` | R/W | 96-bit Initialization Vector (3 words) |
| `0x040 - 0x044` | `AAD_LEN` | R/W | Total AAD byte length (64-bit integer, LO/HI) |
| `0x048 - 0x04C` | `DATA_LEN` | R/W | Total Plaintext/Ciphertext byte length (64-bit integer, LO/HI) |
| `0x050 - 0x05C` | `TAG_IN_0..3` | R/W | Expected 128-bit Authentication Tag (for decrypt verification) |
| `0x060 - 0x06C` | `TAG_OUT_0..3`| RO | Computed 128-bit Authentication Tag |
| `0x070 - 0x07C` | `DATA_IN_0..3`| R/W | 128-bit Input Block (Plaintext, Ciphertext, or AAD) |
| `0x080 - 0x08C` | `DATA_OUT_0..3`| RO | 128-bit Output Block (Ciphertext or Plaintext) |
| `0x090 - 0x0AC` | `DIGEST_0..7` | RO | 256-bit SHA3 Digest Output |
