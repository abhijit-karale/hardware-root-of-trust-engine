# ==============================================================================
# Company: Hardware Root-of-Trust (RoT) Silicon Lab
# Engineer: Abhijit Karale
# File: Makefile
# Description: Production Makefile supporting simulation, formal verification,
#              synthesis, linting, and reference testing.
# Target Node: SkyWater 130nm @ 200 MHz
# ==============================================================================

SHELL := /usr/bin/env bash

# Directories
RTL_DIR    := rtl
TB_DIR     := tb
SYN_DIR    := syn
DOCS_DIR   := docs
SCRIPTS_DIR:= scripts
BUILD_DIR  := build

# Source Files
RTL_SRCS := $(RTL_DIR)/aes/aes_sbox.sv \
            $(RTL_DIR)/aes/aes_inv_sbox.sv \
            $(RTL_DIR)/aes/aes_rcon.sv \
            $(RTL_DIR)/aes/aes_round.sv \
            $(RTL_DIR)/aes/aes_inv_round.sv \
            $(RTL_DIR)/aes/aes_key_expand_256.sv \
            $(RTL_DIR)/aes/aes_core.sv \
            $(RTL_DIR)/ghash/gf_mul128.sv \
            $(RTL_DIR)/ghash/ghash_core.sv \
            $(RTL_DIR)/gcm/aes_gcm_top.sv \
            $(RTL_DIR)/sha3/keccak_round_constants.sv \
            $(RTL_DIR)/sha3/keccak_round.sv \
            $(RTL_DIR)/sha3/keccak_f1600.sv \
            $(RTL_DIR)/sha3/sha3_core.sv \
            $(RTL_DIR)/rot_top.sv

STANDALONE_TB := $(TB_DIR)/standalone/tb_rot_top.sv
STANDALONE_INC := $(TB_DIR)/standalone

UVM_TB   := $(TB_DIR)/uvm/rot_uvm_tb_top.sv
UVM_PKG  := $(TB_DIR)/uvm/rot_uvm_pkg.sv
UVM_INC  := $(TB_DIR)/uvm

# Tools
PYTHON   ?= python3
IVERILOG ?= iverilog
VVP      ?= vvp
VERILATOR?= verilator
YOSYS    ?= yosys
SBY      ?= sby

.PHONY: all help test_ref sim sim_uvm formal synth lint clean

all: help

help:
	@echo "================================================================================"
	@echo " Hardware Root-of-Trust (RoT) Engine - Build System"
	@echo " Target: SkyWater 130nm @ 200 MHz | Candidate: Abhijit Karale"
	@echo "================================================================================"
	@echo " Targets:"
	@echo "   make test_ref  : Run Python reference test vector validator against OpenSSL"
	@echo "   make sim       : Compile and run standalone SystemVerilog testbench (Icarus/VVP)"
	@echo "   make sim_verilator : Lint and build standalone simulation with Verilator"
	@echo "   make sim_uvm   : Run UVM 1.2 testbench suite with Questa/VCS"
	@echo "   make formal    : Run SymbiYosys formal verification suite (SVA proofs)"
	@echo "   make synth     : Run Yosys synthesis script targeting SkyWater 130nm"
	@echo "   make lint      : Run Verilator syntax and code linting check"
	@echo "   make clean     : Remove build artifacts and temporary files"
	@echo "================================================================================"

# 1. Reference Validation
test_ref:
	@echo "[INFO] Running Python Reference Cryptographic Vector Validator..."
	@$(PYTHON) $(SCRIPTS_DIR)/verify_golden_vectors.py

# 2. Standalone Simulation (Icarus Verilog)
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

sim: $(BUILD_DIR)
	@echo "[INFO] Compiling Standalone Testbench with Icarus Verilog..."
	$(IVERILOG) -g2012 -I $(STANDALONE_INC) -o $(BUILD_DIR)/tb_rot_top.vvp $(RTL_SRCS) $(STANDALONE_TB)
	@echo "[INFO] Running Standalone Simulation..."
	$(VVP) $(BUILD_DIR)/tb_rot_top.vvp

# 3. Verilator Lint & Simulation
lint:
	@echo "[INFO] Running Verilator Lint Check..."
	$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN \
		-I$(RTL_DIR) -I$(RTL_DIR)/aes -I$(RTL_DIR)/ghash -I$(RTL_DIR)/gcm -I$(RTL_DIR)/sha3 \
		--top-module rot_top $(RTL_SRCS)
	@echo "[INFO] Verilator Lint Clean!"

sim_verilator: $(BUILD_DIR)
	@echo "[INFO] Building C++ Cycle-Accurate Simulator with Verilator..."
	$(VERILATOR) -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN \
		--cc --exe --build -j 4 \
		-I$(RTL_DIR) -I$(RTL_DIR)/aes -I$(RTL_DIR)/ghash -I$(RTL_DIR)/gcm -I$(RTL_DIR)/sha3 \
		--top-module rot_top $(RTL_SRCS)

# 4. QuestaSim Standalone Simulation & Full VCD Waveform Generation
sim_questa:
	@echo "[INFO] Running Standalone Simulation with QuestaSim 10.7c..."
	vlog -sv +incdir+$(STANDALONE_INC) +incdir+$(RTL_DIR) $(RTL_SRCS) $(STANDALONE_TB)
	vsim -c -do "run -all; quit -f" tb_rot_top

# 5. Interactive Software Working Dashboard & VCD Viewer
dashboard:
	@echo "[INFO] Launching Hardware RoT Interactive Dashboard & Logic Analyzer..."
	@$(PYTHON) $(SCRIPTS_DIR)/run_dashboard.py

# 6. UVM 1.2 Simulation (Questa/VCS Example Target)
sim_uvm:
	@echo "[INFO] Running UVM 1.2 Testbench (QuestaSim / ModelSim)..."
	vlog -sv +incdir+$(UVM_INC) +incdir+$(RTL_DIR) $(RTL_SRCS) $(UVM_PKG) $(UVM_TB)
	vsim -c -do "run -all; quit -f" rot_uvm_tb_top +UVM_TESTNAME=rot_nist_kat_test

# 7. Formal Verification (SymbiYosys)
formal:
	@echo "[INFO] Executing SymbiYosys Formal Verification Proofs..."
	cd $(TB_DIR)/formal && $(SBY) -f rot_formal.sby

# 8. Yosys Synthesis
synth: $(BUILD_DIR)
	@echo "[INFO] Running Yosys Synthesis for SkyWater 130nm @ 200 MHz..."
	cd $(SYN_DIR) && $(YOSYS) -s synth.ys

# 7. Clean
clean:
	rm -rf $(BUILD_DIR) *.vcd *.log *.vvp $(SYN_DIR)/rot_top_synth.* $(TB_DIR)/formal/rot_formal
	@echo "[INFO] Workspace clean."
