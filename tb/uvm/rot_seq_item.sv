`ifndef ROT_SEQ_ITEM_SV
`define ROT_SEQ_ITEM_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

typedef enum {
    OP_AES_ECB,
    OP_AES_CBC,
    OP_AES_GCM_ENC,
    OP_AES_GCM_DEC,
    OP_SHA3_256,
    OP_SHA3_512,
    OP_ZEROIZE
} rot_op_type_e;

class rot_seq_item extends uvm_sequence_item;
    `uvm_object_utils(rot_seq_item)

    // Transaction Stimulus Fields
    rand rot_op_type_e  op_type;
    rand bit [255:0]    key;
    rand bit [95:0]     iv;
    rand bit [63:0]     aad_len_bytes;
    rand bit [63:0]     data_len_bytes;
    rand bit [7:0]      aad_payload   [];
    rand bit [7:0]      data_payload  [];
    rand bit [127:0]    tag_in;           // For GCM decrypt verification
    rand bit            lock_key;

    // Expected Golden Answers
    bit [7:0]           expected_data [];
    bit [127:0]         expected_tag;
    bit [255:0]         expected_digest_256;
    bit [511:0]         expected_digest_512;
    bit                 expected_tag_match;

    // Actual DUT Responses
    bit [7:0]           actual_data   [];
    bit [127:0]         actual_tag;
    bit [255:0]         actual_digest_256;
    bit                 actual_tag_match;

    // Constraints
    constraint c_payload_size {
        data_payload.size() == data_len_bytes;
        aad_payload.size()  == aad_len_bytes;
        data_len_bytes inside {[0:256]};
        aad_len_bytes inside {[0:128]};
    }

    function new(string name = "rot_seq_item");
        super.new(name);
    endfunction

    virtual function string convert2string();
        return $sformatf("op_type=%s, key=0x%064x, iv=0x%024x, aad_len=%0d, data_len=%0d",
                         op_type.name(), key, iv, aad_len_bytes, data_len_bytes);
    endfunction

endclass

`endif
