# Hardware Root-of-Trust (RoT) Engine: Cycle-Accurate Waveform Guide
**Target Tech Node & Clock**: SkyWater 130nm @ 200 MHz ($T = 5.000\text{ ns}$)  
**Candidate & Lead Architect**: Abhijit Karale  

This guide provides cycle-by-cycle ASCII timing traces detailing key lifecycle events, pipelined cryptographic datapaths, authenticated encryption, and physical security triggers.

---

## 1. Key Loading, On-the-Fly Expansion & Key Lock Sequence
The 256-bit root key is loaded over the 32-bit APB slave bus (8 writes to `0x010..0x02C`), followed by a commit strobe (`CONTROL[7]=1`) and lock assertion (`CONTROL[16]=1`).

```
Cycle:       0   1   2   3 ... 8   9  10  11  12  13  14  15  16  17  18
pclk       : _|~|_|~|_|~|_|~|..._|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|
paddr      : --<010><014><018>...<02C><000>------------------------------
pwdata     : --< W0>< W1>< W2>...< W7><8080>-----------------------------
psel       : __/~~~~~~~~\_______/~~~~~~~\________________________________
penable    : _____/~~~\___/~~~\_____/~~~\________________________________
pwrite     : __/~~~~~~~~~~~~~~~~~~~~~~~~\________________________________
key_commit : ____________________________/~~~\___________________________
key_locked : ________________________________/~~~~~~~~~~~~~~~~~~~~~~~~~~~~
state_q    : < IDLE  ><    EXPAND (Steps 1..7)     ><       READY        >
step_q     : <  0   >< 1 >< 2 >< 3 >< 4 >< 5 >< 6 >< 7 ><       0        >
round_keys : < 000000000000000000000000000000000000 >< K0..K14 Valid!   >
key_ready  : ____________________________________________/~~~~~~~~~~~~~~~~
```

- **Cycle 0-8**: APB writes 8 words into `key_words[0..7]`.
- **Cycle 9**: Write to `0x000` with `pwdata[7]=1` (commit) and `pwdata[16]=1` (lock).
- **Cycle 10-16**: `aes_key_expand_256` iterates 7 steps (1 step per cycle) generating round keys $K_0 \dots K_{14}$.
- **Cycle 17**: All 15 round keys latched into `round_keys[0..14]`; `key_ready` asserts; `key_locked` freezes key registers.

---

## 2. 14-Round AES Pipelined Datapath Execution
Demonstrates cycle-accurate block progression through the 14-stage pipelined datapath.
Throughput: **1 block per cycle** once the pipeline is primed.
Latency: Strictly **14 clock cycles** from input stage to output.

```
Cycle:         0    1    2    3    4    5    6    7    8    9   10   11   12   13   14   15
pclk         : _|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|_|~|
data_valid   : _/~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\_____________________________________
data_in      : -< BLK0 >< BLK1 >< BLK2 >------------------------------------------------
pipe_state[0]: -----< S0_0 >< S0_1 >< S0_2 >--------------------------------------------
pipe_state[1]: ----------< S1_0 >< S1_1 >< S1_2 >---------------------------------------
pipe_state[2]: ---------------< S2_0 >< S2_1 >< S2_2 >----------------------------------
pipe_state[3]: --------------------< S3_0 >< S3_1 >< S3_2 >-----------------------------
  ...          :                                    ...
pipe_state[13]: ---------------------------------------------------<S13_0><S13_1><S13_2>
pipe_state[14]: --------------------------------------------------------<S14_0><S14_1><S14_2>
data_out_valid: _________________________________________________________/~~~~~~~~~~~~~~\_
data_out     : --------------------------------------------------------< CT0  >< CT1  >< CT2  >
```

- **Cycle 0**: `BLK0` enters pipeline stage 0 (AddRoundKey with $K_0$).
- **Cycle 1**: `BLK0` moves to Stage 1 (SubBytes $\rightarrow$ ShiftRows $\rightarrow$ MixColumns $\rightarrow$ AddRoundKey with $K_1$). Concurrently, `BLK1` enters Stage 0!
- **Cycle 14**: `BLK0` completes final Round 14; `data_out_valid` asserts; `CT0` is emitted.
- **Cycle 15**: `CT1` emitted (back-to-back 1 block/cycle throughput!).

---

## 3. AES-256-GCM Complete Authenticated Encryption & Tag Generation
Sequence for NIST SP 800-38D:
1. Subkey $H = \text{AES}_K(0^{128})$ generated via AES pipeline.
2. Tag mask $S_0 = \text{AES}_K(J_0)$ generated ($J_0 = \{\text{IV}, 31'b0, 1'b1\}$).
3. Plaintext block CTR encryption: $C_1 = P_1 \oplus \text{AES}_K(\text{CTR}_1)$.
4. GHASH Galois Field accumulation over AAD, CT, and length block.
5. Final tag calculation: $T = \text{GHASH} \oplus S_0$.

```
Cycle:       0      14     15     29     30     32     34     48     50     52     54
pclk       : _|~|..._|~|_..._|~|..._|~|_..._|~|_..._|~|_..._|~|_..._|~|_..._|~|_..._|~|
gcm_state  : <GEN_H><WAIT_H><GEN_S0><WAIT_S0><PROC_AAD><PROC_DATA><PROC_LEN><WAIT_G><FIN><DONE>
aes_in     : <  0^128  >----<  J0   >------------------< CTR1 >------------------------
aes_out    : -------< H >----------< S0 >-------------------< KS1 >--------------------
ghash_in   : --------------------------------< AAD1 >---------< CT1  >-< LEN  >--------
ghash_done : ____________________________________/~~~\____________/~~~\____/~~~\_______
ghash_y_out: ------------------------------------< Y1 >-----------< Y2 >---< Y_FIN >---
tag_out    : ------------------------------------------------------------------< T_FIN >
tag_valid  : ______________________________________________________________________/~~~\
rot_irq_out: ______________________________________________________________________/~~~\
```

- **Cycle 0-14**: Pipeline computes hash subkey $H = \text{AES}_K(0^{128})$.
- **Cycle 15-29**: Pipeline computes pre-counter block $S_0 = \text{AES}_K(\text{IV} \,\|\, 1)$.
- **Cycle 30-32**: GHASH absorbs AAD block ($Y_1 = \text{AAD}_1 \cdot H$).
- **Cycle 34-48**: AES generates keystream $\text{KS}_1 = \text{AES}_K(\text{IV} \,\|\, 2)$; ciphertext $C_1 = P_1 \oplus \text{KS}_1$.
- **Cycle 48-50**: GHASH absorbs ciphertext $C_1$ ($Y_2 = (Y_1 \oplus C_1) \cdot H$).
- **Cycle 50-52**: GHASH absorbs length block $[len(A)]_{64} \,\|\, [len(C)]_{64}$.
- **Cycle 52-54**: Tag finalized: $T = Y_{\text{FIN}} \oplus S_0$; `tag_valid` and `rot_irq_out` assert!

---

## 4. Hardware Anti-Tamper & 1-Cycle Instantaneous Zeroization
Demonstrates emergency zeroization triggered by the physical `rot_zeroize_pin` line during active computation.

```
Cycle:             0        1        2        3        4        5
pclk             : _|~|_    _|~|_    _|~|_    _|~|_    _|~|_    _|~|_
rot_zeroize_pin  : _________/~~~~~~~~~~~~~~~~~\______________________
rot_alarm_out    : _________/~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
key_words[0..7]  : < SECRET KEY BITS >< 0000000000000000000000000000 >
round_keys[0..14]: < ACTIVE ROUND KEYS >< 00000000000000000000000000 >
pipe_state[0..14]: < IN-FLIGHT CIPHER >< 00000000000000000000000000 >
sponge_state     : < IN-FLIGHT SHA-3  >< 00000000000000000000000000 >
gcm_state        : <    GCM_DATA      ><           IDLE              >
status[5] (Zero) : ___________________/~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

- **Cycle 1**: Emergency tamper line `rot_zeroize_pin` asserts.
- **Cycle 2 (Immediately on next clock edge)**:
  - All master key registers wiped to `32'h0`.
  - All 15 round key registers wiped to `128'h0`.
  - All 14 AES pipeline stages wiped to `128'h0`.
  - Keccak-f[1600] 1600-bit state wiped to `1600'h0`.
  - FSM aborts immediately to `IDLE`.
  - `rot_alarm_out` asserts to notify the security subsystem.

---

## 5. Keccak-f[1600] / SHA3-256 Sponge Function Timing Trace
Demonstrates message absorption, 24-round permutation, and digest squeezing.

```
Cycle:         0    1    2 ... 17   18   19 ... 42   43   44
pclk         : _|~|_|~|_|~|..._|~|_|~|_|~|_..._|~|_|~|_|~|_|~|
start_hash   : _/~~~\_________________________________________
word_valid   : _/~~~~~~~~~~~~~~~~~\___________________________
lane_cnt_q   : < 0 >< 1 >< 2 >...<16>< 0 >< 0 >...< 0 >< 0 >
sha3_state   : <IDLE><    ABSORB    ><PAD>< PERMUTE (24 Rnds) ><DONE>
round_cnt_q  : < 0 >< 0 >< 0 >...< 0 >< 0 >< 0 >...<23>< 0 >
keccak_done  : _________________________________________/~~~\_
digest_valid : ______________________________________________/
digest_256   : ----------------------------------------------< DIGEST >
```

- **Cycle 0**: `start_hash` initiates session; state cleared.
- **Cycle 1-17**: Streams up to 17 64-bit lanes (1088-bit rate for SHA3-256).
- **Cycle 18**: Hardware Pad10*1 adds `0x06` domain suffix and `0x80` final bit.
- **Cycle 19-42**: Executes exactly 24 permutation rounds (strictly 1 round per cycle = 24 cycles).
- **Cycle 43**: Permutation done; state squeezed.
- **Cycle 44**: 256-bit digest valid on `DIGEST_0..7`.
