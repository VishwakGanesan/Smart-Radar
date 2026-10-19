// sevenseg_mux.sv
// Time-multiplexed driver for a 4-digit common-anode seven-segment display.
// Digit enables go to PNP high-side switches (active-low base drive), and
// segments are sunk by the FPGA through 220 ohm resistors (active-low).
// chars[3] is the leftmost digit.

module sevenseg_mux
  import doorbell_pkg::*;
#(
  parameter int REFRESH_DIV = 12_000  // clocks per digit (1 ms @ 12 MHz -> 250 Hz frame)
)(
  input  logic             clk,
  input  logic             rst,
  input  char_t [3:0]      chars,
  output logic  [6:0]      seg_n,   // {g,f,e,d,c,b,a}, active-low
  output logic  [3:0]      an_n     // digit enables, active-low
);

  localparam int W = (REFRESH_DIV > 1) ? $clog2(REFRESH_DIV) : 1;

  logic [W-1:0] div;
  logic [1:0]   digit;

  always_ff @(posedge clk) begin
    if (rst) begin
      div   <= '0;
      digit <= '0;
    end else if (div == W'(REFRESH_DIV - 1)) begin
      div   <= '0;
      digit <= digit + 1'b1;
    end else begin
      div <= div + 1'b1;
    end
  end

  function automatic logic [6:0] encode(input char_t c);
    unique case (c)            //  gfedcba
      C_0:     encode = 7'b0111111;
      C_1:     encode = 7'b0000110;
      C_2:     encode = 7'b1011011;
      C_3:     encode = 7'b1001111;
      C_4:     encode = 7'b1100110;
      C_5:     encode = 7'b1101101;
      C_6:     encode = 7'b1111101;
      C_7:     encode = 7'b0000111;
      C_8:     encode = 7'b1111111;
      C_9:     encode = 7'b1101111;
      C_DASH:  encode = 7'b1000000;
      C_H:     encode = 7'b1110110;
      C_I:     encode = 7'b0110000;
      C_B:     encode = 7'b1111100;
      C_E:     encode = 7'b1111001;
      C_L:     encode = 7'b0111000;
      default: encode = 7'b0000000;  // C_BLANK
    endcase
  endfunction

  always_ff @(posedge clk) begin
    if (rst) begin
      seg_n <= 7'h7F;
      an_n  <= 4'hF;
    end else begin
      seg_n <= ~encode(chars[digit]);
      an_n  <= ~(4'b0001 << digit);
    end
  end

endmodule
