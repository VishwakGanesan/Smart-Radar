// sync2.sv
// Two-flop synchronizer for asynchronous inputs (ECHO, button, reset).

module sync2 #(
  parameter logic RESET_VAL = 1'b0
)(
  input  logic clk,
  input  logic rst,
  input  logic d,
  output logic q
);

  logic meta;

  always_ff @(posedge clk) begin
    if (rst) begin
      meta <= RESET_VAL;
      q    <= RESET_VAL;
    end else begin
      meta <= d;
      q    <= meta;
    end
  end

endmodule
