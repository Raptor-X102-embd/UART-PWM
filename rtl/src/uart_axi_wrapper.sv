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
    output logic                  bready,
    output logic [9:0] state_led,
    output logic pwm_out
);

    logic [23:0] divider_reg;
    logic [23:0] duty_reg;

    typedef enum logic [4:0] {
        IDLE,
        GOT_CMD,
        GOT_DATA1,
        GOT_DATA2,
       // AXI_AW,
       // AXI_W,
       // AXI_B,
        SEND_CMD,
        WAIT_CMD,
        SEND_DATA1,
        WAIT_DATA1,
        SEND_DATA2,
        WAIT_DATA2,
        SEND_DATA3,
        WAIT_DATA3
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
            divider_reg <= 24'd12_500_000; // ~1 Гц при 25 МГц
            duty_reg    <= 24'd6_250_000;  // 50% скважность
        end else begin
            // Сброс импульсных сигналов по умолчанию
            awvalid <= 1'b0;
            wvalid  <= 1'b0;
            bready  <= 1'b0;
            tx_valid <= 1'b0;

            case (state)
                // ---------- Приём 4 байт ----------
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
                        state <= SEND_CMD;
                       // awvalid <= 1'b1;       // выставляем адрес
                       // awaddr  <= write_addr;
                        
                    end
                end

                // ---------- AXI-запись ----------
          //      AXI_AW: begin
          //          if (awready) begin
          //              awvalid <= 1'b0;       // снимаем после подтверждения
          //              state <= AXI_W;
          //              wvalid <= 1'b1;
          //              wdata  <= write_data;
          //              wstrb  <= 4'b0111;
          //          end
          //      end

          //      AXI_W: begin
          //          if (wready) begin
          //              wvalid <= 1'b0;
          //              state <= AXI_B;
          //              bready <= 1'b1;            // ждём ответ
          //          end
          //      end

          //      AXI_B: begin
          //          if (bvalid) begin
          //              bready <= 1'b0;
          //              state <= SEND_CMD;     // переходим к эхо
          //          end
          //      end

                // ---------- Эхо: отправка 4 байт (SEND/WAIT) ----------
                SEND_CMD: begin
                    wvalid <= 1'b1;
                    wdata  <= write_data;
                    wstrb  <= 4'b1111;

                    tx_valid <= 1'b1;
                    tx_byte  <= cmd_reg;
                    state <= WAIT_CMD;
                end

                WAIT_CMD: begin
                    if (tx_done) state <= SEND_DATA1;
                end

                SEND_DATA1: begin
                    tx_valid <= 1'b1;
                    tx_byte  <= data_1b_reg;
                    state <= WAIT_DATA1;
                end

                WAIT_DATA1: begin
                    if (tx_done) state <= SEND_DATA2;
                end

                SEND_DATA2: begin
                    tx_valid <= 1'b1;
                    tx_byte  <= data_2b_reg;
                    state <= WAIT_DATA2;
                end

                WAIT_DATA2: begin
                    if (tx_done) state <= SEND_DATA3;
                end

                SEND_DATA3: begin
                    tx_valid <= 1'b1;
                    tx_byte  <= data_3b_reg;
                    state <= WAIT_DATA3;
                end

                WAIT_DATA3: begin
                    if (tx_done) state <= IDLE;
                end

                default: state <= IDLE;
            endcase
            
            if (wvalid) begin
                case ((wdata[31:24]))
                    // to be honest, here we need full logic with wstrb check, but
                    // we always write wstrb <= 4'b0111, so it is an optimization
                    // :)
                    W_DIV_REG:  divider_reg <= wdata[23:0];
                    W_DUTY_REG: duty_reg    <= wdata[23:0];
                    default: begin
                        divider_reg <= 24'd1250000; 
                        duty_reg    <= 24'd625000;  // 50% скважность
                    end
                endcase
            end
        end
    end

    // Отладочные светодиоды
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_led <= '0;
        end else begin
            if (state == IDLE)          state_led[0]  <= 1'b1;
            if (state == GOT_CMD)       state_led[1]  <= 1'b1;
            if (state == GOT_DATA1)     state_led[2]  <= 1'b1;
            if (state == GOT_DATA2)     state_led[3]  <= 1'b1;
          //  if (state == AXI_AW)        state_led[4]  <= 1'b1;
          //  if (state == AXI_W)         state_led[4]  <= 1'b1;
          //  if (state == AXI_B)         state_led[5]  <= 1'b1;
            if (state == SEND_CMD)      state_led[6]  <= 1'b1;
            if (state == WAIT_CMD)      state_led[7]  <= 1'b1;
            if (state == SEND_DATA1)    state_led[8]  <= 1'b1;
            if (state == WAIT_DATA1)    state_led[9] <= 1'b1;
        end
    end
    
    logic [23:0] counter;

   always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            counter <= 0;
            pwm_out <= 1'b0;
        end else begin
            if (divider_reg == 0) begin
                pwm_out <= 1'b1;
            end else begin
                if (counter >= divider_reg)
                    counter <= 0;
                else
                    counter <= counter + 1;
                pwm_out <= (counter < duty_reg) ? 1'b1 : 1'b0;
            end
        end
    end
endmodule
