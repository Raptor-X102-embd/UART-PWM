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
    input  logic tx_done,
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

    typedef enum logic [4:0] {
        IDLE,
        GOT_CMD,
        GOT_DATA1,
        GOT_DATA2,
        AXI_AW,
        AXI_W,
        AXI_B,
        SEND_CMD,
        SEND_DATA1,
        SEND_DATA2,
        SEND_DATA3
    } state_t;

    state_t state;
    pwm_pkg::cmd_t cmd_reg;
    logic [7:0] data_1b_reg, data_2b_reg, data_3b_reg;
    logic [ADDR_WIDTH-1:0] write_addr;
    logic [DATA_WIDTH-1:0] write_data;

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
            awaddr <= '0;
            wvalid <= 1'b0;
            wdata <= '0;
            wstrb <= 4'b0000;
            bready <= 1'b0;
            tx_valid <= 1'b0;
            tx_byte <= '0;
        end else begin
            awvalid <= 1'b0;
            wvalid  <= 1'b0;
            bready  <= 1'b0;
            tx_valid <= 1'b0;

            case (state)
                IDLE: begin
                    if (rx_valid) begin
                        `ifdef YOSYS
                        cmd_reg <= rx_byte;
                        `else
                        cmd_reg <= cmd_t'(rx_byte);
                        `endif
                        state <= GOT_CMD;
                    end
                end

                GOT_CMD: begin
                    if (rx_valid) begin
                        data_1b_reg <= rx_byte;
                        state <= GOT_DATA1;
                    end
                end

                GOT_DATA1: begin
                    if (rx_valid) begin
                        data_2b_reg <= rx_byte;
                        state <= GOT_DATA2;
                    end
                end

                GOT_DATA2: begin
                    if (rx_valid) begin
                        data_3b_reg <= rx_byte;
                        state <= AXI_AW;
                        awvalid <= 1'b1;
                        awaddr  <= write_addr;
                    end
                end

                // ---------- AXI-write ----------
                AXI_AW: begin
                    if (awready) begin
                        awvalid <= 1'b0;
                        state <= AXI_W;
                        wvalid <= 1'b1;
                        wdata  <= write_data;
                        wstrb  <= 4'b0111;
                    end
                end

                AXI_W: begin
                    if (wready) begin
                        wvalid <= 1'b0;
                        state <= AXI_B;
                        bready <= 1'b1;
                    end
                end

                AXI_B: begin
                    if (bvalid) begin
                        bready <= 1'b0;
                        tx_valid <= 1'b1;
                        tx_byte  <= cmd_reg;
                        state <= SEND_CMD;
                    end
                end

                // ---------- echo ----------
                SEND_CMD: begin
                    if (tx_done) begin 
                        tx_valid <= 1'b1;
                        tx_byte  <= data_1b_reg;
                        state <= SEND_DATA1;
                    end
                end

                SEND_DATA1: begin
                    if (tx_done) begin
                        tx_valid <= 1'b1;
                        tx_byte  <= data_2b_reg;
                        state <= SEND_DATA2;
                    end
                end

                SEND_DATA2: begin
                    if (tx_done) begin
                        tx_valid <= 1'b1;
                        tx_byte  <= data_3b_reg;
                        state <= SEND_DATA3;
                    end
                end

                SEND_DATA3: begin
                    if (tx_done) state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
