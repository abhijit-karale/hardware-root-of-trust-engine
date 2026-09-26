`ifndef ROT_SEQUENCER_SV
`define ROT_SEQUENCER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class rot_sequencer extends uvm_sequencer #(rot_seq_item);
    `uvm_component_utils(rot_sequencer)

    function new(string name = "rot_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass

`endif
