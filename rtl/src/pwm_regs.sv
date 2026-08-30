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
    axi4_if.slave bus,
    output logic [23:0] divider_o,
    output logic [23:0] duty_o,
    output logic [2:0] wstate_led
);

    // Registers
    logic [23:0] divider_reg;
    logic [23:0] duty_reg;

    assign divider_o = divider_reg;
    assign duty_o    = duty_reg;

    // Write FSM
    typedef enum logic [1:0] { W_IDLE,/* W_DATA,*/  W_RESP } wstate_t;
   // wstate_t wstate, wstate_next;

   // always_comb begin
   //     case (wstate)
   //         W_IDLE: wstate_next = (bus.WVALID && bus.WREADY) ? W_RESP : W_IDLE;
   //        // W_DATA: wstate_next =  ? W_RESP : W_DATA;
   //         W_RESP: wstate_next = (bus.BREADY) ? W_IDLE : W_RESP;
   //         default: wstate_next = W_IDLE;
   //     endcase
   // end

  //  always_ff @(posedge bus.ACLK or negedge bus.ARESETn) begin
  //      if (!bus.ARESETn) begin
  //          wstate <= W_IDLE;
  //      end else begin
  //          wstate <= wstate_next;
  //      end
  //  end

  //  logic [ADDR_WIDTH-1:0] awaddr;
    logic [DATA_WIDTH-1:0] wdata;

  //  // AW channel
  //  assign bus.AWREADY = (wstate == W_IDLE);
  //  always_ff @(posedge bus.ACLK or negedge bus.ARESETn) begin
  //      if (!bus.ARESETn) begin
  //          awaddr <= '0;
  //      end else if (bus.AWVALID && bus.AWREADY) begin
  //          awaddr <= bus.AWADDR;
  //      end
  //  end

    // W channel
   // assign bus.WREADY = (wstate == W_IDLE);
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
        end else if (bus.WVALID /*&& bus.WREADY*/) begin
            case ((wdata[31:24]))
                // to be honest, here we need full logic with wstrb check, but
                // we always write wstrb <= 4'b0111, so it is an optimization
                // :)
                W_DIV_REG:  divider_reg <= wdata[23:0];
                W_DUTY_REG: duty_reg    <= wdata[23:0];
                default: begin
                    divider_reg <= 24'd0; 
                    duty_reg    <= 24'd625000;  // 50% скважность
                end
            endcase
        end
    end

    // B channel (response)
  //  always_ff @(posedge bus.ACLK or negedge bus.ARESETn) begin
  //      if (!bus.ARESETn) begin
  //          bus.BVALID <= 1'b0;
  //          bus.BRESP  <= OKAY;
  //          bus.BID    <= '0;
  //      end else begin
  //          bus.BVALID <= 1'b1;
  //          if (wstate == W_RESP && bus.BREADY) begin
  //              bus.BVALID <= 1'b1;
  //              bus.BRESP  <= OKAY;
  //              bus.BID    <= '0;
  //          end
  //      end
  //  end

    // Read not supported
    assign bus.ARREADY = 1'b0;
    assign bus.RVALID  = 1'b0;
    assign bus.RDATA   = '0;
    assign bus.RRESP   = DECERR;
    assign bus.RID     = '0;

  // assign wstate_led[0] = wstate == W_IDLE;
  // assign wstate_led[1] = bus.AWREADY;
  // assign wstate_led[2] = bus.WREADY;
   always @(posedge bus.ACLK or negedge bus.ARESETn) begin
        if (!bus.ARESETn) begin
            wstate_led <= '0;
        end else begin
  //          if (wstate == W_IDLE) wstate_led[0]  <= 1'b1;
           // if (wstate == W_DATA) wstate_led[1]  <= 1'b1;
   //         if (wstate == W_RESP) wstate_led[2]  <= 1'b1;
        end
    end 

    

endmodule
