// doorbell_pkg.sv
// Shared types for the Smart Radar Doorbell.

package doorbell_pkg;

  // Controller states (5-state FSM)
  typedef enum logic [2:0] {
    S_IDLE     = 3'd0,  // waiting out the gap between ultrasonic pings
    S_TRIGGER  = 3'd1,  // driving the 10 us TRIG pulse to the sensor
    S_MEASURE  = 3'd2,  // timing the ECHO pulse width (or timing out)
    S_ALERT    = 3'd3,  // chime on, display shows HI / bELL
    S_COOLDOWN = 3'd4   // detection suppressed so one visitor = one chime
  } state_t;

  // Characters the seven-segment display can show
  typedef enum logic [4:0] {
    C_0 = 5'd0, C_1 = 5'd1, C_2 = 5'd2, C_3 = 5'd3, C_4 = 5'd4,
    C_5 = 5'd5, C_6 = 5'd6, C_7 = 5'd7, C_8 = 5'd8, C_9 = 5'd9,
    C_BLANK = 5'd10,
    C_DASH  = 5'd11,
    C_H     = 5'd12,
    C_I     = 5'd13,
    C_B     = 5'd14,  // lower-case b
    C_E     = 5'd15,
    C_L     = 5'd16
  } char_t;

  // HC-SR04: distance_cm = echo_us / 58
  localparam int US_PER_CM = 58;

endpackage
