# Smart Radar Doorbell
#   make lint     - Verilator lint, all warnings on
#   make sim      - build + run the self-checking testbench
#   make wave     - same, and dump waves.vcd (open with GTKWave)
#   make synth    - sv2v + Yosys + nextpnr for iCE40 (needs the OSS CAD Suite and sv2v)
#   make schematics - regenerate schematics/*.svg (needs: pip install schemdraw)

RTL := rtl/doorbell_pkg.sv \
       rtl/sync2.sv rtl/tick_gen.sv rtl/debounce.sv \
       rtl/doorbell_fsm.sv rtl/echo_to_cm.sv rtl/bin2bcd.sv \
       rtl/sevenseg_mux.sv rtl/chime.sv rtl/doorbell_top.sv
TB  := tb/tb_doorbell.sv

VFLAGS := --binary --timing --timescale 1ns/1ps -j 0 -Wall -Wno-fatal --top-module tb_doorbell \
          -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-INITIALDLY \
          -Wno-WIDTHEXPAND -Wno-BLKSEQ

.PHONY: all lint sim wave synth schematics clean

all: lint sim

lint:
	verilator --lint-only -Wall --top-module doorbell_top $(RTL)

obj_dir/Vtb_doorbell: $(RTL) $(TB)
	verilator $(VFLAGS) $(RTL) $(TB)

sim: obj_dir/Vtb_doorbell
	./obj_dir/Vtb_doorbell

wave:
	verilator $(VFLAGS) --trace -DTRACE -Mdir obj_dir_trace $(RTL) $(TB)
	./obj_dir_trace/Vtb_doorbell

# Target: iCEBreaker (iCE40UP5K, 12 MHz). Edit constraints/ for other boards.
synth: build/doorbell.bin

# sv2v flattens packages/enums to plain Verilog so Yosys's parser is happy.
build/doorbell.v: $(RTL)
	mkdir -p build
	sv2v $(RTL) > $@

build/doorbell.json: build/doorbell.v
	yosys -q -p "read_verilog $<; synth_ice40 -top doorbell_top -json $@"

build/doorbell.asc: build/doorbell.json constraints/icebreaker.pcf
	nextpnr-ice40 --up5k --package sg48 --freq 12 --json $< --pcf constraints/icebreaker.pcf --asc $@

build/doorbell.bin: build/doorbell.asc
	icepack $< $@

schematics:
	python3 schematics/draw_schematics.py

clean:
	rm -rf obj_dir obj_dir_trace build waves.vcd
