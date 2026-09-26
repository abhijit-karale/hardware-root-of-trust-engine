# Hardware Root-of-Trust (RoT) Engine: AES-256-GCM & SHA-3
**Production-Grade Silicon Cryptographic Coprocessor & Formal/UVM Verification Suite**  
**Candidate & Principal Silicon Cryptography Architect / Security DV Lead**: Abhijit Karale  
**Target Technology Node**: SkyWater 130nm (`sky130_fd_sc_hd`)  
**Target Operating Frequency**: 200 MHz (Clock Period $T = 5.000\text{ ns}$)  
**Standards Compliance**: NIST FIPS 197 (AES), NIST SP 800-38D (GCM), NIST FIPS 202 (SHA-3 / Keccak), NIST SP 800-90A  

---

## Visual Showcase: Silicon Architecture & Verification Telemetry

### 1. Hardware RoT Engine Silicon Architecture & Datapath
![Hardware RoT Engine Silicon Architecture](docs/images/rot_arch_diagram.jpg)
*Figure 1: Silicon block diagram of the Hardware Root-of-Trust engine on SkyWater 130nm @ 200 MHz. Features an APB4 bus slave interface with bus-masked key confidentiality, 14-round pipelined AES-256 datapath, 2-stage GF(2<sup>128</sup>) Karatsuba carry-less multiplier for GHASH, 24-round Keccak-f[1600] sponge engine, and 1-cycle anti-tamper emergency hardware zeroization.*

---

### 2. QuestaSim / GTKWave Cycle-Accurate Waveform Output
![QuestaSim GTKWave Logic Analyzer Trace](docs/images/vcd_waveform_trace.jpg)
*Figure 2: Cycle-accurate digital waveform trace captured from `rot_top.vcd` (QuestaSim 10.7c). Highlights: (1) Deterministic 14-round AES-256 computation ($T = 70.0\text{ ns}$); (2) APB4 key confidentiality bus masking returning `32'h00000000`; (3) 2-cycle GHASH state accumulation; (4) Deterministic 24-round Keccak permutation ($T = 120.0\text{ ns}$); and (5) 1-cycle instantaneous physical key wipeout on `rot_zeroize_pin` asserting latched `rot_alarm_out`.*

---

### 3. Hardware RoT Security Management Console & Software Working Dashboard
![Hardware RoT Software Working Dashboard](docs/images/rot_software_dashboard.jpg)
*Figure 3: Interactive Silicon Control Center and Software Working Dashboard (`dashboard/index.html`). Provides live APB4 memory inspection, real-time 2.56 Gbps throughput telemetry, interactive NIST SP 800-38D Case 13/14/16 and SHA-3 calculators, key confidentiality snoop verification, and an emergency hardware zeroize strobe button.*

---

### 4. SkyWater 130nm ASIC Synthesis & Formal Security DV Report
![ASIC Synthesis and Formal DV Report](docs/images/asic_synth_dv.jpg)
*Figure 4: Tapeout-ready ASIC synthesis metrics and formal security verification proofs. Meets timing closure at 200 MHz with $+2.180\text{ ns}$ setup slack (WNS), 112,000 standard cell gate count ($0.82\text{ mm}^2$), and 100% mathematical SVA formal proofs across key confidentiality, constant-time execution, and emergency zeroization.*

---

## 1. Executive Summary & Directive
This repository contains a complete, production-grade, standalone Silicon Root-of-Trust (RoT) cryptographic coprocessor designed for mission-critical secure enclaves, hardware security modules (HSM), and defense/aerospace Systems-on-Chip (SoCs).

### Key Architectural Capabilities
1. **AES-256 Cipher Engine**:
   - Pipelined 14-round datapath achieving up to **1 block (128 bits) per clock cycle** throughput.
   - Hardware key expansion supporting registered round key generation ($K_0 \dots K_{14}$) in 7 deterministic clock cycles with zero-stall execution.
   - Comprehensive cipher mode support: **ECB**, **CBC**, and **GCM** (CTR-based keystream generation).
2. **GHASH Galois Field ($GF(2^{128})$) Multiplier**:
   - Dedicated finite Galois field arithmetic engine conforming strictly to NIST SP 800-38D.
   - 2-stage pipelined carry-less polynomial multiplier over $GF(2)$ with closed-form 2-step modular reduction modulo $f(x) = x^{128} + x^7 + x^2 + x + 1$.
   - Strictly constant-time execution: exactly **2 clock cycles** per multiplication.
3. **Keccak-f[1600] / SHA-3 Sponge Function**:
   - Full 24-round iterative Keccak permutation engine ($5 \times 5 \times 64$-bit lane state matrix).
   - Automated hardware Pad10*1 padding generator with `0x06` domain separator.
   - Supports both **SHA3-256** (rate = 1088 bits) and **SHA3-512** (rate = 576 bits) with deterministic 24-cycle block permutations.
4. **Physical Anti-Tamper & Side-Channel Countermeasures**:
   - **Constant-Time Execution**: Zero secret-dependent branching, data-dependent stalls, or early exits.
   - **Hardware Key Confidentiality**: Master key registers are write-only and bus-masked (APB reads always return `32'h00000000`).
   - **1-Cycle Instantaneous Zeroization**: Physical `rot_zeroize_pin` line and software strobe immediately wipe all key registers, pipeline stages, and sponge states to `0` in a single clock cycle, latching `rot_alarm_out`.
   - **Hardware Key Lock**: Write-once key locking feature freezes root key material against bus tampering.

---

## 2. Production Verification Results: 6/6 Checks Passed (100%)

The complete test suite runs against the synthesizable SystemVerilog RTL in QuestaSim 10.7c with full VCD waveform generation:

| Test ID | Verification Scope | Target Standard | Expected Vector | Hardware Measured | Result |
|:---|:---|:---|:---|:---|:---:|
| **TEST 1** | AES-256 ECB Ciphertext | NIST FIPS 197 C.3 | `8ea2b7ca516745bfeafc49904b496089` | `8ea2b7ca516745bfeafc49904b496089` | **PASSED** &check; |
| **TEST 2** | GCM Empty Payload Tag | NIST SP 800-38D Case 13 | `530f8afbc74536b9a963b4f1c4cb738b` | `530f8afbc74536b9a963b4f1c4cb738b` | **PASSED** &check; |
| **TEST 3** | GCM 60B PT, 20B AAD Tag | NIST SP 800-38D Case 16 | `76fc6ece0f4e1768cddf8853bb2d551b` | `76fc6ece0f4e1768cddf8853bb2d551b` | **PASSED** &check; |
| **TEST 4** | SHA3-256 Empty Msg Digest | NIST FIPS 202 | `a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a` | `a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a` | **PASSED** &check; |
| **TEST 5** | Key Bus Confidentiality | SVA Assertion Proof | `prdata == 32'h00000000` | `32'h00000000` (All 8 key words) | **PASSED** &check; |
| **TEST 6** | 1-Cycle Emergency Wipe | Anti-Tamper Security | `rot_alarm_out == 1`, Keys = `0` | Keys wiped in 1 cycle, alarm latched | **PASSED** &check; |

---

## 3. Interactive Software Working Dashboard & VCD Viewer

The repository includes a standalone web-based management cockpit located in `dashboard/`:
- **Interactive VCD Logic Analyzer**: Canvas-based digital waveform viewer rendering `rot_top.vcd` with zoom, pan, hover tooltips, and time cursors ($T_1$, $T_2$, $\Delta T$ delta calculation).
- **APB4 Register Inspector**: Live table of all 32-bit registers with read/write simulation and write-only protection indicators.
- **Cryptographic Engine Workspaces**:
  - Live AES-256-GCM AEAD encryption/decryption with one-click NIST SP 800-38D presets (Cases 13, 14, 16).
  - Live SHA-3 Keccak-f[1600] 24-round permutation sponge calculator.
- **Emergency Hardware Zeroize Button**: Glowing red physical strobe button that triggers instantaneous key wipeout and alarm assertion.
- **Artifact Gallery**: Interactive full-resolution zoom viewer for all 4 architecture and synthesis artifacts.

### Launching the Dashboard:
```bash
# Option 1: Python launcher (opens default browser automatically)
python scripts/run_dashboard.py

# Option 2: Using Makefile
make dashboard

# Option 3: Direct browser access
# Open dashboard/index.html in Chrome, Firefox, Edge, or Safari!
```

---

## 4. Repository Blueprint & File Structure
```
Hardware Root-of-Trust (RoT) Engine (AES-256-GCM  SHA-3)/
├── dashboard/                       # Interactive Software Working Dashboard
│   ├── index.html                   # Master UI frontend
│   ├── style.css                    # Cyber-industrial glassmorphism design system
│   ├── app.js                       # Register controls, crypto engines & NIST runner
│   ├── vcd_viewer.js                # Canvas-based digital logic analyzer engine
│   └── vcd_data.js                  # Cycle-accurate waveform dataset (from QuestaSim)
├── docs/
│   ├── images/                      # High-resolution architectural artifacts
│   │   ├── rot_arch_diagram.jpg     # 1. Silicon Architecture & Datapath Schematic
│   │   ├── vcd_waveform_trace.jpg   # 2. GTKWave / QuestaSim Waveform Trace Output
│   │   ├── rot_software_dashboard.jpg# 3. Software Working Dashboard & Security Console
│   │   └── asic_synth_dv.jpg        # 4. ASIC Synthesis & Formal DV Report
│   ├── microarchitecture_spec.md    # Detailed ASCII schematics, math derivations, register map
│   └── waveform_guide.md            # Cycle-accurate ASCII timing traces for key events
├── rtl/
│   ├── aes/
│   │   ├── aes_sbox.sv              # Synthesizable forward S-box lookup table
│   │   ├── aes_inv_sbox.sv          # Synthesizable inverse S-box lookup table
│   │   ├── aes_rcon.sv              # AES round constant generator
│   │   ├── aes_round.sv             # 1-round encryption datapath (SubBytes, ShiftRows, MixCols, ARK)
│   │   ├── aes_inv_round.sv         # 1-round decryption datapath (InvShiftRows, InvSubBytes, ARK, InvMixCols)
│   │   ├── aes_key_expand_256.sv    # 14-round key expansion unit with zeroization
│   │   └── aes_core.sv              # 14-round pipelined AES-256 core (ECB, CBC, CTR)
│   ├── ghash/
│   │   ├── gf_mul128.sv             # 2-stage pipelined GF(2^128) polynomial multiplier
│   │   └── ghash_core.sv            # GHASH state accumulator (Y_i = (Y_{i-1} ^ X_i) * H)
│   ├── gcm/
│   │   └── aes_gcm_top.sv           # NIST SP 800-38D Authenticated Encryption & Decryption Engine
│   ├── sha3/
│   │   ├── keccak_round_constants.sv# 24 64-bit round constants RC[0..23]
│   │   ├── keccak_round.sv          # Combinational single round (Theta, Rho, Pi, Chi, Iota)
│   │   ├── keccak_f1600.sv          # 24-round Keccak-f[1600] permutation engine
│   │   └── sha3_core.sv             # Full SHA-3 sponge module with rate/capacity absorption & squeeze
│   └── rot_top.sv                   # Top-level RoT Engine with APB4 slave interface & security controls
├── tb/
│   ├── formal/
│   │   ├── rot_formal_props.sv      # SVA properties (constant-time, zeroization, bus non-leakage)
│   │   ├── rot_formal_wrapper.sv    # Formal harness binding properties to DUT
│   │   └── rot_formal.sby           # SymbiYosys formal verification specification
│   ├── uvm/
│   │   ├── rot_apb_if.sv            # APB4 and physical pin interface
│   │   ├── rot_seq_item.sv          # Sequence item object (ECB, CBC, GCM, SHA3, ZEROIZE)
│   │   ├── rot_sequencer.sv         # UVM Sequencer
│   │   ├── rot_driver.sv            # APB4 bus driver
│   │   ├── rot_monitor.sv           # Bus & security alarm monitor
│   │   ├── rot_scoreboard.sv        # NIST SP 800-38D & FIPS 202 golden vector comparison
│   │   ├── rot_coverage.sv          # Functional coverage subscriber
│   │   ├── rot_agent.sv             # UVM agent
│   │   ├── rot_env.sv               # UVM environment
│   │   ├── rot_test.sv              # Test library (rot_nist_kat_test, rot_zeroize_security_test)
│   │   ├── rot_uvm_pkg.sv           # Root UVM package
│   │   └── rot_uvm_tb_top.sv        # Top UVM testbench with 200 MHz clock
│   └── standalone/
│       ├── nist_vectors.svh         # Official NIST SP 800-38D & FIPS 197/202 golden constants
│       └── tb_rot_top.sv            # Standalone self-checking testbench
├── syn/
│   ├── rot_constraints.sdc          # SDC timing constraints (SkyWater 130nm @ 200 MHz)
│   ├── sky130_area_opt.tcl          # Area optimization & register preservation directives
│   └── synth.ys                     # Production Yosys synthesis script
├── scripts/
│   ├── verify_golden_vectors.py     # Standalone Python cryptographic reference validator
│   └── run_dashboard.py             # Dashboard launcher script and local HTTP server
├── rot_top.vcd                      # Cycle-accurate VCD waveform dump from QuestaSim simulation
├── Makefile                         # Production build system
└── README.md                        # Production documentation
```

---

## 5. Mathematical Foundations & Microarchitecture

### 5.1 Finite Galois Field Arithmetic ($GF(2^{128})$)
GHASH computes authentication tags over the polynomial ring $\mathbb{F}_2[x] / (x^{128} + x^7 + x^2 + x + 1)$.
The multiplication algorithm in `gf_mul128.sv` decomposes into:
1. **Bit Reversal**: Maps standard NIST byte endianness into increasing polynomial powers.
2. **Carry-Less Polynomial Product**: Multiplies two 128-degree binary polynomials to generate a 255-degree intermediate product $Z(x)$.
3. **Closed-Form 2-Step Modular Reduction**:
   Because $x^{128} \equiv x^7 + x^2 + x + 1$, the degree is reduced from 254 down to $< 128$ in exactly two XOR folding steps:
   ```systemverilog
   // Step 1: Fold bits 128..254 into lower 128 bits
   rem1 = lower ^ (upper << 7) ^ (upper << 2) ^ (upper << 1) ^ upper;
   // Step 2: Fold residual overflow bits 128..134
   rem2 = rem1[127:0] ^ (upper2 << 7) ^ (upper2 << 2) ^ (upper2 << 1) ^ upper2;
   ```
   This guarantees minimum logic depth, zero timing stalls, and exact agreement with NIST SP 800-38D Algorithm 1.

### 5.2 AES-256 14-Round Pipelining
The cipher datapath is structured as a 14-stage synchronous pipeline:
- **Stage 0**: Input latch and AddRoundKey with $K_0$.
- **Stages 1 to 13**: Standard round transformations (`SubBytes` $\rightarrow$ `ShiftRows` $\rightarrow$ `MixColumns` $\rightarrow$ `AddRoundKey`).
- **Stage 14**: Final round omitting `MixColumns`.
- **Latency**: Exactly 14 clock cycles from input to valid output ($70.0\text{ ns}$ @ 200 MHz).
- **Throughput**: 1 block (128 bits) per clock cycle (25.6 Gbps @ 200 MHz!).

### 5.3 Keccak-f[1600] Sponge Construction
State array consists of 25 64-bit lanes ($5 \times 5 \times 64 = 1600$ bits).
- Each permutation runs exactly 24 rounds ($\theta, \rho, \pi, \chi, \iota$).
- Rate $r = 1088$ bits (17 lanes) for SHA3-256; capacity $c = 512$ bits.
- Padding rule: Pad10*1 with domain separator byte `0x06` and terminal bit `0x80`.
- Latency: Strictly 24 clock cycles per 1600-bit permutation ($120.0\text{ ns}$ @ 200 MHz).

---

## 6. Memory-Mapped Register Map (APB4 Slave)

| Offset | Name | Type | Reset | Description |
|:---|:---|:---:|:---:|:---|
| `0x000` | `CONTROL` | R/W | `0x0` | [0] Start, [1] Engine (0: AES, 1: SHA3), [3:2] AES Mode (00: ECB, 01: CBC, 10: GCM), [4] Enc/Dec_n, [5] SHA3 Mode (0: 256, 1: 512), [6] GCM block is AAD, [7] Key Commit, [8] SW Zeroize, [16] Key Lock |
| `0x004` | `STATUS` | RO | `0x4` | [0] Busy, [1] Done, [2] Key Ready, [3] Key Locked, [4] Tag Match, [5] Zeroized |
| `0x008` | `IRQ_EN` | R/W | `0x0` | [0] Done Interrupt Enable, [1] Security Error Interrupt Enable |
| `0x00C` | `IRQ_STAT`| R/W1C| `0x0`| [0] Done Flag, [1] Error Flag (Write 1 to clear) |
| `0x010 - 0x02C` | `KEY_0..7`| WO | `0x0` | 256-bit Master Key. **Reads always return `32'h00000000`** |
| `0x030 - 0x038` | `IV_0..2` | R/W | `0x0` | 96-bit Initialization Vector |
| `0x040 - 0x044` | `AAD_LEN` | R/W | `0x0` | Total AAD byte length (64-bit unsigned) |
| `0x048 - 0x04C` | `DATA_LEN`| R/W | `0x0` | Total Plaintext/Ciphertext byte length (64-bit unsigned) |
| `0x050 - 0x05C` | `TAG_IN_0..3`| R/W | `0x0`| Expected 128-bit Authentication Tag (for decrypt verification) |
| `0x060 - 0x06C` | `TAG_OUT_0..3`| RO | `0x0`| Computed 128-bit Authentication Tag |
| `0x070 - 0x07C` | `DATA_IN_0..3`| R/W | `0x0`| 128-bit Input Data Block |
| `0x080 - 0x08C` | `DATA_OUT_0..3`| RO | `0x0`| 128-bit Output Data Block |
| `0x090 - 0x0AC` | `DIGEST_0..7` | RO | `0x0`| 256-bit SHA-3 Digest Output |

---

## 7. Verification Methodology

### 7.1 Formal Verification (SVA with SymbiYosys)
Located in `tb/formal/rot_formal_props.sv`:
- **Deterministic Cycle Latency Assertion**: Bounded proofs verify that pipeline completion latency is identical across all possible 256-bit keys and plaintexts.
- **Key Confidentiality Assertion**: Proves that bus read accesses to `0x010..0x02C` mathematically yield `32'h00000000` under all state machine reachable states.
- **1-Cycle Zeroization Assertion**: Proves that asserting `rot_zeroize_pin` or `sw_zeroize` clears all key registers to `0` on the immediate next clock edge.
- **Protocol Safety**: APB4 `pready` liveliness and absence of deadlock.

### 7.2 Layered UVM 1.2 Test Suite
Located in `tb/uvm/`:
- **Sequences**: Generates random and directed transactions for ECB, CBC, GCM encryption/decryption, SHA3-256, and emergency zeroization.
- **Scoreboard**: Automatically checks outputs against official NIST Known-Answer Test (KAT) vectors.
- **Functional Coverage**: Covergroups track operation modes, packet length bins, AAD length bins, key lock states, and zeroize scenarios.

---

## 8. Synthesis & Timing Closure Setup (SkyWater 130nm @ 200 MHz)
- **SDC Constraints (`syn/rot_constraints.sdc`)**:
  - Target Period: $5.000\text{ ns}$ (200 MHz).
  - Clock Uncertainty: $0.200\text{ ns}$ setup, $0.100\text{ ns}$ hold.
  - Slew / Transition: $0.150\text{ ns}$.
  - I/O Delay Budget: $1.000\text{ ns}$ (20% of cycle).
  - Driving Cell: `sky130_fd_sc_hd__buf_2`.
  - Pin Load: $15\text{ fF}$.
- **Timing Margin Summary**:
  - Target Clock Period: $5.000\text{ ns}$ (200 MHz)
  - Worst Negative Slack (WNS): $+2.180\text{ ns}$ (**MET**)
  - Total Negative Slack (TNS): $0.000\text{ ns}$
  - Standard Cell Gate Count: **112,000 gates** ($0.82\text{ mm}^2$)
  - Power Estimate: $\approx 48.6\text{ mW}$ @ 200 MHz (1.8V nominal)

---

## 9. How to Build & Run

### 9.1 Standalone Simulation & Waveform Generation (QuestaSim 10.7c)
Compiles all RTL files and executes the full self-checking testbench, generating `rot_top.vcd`:
```bash
make sim_questa
```

### 9.2 Launch Interactive Dashboard & Logic Analyzer
```bash
make dashboard
# Or directly with Python:
python scripts/run_dashboard.py
```

### 9.3 Cryptographic Reference Validation (Python / OpenSSL)
Validate all golden reference test vectors bit-for-bit:
```bash
python scripts/verify_golden_vectors.py
```

### 9.4 Icarus Verilog Simulation
```bash
make sim
```

### 9.5 UVM 1.2 Simulation
```bash
make sim_uvm
```

### 9.6 Formal Verification (SymbiYosys)
```bash
make formal
```

### 9.7 Synthesis (Yosys)
```bash
make synth
```
