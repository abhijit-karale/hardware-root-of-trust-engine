`ifndef ROT_DRIVER_SV
`define ROT_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class rot_driver extends uvm_driver #(rot_seq_item);
    `uvm_component_utils(rot_driver)

    virtual rot_apb_if vif;

    function new(string name = "rot_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual rot_apb_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", "Virtual interface rot_apb_if not found in config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        // Initialize APB signals
        vif.drv_cb.psel            <= 1'b0;
        vif.drv_cb.penable         <= 1'b0;
        vif.drv_cb.pwrite          <= 1'b0;
        vif.drv_cb.paddr           <= 12'h0;
        vif.drv_cb.pwdata          <= 32'h0;
        vif.drv_cb.pstrb           <= 4'hf;
        vif.drv_cb.rot_zeroize_pin <= 1'b0;

        @(posedge vif.presetn);
        @(vif.drv_cb);

        forever begin
            seq_item_port.get_next_item(req);
            drive_item(req);
            seq_item_port.item_done();
        end
    endtask

    // APB Write Task (2-cycle setup and access phase)
    task apb_write(input bit [11:0] addr, input bit [31:0] data);
        @(vif.drv_cb);
        vif.drv_cb.paddr   <= addr;
        vif.drv_cb.pwdata  <= data;
        vif.drv_cb.pwrite  <= 1'b1;
        vif.drv_cb.pstrb   <= 4'hf;
        vif.drv_cb.psel    <= 1'b1;
        vif.drv_cb.penable <= 1'b0;

        @(vif.drv_cb);
        vif.drv_cb.penable <= 1'b1;

        while (!vif.drv_cb.pready) @(vif.drv_cb);

        @(vif.drv_cb);
        vif.drv_cb.psel    <= 1'b0;
        vif.drv_cb.penable <= 1'b0;
        vif.drv_cb.pwrite  <= 1'b0;
    endtask

    // APB Read Task
    task apb_read(input bit [11:0] addr, output bit [31:0] data);
        @(vif.drv_cb);
        vif.drv_cb.paddr   <= addr;
        vif.drv_cb.pwrite  <= 1'b0;
        vif.drv_cb.psel    <= 1'b1;
        vif.drv_cb.penable <= 1'b0;

        @(vif.drv_cb);
        vif.drv_cb.penable <= 1'b1;

        while (!vif.drv_cb.pready) @(vif.drv_cb);

        data = vif.drv_cb.prdata;
        @(vif.drv_cb);
        vif.drv_cb.psel    <= 1'b0;
        vif.drv_cb.penable <= 1'b0;
    endtask

    // Drive sequence item through APB interface
    task drive_item(rot_seq_item item);
        bit [31:0] rdata;
        int blocks;

        `uvm_info(get_type_name(), $sformatf("Driving transaction: %s", item.convert2string()), UVM_HIGH)

        if (item.op_type == OP_ZEROIZE) begin
            // Pulse physical zeroize pin
            @(vif.drv_cb);
            vif.drv_cb.rot_zeroize_pin <= 1'b1;
            repeat (3) @(vif.drv_cb);
            vif.drv_cb.rot_zeroize_pin <= 1'b0;
            @(vif.drv_cb);
            return;
        end

        // 1. Program Master Key (8 words)
        for (int k = 0; k < 8; k++) begin
            apb_write(12'h010 + 4*k, item.key[255 - 32*k -: 32]);
        end

        // 2. Program IV (3 words = 96 bits)
        apb_write(12'h030, item.iv[95:64]);
        apb_write(12'h034, item.iv[63:32]);
        apb_write(12'h038, item.iv[31:0]);

        // 3. Program Lengths
        apb_write(12'h040, item.aad_len_bytes[31:0]);
        apb_write(12'h044, item.aad_len_bytes[63:32]);
        apb_write(12'h048, item.data_len_bytes[31:0]);
        apb_write(12'h04C, item.data_len_bytes[63:32]);

        // 4. Program Expected Tag for Decrypt
        if (item.op_type == OP_AES_GCM_DEC) begin
            apb_write(12'h050, item.tag_in[127:96]);
            apb_write(12'h054, item.tag_in[95:64]);
            apb_write(12'h058, item.tag_in[63:32]);
            apb_write(12'h05C, item.tag_in[31:0]);
        end

        // 5. Commit Key and optionally lock
        apb_write(12'h000, 32'h00000080 | (item.lock_key ? 32'h00010000 : 32'h0));
        repeat (10) @(vif.drv_cb); // Wait for key expansion (7 cycles)

        // 6. Execute based on operation
        case (item.op_type)
            OP_AES_ECB: begin
                // Load data block
                apb_write(12'h070, {item.data_payload[0], item.data_payload[1], item.data_payload[2], item.data_payload[3]});
                apb_write(12'h074, {item.data_payload[4], item.data_payload[5], item.data_payload[6], item.data_payload[7]});
                apb_write(12'h078, {item.data_payload[8], item.data_payload[9], item.data_payload[10], item.data_payload[11]});
                apb_write(12'h07C, {item.data_payload[12], item.data_payload[13], item.data_payload[14], item.data_payload[15]});

                // Start ECB Encrypt: mode=00, enc=1, start=1
                apb_write(12'h000, 32'h00000011);
                repeat (20) @(vif.drv_cb); // 14-cycle pipeline latency

                // Read output block
                item.actual_data = new[16];
                for (int w = 0; w < 4; w++) begin
                    apb_read(12'h080 + 4*w, rdata);
                    item.actual_data[4*w + 0] = rdata[31:24];
                    item.actual_data[4*w + 1] = rdata[23:16];
                    item.actual_data[4*w + 2] = rdata[15:8];
                    item.actual_data[4*w + 3] = rdata[7:0];
                end
            end

            OP_AES_GCM_ENC, OP_AES_GCM_DEC: begin
                // Trigger GCM session: mode=10 (GCM), enc=(op==ENC), start=1
                apb_write(12'h000, (item.op_type == OP_AES_GCM_ENC ? 32'h00000019 : 32'h00000009));
                repeat (30) @(vif.drv_cb); // Wait for H and S0 generation

                // Stream AAD blocks if any
                if (item.aad_len_bytes > 0) begin
                    blocks = (item.aad_len_bytes + 15) / 16;
                    for (int b = 0; b < blocks; b++) begin
                        bit [127:0] aad_block = '0;
                        for (int i = 0; i < 16; i++) begin
                            if (b*16 + i < item.aad_len_bytes)
                                aad_block[127 - 8*i -: 8] = item.aad_payload[b*16 + i];
                        end
                        // Set block_is_aad = 1 (bit 6 of CONTROL)
                        apb_write(12'h000, 32'h00000049);
                        apb_write(12'h070, aad_block[127:96]);
                        apb_write(12'h074, aad_block[95:64]);
                        apb_write(12'h078, aad_block[63:32]);
                        apb_write(12'h07C, aad_block[31:0]);
                        repeat (5) @(vif.drv_cb);
                    end
                end

                // Stream Data blocks if any
                if (item.data_len_bytes > 0) begin
                    blocks = (item.data_len_bytes + 15) / 16;
                    item.actual_data = new[item.data_len_bytes];
                    for (int b = 0; b < blocks; b++) begin
                        bit [127:0] pt_block = '0;
                        for (int i = 0; i < 16; i++) begin
                            if (b*16 + i < item.data_len_bytes)
                                pt_block[127 - 8*i -: 8] = item.data_payload[b*16 + i];
                        end
                        // Set block_is_aad = 0
                        apb_write(12'h000, 32'h00000009);
                        apb_write(12'h070, pt_block[127:96]);
                        apb_write(12'h074, pt_block[95:64]);
                        apb_write(12'h078, pt_block[63:32]);
                        apb_write(12'h07C, pt_block[31:0]);
                        repeat (20) @(vif.drv_cb);

                        // Read output ciphertext/plaintext block
                        for (int w = 0; w < 4; w++) begin
                            apb_read(12'h080 + 4*w, rdata);
                            for (int byte_i = 0; byte_i < 4; byte_i++) begin
                                int idx = b*16 + 4*w + byte_i;
                                if (idx < item.data_len_bytes)
                                    item.actual_data[idx] = rdata[31 - 8*byte_i -: 8];
                            end
                        end
                    end
                end

                // Wait for final tag computation
                repeat (20) @(vif.drv_cb);

                // Read Tag Out
                for (int w = 0; w < 4; w++) begin
                    apb_read(12'h060 + 4*w, rdata);
                    item.actual_tag[127 - 32*w -: 32] = rdata;
                end

                // Read Status for Tag Match
                apb_read(12'h004, rdata);
                item.actual_tag_match = rdata[4];
            end

            OP_SHA3_256: begin
                // Trigger SHA3: engine_sel=1, mode=0 (256), start=1
                apb_write(12'h000, 32'h00000003);
                repeat (30) @(vif.drv_cb);

                // Read 256-bit digest (8 words)
                for (int w = 0; w < 8; w++) begin
                    apb_read(12'h090 + 4*w, rdata);
                    item.actual_digest_256[32*w +: 32] = rdata;
                end
            end
            default: ;
        endcase
    endtask

endclass

`endif
