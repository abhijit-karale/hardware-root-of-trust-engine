`ifndef ROT_AGENT_SV
`define ROT_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class rot_agent extends uvm_agent;
    `uvm_component_utils(rot_agent)

    rot_sequencer sequencer;
    rot_driver    driver;
    rot_monitor   monitor;

    function new(string name = "rot_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = rot_monitor::type_id::create("monitor", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sequencer = rot_sequencer::type_id::create("sequencer", this);
            driver    = rot_driver::type_id::create("driver", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass

`endif
