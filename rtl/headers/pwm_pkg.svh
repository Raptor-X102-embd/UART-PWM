`ifndef PWM_PKG
`define PWM_PKG

package pwm_pkg;
    typedef enum logic [7:0] { NOP, W_DIV_REG, W_DUTY_REG } cmd_t;
endpackage

`endif
