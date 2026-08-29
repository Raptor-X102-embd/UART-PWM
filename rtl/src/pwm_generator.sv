module pwm_generator #(
    parameter WIDTH = 24
)(
    input  logic clk,
    input  logic rst_n,
    input  logic [WIDTH-1:0] divider_i,
    input  logic [WIDTH-1:0] duty_i,
    output logic pwm_out
);

    logic [WIDTH-1:0] counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            pwm_out <= 1'b0;
        end else begin
            if (divider_i == 0) begin
                pwm_out <= 1'b1;
            end else begin
                if (counter >= divider_i)
                    counter <= 0;
                else
                    counter <= counter + 1;
                pwm_out <= (counter < duty_i) ? 1'b1 : 1'b0;
            end
        end
    end

endmodule
