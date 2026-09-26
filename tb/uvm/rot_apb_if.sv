`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Hardware Root-of-Trust (RoT) Silicon Lab
// Engineer: Abhijit Karale
// 
// Interface Name: rot_apb_if
// Description: APB4 Bus and RoT Control Interface for UVM verification.
//////////////////////////////////////////////////////////////////////////////////

interface rot_apb_if (input logic pclk, input logic presetn);

    // APB4 Signals
    logic [11:0] paddr;
    logic        psel;
    logic        penable;
    logic        pwrite;
    logic [31:0] pwdata;
    logic [3:0]  pstrb;
    logic        pready;
    logic [31:0] prdata;
    logic        pslverr;

    // Dedicated Physical Pins
    logic        rot_zeroize_pin;
    logic        rot_alarm_out;
    logic        rot_irq_out;

    // Clocking block for driver
    clocking drv_cb @(posedge pclk);
        default input #1ns output #1ns;
        output paddr, psel, penable, pwrite, pwdata, pstrb, rot_zeroize_pin;
        input  pready, prdata, pslverr, rot_alarm_out, rot_irq_out;
    endclocking

    // Clocking block for monitor
    clocking mon_cb @(posedge pclk);
        default input #1ns output #1ns;
        input paddr, psel, penable, pwrite, pwdata, pstrb;
        input pready, prdata, pslverr, rot_zeroize_pin, rot_alarm_out, rot_irq_out;
    endclocking

    modport DRV (clocking drv_cb, input pclk, input presetn);
    modport MON (clocking mon_cb, input pclk, input presetn);

endinterface
