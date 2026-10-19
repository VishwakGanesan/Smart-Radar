// doorbell_top.sv
// Smart Radar Doorbell - top level.
//
// FPGA I/O is 3.3 V. The HC-SR04 runs at 5 V, so TRIG and ECHO pass through
// a BSS138 bidirectional level shifter, and the 5 V buzzer is switched by an
// NPN transistor. See schematics/ for the board-level circuit.

module doorbell_top
  import doorbell_pkg::*;
#(
  parameter int CLK_HZ          = 12_000_000,
  parameter int DEBOUNCE_US     = 10_000,
  parameter int TRIG_US         = 10,
  parameter int GAP_US          = 60_000,
  parameter int ECHO_TIMEOUT_US = 30_000,
  parameter int MIN_ECHO_US     = 116,
  parameter int NEAR_CM         = 100,
  parameter int HITS_REQUIRED   = 3,
  parameter int ALERT_US        = 2_000_000,
  parameter int COOLDOWN_US     = 5_000_000,
  parameter int REFRESH_DIV     = CLK_HZ / 1000
)(
  input  logic       clk,
  input  logic       rst_n,      // active-low reset button
  input  logic       btn_n,      // doorbell button, active-low (pull-up on board)
  input  logic       echo,       // from level shifter (3.3 V side)
  output logic       trig,       // to level shifter (3.3 V side)
  output logic       buzz,       // to NPN buzzer driver base resistor
  output logic       led_alert,  // on while chiming
  output logic [6:0] seg_n,
  output logic       dp_n,
  output logic [3:0] an_n
);

  // ---------------------------------------------------------------- reset
  logic rst;
  sync2 #(.RESET_VAL(1'b1)) u_rst_sync (
    .clk(clk), .rst(1'b0), .d(~rst_n), .q(rst)
  );

  // ---------------------------------------------------------------- timebase
  logic us_tick;
  tick_gen #(.DIV(CLK_HZ / 1_000_000)) u_tick (
    .clk(clk), .rst(rst), .tick(us_tick)
  );

  // ---------------------------------------------------------------- inputs
  logic echo_s, btn_s, press;
  /* verilator lint_off UNUSEDSIGNAL */
  logic btn_level;  // debounced level; reserved for a long-press feature
  /* verilator lint_on UNUSEDSIGNAL */

  sync2 u_echo_sync (.clk(clk), .rst(rst), .d(echo),   .q(echo_s));
  sync2 u_btn_sync  (.clk(clk), .rst(rst), .d(~btn_n), .q(btn_s));

  debounce #(.STABLE_US(DEBOUNCE_US)) u_debounce (
    .clk(clk), .rst(rst), .us_tick(us_tick),
    .din(btn_s), .level(btn_level), .rise(press)
  );

  // ---------------------------------------------------------------- controller
  state_t      state;
  logic        chime_en, dist_valid, alert_by_button;
  logic [15:0] echo_us;

  doorbell_fsm #(
    .TRIG_US        (TRIG_US),
    .GAP_US         (GAP_US),
    .ECHO_TIMEOUT_US(ECHO_TIMEOUT_US),
    .MIN_ECHO_US    (MIN_ECHO_US),
    .NEAR_CM        (NEAR_CM),
    .HITS_REQUIRED  (HITS_REQUIRED),
    .ALERT_US       (ALERT_US),
    .COOLDOWN_US    (COOLDOWN_US)
  ) u_fsm (
    .clk(clk), .rst(rst), .us_tick(us_tick),
    .echo(echo_s), .press(press),
    .state(state), .trig(trig), .chime_en(chime_en),
    .dist_valid(dist_valid), .echo_us(echo_us),
    .alert_by_button(alert_by_button)
  );

  // ---------------------------------------------------------------- display
  logic [13:0] cm;
  logic [3:0]  d3, d2, d1, d0;
  char_t [3:0] chars;

  echo_to_cm u_cm  (.echo_us(echo_us), .cm(cm));
  bin2bcd    u_bcd (.bin(cm), .thousands(d3), .hundreds(d2), .tens(d1), .ones(d0));

  always_comb begin
    if (state == S_ALERT) begin
      chars = alert_by_button ? {C_B, C_E, C_L, C_L}
                              : {C_BLANK, C_BLANK, C_H, C_I};
    end else if (dist_valid) begin
      // distance in cm, right-aligned, leading zeros blanked
      chars[3] = (d3 == 0)                         ? C_BLANK : char_t'(d3);
      chars[2] = (d3 == 0 && d2 == 0)              ? C_BLANK : char_t'(d2);
      chars[1] = (d3 == 0 && d2 == 0 && d1 == 0)   ? C_BLANK : char_t'(d1);
      chars[0] = char_t'(d0);
    end else begin
      chars = {C_DASH, C_DASH, C_DASH, C_DASH};   // nothing in range
    end
  end

  sevenseg_mux #(.REFRESH_DIV(REFRESH_DIV)) u_disp (
    .clk(clk), .rst(rst), .chars(chars), .seg_n(seg_n), .an_n(an_n)
  );
  assign dp_n = 1'b1;

  // ---------------------------------------------------------------- outputs
  chime #(.CLK_HZ(CLK_HZ)) u_chime (
    .clk(clk), .rst(rst), .en(chime_en), .buzz(buzz)
  );
  assign led_alert = chime_en;

endmodule
