// debounce.sv
// Counter-based debouncer. The output only follows the input after the input
// has held a new value for STABLE_US consecutive microseconds; any bounce
// shorter than that restarts the count. `rise` pulses for one clock when the
// debounced level goes 0 -> 1 (i.e. one clean "press" event).
//
// `din` must already be synchronized to clk (see sync2).

module debounce #(
  parameter int STABLE_US = 10_000  // 10 ms
)(
  input  logic clk,
  input  logic rst,
  input  logic us_tick,
  input  logic din,
  output logic level,
  output logic rise
);

  localparam int W = (STABLE_US > 1) ? $clog2(STABLE_US) : 1;

  logic [W-1:0] cnt;

  always_ff @(posedge clk) begin
    if (rst) begin
      level <= 1'b0;
      rise  <= 1'b0;
      cnt   <= '0;
    end else begin
      rise <= 1'b0;
      if (din == level) begin
        cnt <= '0;                         // no change pending
      end else if (us_tick) begin
        if (cnt == W'(STABLE_US - 1)) begin
          level <= din;                    // held long enough: accept it
          rise  <= din;
          cnt   <= '0;
        end else begin
          cnt <= cnt + 1'b1;
        end
      end
    end
  end

endmodule
