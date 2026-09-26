`ifndef ROT_COVERAGE_SV
`define ROT_COVERAGE_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class rot_coverage extends uvm_subscriber #(rot_seq_item);
    `uvm_component_utils(rot_coverage)

    rot_seq_item item_cov;

    covergroup rot_cg;
        option.per_instance = 1;
        option.name = "rot_functional_coverage";

        cp_op_type: coverpoint item_cov.op_type {
            bins ecb      = {OP_AES_ECB};
            bins cbc      = {OP_AES_CBC};
            bins gcm_enc  = {OP_AES_GCM_ENC};
            bins gcm_dec  = {OP_AES_GCM_DEC};
            bins sha3_256 = {OP_SHA3_256};
            bins sha3_512 = {OP_SHA3_512};
            bins zeroize  = {OP_ZEROIZE};
        }

        cp_data_len: coverpoint item_cov.data_len_bytes {
            bins zero        = {0};
            bins single_blk  = {16};
            bins short_pkt   = {[1:15]};
            bins medium_pkt  = {[17:64]};
            bins long_pkt    = {[65:256]};
        }

        cp_aad_len: coverpoint item_cov.aad_len_bytes {
            bins zero       = {0};
            bins single_blk = {16};
            bins partial    = {[1:15]};
            bins multi_blk  = {[17:128]};
        }

        cp_key_lock: coverpoint item_cov.lock_key {
            bins unlocked = {1'b0};
            bins locked   = {1'b1};
        }

        cross_op_data_len: cross cp_op_type, cp_data_len {
            ignore_bins ig_zeroize = binsof(cp_op_type) intersect {OP_ZEROIZE};
        }

        cross_gcm_aad: cross cp_op_type, cp_aad_len {
            bins gcm_enc_aad = binsof(cp_op_type) intersect {OP_AES_GCM_ENC};
            bins gcm_dec_aad = binsof(cp_op_type) intersect {OP_AES_GCM_DEC};
            ignore_bins others = binsof(cp_op_type) intersect {OP_AES_ECB, OP_AES_CBC, OP_SHA3_256, OP_SHA3_512, OP_ZEROIZE};
        }
    endgroup

    function new(string name = "rot_coverage", uvm_component parent = null);
        super.new(name, parent);
        rot_cg = new();
    endfunction

    virtual function void write(rot_seq_item t);
        item_cov = t;
        rot_cg.sample();
    endfunction

endclass

`endif
