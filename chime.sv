// chime.sv
// "Ding-dong" square-wave generator for a piezo/magnetic buzzer driven
// through an NPN low-side switch. First DING_MS at F_DING, then F_DONG
// for as long as `en` stays high. Output is 0 whenever `en` is low.

module chime #(
  parameter int CLK_HZ  = 12_000_000,
  parameter int F_DING  = 880,
  parameter int F_DONG  = 660,
  parameter int DING_MS = 400
)(
  input  logic clk,
  input  logic rst,
  input  logic en,
  output logic buzz
);

  localparam int HALF_DING = CLK_HZ / (2 * F_DING);
  localparam int HALF_DONG = CLK_HZ / (2 * F_DONG);
  localparam int DING_CYC  = (CLK_HZ / 1000) * DING_MS;

  localparam int PW = $clog2((HALF_DING > HALF_DONG ? HALF_DING : HALF_DONG) + 1);
  localparam int TW = $clog2(DING_CYC + 1);

  logic [PW-1:0] phase;
  logic [TW-1:0] t;
  logic          dong;

  wire [PW-1:0] half = dong ? PW'(HALF_DONG - 1) : PW'(HALF_DING - 1);

  always_ff @(posedge clk) begin
    if (rst || !en) begin
      phase <= '0;
      t     <= '0;
      dong  <= 1'b0;
      buzz  <= 1'b0;
    end else begin
      if (!dong) begin
        if (t == TW'(DING_CYC - 1)) begin
          dong <= 1'b1;
        end else begin
          t <= t + 1'b1;
        end
      end
      if (phase == half) begin
        phase <= '0;
        buzz  <= ~buzz;
      end else begin
        phase <= phase + 1'b1;
      end
    end
  end

endmodule
