`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Package Name: rot_uvm_pkg
// Description: UVM 1.2 Package for Hardware Root-of-Trust Verification Suite.
//////////////////////////////////////////////////////////////////////////////////

`ifndef ROT_UVM_PKG_SV
`define ROT_UVM_PKG_SV

package rot_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "rot_seq_item.sv"
    `include "rot_sequencer.sv"
    `include "rot_driver.sv"
    `include "rot_monitor.sv"
    `include "rot_scoreboard.sv"
    `include "rot_coverage.sv"
    `include "rot_agent.sv"
    `include "rot_env.sv"
    `include "rot_test.sv"

endpackage

`endif
