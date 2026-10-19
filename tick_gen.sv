// tick_gen.sv
// Emits a single-cycle pulse every DIV clock cycles.
// Used to make a 1 us timebase that every timer in the design shares.

module tick_gen #(
  parameter int DIV = 12  // e.g. 12 for a 12 MHz clock -> 1 us tick
)(
  input  logic clk,
  input  logic rst,
  output logic tick
);

  localparam int W = (DIV > 1) ? $clog2(DIV) : 1;

  logic [W-1:0] cnt;

  always_ff @(posedge clk) begin
    if (rst) begin
      cnt  <= '0;
      tick <= 1'b0;
    end else if (cnt == W'(DIV - 1)) begin
      cnt  <= '0;
      tick <= 1'b1;
    end else begin
      cnt  <= cnt + 1'b1;
      tick <= 1'b0;
    end
  end

endmodule
