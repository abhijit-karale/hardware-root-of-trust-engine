`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Module Name: rot_uvm_tb_top
// Description: UVM 1.2 Top Testbench for Hardware Root-of-Trust Engine.
//              Generates 200 MHz target clock (5.000 ns period) for SkyWater 130nm,
//              instantiates rot_top DUT, binds APB interface, and runs UVM tests.
//////////////////////////////////////////////////////////////////////////////////

import uvm_pkg::*;
`include "uvm_macros.svh"
import rot_uvm_pkg::*;

module rot_uvm_tb_top;

    // 200 MHz Clock Generation (5.000 ns period, 2.500 ns high / 2.500 ns low)
    logic clk;
    logic rst_n;

    initial begin
        clk = 1'b0;
        forever #2.5 clk = ~clk;
    end

    // Reset Generation
    initial begin
        rst_n = 1'b0;
        #20;
        @(posedge clk);
        rst_n = 1'b1;
    end

    // Instantiate APB4 / RoT Interface
    rot_apb_if intf (
        .pclk    (clk),
        .presetn (rst_n)
    );

    // Instantiate DUT: rot_top
    rot_top u_dut (
        .pclk            (intf.pclk),
        .presetn         (intf.presetn),
        .rot_zeroize_pin (intf.rot_zeroize_pin),
        .rot_alarm_out   (intf.rot_alarm_out),
        .rot_irq_out     (intf.rot_irq_out),
        .paddr           (intf.paddr),
        .psel            (intf.psel),
        .penable         (intf.penable),
        .pwrite          (intf.pwrite),
        .pwdata          (intf.pwdata),
        .pstrb           (intf.pstrb),
        .pready          (intf.pready),
        .prdata          (intf.prdata),
        .pslverr         (intf.pslverr)
    );

    // UVM Configuration and Execution
    initial begin
        // Set virtual interface in config_db
        uvm_config_db#(virtual rot_apb_if)::set(null, "*", "vif", intf);

        // Optional VCD/FSDB Waveform Dump
        $dumpfile("rot_uvm_waves.vcd");
        $dumpvars(0, rot_uvm_tb_top);

        // Run UVM Test (Default to NIST KAT Test)
        run_test("rot_nist_kat_test");
    end

endmodule
