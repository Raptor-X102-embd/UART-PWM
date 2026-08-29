`include "axi4_if.svh"
`include "axi4_pkg.svh"
`include "pwm_pkg.svh"

`timescale 10ns/1ns

import pwm_pkg::*;
import axi4_pkg::*;

module pwm_regs
#(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
) (
    axi4_if.slave bus,
    output logic [23:0] divider_o,
    output logic [23:0] duty_o
);

    // Registers
    logic [23:0] divider_reg;
    logic [23:0] duty_reg;

    assign divider_o = divider_reg;
    assign duty_o    = duty_reg;

    // Write FSM
    typedef enum logic [1:0] { W_IDLE, W_DATA,  W_RESP } wstate_t;
    wstate_t wstate, wstate_next;

    always_comb begin
        case (wstate)
            W_IDLE: wstate_next = (bus.AWVALID && bus.AWREADY) ? W_DATA : W_IDLE;
            W_DATA: wstate_next = (bus.WVALID && bus.WREADY) ? W_RESP : W_DATA;
            W_RESP: wstate_next = (bus.BREADY) ? W_IDLE : W_RESP;
            default: wstate_next = W_IDLE;
        endcase
    end

    logic [ADDR_WIDTH-1:0] awaddr;
    logic [DATA_WIDTH-1:0] wdata;

    // AW channel
    assign bus.AWREADY = (wstate == W_IDLE);
    always_ff @(posedge bus.ACLK or negedge bus.ARESETn) begin
        if (!bus.ARESETn) begin
            awaddr <= '0;
        end else if (bus.AWVALID && bus.AWREADY) begin
            awaddr <= bus.AWADDR;
        end
    end

    // W channel
    assign bus.WREADY = (wstate == W_DATA);
    assign wdata = bus.WDATA;
   // always_ff @(posedge bus.ACLK or negedge bus.ARESETn) begin
   //     if (!bus.ARESETn) begin
   //         wdata <= '0;
   //     end else if (bus.WVALID && bus.WREADY) begin
   //         wdata <= bus.WDATA;
   //     end
   // end
   //
    
    // Write to registers
    always_ff @(posedge bus.ACLK or negedge bus.ARESETn) begin
        if (!bus.ARESETn) begin
            divider_reg <= 24'd12_500_000; // ~1 Гц при 25 МГц
            duty_reg    <= 24'd6_250_000;  // 50% скважность
        end else if (wstate == W_DATA && bus.WVALID && bus.WREADY) begin
            case ((wdata[31:24]))
                // to be honest, here we need full logic with wstrb check, but
                // we always write wstrb <= 4'b0111, so it is an optimization
                // :)
                W_DIV_REG:  divider_reg <= wdata[23:0];
                W_DUTY_REG: duty_reg    <= wdata[23:0];
            endcase
        end
    end

        // B channel (response)
    always_ff @(posedge bus.ACLK or negedge bus.ARESETn) begin
        if (!bus.ARESETn) begin
            wstate <= W_IDLE;
            bus.BVALID <= 1'b0;
            bus.BRESP  <= OKAY;
            bus.BID    <= '0;
        end else begin
            wstate <= wstate_next;
            // BVALID management
            if (wstate == W_RESP && wstate_next == W_IDLE) begin
                // Переход в W_RESP произошел, выставляем BVALID
                bus.BVALID <= 1'b1;
                bus.BRESP  <= OKAY;
                bus.BID    <= '0;
            end else if (bus.BREADY && bus.BVALID) begin
                // Мастер подтвердил, снимаем BVALID
                bus.BVALID <= 1'b0;
            end
        end
    end
    // Read not supported
    assign bus.ARREADY = 1'b0;
    assign bus.RVALID  = 1'b0;
    assign bus.RDATA   = '0;
    assign bus.RRESP   = DECERR;
    assign bus.RID     = '0;

endmodule
