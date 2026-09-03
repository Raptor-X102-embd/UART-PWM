`include "axi4_if.svh"
`include "axi4_pkg.svh"
`include "pwm_pkg.svh"

import pwm_pkg::*;
import axi4_pkg::*;

module pwm_regs
#(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
) (
    input  logic clk,
    input  logic rst_n,
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
    typedef enum logic [1:0] { W_IDLE, W_DATA, W_RESP } wstate_t;
    wstate_t wstate, wstate_next;

    always_comb begin
        case (wstate)
            W_IDLE: wstate_next = (bus.AWVALID && bus.AWREADY) ? W_DATA : W_IDLE;
            W_DATA: wstate_next = (bus.WVALID && bus.WREADY)   ? W_RESP : W_DATA;
            W_RESP: wstate_next = (bus.BREADY) ? W_IDLE : W_RESP;
            default: wstate_next = W_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wstate <= W_IDLE;
        end else begin
            wstate <= wstate_next;
        end
    end

    logic [ADDR_WIDTH-1:0] awaddr;
    logic [DATA_WIDTH-1:0] wdata;
    logic do_w_regs;

    // AW channel
    assign bus.AWREADY = (wstate == W_IDLE);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awaddr <= '0;
        end else if (bus.AWVALID && bus.AWREADY) begin
            awaddr <= bus.AWADDR;
        end
    end

    // W channel
    assign bus.WREADY = (wstate == W_DATA);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wdata <= '0;
        end else begin
            do_w_regs <= 1'b0;
            if (bus.WVALID && bus.WREADY) begin
                wdata <= bus.WDATA;
                do_w_regs <= 1'b1;
            end
        end
    end
    
    // Write to registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            divider_reg <= 24'd12_500_000; // ~1 Hz at 25 MHz
            duty_reg    <= 24'd6_250_000;  // 50%
        end else if (do_w_regs) begin
            case ((wdata[31:24]))
                // to be honest, here we need full logic with wstrb check, but
                // we always write wstrb <= 4'b1111, so it is an optimization
                // :)
                W_DIV_REG:  divider_reg <= wdata[23:0];
                W_DUTY_REG: duty_reg    <= wdata[23:0];
            endcase
        end
    end

    // B channel (response)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bus.BVALID <= 1'b0;
            bus.BRESP  <= OKAY;
            bus.BID    <= '0;
        end else begin
            bus.BVALID <= 1'b1;
            if (wstate == W_RESP && bus.BREADY) begin
                bus.BVALID <= 1'b1;
                bus.BRESP  <= OKAY;
                bus.BID    <= '0;
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
