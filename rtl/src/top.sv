`include "axi4_if.svh"
`include "axi4_pkg.svh"
`include "pwm_pkg.svh"

module top #(
    parameter CLK_FREQ_HZ = 25_000_000,
    parameter UART_BAUD   = 9600,
    parameter CLKS_PER_BIT = CLK_FREQ_HZ / UART_BAUD
)(
    input  logic clk,
    input  logic rst_n,
    input  logic rx,
    output logic tx,
    output logic [9:0] state_led,
    output logic [2:0] wstate_led,
    //output logic [3:0] rx_valid_led,
    //output logic [3:0] tx_done_led,
    output logic pwm_out
);

    //localparam CLKS_PER_BIT = CLK_FREQ_HZ / UART_BAUD; // 217

    // Parameters
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam ID_WIDTH   = 4;
    localparam USER_WIDTH = 0;

    // AXI bus
    axi4_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .USER_WIDTH(USER_WIDTH)
    ) bus (
        .ACLK(clk),
        .ARESETn(rst_n)
    );

    // UART signals
    logic rx_valid, tx_valid;
    logic [7:0] rx_byte, tx_byte;
    logic tx_active;
    logic tx_done;

    UART_RX #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart_rx (
        .i_Rst_L(rst_n),
        .i_Clock(clk),
        .i_RX_Serial(rx),
        .o_RX_DV(rx_valid),
        .o_RX_Byte(rx_byte)
    );

    UART_TX #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart_tx (
        .i_Rst_L(rst_n),
        .i_Clock(clk),
        .i_TX_DV(tx_valid),
        .i_TX_Byte(tx_byte),
        .o_TX_Active(tx_active),
        .o_TX_Serial(tx),
        .o_TX_Done(tx_done)
    );

    //assign tx_ready = ~tx_active;

    // AXI write master (wrapper)
    uart_axi_wrapper #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_wrapper (
        .clk(clk),
        .rst_n(rst_n),
        .rx_valid(rx_valid),
        .rx_byte(rx_byte),
        .tx_valid(tx_valid),
        .tx_byte(tx_byte),
        //.tx_ready(tx_ready),
        .tx_done(tx_done),
        // AXI
        .awaddr(bus.AWADDR),
        .awvalid(bus.AWVALID),
        .awready(bus.AWREADY),
        .wdata(bus.WDATA),
        .wvalid(bus.WVALID),
        .wready(bus.WREADY),
        .wstrb(bus.WSTRB),
        .bvalid(bus.BVALID),
        .bready(bus.BREADY),
        .state_led(state_led),
        .pwm_out(pwm_out)
        //.rx_valid_led(rx_valid_led),
        //.tx_done_led(tx_done_led)
    );

    // PWM registers (AXI-Lite slave)
//    logic [23:0] divider, duty;
//    pwm_regs #(
//        .ADDR_WIDTH(ADDR_WIDTH),
//        .DATA_WIDTH(DATA_WIDTH),
//        .ID_WIDTH(ID_WIDTH)
//    ) u_pwm_regs (
//        .bus(bus),
//        .divider_o(divider),
//        .duty_o(duty),
//        .wstate_led(wstate_led)
//    );

   // // PWM generator
   // pwm_generator #(.WIDTH(24)) u_pwm (
   //     .clk(clk),
   //     .rst_n(rst_n),
   //     .divider_i(divider),
   //     .duty_i(duty),
   //     .pwm_out(pwm_out)
   // );

endmodule
