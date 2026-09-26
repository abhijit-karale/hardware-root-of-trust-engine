`ifndef ROT_ENV_SV
`define ROT_ENV_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class rot_env extends uvm_env;
    `uvm_component_utils(rot_env)

    rot_agent      agent;
    rot_scoreboard scoreboard;
    rot_coverage   coverage;

    function new(string name = "rot_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = rot_agent::type_id::create("agent", this);
        scoreboard = rot_scoreboard::type_id::create("scoreboard", this);
        coverage   = rot_coverage::type_id::create("coverage", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.mon_ap.connect(scoreboard.sb_export);
        agent.monitor.mon_ap.connect(coverage.analysis_export);
    endfunction

endclass

`endif
