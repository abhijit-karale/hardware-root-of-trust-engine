`ifndef ROT_SCOREBOARD_SV
`define ROT_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class rot_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(rot_scoreboard)

    uvm_analysis_imp #(rot_seq_item, rot_scoreboard) sb_export;

    int total_checks;
    int pass_count;
    int fail_count;

    function new(string name = "rot_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        sb_export = new("sb_export", this);
        total_checks = 0;
        pass_count   = 0;
        fail_count   = 0;
    endfunction

    virtual function void write(rot_seq_item item);
        total_checks++;
        `uvm_info(get_type_name(), $sformatf("Evaluating transaction: %s", item.convert2string()), UVM_MEDIUM)

        case (item.op_type)
            OP_AES_ECB: begin
                check_data_payload(item);
            end

            OP_AES_GCM_ENC: begin
                check_data_payload(item);
                check_tag(item);
            end

            OP_AES_GCM_DEC: begin
                check_data_payload(item);
                if (item.actual_tag_match !== item.expected_tag_match) begin
                    `uvm_error("GCM_TAG_MISMATCH", $sformatf("Tag match expected=%0b, actual=%0b",
                                                             item.expected_tag_match, item.actual_tag_match))
                    fail_count++;
                end else begin
                    pass_count++;
                end
            end

            OP_SHA3_256: begin
                if (item.actual_digest_256 !== item.expected_digest_256) begin
                    `uvm_error("SHA3_DIGEST_MISMATCH", $sformatf("Expected=0x%064x, Actual=0x%064x",
                                                                 item.expected_digest_256, item.actual_digest_256))
                    fail_count++;
                end else begin
                    `uvm_info("SHA3_PASS", $sformatf("SHA3-256 Digest Matched Golden Vector: 0x%064x", item.actual_digest_256), UVM_LOW)
                    pass_count++;
                end
            end

            default: ;
        endcase
    endfunction

    virtual function void check_data_payload(rot_seq_item item);
        bit mismatch = 1'b0;
        if (item.expected_data.size() != item.actual_data.size()) begin
            `uvm_error("PAYLOAD_LEN_MISMATCH", $sformatf("Expected len=%0d, Actual len=%0d",
                                                         item.expected_data.size(), item.actual_data.size()))
            fail_count++;
            return;
        end

        for (int i = 0; i < item.expected_data.size(); i++) begin
            if (item.expected_data[i] !== item.actual_data[i]) begin
                `uvm_error("BYTE_MISMATCH", $sformatf("Byte [%0d] Expected=0x%02x, Actual=0x%02x",
                                                      i, item.expected_data[i], item.actual_data[i]))
                mismatch = 1'b1;
                break;
            end
        end

        if (mismatch) begin
            fail_count++;
        end else if (item.expected_data.size() > 0) begin
            pass_count++;
            `uvm_info("PAYLOAD_PASS", $sformatf("Data payload verified (%0d bytes matched golden vector)",
                                                item.expected_data.size()), UVM_LOW)
        end
    endfunction

    virtual function void check_tag(rot_seq_item item);
        if (item.actual_tag !== item.expected_tag) begin
            `uvm_error("NIST_TAG_MISMATCH", $sformatf("Expected Tag=0x%032x, Actual Tag=0x%032x",
                                                      item.expected_tag, item.actual_tag))
            fail_count++;
        end else begin
            pass_count++;
            `uvm_info("NIST_TAG_PASS", $sformatf("GCM Tag Verified Against NIST SP 800-38D: 0x%032x", item.actual_tag), UVM_LOW)
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCOREBOARD_SUMMARY", 
                  $sformatf("\n==================================================\n" +
                            "   RoT UVM Scoreboard Verification Summary\n" +
                            "   Total Checks: %0d\n" +
                            "   Passed Checks: %0d\n" +
                            "   Failed Checks: %0d\n" +
                            "   Status: %s\n" +
                            "==================================================",
                            total_checks, pass_count, fail_count,
                            (fail_count == 0) ? "ALL TESTS PASSED" : "FAILED"),
                  UVM_NONE)
    endfunction

endclass

`endif
