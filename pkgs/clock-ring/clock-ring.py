#!/usr/bin/env python3
# Wall clock. Stacks the hour and minute in two rows inside a circle, and draws the spectrum of the playing audio radially inward from the rim.
# waybar's CSS cannot arrange things in a circle, so draw a transparent layer-shell window ourselves.
# The spectrum is read from cava's raw output (one frame is bars bytes, each 0-255).
# The top, where lines from the vertical bar come in, is left empty; bars span the 240 degrees from 10 o'clock around through 6 to 2 o'clock.
# The left and right channels go on the left and right of the circle, with bass at the bottom and treble at the top.
import argparse
import json
import math
import os
import re
import subprocess
import sys
import time
import traceback

import cairo
import gi

gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import GLib, Pango, PangoCairo  # noqa: E402

FONT = "Moralerspace Argon HW"
FONT_SIZE = 52
# Place 48 bars over 240 degrees, the same spacing as the former 72 bars over 360 degrees
BARS = 48
ARC_START = math.radians(300)
ARC_SPAN = math.radians(240)
# Matching the 150px square box from when this was a waybar clock, place a 150px-diameter circle 12px from the top of the screen.
# Its right edge is 12px from the left edge of the vertical bar
RADIUS = 75
TOP = 12
# The gap from the rim to the base of the bars, and the maximum bar length
BAR_GAP = 4
BAR_MAX = 30
# Margin for the lines extending left of and below the circle. Sizes match ring in dotfiles/waybar/circuit/layout.mjs
PAD_LEFT = 60
PAD_BOTTOM = 50
PAD_RIGHT = 12
WIDTH = PAD_LEFT + RADIUS * 2 + PAD_RIGHT
HEIGHT = TOP + RADIUS * 2 + PAD_BOTTOM
CX = PAD_LEFT + RADIUS
CY = TOP + RADIUS

CAVA_CONFIG = f"""
[general]
framerate = 60
bars = {BARS}
autosens = 1
sleep_timer = 3

[input]
method = pipewire
source = auto

[output]
method = raw
channels = stereo
raw_target = /dev/stdout
data_format = binary
bit_format = 8bit

[smoothing]
noise_reduction = 77
"""


def load_palette(path):
    """Turn "@define-color name #rrggbb;" lines in nordfox.css into {name: (r, g, b)}"""
    palette = {}
    with open(path) as f:
        for m in re.finditer(r"@define-color ([a-z0-9]+) #([0-9a-f]{6});", f.read()):
            h = m.group(2)
            palette[m.group(1)] = tuple(int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return palette


def load_wires(path):
    """Read the wiring pixels written by dotfiles/waybar/circuit/build.mjs"""
    with open(path) as f:
        wires = json.load(f)
    if wires["size"] != [WIDTH, HEIGHT]:
        print(f"wires.json size {wires['size']} does not match {[WIDTH, HEIGHT]}", file=sys.stderr)
        os._exit(1)
    return wires


def paint(cr, palette, wires, bars, now):
    """Paint the whole window. bars is a sequence of 0-255 values; if empty, only the circle and time are drawn"""
    glass = (*palette["bg1"], 0.6)
    edge = (*palette["fg1"], 0.4)
    wire = (*palette["fg1"], 0.3)

    cr.set_operator(cairo.OPERATOR_CLEAR)
    cr.paint()
    cr.set_operator(cairo.OPERATOR_OVER)
    cr.set_line_width(1)

    # Wiring is drawn pixel by pixel. The third value is the opacity in fading segments
    for x, y, a in wires["wires"]:
        cr.rectangle(x, y, 1, 1)
        cr.set_source_rgba(*wire[:3], wire[3] * a)
        cr.fill()

    cr.arc(CX, CY, RADIUS, 0, 2 * math.pi)
    cr.set_source_rgba(*glass)
    cr.fill()
    cr.arc(CX, CY, RADIUS - 0.5, 0, 2 * math.pi)
    cr.set_source_rgba(*edge)
    cr.stroke()

    # cava's stereo output runs from left treble to bass, then right bass to treble.
    # Placing it counterclockwise from 10 o'clock puts left treble at 10, the basses meeting at 6, and right treble at 2.
    # The bars lie beneath the time, so make them slightly faint to keep the text readable
    cr.set_line_width(3)
    cr.set_line_cap(cairo.LINE_CAP_ROUND)
    cr.set_source_rgba(*palette["cyan"], 0.7)
    n = len(bars)
    for i, v in enumerate(bars):
        if v == 0:
            continue
        # Angles are measured clockwise with straight up as 0
        a = ARC_START - (i + 0.5) / n * ARC_SPAN
        dx, dy = math.sin(a), -math.cos(a)
        r0 = RADIUS - BAR_GAP
        r1 = r0 - v / 255 * BAR_MAX
        cr.move_to(CX + dx * r0, CY + dy * r0)
        cr.line_to(CX + dx * r1, CY + dy * r1)
    cr.stroke()

    # Stack the hour shifted half a character left and the minute half a character right. The minute is cyan, as an accent in place of a colon
    font = Pango.FontDescription.from_string(FONT)
    font.set_absolute_size(FONT_SIZE * Pango.SCALE)
    half = FONT_SIZE * 0.25
    for text, color, ox, oy in (
        (now.tm_hour, palette["fg1"], -half, -0.42),
        (now.tm_min, palette["cyan"], half, 0.42),
    ):
        layout = PangoCairo.create_layout(cr)
        layout.set_font_description(font)
        layout.set_text(f"{text:02d}", -1)
        ink, _ = layout.get_pixel_extents()
        x = CX + ox - ink.x - ink.width / 2
        y = CY + oy * FONT_SIZE - ink.y - ink.height / 2
        cr.move_to(x, y + 1)
        cr.set_source_rgba(0, 0, 0, 0.6)
        PangoCairo.show_layout(cr, layout)
        cr.move_to(x, y)
        cr.set_source_rgb(*color)
        PangoCairo.show_layout(cr, layout)


class Cava:
    """Start cava and keep the latest frame of its output in bars"""

    def __init__(self, on_frame):
        self.on_frame = on_frame
        self.bars = []
        self.buf = b""
        self.last = 0.0
        path = os.path.join(GLib.get_user_runtime_dir(), "clock-ring-cava.conf")
        with open(path, "w") as f:
            f.write(CAVA_CONFIG)
        # cava does not need the gtk4-layer-shell LD_PRELOAD added by the wrapper
        env = {k: v for k, v in os.environ.items() if k != "LD_PRELOAD"}
        self.proc = subprocess.Popen(["cava", "-p", path], stdout=subprocess.PIPE, env=env)
        GLib.io_add_watch(self.proc.stdout.fileno(), GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP, self.read)

    def read(self, fd, cond):
        data = os.read(fd, 65536)
        if not data:
            # If cava dies, exit the clock too and let systemd restart it
            print("cava exited", file=sys.stderr)
            os._exit(1)
        self.buf += data
        full = len(self.buf) // BARS * BARS
        if full:
            self.bars = list(self.buf[full - BARS : full])
            self.buf = self.buf[full:]
            self.last = time.monotonic()
            self.on_frame()
        return True

    def stale(self):
        """After cava stops on silence, clear the last frame if it is still shown"""
        if self.bars and time.monotonic() - self.last > 0.5:
            self.bars = []
            return True
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, help="output name of the monitor to show the clock on (e.g. DP-3)")
    parser.add_argument("--theme", required=True, help="path to nordfox.css")
    parser.add_argument("--wires", required=True, help="path to the wiring pixels (wires.json)")
    parser.add_argument("--margin-right", type=int, default=0)
    parser.add_argument("--preview", help="draw a state with audio to a PNG and exit without opening a window")
    args = parser.parse_args()
    palette = load_palette(args.theme)
    wires = load_wires(args.wires)

    if args.preview:
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, WIDTH, HEIGHT)
        bars = [int(255 * abs(math.sin(i * 0.37)) * (1 - abs(i - BARS / 2) / BARS)) for i in range(BARS)]
        paint(cairo.Context(surface), palette, wires, bars, time.localtime())
        surface.write_to_png(args.preview)
        return

    gi.require_version("Gdk", "4.0")
    gi.require_version("Gtk", "4.0")
    gi.require_version("Gtk4LayerShell", "1.0")
    from gi.repository import Gdk, Gtk, Gtk4LayerShell as LayerShell

    app = Gtk.Application(application_id="local.clock-ring")

    def setup(app):
        display = Gdk.Display.get_default()
        monitors = display.get_monitors()
        monitor = next(
            (m for m in (monitors.get_item(i) for i in range(monitors.get_n_items())) if m.get_connector() == args.output),
            None,
        )
        if monitor is None:
            print(f"output {args.output} not found", file=sys.stderr)
            os._exit(1)

        css = Gtk.CssProvider()
        css.load_from_string("window { background: transparent; }")
        Gtk.StyleContext.add_provider_for_display(display, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        win = Gtk.Window(application=app, decorated=False)
        LayerShell.init_for_window(win)
        LayerShell.set_namespace(win, "clock-ring")
        LayerShell.set_monitor(win, monitor)
        # Like the vertical bar, always on top without reserving space
        LayerShell.set_layer(win, LayerShell.Layer.OVERLAY)
        LayerShell.set_anchor(win, LayerShell.Edge.TOP, True)
        LayerShell.set_anchor(win, LayerShell.Edge.RIGHT, True)
        LayerShell.set_margin(win, LayerShell.Edge.RIGHT, args.margin_right)
        LayerShell.set_exclusive_zone(win, -1)

        area = Gtk.DrawingArea(content_width=WIDTH, content_height=HEIGHT)
        cava = Cava(area.queue_draw)
        area.set_draw_func(lambda _a, cr, _w, _h: paint(cr, palette, wires, cava.bars, time.localtime()))
        win.set_child(area)

        # Empty the input region so clicks pass through to the window below
        win.connect("map", lambda w: w.get_surface().set_input_region(cairo.Region()))

        # During silence cava stops and no redraws come, so check the time and clear the bars every second
        minute = [time.localtime().tm_min]

        def tick():
            m = time.localtime().tm_min
            if cava.stale() or m != minute[0]:
                minute[0] = m
                area.queue_draw()
            return True

        GLib.timeout_add_seconds(1, tick)
        win.present()

    def activate(app):
        # PyGObject only prints exceptions from callbacks and continues, so it would exit with code 0 without ever showing the window.
        # Exit as a failure and let systemd restart it
        try:
            setup(app)
        except Exception:
            traceback.print_exc()
            os._exit(1)

    app.connect("activate", activate)
    app.run([])


if __name__ == "__main__":
    main()
