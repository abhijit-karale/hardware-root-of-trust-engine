`ifndef ROT_MONITOR_SV
`define ROT_MONITOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class rot_monitor extends uvm_monitor;
    `uvm_component_utils(rot_monitor)

    virtual rot_apb_if vif;
    uvm_analysis_port #(rot_seq_item) mon_ap;

    function new(string name = "rot_monitor", uvm_component parent = null);
        super.new(name, parent);
        mon_ap = new("mon_ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual rot_apb_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", "Virtual interface rot_apb_if not found in config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            @(vif.mon_cb);
            // Monitor interrupt assertion
            if (vif.mon_cb.rot_irq_out) begin
                `uvm_info(get_type_name(), "Observed RoT Interrupt Asserted (rot_irq_out=1)", UVM_HIGH)
            end
            if (vif.mon_cb.rot_alarm_out) begin
                `uvm_info(get_type_name(), "Observed Physical Security Alarm (rot_alarm_out=1)", UVM_MEDIUM)
            end
        end
    endtask

endclass

`endif
