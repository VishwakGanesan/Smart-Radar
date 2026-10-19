// bin2bcd.sv
// Combinational double-dabble: 14-bit binary (0..9999) -> four BCD digits.

module bin2bcd (
  input  logic [13:0] bin,
  output logic [3:0]  thousands,
  output logic [3:0]  hundreds,
  output logic [3:0]  tens,
  output logic [3:0]  ones
);

  logic [29:0] s;  // [29:14] = BCD, [13:0] = binary being shifted in

  always_comb begin
    s = {16'd0, bin};
    for (int i = 0; i < 14; i++) begin
      if (s[17:14] >= 4'd5) s[17:14] = s[17:14] + 4'd3;
      if (s[21:18] >= 4'd5) s[21:18] = s[21:18] + 4'd3;
      if (s[25:22] >= 4'd5) s[25:22] = s[25:22] + 4'd3;
      if (s[29:26] >= 4'd5) s[29:26] = s[29:26] + 4'd3;
      s = s << 1;
    end
    {thousands, hundreds, tens, ones} = s[29:14];
  end

endmodule
