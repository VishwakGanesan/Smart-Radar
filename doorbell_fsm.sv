// doorbell_fsm.sv
// Main controller for the Smart Radar Doorbell.
//
//   IDLE ──gap elapsed──▶ TRIGGER ──10 us──▶ MEASURE ──echo done / timeout──▶ IDLE
//                                               │
//                                 HITS_REQUIRED consecutive "near" readings
//                                               ▼
//   (button press from any state but ALERT) ─▶ ALERT ──ALERT_US──▶ COOLDOWN ──COOLDOWN_US──▶ IDLE
//
// All timers count a shared 1 us tick. IDLE->TRIGGER and TRIGGER->MEASURE only
// happen on a tick, so the TRIG pulse is exactly TRIG_US microseconds long and
// the echo timeout is exactly ECHO_TIMEOUT_US. The testbench checks both to
// the clock cycle.
//
// Echo width is measured by counting us ticks while ECHO is high. Any window of
// N us contains exactly N ticks, so the count is exact for whole-us pulses.

module doorbell_fsm
  import doorbell_pkg::*;
#(
  parameter int TRIG_US         = 10,         // HC-SR04 needs >= 10 us
  parameter int GAP_US          = 60_000,     // >= 60 ms between pings
  parameter int ECHO_TIMEOUT_US = 30_000,     // ~5 m round trip
  parameter int MIN_ECHO_US     = 116,        // < 2 cm is below sensor range: noise
  parameter int NEAR_CM         = 100,        // "someone is at the door" threshold
  parameter int HITS_REQUIRED   = 3,          // consecutive near readings to alert
  parameter int ALERT_US        = 2_000_000,  // chime length
  parameter int COOLDOWN_US     = 5_000_000   // ignore proximity after a chime
)(
  input  logic        clk,
  input  logic        rst,
  input  logic        us_tick,
  input  logic        echo,            // synchronized ECHO from the sensor
  input  logic        press,           // one-cycle debounced button press

  output state_t      state,
  output logic        trig,            // registered: glitch-free into the sensor
  output logic        chime_en,        // registered
  output logic        dist_valid,      // last reading was in range
  output logic [15:0] echo_us,         // last valid echo width in us
  output logic        alert_by_button  // 1 = button press, 0 = proximity
);

  localparam int CW      = 24;                     // up to ~16.7 s of us ticks
  localparam int NEAR_US = NEAR_CM * US_PER_CM;    // compare in the us domain
  localparam int HW      = $clog2(HITS_REQUIRED + 1);

  // ------------------------------------------------------------------ state
  state_t        state_n;
  logic [CW-1:0] cnt, cnt_n;          // per-state us counter
  logic [15:0]   echo_cnt, echo_cnt_n;
  logic          echo_q;              // echo delayed one cycle, for edge detect
  logic          echo_seen, echo_seen_n;
  logic [HW-1:0] hits, hits_n;
  logic          dist_valid_n;
  logic [15:0]   echo_us_n;
  logic          by_button_n;

  wire echo_rise = echo & ~echo_q;
  wire echo_fall = ~echo & echo_q;

  // ------------------------------------------------------------------ next state
  always_comb begin
    state_n      = state;
    cnt_n        = cnt;
    echo_cnt_n   = echo_cnt;
    echo_seen_n  = echo_seen;
    hits_n       = hits;
    dist_valid_n = dist_valid;
    echo_us_n    = echo_us;
    by_button_n  = alert_by_button;

    if (press && state != S_ALERT) begin
      // A visitor pressing the button always rings, even mid-measurement
      // or during cooldown.
      state_n     = S_ALERT;
      cnt_n       = '0;
      hits_n      = '0;
      echo_seen_n = 1'b0;
      by_button_n = 1'b1;
    end else begin
      unique case (state)

        S_IDLE: if (us_tick) begin
          if (cnt == CW'(GAP_US - 1)) begin
            state_n = S_TRIGGER;
            cnt_n   = '0;
          end else begin
            cnt_n = cnt + 1'b1;
          end
        end

        S_TRIGGER: if (us_tick) begin
          if (cnt == CW'(TRIG_US - 1)) begin
            state_n     = S_MEASURE;
            cnt_n       = '0;
            echo_cnt_n  = '0;
            echo_seen_n = 1'b0;
          end else begin
            cnt_n = cnt + 1'b1;
          end
        end

        S_MEASURE: begin
          // Count us ticks while ECHO is high. The rising-edge cycle counts
          // too, otherwise a tick landing on that exact cycle would be lost.
          if (echo_rise && !echo_seen) begin
            echo_seen_n = 1'b1;
            echo_cnt_n  = us_tick ? 16'd1 : 16'd0;
          end else if (echo_seen && echo && us_tick) begin
            echo_cnt_n = echo_cnt + 1'b1;
          end

          if (echo_seen && echo_fall) begin
            // ---- echo finished: evaluate the reading
            state_n     = S_IDLE;
            cnt_n       = '0;
            echo_seen_n = 1'b0;
            if (echo_cnt < 16'(MIN_ECHO_US)) begin
              hits_n = '0;                         // glitch: ignore, keep display
            end else begin
              dist_valid_n = 1'b1;
              echo_us_n    = echo_cnt;
              if (echo_cnt < 16'(NEAR_US)) begin
                if (hits == HW'(HITS_REQUIRED - 1)) begin
                  state_n     = S_ALERT;
                  hits_n      = '0;
                  by_button_n = 1'b0;
                end else begin
                  hits_n = hits + 1'b1;
                end
              end else begin
                hits_n = '0;
              end
            end
          end else if (us_tick) begin
            if (cnt == CW'(ECHO_TIMEOUT_US - 1)) begin
              // ---- no echo, or echo longer than range: nothing there
              state_n      = S_IDLE;
              cnt_n        = '0;
              echo_seen_n  = 1'b0;
              hits_n       = '0;
              dist_valid_n = 1'b0;
            end else begin
              cnt_n = cnt + 1'b1;
            end
          end
        end

        S_ALERT: if (us_tick) begin
          if (cnt == CW'(ALERT_US - 1)) begin
            state_n = S_COOLDOWN;
            cnt_n   = '0;
          end else begin
            cnt_n = cnt + 1'b1;
          end
        end

        S_COOLDOWN: if (us_tick) begin
          if (cnt == CW'(COOLDOWN_US - 1)) begin
            state_n = S_IDLE;
            cnt_n   = '0;
          end else begin
            cnt_n = cnt + 1'b1;
          end
        end

        default: begin
          state_n = S_IDLE;
          cnt_n   = '0;
        end
      endcase
    end
  end

  // ------------------------------------------------------------------ registers
  always_ff @(posedge clk) begin
    if (rst) begin
      state           <= S_IDLE;
      cnt             <= '0;
      echo_cnt        <= '0;
      echo_q          <= 1'b0;
      echo_seen       <= 1'b0;
      hits            <= '0;
      dist_valid      <= 1'b0;
      echo_us         <= '0;
      alert_by_button <= 1'b0;
      trig            <= 1'b0;
      chime_en        <= 1'b0;
    end else begin
      state           <= state_n;
      cnt             <= cnt_n;
      echo_cnt        <= echo_cnt_n;
      echo_q          <= echo;
      echo_seen       <= echo_seen_n;
      hits            <= hits_n;
      dist_valid      <= dist_valid_n;
      echo_us         <= echo_us_n;
      alert_by_button <= by_button_n;
      // Outputs are decoded from the *next* state and registered, so they
      // line up with `state` exactly and never glitch.
      trig            <= (state_n == S_TRIGGER);
      chime_en        <= (state_n == S_ALERT);
    end
  end

endmodule
