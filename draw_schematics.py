"""Generate the Smart Radar Doorbell schematics.

    pip install schemdraw matplotlib
    python3 schematics/draw_schematics.py

Writes one SVG + PNG per sheet into schematics/, plus a combined
schematics/doorbell_schematics.pdf.

Sheets
  1  HC-SR04 interface: 2-channel BSS138 bidirectional level shifter (3.3 V <-> 5 V)
  2  Buzzer driver (2N3904 low-side switch) and alert LED
  3  Doorbell button input (pull-up + RC pre-filter; digital debounce in RTL)
  4  4-digit common-anode seven-segment display with 2N3906 digit drivers
  5  Power distribution and decoupling
"""

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import schemdraw
import schemdraw.elements as elm
from matplotlib.backends.backend_pdf import PdfPages
import matplotlib.image as mpimg
import matplotlib.pyplot as plt

schemdraw.use("matplotlib")

OUT = Path(__file__).resolve().parent
FONT = 11


def title_block(d, x, y, title, sheet, note=None):
    d.add(elm.Label().at((x, y)).label(title, fontsize=14, halign="left", valign="bottom"))
    d.add(elm.Label().at((x, y - 0.6)).label(
        f"Smart Radar Doorbell  |  Sheet {sheet} of 5", fontsize=9, halign="left", valign="top", color="#555"))
    if note:
        d.add(elm.Label().at((x, y - 1.2)).label(note, fontsize=9, halign="left", valign="top", color="#555"))


# --------------------------------------------------------------------------- sheet 1
def sheet_level_shifter():
    d = schemdraw.Drawing(show=False)
    d.config(fontsize=FONT, unit=2.5)

    fpga = d.add(elm.Ic(
        pins=[elm.IcPin(name="TRIG", side="right", slot="2/2"),
              elm.IcPin(name="ECHO", side="right", slot="1/2")],
        edgepadW=1.2, edgepadH=1.2, pinspacing=6, leadlen=0.4,
        label="FPGA\n3.3 V I/O", lblsize=12).at((0, 0)).anchor("ECHO"))

    sensor = d.add(elm.Ic(
        pins=[elm.IcPin(name="VCC", side="left", slot="4/4"),
              elm.IcPin(name="TRIG", side="left", slot="3/4"),
              elm.IcPin(name="ECHO", side="left", slot="2/4"),
              elm.IcPin(name="GND", side="left", slot="1/4")],
        edgepadW=1.2, edgepadH=0.6, pinspacing=2, leadlen=0.4,
        label="HC-SR04\n(5 V)", lblsize=12).at((17, 0)).anchor("ECHO"))

    def channel(y, name, series_r):
        """One BSS138 channel. Source = 3.3 V side, drain = 5 V side."""
        src_x = 7.0
        q = d.add(elm.NMos(theta=-90).at((src_x, y)).anchor("source")
                  .label(f"Q{1 if name == 'TRIG' else 2}\nBSS138", loc="bottom", fontsize=10, ofst=(0, -0.2)))
        # gate -> 3.3 V
        g = q.gate
        d.add(elm.Line().at(g).up(0.9))
        d.add(elm.Vdd().label("3V3", fontsize=10))

        # low-voltage node with pull-up
        lv = (src_x - 1.5, y)
        d.add(elm.Line().at(q.source).to(lv))
        d.add(elm.Dot().at(lv))
        d.add(elm.Resistor().at(lv).up(2.2).label(f"R{1 if name == 'TRIG' else 3}\n10 k", loc="bottom", fontsize=10))
        d.add(elm.Vdd().label("3V3", fontsize=10))

        # high-voltage node with pull-up
        hv = (q.drain[0] + 1.5, y)
        d.add(elm.Line().at(q.drain).to(hv))
        d.add(elm.Dot().at(hv))
        d.add(elm.Resistor().at(hv).up(2.2).label(f"R{2 if name == 'TRIG' else 4}\n10 k", loc="top", fontsize=10))
        d.add(elm.Vdd().label("5V", fontsize=10))

        # to sensor
        sp = sensor.absanchors[name]
        d.add(elm.Line().at(hv).to((sp[0] - 2.2, y)))
        d.add(elm.Line().to((sp[0] - 2.2, sp[1])))
        d.add(elm.Line().to(sp))

        # to FPGA (optionally through a series resistor)
        fp = fpga.absanchors[name]
        if series_r:
            d.add(elm.Line().at(lv).left(0.6))
            d.add(elm.Resistor().left(2.2).label(series_r, fontsize=10))
            d.add(elm.Line().to(fp))
        else:
            d.add(elm.Line().at(lv).to(fp))
        d.add(elm.Label().at((fp[0] + 1.6, y + 0.25)).label(
            "trig" if name == "TRIG" else "echo", fontsize=9, color="#1a5fb4", valign="bottom"))

    channel(fpga.absanchors["TRIG"][1], "TRIG", None)
    channel(fpga.absanchors["ECHO"][1], "ECHO", "R5\n330 Ω")

    # sensor power + decoupling
    vcc = sensor.absanchors["VCC"]
    gnd = sensor.absanchors["GND"]
    d.add(elm.Line().at(vcc).left(0.6))
    d.add(elm.Line().up(1.2))
    d.add(elm.Vdd().label("5V", fontsize=10))
    d.add(elm.Line().at(gnd).left(0.6))
    d.add(elm.Line().down(1.0))
    d.add(elm.Ground())

    cx = sensor.absanchors["GND"][0] + 5.5
    top = vcc[1] + 1.2
    d.add(elm.Vdd().at((cx, top)).label("5V", fontsize=10))
    d.add(elm.Line().at((cx, top)).down(0.8))
    d.add(elm.Dot())
    c1 = d.add(elm.Capacitor().down(2.0).label("C1\n100 nF", loc="bottom", fontsize=10))
    d.add(elm.Ground())
    d.add(elm.Line().at((cx, top - 0.8)).right(2.0))
    d.add(elm.Capacitor(polar=True).down(2.0).label("C2\n10 µF", loc="bottom", fontsize=10))
    d.add(elm.Ground())
    d.add(elm.Label().at((cx + 1.0, top - 4.6)).label("decoupling at\nsensor header", fontsize=9, color="#555"))
    d.add(elm.Line().at((cx + 3.2, top)).right(0.01).color("white"))  # right margin

    title_block(d, -3.5, fpga.absanchors["TRIG"][1] + 5.0,
                "HC-SR04 interface - BSS138 bidirectional level shifter", 1,
                "Gate tied to 3.3 V. Low side pulled to 3.3 V, high side to 5 V, so a 5 V ECHO never reaches an FPGA pin.")
    return d


# --------------------------------------------------------------------------- sheet 2
def sheet_buzzer_led():
    d = schemdraw.Drawing(show=False)
    d.config(fontsize=FONT, unit=2.5)

    # buzzer driver: buzz -> R6 -> Q3 base; buzzer from +5 V to collector
    d.add(elm.Tag().at((0, 0)).left().label("buzz", fontsize=10, color="#1a5fb4"))
    d.add(elm.Resistor().at((0, 0)).right(2.5).label("R6\n1 k", fontsize=10))
    d.add(elm.Dot())
    bnode = d.here
    q = d.add(elm.BjtNpn(circle=True).anchor("base").label("Q3\n2N3904", loc="right", fontsize=10, ofst=(0.3, 0)))
    d.add(elm.Resistor().at(bnode).down(2.4).label("R7\n10 k", loc="top", fontsize=10))
    d.add(elm.Ground())
    d.add(elm.Line().at(q.emitter).down(1.7))
    d.add(elm.Ground())

    d.add(elm.Line().at(q.collector).up(0.7))
    d.add(elm.Dot())
    cnode = d.here
    d.add(elm.ResistorIEC().up(2.6).label("BZ1\n5 V magnetic\nbuzzer", loc="bottom", fontsize=10))
    d.add(elm.Label().at((cnode[0] - 0.35, cnode[1] + 2.4)).label("+", fontsize=11))
    d.add(elm.Dot())
    tnode = d.here
    d.add(elm.Line().up(0.8))
    d.add(elm.Vdd().label("5V", fontsize=10))

    # flyback diode in parallel with the buzzer, cathode to +5 V
    d.add(elm.Line().at(cnode).left(2.0))
    d.add(elm.Diode().up(2.6).label("D1\n1N4148", loc="top", fontsize=10))
    d.add(elm.Line().to(tnode))

    d.add(elm.Label().at((-2.5, -4.0)).label(
        "Ib = (3.3 - 0.7) / 1 k = 2.6 mA; with a 30 mA buzzer that is a forced beta of about 12, so Q3 saturates hard.\n"
        "D1 clamps the coil kick when Q3 turns off. R7 holds Q3 off while the FPGA is unconfigured.",
        fontsize=9, halign="left", valign="top", color="#555"))

    # alert LED
    ox = 11
    d.add(elm.Tag().at((ox, 0)).left().label("led_alert", fontsize=10, color="#1a5fb4"))
    d.add(elm.Resistor().at((ox, 0)).right(2.5).label("R8\n330 Ω", fontsize=10))
    d.add(elm.LED().down(2.0).label("D2\ngreen", loc="bottom", fontsize=10))
    d.add(elm.Ground())

    title_block(d, -2.5, 8.2, "Buzzer driver and alert LED", 2,
                "The FPGA cannot source 30 mA or switch 5 V, so an NPN low-side switch drives the buzzer.")
    return d


# --------------------------------------------------------------------------- sheet 3
def sheet_button():
    d = schemdraw.Drawing(show=False)
    d.config(fontsize=FONT, unit=2.5)

    d.add(elm.Vdd().at((0, 3.0)).label("3V3", fontsize=10))
    d.add(elm.Resistor().at((0, 3.0)).down(2.5).label("R9\n10 k", fontsize=10))
    d.add(elm.Dot())
    node = d.here
    d.add(elm.Line().left(1.5))
    d.add(elm.Tag().left().label("btn_n", fontsize=10, color="#1a5fb4"))

    d.add(elm.Line().at(node).right(1.8))
    d.add(elm.Dot())
    n2 = d.here
    d.add(elm.Capacitor().down(2.2).label("C3\n100 nF", loc="bottom", fontsize=10))
    d.add(elm.Ground())
    d.add(elm.Line().at(n2).right(2.2))
    d.add(elm.Resistor().down(1.2).label("R10\n100 Ω", fontsize=10))
    d.add(elm.Button().down(1.6).label("SW1\ndoorbell", fontsize=10))
    d.add(elm.Ground())

    d.add(elm.Label().at((-3.5, -3.6)).label(
        "R9·C3 = 1 ms knocks down fast contact chatter; R10 limits the cap discharge current through SW1.\n"
        "The real debounce is digital (rtl/debounce.sv): the input must hold for 10 ms before it is accepted.",
        fontsize=9, halign="left", valign="top", color="#555"))

    title_block(d, -3.5, 5.5, "Doorbell button input", 3)
    return d


# --------------------------------------------------------------------------- sheet 4
def sheet_display():
    d = schemdraw.Drawing(show=False)
    d.config(fontsize=FONT, unit=2.5)

    pitch = 6.0
    disp_y = -3.0
    for i in range(4):
        x = i * pitch
        d.add(elm.Tag().at((x - 2.2, 0)).left().label(f"an_n[{i}]", fontsize=10, color="#1a5fb4"))
        d.add(elm.Resistor().at((x - 2.2, 0)).right(1.4).label(f"R{11 + i}\n1 k", fontsize=9))
        q = d.add(elm.BjtPnp(circle=True).anchor("base").label(f"Q{4 + i}\n2N3906", loc="right", fontsize=9, ofst=(0.2, 0)))
        d.add(elm.Line().at(q.emitter).up(0.8))
        d.add(elm.Vdd().label("3V3", fontsize=10))
        d.add(elm.Line().at(q.collector).toy(disp_y))
        d.add(elm.Label().at((q.collector[0], disp_y - 0.1)).label(f"DIG{i + 1}\ncommon anode", fontsize=8, valign="top"))

    # display body
    left = -1.0
    right = 3 * pitch + 2.4
    d.add(elm.Line().at((left, disp_y)).to((right, disp_y)).color("#888"))
    d.add(elm.Line().at((left, disp_y - 3.6)).to((right, disp_y - 3.6)).color("#888"))
    d.add(elm.Line().at((left, disp_y)).to((left, disp_y - 3.6)).color("#888"))
    d.add(elm.Line().at((right, disp_y)).to((right, disp_y - 3.6)).color("#888"))
    d.add(elm.Label().at(((left + right) / 2, disp_y - 1.9)).label(
        "DS1  4-digit 7-segment, common anode", fontsize=11))

    # segment cathodes
    segs = ["a", "b", "c", "d", "e", "f", "g", "dp"]
    sx0 = left + 0.6
    sp = (right - left - 1.2) / (len(segs) - 1)
    for k, s in enumerate(segs):
        x = sx0 + k * sp
        d.add(elm.Line().at((x, disp_y - 3.6)).down(0.6))
        d.add(elm.Resistor().down(1.8).label(f"R{15 + k}\n220 Ω", loc="bottom", fontsize=8))
        name = "dp_n" if s == "dp" else f"seg_n[{k}]"
        d.add(elm.Line().down(0.4))
        d.add(elm.Dot(open=True))
        d.add(elm.Label().at((x, d.here[1] - 0.3)).label(f"{name}\n({s})", fontsize=9, color="#1a5fb4", valign="top"))

    d.add(elm.Label().at((-3.0, disp_y - 8.6)).label(
        "Digits are scanned by rtl/sevenseg_mux.sv at 1 ms each (250 Hz frame). an_n low turns a PNP on;\n"
        "seg_n low sinks that segment. Segment current = (3.3 - 0.1 - 2.0) / 220 = 5.5 mA.\n"
        "The whole display runs from 3.3 V so no FPGA pin ever sees 5 V.",
        fontsize=9, halign="left", valign="top", color="#555"))

    title_block(d, -3.0, 3.5, "Seven-segment display and PNP digit drivers", 4)
    return d


# --------------------------------------------------------------------------- sheet 5
def sheet_power():
    d = schemdraw.Drawing(show=False)
    d.config(fontsize=FONT, unit=2.5)

    j = d.add(elm.Ic(
        pins=[elm.IcPin(name="VBUS", side="right", slot="2/2"),
              elm.IcPin(name="GND", side="right", slot="1/2")],
        edgepadW=0.8, pinspacing=2.5, leadlen=0.4, label="J1\nUSB 5 V in", lblsize=11).at((0, 0)).anchor("GND"))
    vb = j.absanchors["VBUS"]
    g = j.absanchors["GND"]

    # 5 V rail
    d.add(elm.Line().at(vb).right(1.5))
    d.add(elm.Dot())
    n1 = d.here
    d.add(elm.Capacitor(polar=True).toy(g[1]).label("C4\n47 µF", loc="bottom", fontsize=10))
    d.add(elm.Dot())
    d.add(elm.Line().at(g).to(d.here))
    d.add(elm.Line().at(n1).right(4.0))
    d.add(elm.Dot())
    n2 = d.here
    d.add(elm.Line().right(5.0))
    d.add(elm.Dot(open=True))
    d.add(elm.Label().at((d.here[0] + 0.3, d.here[1])).label(
        "5V  ->  HC-SR04 VCC, BZ1, level-shifter pull-ups R2/R4", fontsize=10, halign="left"))
    d.add(elm.Label().at((n1[0] + 2.0, vb[1] + 0.25)).label("5V", fontsize=10, color="#1a5fb4", valign="bottom"))

    # FPGA board
    fb = d.add(elm.Ic(
        pins=[elm.IcPin(name="5V IN", side="top", slot="1/1"),
              elm.IcPin(name="3V3 OUT", side="right", slot="1/1"),
              elm.IcPin(name="GND", side="bottom", slot="1/1")],
        edgepadW=6.5, edgepadH=1.4, pinspacing=2, leadlen=0.4,
        label="FPGA board\n(on-board\n3.3 V LDO)", lblsize=10).at((n2[0], n2[1] - 3.0)).anchor("5V IN"))
    d.add(elm.Line().at(n2).to(fb.absanchors["5V IN"]))
    d.add(elm.Line().at(fb.absanchors["GND"]).down(0.6))
    d.add(elm.Ground())

    o = fb.absanchors["3V3 OUT"]
    d.add(elm.Line().at(o).right(1.5))
    d.add(elm.Dot())
    n3 = d.here
    d.add(elm.Capacitor().down(1.8).label("C5\n100 nF", loc="bottom", fontsize=10))
    d.add(elm.Ground())
    d.add(elm.Line().at(n3).right(3.5))
    d.add(elm.Dot(open=True))
    d.add(elm.Label().at((d.here[0] + 0.3, d.here[1])).label(
        "3V3  ->  BSS138 gates, R1/R3, R9, Q4-Q7 emitters", fontsize=10, halign="left"))

    d.add(elm.Label().at((-1.5, -6.6)).label(
        "One ground, star-connected at J1. 3V3 only feeds logic-level parts; the only places 5 V and 3.3 V meet are\n"
        "the BSS138 level shifter (sheet 1) and the NPN collector (sheet 2), neither of which connects 5 V to an FPGA pin.",
        fontsize=9, halign="left", valign="top", color="#555"))

    title_block(d, -1.5, 4.8, "Power and grounding", 5)
    return d


SHEETS = [
    ("1_hcsr04_level_shifter", sheet_level_shifter),
    ("2_buzzer_driver", sheet_buzzer_led),
    ("3_button_input", sheet_button),
    ("4_display_drivers", sheet_display),
    ("5_power", sheet_power),
]


def main():
    pngs = []
    for name, fn in SHEETS:
        d = fn()
        d.save(str(OUT / f"{name}.svg"))
        d.save(str(OUT / f"{name}.png"), dpi=160)
        pngs.append(OUT / f"{name}.png")
        print("wrote", name)

    with PdfPages(OUT / "doorbell_schematics.pdf") as pdf:
        for p in pngs:
            img = mpimg.imread(p)
            h, w = img.shape[:2]
            fig = plt.figure(figsize=(11, 11 * h / w if w else 8.5))
            ax = fig.add_axes([0.03, 0.03, 0.94, 0.94])
            ax.imshow(img)
            ax.axis("off")
            pdf.savefig(fig)
            plt.close(fig)
    print("wrote doorbell_schematics.pdf")


if __name__ == "__main__":
    main()
