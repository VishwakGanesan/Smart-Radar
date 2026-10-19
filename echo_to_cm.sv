// echo_to_cm.sv
// distance_cm = echo_us / 58, without a divider.
// 65536 / 58 = 1129.93, so cm = (echo_us * 1130) >> 16.
// Exact for every whole-centimetre echo below 16384 cm: n*58*1130 = n*65540,
// and n*65540 >> 16 = n while n*4 < 65536.

module echo_to_cm (
  input  logic [15:0] echo_us,
  output logic [13:0] cm
);

  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] scaled;   // only [29:16] is the result; low bits are the fraction
  /* verilator lint_on UNUSEDSIGNAL */

  assign scaled = {16'd0, echo_us} * 32'd1130;
  assign cm     = scaled[29:16];

endmodule
