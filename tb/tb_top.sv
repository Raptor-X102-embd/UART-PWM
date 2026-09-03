`timescale 1ns/1ps

module tb_top;
    parameter CLK_FREQ_HZ = 25_000_000;   // 25 MHz
    parameter UART_BAUD   = 9600;         // 9600 baud

    localparam integer CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ_HZ;   // 40 ns
    localparam integer BIT_CLOCKS    = CLK_FREQ_HZ / UART_BAUD;       // 2604
    localparam integer BIT_CLOCKS_SAFE = (BIT_CLOCKS > 0) ? BIT_CLOCKS : 1;

    reg clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    reg rst_n = 0;
    reg rx = 1;
    wire tx;
    wire pwm_out;

    top #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .UART_BAUD(UART_BAUD)
    ) u_top (
        .clk(clk),
        .rst_n(rst_n),
        .rx(rx),
        .tx(tx),
        .pwm_out(pwm_out)
    );

    task send_byte(input [7:0] data);
        integer i;
        rx = 0;
        repeat(BIT_CLOCKS_SAFE) @(posedge clk);
        for (i = 0; i < 8; i = i + 1) begin
            rx = data[i];
            repeat(BIT_CLOCKS_SAFE) @(posedge clk);
        end
        rx = 1;
        repeat(BIT_CLOCKS_SAFE) @(posedge clk);
    endtask

    task send_cmd(input [7:0] cmd, input [23:0] data);
        send_byte(cmd);
        send_byte(data[23:16]);
        send_byte(data[15:8]);
        send_byte(data[7:0]);
    endtask

    task check_echo_4bytes(input [7:0] exp_cmd, input [23:0] exp_data);
        reg [7:0] echo_bytes [0:3];
        integer i;
        logic [7:0] expected [0:3];

        expected[0] = exp_cmd;
        expected[1] = exp_data[23:16];
        expected[2] = exp_data[15:8];
        expected[3] = exp_data[7:0];

        for (i = 0; i < 4; i = i + 1) begin
            @(posedge clk);
            while (u_top.u_wrapper.tx_done == 1'b0) @(posedge clk);
            echo_bytes[i] = u_top.u_wrapper.tx_byte;
            $display("Echo byte %0d: 0x%02X", i, echo_bytes[i]);
            @(posedge clk);
            while (u_top.u_wrapper.tx_valid == 1'b1) @(posedge clk);
        end

        for (i = 0; i < 4; i = i + 1) begin
            if (echo_bytes[i] !== expected[i]) begin
                $display("ERROR: Echo mismatch at byte %0d: expected 0x%02X, got 0x%02X",
                         i, expected[i], echo_bytes[i]);
                $finish;
            end
        end
        $display("Full echo OK: %02X %02X %02X %02X", echo_bytes[0], echo_bytes[1], echo_bytes[2], echo_bytes[3]);
    endtask

    initial begin
        $dumpfile("build/tb_top.vcd");
        $dumpvars(0, tb_top);

        $display("===== Simulation with real hardware parameters =====");
        $display("CLK_FREQ_HZ = %0f", CLK_FREQ_HZ);
        $display("UART_BAUD   = %0f", UART_BAUD);
        $display("CLK_PERIOD  = %0d ns", CLK_PERIOD_NS);
        $display("BIT_CLOCKS  = %0d", BIT_CLOCKS_SAFE);
        $display("===================================================");

        rst_n = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(10) @(posedge clk);

        $display("Send DIVIDER=25000");
        send_cmd(8'h01, 24'd25000);
        check_echo_4bytes(8'h01, 24'd25000);

        $display("Send DUTY=12500");
        send_cmd(8'h02, 24'd12500);
        check_echo_4bytes(8'h02, 24'd12500);

        $display("Send DIVIDER=0xABCDEF");
        send_cmd(8'h01, 24'hABCDEF);
        check_echo_4bytes(8'h01, 24'hABCDEF);

        repeat(1000) @(posedge clk);
        $display("All tests passed!");
        $finish;
    end
endmodule
