// tb_doorbell.sv
// Self-checking testbench for doorbell_top. 16 directed test cases.
//
// Includes a behavioral HC-SR04 model: on each falling edge of TRIG it waits
// SNS_DELAY_US, then drives ECHO high for the configured width (58 us per cm).
//
// Timing checks are cycle-exact where the design guarantees it (TRIG width,
// echo timeout, cooldown) and +/-1 us where an event is not aligned to the
// 1 us tick (e.g. ALERT entered on an echo edge).
//
// Run:  make sim        (Verilator --binary --timing)
//       make wave       (same, plus waves.vcd for GTKWave)

// Timescale (1ns/1ps) is set on the Verilator command line (see Makefile).

module tb_doorbell;
  import doorbell_pkg::*;

  // ---------------------------------------------------------------- config
  // Sim clock is 4 MHz (4 cycles per us) so long timers finish quickly while
  // still exercising tick alignment. Long hardware timers are scaled down.
  localparam int CLK_HZ          = 4_000_000;
  localparam int P               = CLK_HZ / 1_000_000;  // cycles per us
  localparam int TRIG_US         = 10;
  localparam int GAP_US          = 2_000;
  localparam int ECHO_TIMEOUT_US = 30_000;
  localparam int MIN_ECHO_US     = 116;
  localparam int NEAR_CM         = 100;
  localparam int HITS_REQUIRED   = 3;
  localparam int ALERT_US        = 20_000;
  localparam int COOLDOWN_US     = 40_000;
  localparam int DEBOUNCE_US     = 2_000;
  localparam int SNS_DELAY_US    = 200;   // HC-SR04 burst time before ECHO rises
  localparam int SNS_STUCK_US    = 38_000; // HC-SR04 "nothing in range" pulse

  // ---------------------------------------------------------------- DUT
  logic       clk = 1'b0;
  logic       rst_n = 1'b0;
  logic       btn_n = 1'b1;
  logic       echo  = 1'b0;
  logic       trig, buzz, led_alert, dp_n;
  logic [6:0] seg_n;
  logic [3:0] an_n;

  always #125 clk = ~clk;  // 4 MHz

  doorbell_top #(
    .CLK_HZ         (CLK_HZ),
    .DEBOUNCE_US    (DEBOUNCE_US),
    .TRIG_US        (TRIG_US),
    .GAP_US         (GAP_US),
    .ECHO_TIMEOUT_US(ECHO_TIMEOUT_US),
    .MIN_ECHO_US    (MIN_ECHO_US),
    .NEAR_CM        (NEAR_CM),
    .HITS_REQUIRED  (HITS_REQUIRED),
    .ALERT_US       (ALERT_US),
    .COOLDOWN_US    (COOLDOWN_US),
    .REFRESH_DIV    (100)
  ) dut (
    .clk(clk), .rst_n(rst_n), .btn_n(btn_n), .echo(echo),
    .trig(trig), .buzz(buzz), .led_alert(led_alert),
    .seg_n(seg_n), .dp_n(dp_n), .an_n(an_n)
  );

`ifdef TRACE
  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb_doorbell);
  end
`endif

  // ---------------------------------------------------------------- HC-SR04 model
  typedef enum int { SNS_SILENT, SNS_ECHO, SNS_STUCK } sns_mode_t;

  sns_mode_t sns_mode    = SNS_SILENT;
  int        sns_echo_us = 0;
  int        sns_resp    = 0;

  // Each response is shifted by a different sub-microsecond phase (0..P-1
  // cycles) so ECHO edges land at every alignment relative to the 1 us tick,
  // including the cycle the tick fires on.
  initial forever begin
    int w;
    @(negedge trig);
    if (sns_mode != SNS_SILENT) begin
      w = (sns_mode == SNS_STUCK) ? SNS_STUCK_US : sns_echo_us;
      repeat (SNS_DELAY_US * P + (sns_resp % P)) @(posedge clk);
      sns_resp++;
      echo <= 1'b1;
      repeat (w * P) @(posedge clk);
      echo <= 1'b0;
    end
  end

  // ---------------------------------------------------------------- monitors
  longint cyc = 0;
  logic   trig_d = 1'b0;
  logic   buzz_d = 1'b0;
  state_t state_d = S_IDLE;
  longint trig_rise_cyc = 0, trig_fall_cyc = 0;
  longint entry_cyc [5];          // cycle each state was last entered
  int     trig_rises = 0;
  int     alert_entries = 0;
  int     buzz_edges = 0;
  state_t state_before_alert = S_IDLE;

  initial for (int i = 0; i < 5; i++) entry_cyc[i] = 0;

  always @(posedge clk) begin
    cyc    <= cyc + 1;
    trig_d <= trig;
    buzz_d <= buzz;
    if (trig && !trig_d) begin
      trig_rise_cyc <= cyc;
      trig_rises    <= trig_rises + 1;
    end
    if (!trig && trig_d) trig_fall_cyc <= cyc;
    if (buzz != buzz_d)  buzz_edges <= buzz_edges + 1;

    state_d <= dut.state;
    if (dut.state != state_d) begin
      entry_cyc[dut.state] <= cyc;
      if (dut.state == S_ALERT) begin
        alert_entries      <= alert_entries + 1;
        state_before_alert <= state_d;
      end
    end
  end

  // ---------------------------------------------------------------- helpers
  int    errors = 0, passed = 0, test_num = 0, errs_at_start = 0;
  string cur_name;

  task automatic begin_test(input string name);
    test_num++;
    cur_name      = name;
    errs_at_start = errors;
  endtask

  task automatic end_test();
    if (errors == errs_at_start) begin
      passed++;
      $display("[PASS] T%02d  %s", test_num, cur_name);
    end else begin
      $display("[FAIL] T%02d  %s", test_num, cur_name);
    end
  endtask

  task automatic check(input bit cond, input string what);
    if (!cond) begin
      errors++;
      $display("        x %s", what);
    end
  endtask

  task automatic wait_cycles(input int n);
    repeat (n) @(posedge clk);
  endtask

  task automatic wait_us(input int n);
    repeat (n * P) @(posedge clk);
  endtask

  task automatic wait_state(input state_t s);
    int i = 0;
    while (dut.state != s) begin
      @(posedge clk);
      i++;
      if (i > 400_000 * P) $fatal(1, "timeout waiting for state %s", s.name());
    end
  endtask

  task automatic wait_leave(input state_t s);
    int i = 0;
    while (dut.state == s) begin
      @(posedge clk);
      i++;
      if (i > 400_000 * P) $fatal(1, "timeout waiting to leave %s", s.name());
    end
  endtask

  // One full ultrasonic measurement with the sensor configured as given.
  // Waits for any in-flight measurement to finish first so the new setting
  // applies to a fresh ping.
  task automatic ping(input sns_mode_t mode, input int echo_us);
    if (dut.state == S_TRIGGER || dut.state == S_MEASURE) wait_state(S_IDLE);
    sns_mode    = mode;
    sns_echo_us = echo_us;
    wait_state(S_TRIGGER);
    wait_leave(S_TRIGGER);
    wait_leave(S_MEASURE);
    wait_cycles(4);
  endtask

  function automatic string disp_str(input char_t [3:0] d);
    string s = "";
    for (int i = 3; i >= 0; i--) begin
      case (d[i])
        C_BLANK: s = {s, " "};
        C_DASH:  s = {s, "-"};
        C_H:     s = {s, "H"};
        C_I:     s = {s, "I"};
        C_B:     s = {s, "b"};
        C_E:     s = {s, "E"};
        C_L:     s = {s, "L"};
        default: s = {s, $sformatf("%0d", int'(d[i]))};
      endcase
    end
    return s;
  endfunction

  task automatic check_disp(input string expected);
    string got = disp_str(dut.chars);
    check(got == expected, $sformatf("display \"%s\", expected \"%s\"", got, expected));
  endtask

  task automatic press_button(input int hold_us);
    btn_n <= 1'b0;
    wait_us(hold_us);
    btn_n <= 1'b1;
  endtask

  // ---------------------------------------------------------------- tests
  initial begin
    longint idle_entry, d, press_cyc;
    int     rises_before, alerts_before, buzz_before;

    $display("Smart Radar Doorbell - directed tests");
    $display("--------------------------------------");

    rst_n <= 1'b0;
    wait_cycles(20);
    rst_n <= 1'b1;
    wait_cycles(8);

    // ---- T01
    begin_test("Reset: IDLE, outputs low, display '----'");
    check(dut.state == S_IDLE, "state should be IDLE");
    check(trig == 1'b0 && buzz == 1'b0 && led_alert == 1'b0, "outputs should be low");
    check(dut.dist_valid == 1'b0, "no valid distance yet");
    check_disp("----");
    end_test();

    // ---- T02
    begin_test("TRIG pulse is exactly 10 us (cycle-exact)");
    sns_mode    = SNS_ECHO;
    sns_echo_us = 200 * 58;
    wait_state(S_TRIGGER);
    wait_leave(S_TRIGGER);
    wait_cycles(3);
    d = trig_fall_cyc - trig_rise_cyc;
    check(d == TRIG_US * P,
          $sformatf("TRIG high %0d cycles, expected %0d", d, TRIG_US * P));
    end_test();

    // ---- T03
    begin_test("Far object (200 cm): distance latched and shown, no alert");
    wait_leave(S_MEASURE);
    wait_cycles(4);
    check(dut.state == S_IDLE, "back to IDLE");
    check(dut.dist_valid == 1'b1, "distance valid");
    check(dut.u_fsm.hits == 0, "not counted as near");
    check(alert_entries == 0, "no alert");
    check_disp(" 200");
    end_test();

    // ---- T04
    begin_test("Next ping starts GAP_US after the last reading (+/-1 us)");
    idle_entry = entry_cyc[S_IDLE];
    ping(SNS_ECHO, 150 * 58);
    d = trig_rise_cyc - idle_entry;
    check(d >= longint'((GAP_US - 1) * P + 1) && d <= longint'(GAP_US * P),
          $sformatf("gap %0d cycles, expected %0d..%0d", d, (GAP_US - 1) * P + 1, GAP_US * P));
    check_disp(" 150");
    end_test();

    // ---- T05
    begin_test("5800 us echo converts to exactly 100 cm; 100 cm is not 'near'");
    ping(SNS_ECHO, 100 * 58);
    check_disp(" 100");
    check(dut.u_fsm.hits == 0, "100 cm must not count (threshold is < 100)");
    end_test();

    // ---- T06
    begin_test("99 cm counts as a near hit but does not alert on its own");
    ping(SNS_ECHO, 99 * 58);
    check_disp("  99");
    check(dut.u_fsm.hits == 1, $sformatf("hits = %0d, expected 1", dut.u_fsm.hits));
    check(dut.state == S_IDLE && alert_entries == 0, "no alert yet");
    end_test();

    // ---- T07
    begin_test("Near hits must be consecutive: near, near, far -> no alert");
    ping(SNS_ECHO, 99 * 58);
    check(dut.u_fsm.hits == 2, $sformatf("hits = %0d, expected 2", dut.u_fsm.hits));
    ping(SNS_ECHO, 150 * 58);
    check(dut.u_fsm.hits == 0, "far reading must clear the hit count");
    check(alert_entries == 0, "no alert");
    end_test();

    // ---- T08
    begin_test("Three consecutive near readings -> ALERT, display '  HI', chime on");
    ping(SNS_ECHO, 60 * 58);
    ping(SNS_ECHO, 60 * 58);
    check(dut.state == S_IDLE, "still IDLE after 2 hits");
    ping(SNS_ECHO, 60 * 58);
    check(dut.state == S_ALERT, "ALERT after 3rd hit");
    check(alert_entries == 1, "exactly one alert");
    check(led_alert == 1'b1, "alert LED on");
    check(dut.alert_by_button == 1'b0, "source should be proximity");
    check_disp("  HI");
    buzz_before = buzz_edges;
    wait_us(3_000);
    check(buzz_edges - buzz_before >= 4, "buzzer should be toggling");
    end_test();

    // ---- T09
    begin_test("ALERT lasts ALERT_US (+/-1 us), then chime stops");
    wait_state(S_COOLDOWN);
    wait_cycles(4);
    d = entry_cyc[S_COOLDOWN] - entry_cyc[S_ALERT];
    check(d >= longint'((ALERT_US - 1) * P + 1) && d <= longint'(ALERT_US * P),
          $sformatf("ALERT lasted %0d cycles, expected %0d..%0d",
                    d, (ALERT_US - 1) * P + 1, ALERT_US * P));
    check(led_alert == 1'b0 && buzz == 1'b0, "chime off in COOLDOWN");
    end_test();

    // ---- T10
    begin_test("COOLDOWN: no pings, no re-alert, lasts exactly COOLDOWN_US");
    rises_before = trig_rises;               // sensor still sees 60 cm
    wait_leave(S_COOLDOWN);
    wait_cycles(4);
    check(trig_rises == rises_before, "TRIG must stay low during COOLDOWN");
    check(alert_entries == 1, "no second alert");
    d = entry_cyc[S_IDLE] - entry_cyc[S_COOLDOWN];
    check(d == longint'(COOLDOWN_US * P),
          $sformatf("COOLDOWN lasted %0d cycles, expected %0d", d, COOLDOWN_US * P));
    end_test();

    // ---- T11
    begin_test("Measuring resumes after COOLDOWN");
    ping(SNS_ECHO, 250 * 58);
    check(dut.state == S_IDLE, "IDLE after reading");
    check(dut.dist_valid == 1'b1, "distance valid");
    check_disp(" 250");
    end_test();

    // ---- T12
    begin_test("No echo: times out after exactly 30 ms, display '----'");
    ping(SNS_SILENT, 0);
    d = entry_cyc[S_IDLE] - entry_cyc[S_MEASURE];
    check(d == longint'(ECHO_TIMEOUT_US * P),
          $sformatf("MEASURE lasted %0d cycles, expected %0d", d, ECHO_TIMEOUT_US * P));
    check(dut.dist_valid == 1'b0, "reading invalid");
    check_disp("----");
    end_test();

    // ---- T13
    begin_test("Echo stuck high (out of range) times out and clears the reading");
    ping(SNS_ECHO, 120 * 58);
    check_disp(" 120");
    ping(SNS_STUCK, 0);
    check(dut.dist_valid == 1'b0, "reading invalid after stuck echo");
    check(dut.u_fsm.hits == 0, "hits cleared");
    check_disp("----");
    while (echo) @(posedge clk);             // let the sensor model finish
    sns_mode = SNS_ECHO;
    sns_echo_us = 300 * 58;
    wait_state(S_MEASURE);
    wait_leave(S_MEASURE);
    end_test();

    // ---- T14
    begin_test("Echo shorter than 2 cm is rejected as noise");
    ping(SNS_ECHO, 80 * 58);
    check(dut.u_fsm.hits == 1, "80 cm is a near hit");
    check_disp("  80");
    ping(SNS_ECHO, 50);                      // 50 us ~ 0.9 cm: glitch
    check(dut.u_fsm.hits == 0, "glitch must reset the hit count");
    check(dut.dist_valid == 1'b1, "previous reading kept");
    check_disp("  80");
    check(alert_entries == 1, "no alert from glitch");
    end_test();

    // ---- T15
    begin_test("Bouncy button press -> exactly one debounced ALERT, display 'bELL'");
    sns_mode      = SNS_ECHO;
    sns_echo_us   = 300 * 58;
    alerts_before = alert_entries;
    // contact bounce on press (every bounce shorter than DEBOUNCE_US)
    btn_n <= 1'b0; wait_us(100);
    btn_n <= 1'b1; wait_us(150);
    btn_n <= 1'b0; wait_us(300);
    btn_n <= 1'b1; wait_us(80);
    btn_n <= 1'b0;
    press_cyc = cyc;
    wait_us(DEBOUNCE_US - 50);
    check(alert_entries == alerts_before, "must not fire before the debounce window");
    wait_us(4_000);
    // contact bounce on release
    btn_n <= 1'b1; wait_us(100);
    btn_n <= 1'b0; wait_us(200);
    btn_n <= 1'b1;
    wait_us(5_000);
    check(alert_entries == alerts_before + 1,
          $sformatf("%0d alerts, expected exactly 1", alert_entries - alerts_before));
    d = entry_cyc[S_ALERT] - press_cyc;
    check(d >= longint'((DEBOUNCE_US - 1) * P) && d <= longint'(DEBOUNCE_US * P + 8),
          $sformatf("press-to-alert %0d cycles, expected ~%0d", d, DEBOUNCE_US * P));
    check(dut.state == S_ALERT, "in ALERT");
    check(dut.alert_by_button == 1'b1, "source should be button");
    check_disp("bELL");
    end_test();

    // ---- T16
    begin_test("Button during MEASURE aborts the reading and rings immediately");
    wait_state(S_IDLE);                      // finish T15 alert + cooldown
    sns_mode      = SNS_ECHO;
    sns_echo_us   = 400 * 58;                // 23.2 ms echo
    alerts_before = alert_entries;
    wait_state(S_MEASURE);
    while (!echo) @(posedge clk);
    btn_n <= 1'b0;
    wait_us(DEBOUNCE_US + 100);
    check(alert_entries == alerts_before + 1, "ALERT entered");
    check(state_before_alert == S_MEASURE, "ALERT came straight from MEASURE");
    check(dut.state == S_ALERT && dut.alert_by_button == 1'b1, "button ALERT active");
    check(trig == 1'b0, "TRIG low");
    check(dut.u_fsm.echo_us != 16'(400 * 58), "aborted echo must not be latched");
    check_disp("bELL");
    btn_n <= 1'b1;
    end_test();

    // ---- summary
    $display("--------------------------------------");
    $display("%0d / %0d tests passed", passed, test_num);
    if (errors != 0) $fatal(1, "%0d check(s) failed", errors);
    $finish;
  end

  // watchdog
  initial begin
    #(2_000_000_000);
    $fatal(1, "simulation watchdog expired");
  end

endmodule
