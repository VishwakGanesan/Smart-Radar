# Smart Radar Doorbell

An FPGA doorbell that notices someone walking up before they press the button. A 5-state SystemVerilog FSM pings an HC-SR04 ultrasonic sensor, times the echo to get distance in centimetres, shows it on a 4-digit seven-segment display, and plays a "ding-dong" chime when someone is close for three readings in a row or presses the (debounced) button.

**Stack:** SystemVerilog · Verilator · iCE40 FPGA (Yosys / nextpnr) · BSS138 level shifting · BJT drivers

![FSM](docs/fsm.png)

## What it does

| Situation | Display | Chime |
|---|---|---|
| Nothing within ~5 m | `----` | off |
| Object in range | distance in cm, e.g. ` 182` | off |
| Under 100 cm for 3 consecutive pings | `  HI` | 2 s ding-dong |
| Doorbell button pressed | `bELL` | 2 s ding-dong |

After an alert the doorbell sits in a 5 s cooldown so one visitor triggers one chime. The button still works during cooldown.

## Architecture

![Block diagram](docs/block_diagram.png)

| File | Purpose |
|---|---|
| `rtl/doorbell_fsm.sv` | 5-state controller: `IDLE → TRIGGER → MEASURE → ALERT → COOLDOWN` |
| `rtl/debounce.sv` | Counter debouncer: the input must hold for 10 ms before it is accepted |
| `rtl/sync2.sv` | 2-flop synchronizers for the asynchronous ECHO and button inputs |
| `rtl/tick_gen.sv` | Shared 1 µs timebase for every timer |
| `rtl/echo_to_cm.sv` | `cm = echo_us / 58` as a multiply-and-shift: `(echo_us × 1130) >> 16` |
| `rtl/bin2bcd.sv` | Double-dabble binary to BCD for the display |
| `rtl/sevenseg_mux.sv` | Multiplexed common-anode display driver, 250 Hz frame |
| `rtl/chime.sv` | Two-tone square-wave generator for the buzzer |
| `rtl/doorbell_top.sv` | Top level and display formatting (leading-zero blanking, `HI`, `bELL`, `----`) |

### Timing details

* All state timers count the shared 1 µs tick, and `IDLE → TRIGGER → MEASURE` transitions only happen on a tick. That makes the TRIG pulse exactly 10 µs and the echo timeout exactly 30 ms, to the clock cycle.
* `trig` and `chime_en` are decoded from the next state and registered, so they line up with the state register and never glitch into the sensor.
* Echo width is measured by counting ticks while ECHO is high, including the cycle ECHO rises on. Any window of N µs contains exactly N ticks, so whole-microsecond echoes are measured exactly whatever their phase relative to the tick.
* Echoes shorter than 116 µs (< 2 cm, below the sensor's range) are treated as noise. They reset the "near" counter and leave the display unchanged.

## Verification

`tb/tb_doorbell.sv` is a self-checking testbench with a behavioural HC-SR04 model and **16 directed test cases**. It covers reset, cycle-exact TRIG width, ping spacing, cm conversion at the 100 cm boundary, consecutive-hit logic, alert and cooldown timing, timeouts, stuck and glitch echoes, a bouncy button press, and a button press that aborts a measurement. The sensor model shifts every response by a different sub-microsecond phase so that echo edges land at every alignment relative to the 1 µs tick.

```
$ make sim
[PASS] T01  Reset: IDLE, outputs low, display '----'
[PASS] T02  TRIG pulse is exactly 10 us (cycle-exact)
...
[PASS] T16  Button during MEASURE aborts the reading and rings immediately
16 / 16 tests passed
```

Full log: [`docs/sim_output.txt`](docs/sim_output.txt). As a check on the testbench itself, deliberately injected one-cycle and threshold bugs in the RTL (TRIG one µs long, timeout off by one, a dropped tick on the echo edge, `<=` instead of `<`, a broken debouncer) each make at least one test fail.

## Hardware

FPGA I/O is 3.3 V and the HC-SR04 is a 5 V part, so the board-level interface matters as much as the RTL. Schematics are in [`schematics/`](schematics/) (PDF: [`doorbell_schematics.pdf`](schematics/doorbell_schematics.pdf)).

| Sheet | Circuit |
|---|---|
| 1 | HC-SR04 interface: 2-channel BSS138 bidirectional level shifter. ECHO (5 V) is clamped to 3.3 V before it reaches the FPGA, and TRIG is lifted from 3.3 V to 5 V. |
| 2 | 2N3904 low-side switch for the 5 V buzzer with a 1N4148 flyback diode, plus the alert LED |
| 3 | Doorbell button: 10 k pull-up and a 1 ms RC pre-filter ahead of the digital debouncer |
| 4 | 4-digit common-anode display with 2N3906 high-side digit drivers, all on 3.3 V |
| 5 | Power: one 5 V input, 3V3 from the FPGA board's regulator, single star ground |

![Level shifter](schematics/1_hcsr04_level_shifter.png)

**Why the interface looks like this:** wiring the 5 V ECHO straight into a 3.3 V pin forward-biases the pin's ESD clamp diode and dumps current into the 3.3 V rail, which can latch up the I/O bank. A floating or slow input can also read as spurious echoes. The BSS138 stage plus pull-ups on both sides fixes the voltage levels and gives every line a defined idle state. The 2-flop synchronizer, minimum-echo filter, and 3-hit requirement in the RTL then reject what is left.

### Bill of materials

| Ref | Part | Qty |
|---|---|---|
| — | iCE40 FPGA board (3.3 V I/O, 12 MHz) | 1 |
| U1 | HC-SR04 ultrasonic sensor | 1 |
| Q1, Q2 | BSS138 N-MOSFET | 2 |
| Q3 | 2N3904 NPN | 1 |
| Q4–Q7 | 2N3906 PNP | 4 |
| DS1 | 4-digit 7-segment, common anode | 1 |
| BZ1 | 5 V magnetic buzzer | 1 |
| D1 | 1N4148 | 1 |
| D2 | Green LED | 1 |
| SW1 | Momentary push button | 1 |
| R1–R4, R7, R9 | 10 kΩ | 6 |
| R6, R11–R14 | 1 kΩ | 5 |
| R5, R8 | 330 Ω | 2 |
| R10 | 100 Ω | 1 |
| R15–R22 | 220 Ω | 8 |
| C1, C3, C5 | 100 nF | 3 |
| C2 | 10 µF | 1 |
| C4 | 47 µF | 1 |

## Build and run

Requires [Verilator](https://verilator.org) 5.x (for `--timing`).

```bash
make lint         # Verilator -Wall lint of the RTL
make sim          # build and run the 16-case testbench
make wave         # same, plus waves.vcd for GTKWave
make synth        # sv2v + Yosys + nextpnr -> build/doorbell.bin (iCEBreaker pin map)
make schematics   # regenerate schematics (pip install schemdraw matplotlib)
```

Default parameters target a 12 MHz clock. The testbench overrides them, using a 4 MHz clock and shorter alert, cooldown, and debounce times, so a full run takes under a second. Pin assignments are in `constraints/icebreaker.pcf`; change them to match your board.

## Repository layout

```
rtl/            synthesizable SystemVerilog
tb/             self-checking Verilator testbench
schematics/     schematic source (Python/schemdraw) + SVG, PNG, PDF
docs/           FSM and block diagrams, simulation log
constraints/    FPGA pin constraints
```

## Note

The original project files (Mar–May 2026) were lost. This repository is a rebuild of the design (Oct 2026); the testbench was rerun and the schematics redrawn as part of it.
