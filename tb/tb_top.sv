`timescale 10ns/1ns

module tb_top;
    // Быстрая симуляция: число тактов на один UART-бит
    parameter CLKS_PER_BIT = 4;

    reg clk = 0;
    reg rst_n = 0;
    reg rx = 1;
    wire tx;
    wire pwm_out;

    // Инстанцируем top с переопределённым CLKS_PER_BIT
    top #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_top (
        .clk(clk),
        .rst_n(rst_n),
        .rx(rx),
        .tx(tx),
        .pwm_out(pwm_out)
    );

    // Генератор тактов (25 МГц -> период 40 нс)
    always #20 clk = ~clk;

    // ------------------------------------------------------------
    // Задачи UART-отправки (с быстрым временем)
    // ------------------------------------------------------------
    task send_byte(input [7:0] data);
        integer i;
        #(20);
        rx = 0;                         // start bit
        #(CLKS_PER_BIT * 40);
        for (i = 0; i < 8; i = i + 1) begin
            rx = data[i];
            #(CLKS_PER_BIT * 40);
        end
        rx = 1;                         // stop bit
        #(CLKS_PER_BIT * 40);
    endtask

    // Отправка команды + 3 байта данных (Big‑Endian)
    task send_cmd(input [7:0] cmd, input [23:0] data);
        send_byte(cmd);
        send_byte(data[23:16]);
        send_byte(data[15:8]);
        send_byte(data[7:0]);
    endtask

    // ------------------------------------------------------------
    // Проверка эхо (ждём, пока u_wrapper выставит tx_valid)
    // ------------------------------------------------------------
    task check_echo(input [7:0] expected_cmd);
        integer timeout = 1000;  // максимальное число тактов ожидания
        // Ждём, пока tx_valid станет 1
        while (timeout > 0 && u_top.u_wrapper.tx_valid == 1'b0) begin
            #(40);
            timeout = timeout - 1;
        end
        if (timeout == 0) begin
            $display("ERROR: Echo timeout for cmd 0x%02X", expected_cmd);
            $finish;
        end else begin
            // Читаем байт из u_wrapper (он уже зафиксирован)
            if (u_top.u_wrapper.tx_byte !== expected_cmd) begin
                $display("ERROR: Expected echo 0x%02X, got 0x%02X", 
                         expected_cmd, u_top.u_wrapper.tx_byte);
                $finish;
            end else begin
                $display("Echo OK: 0x%02X", expected_cmd);
            end
        end
        // Ждём, пока tx_valid сбросится (для следующей команды)
        #(CLKS_PER_BIT * 40 * 2);
    endtask

    // ------------------------------------------------------------
    // Основной тест
    // ------------------------------------------------------------
    initial begin
        $dumpfile("build/tb_top.vcd");
        $dumpvars(0, tb_top);

        $display("Starting simulation with CLKS_PER_BIT = %0d", CLKS_PER_BIT);

        // Сброс
        rst_n = 0;
        #100;
        rst_n = 1;
        #100;

        // 1. Установить DIVIDER = 25000
        $display("Send DIVIDER=25000");
        send_cmd(8'h01, 24'd25000);
        check_echo(8'h01);          // ожидаем эхо команды 0x01

        // 2. Установить DUTY = 12500
        $display("Send DUTY=12500");
        send_cmd(8'h02, 24'd12500);
        check_echo(8'h02);

        // 3. Проверка больших значений
        $display("Send DIVIDER=0xABCDEF");
        send_cmd(8'h01, 24'hABCDEF);
        check_echo(8'h01);

        #20000;
        $display("All tests passed!");
        $finish;
    end
endmodule
