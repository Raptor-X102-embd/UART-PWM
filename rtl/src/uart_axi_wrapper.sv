`include "pwm_pkg.svh"

import pwm_pkg::*;

module uart_axi_wrapper #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter UART_CMD_DATA_ADDR = 32'h8
)(
    input  logic clk,
    input  logic rst_n,

    input  logic rx_valid,
    input  logic [7:0] rx_byte,

    output logic tx_valid,
    output logic [7:0] tx_byte,
    input  logic tx_ready,

    output logic [ADDR_WIDTH-1:0] awaddr,
    output logic                  awvalid,
    input  logic                  awready,
    output logic [DATA_WIDTH-1:0] wdata,
    output logic                  wvalid,
    input  logic                  wready,
    output logic [DATA_WIDTH/8-1:0] wstrb,
    input  logic                  bvalid,
    output logic                  bready
);

    typedef enum logic [2:0] {
        IDLE,
        GOT_CMD,
        GOT_DATA_1B,
        GOT_DATA_2B,
        WAIT_AW_READY,
        WAIT_W_READY,
        WAIT_B_RESP
    } state_t;

    state_t state, next_state;
    pwm_pkg::cmd_t cmd_reg;
    logic [7:0] data_1b_reg, data_2b_reg, data_3b_reg;
    logic [ADDR_WIDTH-1:0] write_addr;
    logic [DATA_WIDTH-1:0] write_data;

    always_comb begin
        case (state)
            IDLE:          next_state = rx_valid ? GOT_CMD       : IDLE;
            GOT_CMD:       next_state = rx_valid ? GOT_DATA_1B   : GOT_CMD;
            GOT_DATA_1B:   next_state = rx_valid ? GOT_DATA_2B   : GOT_DATA_1B;
            GOT_DATA_2B:   next_state = rx_valid ? WAIT_AW_READY : GOT_DATA_2B;
            WAIT_AW_READY: next_state = awready  ? WAIT_W_READY  : WAIT_AW_READY;
            WAIT_W_READY:  next_state = wready   ? WAIT_B_RESP   : WAIT_W_READY;
            WAIT_B_RESP:   next_state = bvalid   ? IDLE          : WAIT_B_RESP;
            default:       next_state = IDLE;
        endcase
    end

    assign write_data = {cmd_reg, data_1b_reg, data_2b_reg, data_3b_reg};
    assign write_addr = UART_CMD_DATA_ADDR;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            cmd_reg <= NOP;
            data_1b_reg <= '0;
            data_2b_reg <= '0;
            data_3b_reg <= '0;
            awvalid <= 1'b0;
            awaddr <= {ADDR_WIDTH{1'b0}};
            wvalid <= 1'b0;
            bready <= 1'b0;
            tx_valid <= 1'b0;
            tx_byte <= '0;
        end else begin
            // Defaults
            awvalid <= 1'b0;
            wvalid <= 1'b0;
            tx_valid <= 1'b0;
            state <= next_state;

            case (state)
                IDLE: begin
                    if (rx_valid) begin
                    `ifdef YOSYS
                        cmd_reg <= rx_byte;
                    `else
                        cmd_reg <= cmd_t'(rx_byte);
                    `endif                    
                    end
                end

                GOT_CMD: begin
                    if (rx_valid) begin
                        data_1b_reg <= rx_byte;
                    end
                end

                GOT_DATA_1B: begin
                    if (rx_valid) begin
                        data_2b_reg <= rx_byte;
                    end
                end

                GOT_DATA_2B: begin
                    if (rx_valid) begin
                        data_3b_reg <= rx_byte;
                    end
                end

                WAIT_AW_READY: begin
                    if (awready) begin
                        awvalid <= 1'b1;
                        awaddr  <= write_addr;
                    end
                end

                WAIT_W_READY: begin
                    if (wready) begin
                        awvalid <= 1'b0;
                        wvalid  <= 1'b1;
                        wdata   <= write_data;
                        wstrb   <= 4'b0111;
                        bready <= 1'b1;
                    end
                end

                WAIT_B_RESP: begin
                    if (bvalid) begin
                        bready <= 1'b0;
                        // echo
                        tx_valid <= 1'b1;
                        tx_byte <= cmd_reg;
                    end
                end
            endcase
        end
    end

endmodule
