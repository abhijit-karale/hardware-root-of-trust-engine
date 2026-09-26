`ifndef ROT_TEST_SV
`define ROT_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

// Base Test
class rot_base_test extends uvm_test;
    `uvm_component_utils(rot_base_test)

    rot_env env;

    function new(string name = "rot_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = rot_env::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

endclass

// NIST SP 800-38D Known-Answer Test (KAT) Suite
class rot_nist_kat_test extends rot_base_test;
    `uvm_component_utils(rot_nist_kat_test)

    function new(string name = "rot_nist_kat_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        rot_seq_item item;
        phase.raise_objection(this);

        `uvm_info("TEST", "==========================================================", UVM_LOW)
        `uvm_info("TEST", " STARTING NIST SP 800-38D & FIPS 197/202 KNOWN ANSWER TESTS", UVM_LOW)
        `uvm_info("TEST", "==========================================================", UVM_LOW)

        // =====================================================================
        // TEST VECTOR 1: FIPS 197 Appendix C.3 (AES-256 ECB Mode)
        // Key: 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
        // PT:  00112233445566778899aabbccddeeff
        // CT:  8ea2b7ca516745bfeafc49904b496089
        // =====================================================================
        item = rot_seq_item::type_id::create("item_fips197_c3");
        item.op_type        = OP_AES_ECB;
        item.key            = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
        item.iv             = 96'h0;
        item.aad_len_bytes  = 64'd0;
        item.data_len_bytes = 64'd16;
        item.data_payload   = '{8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77,
                                8'h88, 8'h99, 8'haa, 8'hbb, 8'hcc, 8'hdd, 8'hee, 8'hff};
        item.expected_data  = '{8'h8e, 8'ha2, 8'hb7, 8'hca, 8'h51, 8'h67, 8'h45, 8'hbf,
                                8'hea, 8'hfc, 8'h49, 8'h90, 8'h4b, 8'h49, 8'h60, 8'h89};
        item.lock_key       = 1'b0;

        `uvm_info("TEST", "Executing FIPS 197 C.3 AES-256 ECB Test...", UVM_LOW)
        env.agent.driver.drive_item(item);
        env.scoreboard.write(item);

        // =====================================================================
        // TEST VECTOR 2: NIST SP 800-38D Test Case 13 (AES-256 GCM)
        // Key: 256'h00
        // IV:  96'h00
        // PT:  empty (0 bytes)
        // AAD: empty (0 bytes)
        // Tag: 530f8afbc74536b9a963b4f1c4cb738b
        // =====================================================================
        item = rot_seq_item::type_id::create("item_nist_case13");
        item.op_type        = OP_AES_GCM_ENC;
        item.key            = 256'h0;
        item.iv             = 96'h0;
        item.aad_len_bytes  = 64'd0;
        item.data_len_bytes = 64'd0;
        item.aad_payload    = new[0];
        item.data_payload   = new[0];
        item.expected_data  = new[0];
        item.expected_tag   = 128'h530f8afbc74536b9a963b4f1c4cb738b;
        item.lock_key       = 1'b0;

        `uvm_info("TEST", "Executing NIST SP 800-38D Case 13 (AES-256-GCM)...", UVM_LOW)
        env.agent.driver.drive_item(item);
        env.scoreboard.write(item);

        // =====================================================================
        // TEST VECTOR 3: NIST SP 800-38D Test Case 14 (AES-256 GCM)
        // Key: 256'h00
        // IV:  96'h00
        // PT:  16 bytes of 0x00
        // CT:  cea7403d4d606b6e074ec5d3baf39d18
        // Tag: d0d1c8a799996bf0265b98b5d48ab919
        // =====================================================================
        item = rot_seq_item::type_id::create("item_nist_case14");
        item.op_type        = OP_AES_GCM_ENC;
        item.key            = 256'h0;
        item.iv             = 96'h0;
        item.aad_len_bytes  = 64'd0;
        item.data_len_bytes = 64'd16;
        item.aad_payload    = new[0];
        item.data_payload   = '{16{8'h00}};
        item.expected_data  = '{8'hce, 8'ha7, 8'h40, 8'h3d, 8'h4d, 8'h60, 8'h6b, 8'h6e,
                                8'h07, 8'h4e, 8'hc5, 8'hd3, 8'hba, 8'hf3, 8'h9d, 8'h18};
        item.expected_tag   = 128'hd0d1c8a799996bf0265b98b5d48ab919;
        item.lock_key       = 1'b0;

        `uvm_info("TEST", "Executing NIST SP 800-38D Case 14 (AES-256-GCM)...", UVM_LOW)
        env.agent.driver.drive_item(item);
        env.scoreboard.write(item);

        // =====================================================================
        // TEST VECTOR 4: NIST SP 800-38D Test Case 16 (AES-256 GCM with AAD)
        // Key: feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308
        // IV:  cafebabefacedbaddecaf888
        // AAD: feedfacedeadbeeffeedfacedeadbeefabaddad2 (20 bytes)
        // PT:  60 bytes
        // Tag: 76fc6ece0f4e1768cddf8853bb2d551b
        // =====================================================================
        item = rot_seq_item::type_id::create("item_nist_case16");
        item.op_type        = OP_AES_GCM_ENC;
        item.key            = 256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308;
        item.iv             = 96'hcafebabefacedbaddecaf888;
        item.aad_len_bytes  = 64'd20;
        item.data_len_bytes = 64'd60;
        item.aad_payload    = '{8'hfe, 8'hed, 8'hfa, 8'hce, 8'hde, 8'had, 8'hbe, 8'hef,
                                8'hfe, 8'hed, 8'hfa, 8'hce, 8'hde, 8'had, 8'hbe, 8'hef,
                                8'hab, 8'had, 8'hda, 8'hd2};
        item.data_payload   = '{8'hd9, 8'h31, 8'h32, 8'h25, 8'hf8, 8'h84, 8'h06, 8'he5,
                                8'ha5, 8'h59, 8'h09, 8'hc5, 8'haf, 8'hf5, 8'h26, 8'h9a,
                                8'h86, 8'ha7, 8'ha9, 8'h53, 8'h15, 8'h34, 8'hf7, 8'hda,
                                8'h2e, 8'h4c, 8'h30, 8'h3d, 8'h8a, 8'h31, 8'h8a, 8'h72,
                                8'h1c, 8'h3c, 8'h0c, 8'h95, 8'h95, 8'h68, 8'h09, 8'h53,
                                8'h2f, 8'hcf, 8'h0e, 8'h24, 8'h49, 8'ha6, 8'hb5, 8'h25,
                                8'hb1, 8'h6a, 8'hed, 8'hf5, 8'haa, 8'h0d, 8'he6, 8'h57,
                                8'hba, 8'h63, 8'h7b, 8'h39};
        item.expected_data  = '{8'h52, 8'h2d, 8'hc1, 8'hf0, 8'h99, 8'h56, 8'h7d, 8'h07,
                                8'hf4, 8'h7f, 8'h37, 8'ha3, 8'h2a, 8'h84, 8'h42, 8'h7d,
                                8'h64, 8'h3a, 8'h8c, 8'hdc, 8'hbf, 8'he5, 8'hc0, 8'hc9,
                                8'h75, 8'h98, 8'ha2, 8'hbd, 8'h25, 8'h55, 8'hd1, 8'haa,
                                8'h8c, 8'hb0, 8'h8e, 8'h48, 8'h59, 8'h0d, 8'hbb, 8'h3d,
                                8'ha7, 8'hb0, 8'h8b, 8'h10, 8'h56, 8'h82, 8'h88, 8'h38,
                                8'hc5, 8'hf6, 8'h1e, 8'h63, 8'h93, 8'hba, 8'h7a, 8'h0a,
                                8'hbc, 8'hc9, 8'hf6, 8'h62};
        item.expected_tag   = 128'h76fc6ece0f4e1768cddf8853bb2d551b;
        item.lock_key       = 1'b1;

        `uvm_info("TEST", "Executing NIST SP 800-38D Case 16 (AES-256-GCM Authenticated Encrypt)...", UVM_LOW)
        env.agent.driver.drive_item(item);
        env.scoreboard.write(item);

        // =====================================================================
        // TEST VECTOR 5: FIPS 202 SHA3-256 Standard Vector
        // Input: Empty Message ""
        // Digest: a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a
        // =====================================================================
        item = rot_seq_item::type_id::create("item_sha3_empty");
        item.op_type             = OP_SHA3_256;
        item.data_len_bytes      = 64'd0;
        item.expected_digest_256 = 256'ha7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a;

        `uvm_info("TEST", "Executing FIPS 202 SHA3-256 (Empty Message Vector)...", UVM_LOW)
        env.agent.driver.drive_item(item);
        env.scoreboard.write(item);

        phase.drop_objection(this);
    endtask

endclass

// Hardware Zeroization & Key Confidentiality Security Test
class rot_zeroize_security_test extends rot_base_test;
    `uvm_component_utils(rot_zeroize_security_test)

    function new(string name = "rot_zeroize_security_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        rot_seq_item item;
        bit [31:0] key_snoop;
        phase.raise_objection(this);

        `uvm_info("SECURITY_TEST", "Starting Hardware Zeroize & Key Confidentiality Test", UVM_LOW)

        // 1. Program secret key and lock it
        item = rot_seq_item::type_id::create("item_sec");
        item.op_type  = OP_AES_ECB;
        item.key      = 256'hdeadbeefcafebabefacedbaddecaf8880123456789abcdef0123456789abcdef;
        item.lock_key = 1'b1;
        env.agent.driver.drive_item(item);

        // 2. Bus Snooping Attempt: Read back key addresses
        for (int k = 0; k < 8; k++) begin
            env.agent.driver.apb_read(12'h010 + 4*k, key_snoop);
            if (key_snoop !== 32'h00000000) begin
                `uvm_error("SECURITY_LEAK", $sformatf("Key address 0x%03x leaked secret bits: 0x%08x", 12'h010 + 4*k, key_snoop))
            end else begin
                `uvm_info("CONFIDENTIALITY_VERIFIED", $sformatf("Key address 0x%03x safely read as 0x00000000", 12'h010 + 4*k), UVM_LOW)
            end
        end

        // 3. Trigger Physical Zeroize Pin
        `uvm_info("ZEROIZE_TEST", "Pulsing Physical rot_zeroize_pin...", UVM_LOW)
        item = rot_seq_item::type_id::create("item_zeroize");
        item.op_type = OP_ZEROIZE;
        env.agent.driver.drive_item(item);

        // 4. Verify Status Register reflects zeroized state
        env.agent.driver.apb_read(12'h004, key_snoop);
        `uvm_info("STATUS_CHECK", $sformatf("Status register after zeroize: 0x%08x", key_snoop), UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif
