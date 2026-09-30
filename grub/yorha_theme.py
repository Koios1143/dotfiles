#!/usr/bin/env python3
"""Generate the YoRHa Boot Manager GRUB theme for a given screen resolution.

The design lives in ./design/'YoRHa Boot Manager.dc.html'. Everything there is
expressed in `cqh` units (percent of viewport height), so the whole layout is
reproduced here in the same units and rasterised per resolution.

GRUB's gfxmenu can only draw solid colours, PNG bitmaps and 9-slice styled
boxes, so the split of work is:

  * every static element (grid, scanlines, grain, frame, header, emblem,
    section rules, footer legend, ring track) is baked into background.png at
    the exact target resolution;
  * the menu rows are a `boot_menu` component whose item / selected-item
    artwork is authored at full size and cut into 9 slices such that GRUB
    reassembles them 1:1 with no scaling;
  * the countdown is a `circular_progress` of small dots plus a `label` bound
    to __timeout__.

Run via ./build.sh; see ./README.md for the deviations from the mock.
"""

from __future__ import annotations

import argparse
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
VENDOR_FONTS = HERE / "vendor" / "fonts"
EMBLEM = HERE / "design" / "uploads" / "yorha.svg"

PLEX = "IBM Plex Mono"
CHAKRA = "Chakra Petch"


def _init_fontconfig() -> None:
    """Point fontconfig at the vendored TTFs before pango initialises."""
    cache = Path(
        os.environ.get("YORHA_CACHE") or (tempfile.gettempdir() + "/yorha-fc")
    )
    cache.mkdir(parents=True, exist_ok=True)
    conf = cache / "fonts.conf"
    conf.write_text(
        "<?xml version='1.0'?>\n"
        "<!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>\n"
        "<fontconfig>\n"
        f"  <dir>{VENDOR_FONTS}</dir>\n"
        f"  <cachedir>{cache / 'cache'}</cachedir>\n"
        "  <include ignore_missing='yes'>/etc/fonts/conf.d</include>\n"
        "</fontconfig>\n"
    )
    os.environ["FONTCONFIG_FILE"] = str(conf)


_init_fontconfig()

import cairo  # noqa: E402
import gi  # noqa: E402

gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
gi.require_version("Rsvg", "2.0")
from gi.repository import Pango, PangoCairo, Rsvg  # noqa: E402


# --------------------------------------------------------------------------
# palette (straight from the design)
# --------------------------------------------------------------------------

BG = (0x0C, 0x0A, 0x08)
FG = (0xCF, 0xC8, 0xBA)
HL = (0xF2, 0xEA, 0xD9)
RING = (0xEF, 0xE6, 0xD4)
DIGIT = (0xF3, 0xEC, 0xDD)
SEL_BORDER = (0xE6, 0xDC, 0xC8)  # rgba(230,220,200,.75)
GLOW = (0xF0, 0xE4, 0xCD)  # rgba(240,228,205,*)
WASH = (70, 58, 44)

DIM = 0.5  # dimOpacity prop default: unselected menu item text/bullet


# --------------------------------------------------------------------------
# layout, in cqh (percent of screen height) exactly as the design uses them
# --------------------------------------------------------------------------

INSET_T, INSET_R, INSET_B, INSET_L = 5.4, 7.6, 5.0, 7.2
HEADER_H = 11.25  # emblem row / title block, measured from the mock
SELECT_GAP = 12.0  # marginTop on the "SELECT BOOT TARGET" row
SELECT_H = 2.4
MENU_GAP = 3.4
ITEM_H = 7.0
ITEM_GAP = 1.0
MENU_W = 58.0
STRIP_GAP = 3.6  # menu -> DEFAULT TARGET strip
STRIP_BRACKET_H = 0.9
STRIP_BRACKET_GAP = 1.6
STRIP_TEXT_H = 1.62
FOOTER_ROW_H = 2.7
FOOTER_DIVIDER_GAP = 2.8
RING_SIZE = 16.0
RING_TOP = 4.2
RING_RIGHT = 7.6


STRIP_H = STRIP_BRACKET_H + STRIP_BRACKET_GAP + STRIP_TEXT_H


class Geo:
    """All derived geometry for one resolution, in device pixels."""

    def __init__(self, w: int, h: int, rows: int, menu_w_cqh: float = MENU_W,
                 centered: bool = False):
        self.w, self.h, self.rows = w, h, rows
        self.menu_w_cqh = menu_w_cqh
        self.centered = centered

        # vertical flow of the design's content column
        self.header_top = INSET_T
        self.menu_h_c = rows * ITEM_H + (rows - 1) * ITEM_GAP
        self.footer_row_top = 100.0 - INSET_B - FOOTER_ROW_H
        self.divider_y = self.footer_row_top - FOOTER_DIVIDER_GAP

        fixed = (INSET_T + HEADER_H + SELECT_H + MENU_GAP + self.menu_h_c
                 + STRIP_GAP + STRIP_H)
        if centered:
            # The centered page replaces the fixed 12cqh header gap with
            # `margin-top: auto` on the section title, `margin-bottom: auto` on
            # the DEFAULT TARGET strip and the existing `margin-top: auto` on
            # the footer rule. Flexbox splits the free space equally between
            # those three autos, so the group sits one third of the way down.
            free = self.divider_y - fixed
            if free < 3.0:
                raise SystemExit(
                    f"rows={rows} does not fit the centered layout: the group ends at "
                    f"{fixed:.2f}cqh with only {free:.2f}cqh of slack before the footer "
                    f"rule at {self.divider_y:.2f}cqh. Use fewer rows."
                )
            select_gap = free / 3.0
        else:
            # The mock reserves 4 rows and a generous 12cqh of air between the
            # header and the section title. Extra rows are paid for out of that
            # air rather than by letting the strip run into the footer rule.
            select_gap = min(SELECT_GAP, self.divider_y - 2.0 - fixed)
            if select_gap < 4.0:
                raise SystemExit(
                    f"rows={rows} does not fit: even with the header gap squeezed to "
                    f"4cqh the DEFAULT TARGET strip would reach "
                    f"{fixed + 4.0:.2f}cqh, past the footer rule at "
                    f"{self.divider_y:.2f}cqh. Use fewer rows."
                )
        self.select_gap = select_gap
        self.select_top = INSET_T + HEADER_H + select_gap
        self.menu_top_c = self.select_top + SELECT_H + MENU_GAP
        self.strip_top = self.menu_top_c + self.menu_h_c + STRIP_GAP

        # menu block in pixels. GRUB adds the item box's top/bottom pads to
        # item_height, so item_height is the design height minus those pads.
        # Horizontal placement: the design's content box runs from INSET_L to
        # W - INSET_R, and `align-self: center` centres inside that box (which
        # is 0.2cqh left of the screen centre, since the insets differ).
        self.content_x0 = self.u(INSET_L)
        self.content_x1 = w - self.u(INSET_R)
        self.content_cx = (self.content_x0 + self.content_x1) / 2

        self.menu_w = self.px(menu_w_cqh)
        if centered:
            self.menu_left = int(round(self.content_cx - self.menu_w / 2))
        else:
            self.menu_left = self.px(INSET_L)
        self.menu_top = self.px(self.menu_top_c)
        if self.menu_w > self.content_x1 - self.content_x0:
            raise SystemExit(
                f"{w}x{h}: a {menu_w_cqh:g}cqh menu is {self.menu_w}px wide but only "
                f"{w - self.px(INSET_R) - self.menu_left}px fit inside the frame."
            )
        self.item_visual_h = self.px(ITEM_H)
        self.item_gap = self.px(ITEM_GAP)
        self.pad_n = self.px(1.4)  # == corner tick length
        self.pad_w = self.px(6.8)  # bullet + gap: where the title starts
        self.pad_e = self.px(1.4)
        self.item_height = self.item_visual_h - 2 * self.pad_n
        self.item_spacing = 2 * self.pad_n + self.item_gap
        self.pitch = self.item_visual_h + self.item_gap
        self.menu_h = rows * self.item_visual_h + (rows - 1) * self.item_gap
        self.content_w = self.menu_w - self.pad_w - self.pad_e
        self.bullet_cx = self.px(3.4)
        self.bullet_side = self.u(1.6)

        # Countdown. The centered page drops the ring entirely and keeps only
        # the digits and the SEC caption; the base page keeps the ring, and
        # GRUB derives the tick radius from the component size
        # (radius = min(w,h)/2 - max(tick)/2 - 1), so the component there is
        # sized backwards from the radius the design asks for.
        self.ring_cx = self.w - self.u(RING_RIGHT) - self.u(RING_SIZE) / 2
        self.ring_cy = self.u(RING_TOP) + self.u(RING_SIZE) / 2
        self.ring_r = self.u(RING_SIZE) * 0.46
        self.ring_sw = max(1.0, self.u(RING_SIZE) * 0.011)
        if centered:
            self.tick = 1
            self.num_ticks = 0
            self.grub_ring_r = 0
            self.ring_box = self.px(RING_SIZE)
        else:
            # tick dot diameter == the design's 1.6/100 ring stroke
            self.tick = max(2, int(round(self.u(RING_SIZE) * 0.016)))
            self.ring_box = 2 * int(round(self.ring_r)) + self.tick + 2
            # GRUB's own radius, recomputed the way circprog_paint does
            self.grub_ring_r = self.ring_box // 2 - self.tick // 2 - 1
            # GRUB blits the tick unrotated at integer positions, so the arc is
            # a bead chain rather than a stroke; overlap them slightly so it
            # reads as a continuous ring. 256 is the cap (1/256 turn each).
            circumference = 2 * math.pi * max(1, self.grub_ring_r)
            self.num_ticks = max(16, min(256, int(round(circumference / self.tick * 1.2))))
        self.ring_left = int(round(self.ring_cx - self.ring_box / 2))
        self.ring_top = int(round(self.ring_cy - self.ring_box / 2))

        # countdown digits: the design centres a 4.8cqh number and a 1.25cqh
        # "SEC" caption as a column inside the 16cqh ring.
        col_h = 4.8 + 0.2 + 1.5
        self.digit_top_c = RING_TOP + (RING_SIZE - col_h) / 2
        self.sec_top_c = self.digit_top_c + 4.8 + 0.2

        # font pixel sizes
        self.item_font_px = max(8, self.px(2.2))
        self.digit_font_px = max(12, self.px(4.8))
        self.term_font_px = max(12, self.px(1.7))

    def u(self, cqh: float) -> float:
        return cqh * self.h / 100.0

    def px(self, cqh: float) -> int:
        return int(round(self.u(cqh)))


# --------------------------------------------------------------------------
# cairo / pango helpers
# --------------------------------------------------------------------------


def rgba(cr, rgb, a=1.0):
    cr.set_source_rgba(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, a)


def fill_rect(cr, x, y, w, h, rgb, a=1.0):
    rgba(cr, rgb, a)
    cr.rectangle(x, y, w, h)
    cr.fill()


def gradient(cr, x, y, w, h, p0, p1, stops):
    lg = cairo.LinearGradient(p0[0], p0[1], p1[0], p1[1])
    for off, rgb, a in stops:
        lg.add_color_stop_rgba(off, rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, a)
    cr.save()
    cr.rectangle(x, y, w, h)
    cr.clip()
    cr.set_source(lg)
    cr.paint()
    cr.restore()


_WEIGHT = {
    200: Pango.Weight.ULTRALIGHT,
    300: Pango.Weight.LIGHT,
    400: Pango.Weight.NORMAL,
    600: Pango.Weight.SEMIBOLD,
}


def make_layout(cr, text, px, *, weight=200, tracking=0.0, family=PLEX):
    lay = PangoCairo.create_layout(cr)
    fd = Pango.FontDescription()
    fd.set_family(family)
    fd.set_weight(_WEIGHT[weight])
    fd.set_absolute_size(px * Pango.SCALE)
    lay.set_font_description(fd)
    lay.set_text(text, -1)
    if tracking:
        attrs = Pango.AttrList()
        attrs.insert(Pango.attr_letter_spacing_new(int(round(tracking * px * Pango.SCALE))))
        lay.set_attributes(attrs)
    return lay


def layout_metrics(cr, px, weight, family):
    fd = Pango.FontDescription()
    fd.set_family(family)
    fd.set_weight(_WEIGHT[weight])
    fd.set_absolute_size(px * Pango.SCALE)
    ctx = PangoCairo.create_context(cr)
    m = ctx.get_metrics(fd, None)
    return m.get_ascent() / Pango.SCALE, m.get_descent() / Pango.SCALE


def text_box(
    cr,
    text,
    px,
    *,
    left=None,
    right=None,
    center=None,
    top=None,
    baseline=None,
    weight=200,
    tracking=0.0,
    family=PLEX,
    color=FG,
    alpha=1.0,
    lh=1.2,
):
    """Draw text positioned like the CSS box it comes from.

    `top` is the top of the line box (height = lh * px); the baseline is placed
    at top + half-leading + ascent, which is what a browser does.
    """
    lay = make_layout(cr, text, px, weight=weight, tracking=tracking, family=family)
    ink, log = lay.get_pixel_extents()
    width = log.width
    asc, desc = layout_metrics(cr, px, weight, family)
    if baseline is None:
        baseline = top + (lh * px - (asc + desc)) / 2 + asc
    if left is not None:
        x = left
    elif right is not None:
        x = right - width
    else:
        x = center - width / 2
    lay_baseline = lay.get_baseline() / Pango.SCALE
    rgba(cr, color, alpha)
    cr.move_to(x, baseline - lay_baseline)
    PangoCairo.show_layout(cr, lay)
    return width


def text_width(cr, text, px, *, weight=200, tracking=0.0, family=PLEX):
    lay = make_layout(cr, text, px, weight=weight, tracking=tracking, family=family)
    return lay.get_pixel_extents()[1].width


def ink_center_from_baseline(cr, text, px, *, weight=200, tracking=0.0, family=PLEX):
    """Vertical centre of the drawn glyphs, relative to the baseline (negative
    = above it). For all-caps strings this is -capHeight/2, which is what the
    eye reads as the middle of the text."""
    lay = make_layout(cr, text, px, weight=weight, tracking=tracking, family=family)
    ink, _ = lay.get_pixel_extents()
    baseline = lay.get_baseline() / Pango.SCALE
    return (ink.y - baseline) + ink.height / 2


def vdash(cr, x, y, w, h, rgb, a, on=1, period=5):
    rgba(cr, rgb, a)
    yy = float(y)
    while yy < y + h:
        cr.rectangle(x, round(yy), w, on)
        yy += period
    cr.fill()


def hdash(cr, x, y, w, h, rgb, a, on, period):
    rgba(cr, rgb, a)
    xx = float(x)
    while xx < x + w:
        cr.rectangle(round(xx), y, min(on, x + w - xx), h)
        xx += period
    cr.fill()


# --------------------------------------------------------------------------
# background
# --------------------------------------------------------------------------


def noise_tile(size=160):
    """160x160 grain tile, standing in for the design's feTurbulence layer."""
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    rnd = random.Random(0x59_4F_52_48)  # "YORH" - deterministic builds
    stride = surf.get_stride()
    data = surf.get_data()
    # three octaves of value noise, bilinearly upsampled
    fields = []
    for octave in (4, 8, 16):
        cell = size // octave
        grid = [[rnd.random() for _ in range(octave + 1)] for _ in range(octave + 1)]
        fields.append((cell, grid))
    for y in range(size):
        for x in range(size):
            v = 0.0
            amp = 0.5
            for cell, grid in fields:
                gx, gy = x / cell, y / cell
                x0, y0 = int(gx), int(gy)
                fx, fy = gx - x0, gy - y0
                a = grid[y0][x0] * (1 - fx) + grid[y0][x0 + 1] * fx
                b = grid[y0 + 1][x0] * (1 - fx) + grid[y0 + 1][x0 + 1] * fx
                v += (a * (1 - fy) + b * fy) * amp
                amp *= 0.5
            g = int(max(0, min(255, v * 255)))
            o = y * stride + x * 4
            a8 = int(0.55 * 255)
            # premultiplied ARGB32
            data[o + 0] = g * a8 // 255
            data[o + 1] = g * a8 // 255
            data[o + 2] = g * a8 // 255
            data[o + 3] = a8
    surf.mark_dirty()
    return surf


def paint_background(cr, g: Geo, opts):
    w, h = g.w, g.h

    fill_rect(cr, 0, 0, w, h, BG)

    # radial-gradient(120% 90% at 30% 40%, rgba(70,58,44,.20), transparent 70%)
    cr.save()
    cr.translate(0.3 * w, 0.4 * h)
    cr.scale(1.2 * w, 0.9 * h)
    rg = cairo.RadialGradient(0, 0, 0, 0, 0, 1)
    rg.add_color_stop_rgba(0.0, WASH[0] / 255, WASH[1] / 255, WASH[2] / 255, 0.20)
    rg.add_color_stop_rgba(0.7, WASH[0] / 255, WASH[1] / 255, WASH[2] / 255, 0.0)
    cr.set_source(rg)
    cr.rectangle(-1, -1, 2, 2)
    cr.fill()
    cr.restore()

    # dotted grid: 5.2cqh major at .07, 1.3cqh minor at .03
    if opts.grid:
        for step, a in ((g.u(5.2), 0.07), (g.u(1.3), 0.03)):
            rgba(cr, FG, a)
            x = 0.0
            while x < w:
                cr.rectangle(round(x), 0, 1, h)
                x += step
            y = 0.0
            while y < h:
                cr.rectangle(0, round(y), w, 1)
                y += step
            cr.fill()

    # CRT scanlines: 1px of black .30 every 3px, whole layer at .55
    if opts.crt:
        rgba(cr, (0, 0, 0), 0.30 * 0.55)
        y = 0
        while y < h:
            cr.rectangle(0, y, w, 1)
            y += 3
        cr.fill()

    # film grain
    if opts.grain:
        tile = noise_tile()
        pat = cairo.SurfacePattern(tile)
        pat.set_extend(cairo.Extend.REPEAT)
        cr.save()
        cr.set_source(pat)
        cr.paint_with_alpha(0.035)
        cr.restore()

    # --- frame -----------------------------------------------------------
    f = g.px(3.0)
    A = 0.28
    # top rule, with the two gaps from the design
    gradient(
        cr, f, f, w - 2 * f, 1, (f, 0), (w - f, 0),
        [(0.0, FG, 0.0), (0.04, FG, A), (0.70, FG, A), (0.78, FG, 0.0),
         (0.84, FG, 0.0), (0.88, FG, A), (0.96, FG, A), (1.0, FG, 0.0)],
    )
    gradient(
        cr, f, h - f, w - 2 * f, 1, (f, 0), (w - f, 0),
        [(0.0, FG, 0.0), (0.04, FG, A), (0.96, FG, A), (1.0, FG, 0.0)],
    )
    gradient(
        cr, f, f, 1, h - 2 * f, (0, f), (0, h - f),
        [(0.0, FG, A), (0.30, FG, A), (0.38, FG, 0.0),
         (0.48, FG, 0.0), (0.56, FG, A), (1.0, FG, A)],
    )
    gradient(
        cr, w - f, f, 1, h - 2 * f, (0, f), (0, h - f),
        [(0.0, FG, A), (0.46, FG, A), (0.54, FG, 0.0),
         (0.62, FG, 0.0), (0.70, FG, A), (1.0, FG, A)],
    )

    # corner brackets
    c = g.px(2.2)
    s = g.px(2.4)
    rgba(cr, FG, 0.55)
    for cx, cy, sx, sy in ((c, c, 1, 1), (w - c, c, -1, 1), (c, h - c, 1, -1), (w - c, h - c, -1, -1)):
        cr.rectangle(cx if sx > 0 else cx - s, cy if sy > 0 else cy - 1, s, 1)
        cr.rectangle(cx if sx > 0 else cx - 1, cy if sy > 0 else cy - s, 1, s)
    cr.fill()

    # side tick strips + vertical part numbers
    vdash(cr, g.px(4.6), g.px(32), g.px(0.8), g.u(26), FG, 0.30)
    vdash(cr, w - g.px(4.6) - g.px(0.8), g.px(24), g.px(0.8), g.u(20), FG, 0.24)
    vtext(cr, g, "YRH-001", g.px(4.2), g.px(66), 1.1, 0.22, 0.30)
    vtext(cr, g, "E-11.02.4-4.3-R", w - g.px(4.2), g.px(26), 1.1, 0.22, 0.26)

    # registration marks
    plus = g.u(1.4)
    for x, y, a, anchor in (
        (g.px(4.6), g.px(21), 0.30, "l"),
        (w - g.px(4.6), g.px(21), 0.30, "r"),
        (g.px(4.6), g.px(75), 0.30, "l"),
        (w - g.px(4.6), g.px(75), 0.30, "r"),
        (0.53 * w, g.px(26), 0.26, "l"),
        (0.53 * w, g.px(75), 0.26, "l"),
        (0.47 * w, g.px(4.4), 0.26, "l"),
    ):
        kw = {"left": x} if anchor == "l" else {"right": x}
        text_box(cr, "+", plus, top=y, color=FG, alpha=a, **kw)

    # top strapline dashes + label
    hdash(cr, 0.24 * w, g.px(5.2), g.u(5), g.px(0.5), FG, 0.30, 2, 6)
    hdash(cr, 0.495 * w, g.px(5.6), g.u(28), 1, FG, 0.26, 3, 9)
    text_box(cr, "SYS-BOOT-CTRL", g.u(1.1), right=w - g.px(21), top=g.px(5.0),
             tracking=0.24, alpha=0.34)

    # EID block, bottom-right of the empty area
    eid_right = w - g.px(8.0)
    eid_bottom = h - g.px(18.0)
    eid_top = eid_bottom - g.u(0.6 + 0.6 + 1.44)
    bar_w = g.u(6.0)
    bar_h = g.px(0.6)
    hdash(cr, eid_right - bar_w, eid_top, bar_w, bar_h, FG, 0.5, 3, 7)
    hdash(cr, eid_right - 2 * bar_w - g.u(1.4), eid_top, bar_w, bar_h, FG, 0.34, 3, 7)
    text_box(cr, "EID_22-107-FA", g.u(1.2), right=eid_right,
             top=eid_top + bar_h + g.u(0.6), tracking=0.20, alpha=0.42)

    # The ring track and the SEC caption deliberately do NOT go here -- they
    # live in the circular_progress center_bitmap so that GRUB hides them along
    # with the ticks and the digits the moment the timeout is cancelled
    # (any arrow key -> grub_gfxmenu_clear_timeout -> update_timeouts(0,...)).
    # Baked into the background they would leave an empty ring behind.

    # --- header ----------------------------------------------------------
    emblem_h = g.u(10.6)
    emblem_w = emblem_h * 197.0 / 232.0
    draw_emblem(cr, g.u(INSET_L), g.u(INSET_T) + g.u(0.6), emblem_w, emblem_h, 0.62)

    tx = g.u(INSET_L) + emblem_w + g.u(2.6)
    y = g.u(INSET_T)
    text_box(cr, f"VER.{opts.version}", g.u(1.4), left=tx, top=y, tracking=0.30, alpha=0.72)
    y += g.u(1.68) + g.u(0.5)
    text_box(cr, "SYSTEM BOOT MANAGER", g.u(3.7), left=tx, top=y, lh=1.1,
             weight=600, tracking=0.28, alpha=0.72)
    y += g.u(3.7 * 1.1) + g.u(0.5)
    text_box(cr, "YoRHa BOOT CONTROL INTERFACE", g.u(1.85), left=tx, top=y,
             weight=300, tracking=0.16, alpha=0.82)
    y += g.u(1.85 * 1.2) + g.u(0.5) + g.u(0.4)
    row_mid = y + g.u(1.38) / 2
    hdash(cr, tx, round(row_mid - g.u(0.35)), g.u(6.4), g.px(0.7), FG, 0.40, 4, 8)
    lx = tx + g.u(6.4) + g.u(1.2)
    lw = text_box(cr, "SYS-CTRL-INTF", g.u(1.15), left=lx, top=y, tracking=0.28, alpha=0.40)
    hdash(cr, lx + lw + g.u(1.2), round(row_mid), g.u(5.0), 1, FG, 0.34, 3, 8)

    # --- section header --------------------------------------------------
    label = "/// SELECT BOOT TARGET"
    if g.centered:
        # justify-content: center over {text, 2cqh gap, 26cqh rule}
        group_w = text_width(cr, label, g.u(2.0), weight=300, tracking=0.14) \
            + g.u(2.0) + g.u(26.0)
        sx = g.content_cx - group_w / 2
    else:
        sx = g.u(INSET_L) + g.u(1.0)  # paddingLeft: 1cqh
    sw = text_box(cr, label, g.u(2.0), left=sx,
                  top=g.u(g.select_top), weight=300, tracking=0.14, alpha=0.92)
    rule_y = round(g.u(g.select_top) + g.u(SELECT_H) / 2)
    gradient(cr, sx + sw + g.u(2.0), rule_y, g.u(26.0), 1,
             (sx + sw + g.u(2.0), 0), (sx + sw + g.u(2.0) + g.u(26.0), 0),
             [(0.0, FG, 0.34), (1.0, FG, 0.10)])

    # --- DEFAULT TARGET strip -------------------------------------------
    bx = g.menu_left if g.centered else g.u(INSET_L)
    by = g.u(g.strip_top)
    bw, bh = g.u(g.menu_w_cqh), g.u(STRIP_BRACKET_H)
    rgba(cr, FG, 0.24)
    cr.rectangle(bx, by, bw, 1)
    cr.rectangle(bx, by, 1, bh)
    cr.rectangle(bx + bw - 1, by, 1, bh)
    cr.fill()
    text_box(cr, f"DEFAULT TARGET  /  {opts.default_target}", g.u(1.35),
             left=bx + g.u(1.4), top=by + bh + g.u(STRIP_BRACKET_GAP),
             tracking=0.22, alpha=0.44)

    # --- footer ----------------------------------------------------------
    dy = round(g.u(g.divider_y))
    dx0, dx1 = g.u(INSET_L), w - g.u(INSET_R)
    gradient(cr, dx0, dy, dx1 - dx0, 1, (dx0, 0), (dx1, 0),
             [(0.0, FG, 0.32), (0.88, FG, 0.32), (1.0, FG, 0.10)])
    rgba(cr, FG, 0.42)
    cr.rectangle(dx0, dy - g.u(0.5), 1, g.u(1.6))
    cr.rectangle(dx1 - 1, dy - g.u(0.5), 1, g.u(1.6))
    cr.fill()

    # The legend is sized in cqh, so on 4:3 / 5:4 modes it can grow wider than
    # the space left beside the version label. Shrink it to fit, and drop the
    # label outright if even that is not enough.
    frow_top = g.u(g.footer_row_top)
    frow_bottom = frow_top + g.u(FOOTER_ROW_H)
    label = f"YORHA SYSTEMS // BOOT CONTROL v{opts.version}"
    label_w = text_width(cr, label, g.u(1.15), tracking=0.24)
    row_w = dx1 - dx0
    natural = legend_width(cr, g, 1.0)
    scale = min(1.0, max(0.62, (row_w - label_w - g.u(2.0)) / natural))
    used = legend_width(cr, g, scale)
    if used + label_w + g.u(2.0) <= row_w:
        text_box(cr, label, g.u(1.15), left=dx0, baseline=frow_bottom - g.u(0.35),
                 tracking=0.24, alpha=0.30)
    draw_legend(cr, g, dx1, frow_bottom, scale)


def vtext(cr, g, text, x, top, size_cqh, tracking, alpha):
    """writing-mode: vertical-rl — glyphs rotated 90 degrees, running downward."""
    cr.save()
    cr.translate(x, top)
    cr.rotate(math.pi / 2)
    text_box(cr, text, g.u(size_cqh), left=0, top=-g.u(size_cqh) * 1.2,
             tracking=tracking, alpha=alpha)
    cr.restore()


def draw_emblem(cr, x, y, w, h, alpha):
    handle = Rsvg.Handle.new_from_file(str(EMBLEM))
    cr.save()
    cr.push_group()
    rect = Rsvg.Rectangle()
    rect.x, rect.y, rect.width, rect.height = x, y, w, h
    handle.render_document(cr, rect)
    cr.pop_group_to_source()
    cr.paint_with_alpha(alpha)
    cr.restore()


LEGEND = [
    (["ENTER"], "CONFIRM", 6.4, 0.9),
    (["↑", "↓"], "SELECT", 2.6, 0.0),
    (["E"], "OPTIONS", 2.6, 0.0),
    (["C"], "CMD-LINE", 2.6, 0.0),
    (["ESC"], "BACK", 4.6, 0.9),
]


def legend_groups(cr, g, scale):
    cap_px = g.u(1.4) * scale
    lab_px = g.u(1.55) * scale
    groups = []
    for caps, label, min_w, pad in LEGEND:
        widths = []
        for t in caps:
            tw = text_width(cr, t, cap_px, tracking=0.14 if pad else 0.0)
            widths.append(max(g.u(min_w) * scale, tw + 2 * g.u(pad) * scale))
        lab_w = text_width(cr, label, lab_px, tracking=0.10)
        total = (sum(widths) + g.u(0.5) * scale * (len(caps) - 1)
                 + g.u(1.2) * scale + lab_w)
        groups.append((caps, widths, label, lab_w, total))
    return groups, cap_px, lab_px


def legend_width(cr, g, scale):
    groups, _, _ = legend_groups(cr, g, scale)
    return sum(gr[4] for gr in groups) + g.u(3.2) * scale * (len(groups) - 1)


def draw_legend(cr, g, right, row_bottom, scale=1.0):
    groups, cap_px, lab_px = legend_groups(cr, g, scale)
    cap_h = g.u(2.68) * scale
    gap = g.u(3.2) * scale

    # Centre the keycap boxes on the middle of the label glyphs. Bottom-aligning
    # them (which is what the flex row's own box model does) leaves the caps
    # visibly riding high above the words they belong to.
    lab_baseline = row_bottom - g.u(0.35) * scale
    cap_top = (lab_baseline
               + ink_center_from_baseline(cr, "CONFIRM", lab_px, tracking=0.10)
               - cap_h / 2)

    x = right - legend_width(cr, g, scale)
    for caps, widths, label, lab_w, _ in groups:
        for t, cw in zip(caps, widths):
            rgba(cr, FG, 0.55)
            cr.set_line_width(1)
            cr.rectangle(round(x) + 0.5, round(cap_top) + 0.5,
                         round(cw) - 1, round(cap_h) - 1)
            cr.stroke()
            text_box(cr, t, cap_px, center=x + cw / 2, top=cap_top + g.u(0.5) * scale,
                     tracking=0.14 if len(t) > 1 else 0.0, alpha=0.9)
            x += cw + g.u(0.5) * scale
        x -= g.u(0.5) * scale
        x += g.u(1.2) * scale
        text_box(cr, label, lab_px, left=x, baseline=lab_baseline,
                 tracking=0.10, alpha=0.78)
        x += lab_w + gap


# --------------------------------------------------------------------------
# menu item artwork + 9-slice
# --------------------------------------------------------------------------


def render_item(g: Geo, selected: bool) -> cairo.ImageSurface:
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, g.menu_w, g.item_visual_h)
    cr = cairo.Context(surf)
    W, H = g.menu_w, g.item_visual_h

    if selected:
        # linear-gradient(90deg, rgba(240,228,205,.05), rgba(240,228,205,.01))
        gradient(cr, 0, 0, W, H, (0, 0), (W, 0),
                 [(0.0, GLOW, 0.05), (1.0, GLOW, 0.01)])
        # inset 0 0 2.4cqh rgba(240,228,205,.05) -- approximated as a soft
        # inward ramp; GRUB cannot render the design's outer glow at all,
        # because a styled box may not bleed outside the item rect.
        glow = max(1, g.px(2.4))
        for i in range(glow):
            a = 0.05 * (1 - i / glow)
            rgba(cr, GLOW, a)
            cr.rectangle(i, i, W - 2 * i, 1)
            cr.rectangle(i, H - 1 - i, W - 2 * i, 1)
            cr.rectangle(i, i, 1, H - 2 * i)
            cr.rectangle(W - 1 - i, i, 1, H - 2 * i)
            cr.fill()
        # 1px frame
        rgba(cr, SEL_BORDER, 0.75)
        cr.rectangle(0, 0, W, 1)
        cr.rectangle(0, H - 1, W, 1)
        cr.rectangle(0, 0, 1, H)
        cr.rectangle(W - 1, 0, 1, H)
        cr.fill()
        # 2px corner ticks, 1.4cqh long
        t, L = 2, g.pad_n
        rgba(cr, HL, 1.0)
        for cx, cy, sx, sy in ((0, 0, 1, 1), (W, 0, -1, 1), (0, H, 1, -1), (W, H, -1, -1)):
            x0 = cx if sx > 0 else cx - L
            y0 = cy if sy > 0 else cy - t
            cr.rectangle(x0, y0, L, t)
            x0 = cx if sx > 0 else cx - t
            y0 = cy if sy > 0 else cy - L
            cr.rectangle(x0, y0, t, L)
        cr.fill()

    draw_bullet(cr, g, g.bullet_cx, H / 2, selected)
    surf.flush()
    return surf


def draw_bullet(cr, g: Geo, cx, cy, selected: bool):
    s = g.bullet_side
    cr.save()
    cr.translate(cx, cy)
    cr.rotate(math.pi / 4)
    rgba(cr, FG, 1.0 if selected else DIM)
    cr.set_line_width(1)
    cr.rectangle(-s / 2 + 0.5, -s / 2 + 0.5, s - 1, s - 1)
    cr.stroke()
    if selected:
        inset = g.u(0.32)
        rgba(cr, HL, 1.0)
        cr.rectangle(-s / 2 + inset, -s / 2 + inset, s - 2 * inset, s - 2 * inset)
        cr.fill()
    cr.restore()


SLICE_NAMES = ("nw", "n", "ne", "w", "c", "e", "sw", "s", "se")


def slice_regions(g: Geo):
    pw, pe, pn, ih, W = g.pad_w, g.pad_e, g.pad_n, g.item_height, g.menu_w
    cw = g.content_w
    return {
        "nw": (0, 0, pw, pn),
        "n": (pw, 0, cw, pn),
        "ne": (W - pe, 0, pe, pn),
        "w": (0, pn, pw, ih),
        "c": (pw, pn, cw, ih),
        "e": (W - pe, pn, pe, ih),
        "sw": (0, pn + ih, pw, pn),
        "s": (pw, pn + ih, cw, pn),
        "se": (W - pe, pn + ih, pe, pn),
    }


def write_slices(surf, g: Geo, outdir: Path, prefix: str):
    for name, (x, y, w, h) in slice_regions(g).items():
        piece = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
        cr = cairo.Context(piece)
        cr.set_source_surface(surf, -x, -y)
        cr.paint()
        piece.flush()
        piece.write_to_png(str(outdir / f"{prefix}_{name}.png"))


def reassemble(g: Geo, outdir: Path, prefix: str) -> cairo.ImageSurface:
    """Rebuild an item the way widget-box.c does, to verify the slicing."""
    out = cairo.ImageSurface(cairo.FORMAT_ARGB32, g.menu_w, g.item_visual_h)
    cr = cairo.Context(out)
    pieces = {
        n: cairo.ImageSurface.create_from_png(str(outdir / f"{prefix}_{n}.png"))
        for n in SLICE_NAMES
    }
    width_w = max(pieces[n].get_width() for n in ("nw", "w", "sw"))
    height_n = max(pieces[n].get_height() for n in ("nw", "n", "ne"))
    cw = pieces["c"].get_width()
    ch = pieces["c"].get_height()
    placements = {
        "n": (width_w, 0), "s": (width_w, height_n + ch),
        "e": (width_w + cw, height_n), "w": (0, height_n),
        "nw": (0, 0), "ne": (width_w + cw, 0),
        "se": (width_w + cw, height_n + ch), "sw": (0, height_n + ch),
        "c": (width_w, height_n),
    }
    for name in ("n", "s", "e", "w", "nw", "ne", "se", "sw", "c"):
        x, y = placements[name]
        cr.set_source_surface(pieces[name], x, y)
        cr.paint()
    out.flush()
    return out


def write_tick(g: Geo, outdir: Path):
    n = g.tick
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, n, n)
    cr = cairo.Context(surf)
    rgba(cr, RING, 1.0)
    if n <= 4:
        # too small for a disc to help; a crisp block keeps the ring even
        cr.rectangle(0, 0, n, n)
    else:
        cr.arc(n / 2, n / 2, n / 2, 0, 2 * math.pi)
    cr.fill()
    surf.flush()
    surf.write_to_png(str(outdir / "tick.png"))


def write_center(g: Geo, outdir: Path):
    """circular_progress center_bitmap: the ring track plus the SEC caption.

    Drawn and hidden by GRUB together with the ticks, so cancelling the timeout
    removes the whole countdown cluster instead of leaving a hollow ring. The
    centered variant has no ring, so this carries the caption alone -- and the
    component still exists purely so the caption hides with the digits.
    """
    n = g.ring_box
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, n, n)
    cr = cairo.Context(surf)
    cx, cy = g.ring_cx - g.ring_left, g.ring_cy - g.ring_top
    if not g.centered:
        rgba(cr, FG, 0.16)
        cr.set_line_width(g.ring_sw)
        cr.arc(cx, cy, g.ring_r, 0, 2 * math.pi)
        cr.stroke()
    text_box(cr, "SEC", g.u(1.25), center=cx,
             top=g.u(g.sec_top_c) - g.ring_top, tracking=0.34, alpha=0.62)
    surf.flush()
    surf.write_to_png(str(outdir / "center.png"))


def write_terminal_box(g: Geo, outdir: Path):
    """1px framed, dimmed panel for the `c` / `e` screens."""
    edge = 1
    for name, (w, h) in (
        ("nw", (edge, edge)), ("ne", (edge, edge)), ("sw", (edge, edge)), ("se", (edge, edge)),
        ("n", (1, edge)), ("s", (1, edge)), ("w", (edge, 1)), ("e", (edge, 1)),
        ("c", (1, 1)),
    ):
        surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
        cr = cairo.Context(surf)
        if name == "c":
            rgba(cr, BG, 0.88)
        else:
            rgba(cr, FG, 0.45)
        cr.paint()
        surf.flush()
        surf.write_to_png(str(outdir / f"term_{name}.png"))


# --------------------------------------------------------------------------
# PFF2 fonts
# --------------------------------------------------------------------------

GLYPH_RANGE = "0x20-0x7e,0xa0-0xff"


def pf2_sections(data):
    off = 0
    while off + 8 <= len(data):
        name = data[off : off + 4].decode("ascii", "replace")
        length = struct.unpack_from(">I", data, off + 4)[0]
        yield name, off + 8, length
        if name == "DATA":
            return
        off += 8 + length


def pf2_add_tracking(path: Path, extra: int):
    """Widen every glyph's advance, i.e. bake CSS letter-spacing into the font."""
    if extra <= 0:
        return
    data = bytearray(path.read_bytes())
    chix = None
    for name, doff, length in pf2_sections(data):
        if name == "CHIX":
            chix = (doff, length)
        elif name == "MAXW":
            cur = struct.unpack_from(">H", data, doff)[0]
            struct.pack_into(">H", data, doff, cur + extra)
    if not chix:
        raise SystemExit(f"{path}: no CHIX section")
    doff, length = chix
    for i in range(length // 9):
        entry = doff + i * 9
        goff = struct.unpack_from(">I", data, entry + 5)[0]
        dw = struct.unpack_from(">H", data, goff + 8)[0]
        struct.pack_into(">H", data, goff + 8, dw + extra)
    path.write_bytes(bytes(data))


def pf2_advance(path: Path, char="M") -> int:
    """Advance width of one glyph, i.e. the cell width for a monospace font."""
    data = path.read_bytes()
    for name, doff, length in pf2_sections(data):
        if name != "CHIX":
            continue
        for i in range(length // 9):
            entry = doff + i * 9
            if struct.unpack_from(">I", data, entry)[0] == ord(char):
                goff = struct.unpack_from(">I", data, entry + 5)[0]
                return struct.unpack_from(">H", data, goff + 8)[0]
    return 0


def pf2_glyphs(path: Path):
    """Decode every glyph's 1bpp bitmap, so the preview can draw exactly what
    GRUB will draw rather than a smooth Pango approximation."""
    data = path.read_bytes()
    chix = next((s for s in pf2_sections(data) if s[0] == "CHIX"), None)
    if chix is None:
        raise SystemExit(f"{path}: no CHIX section")
    _, doff, length = chix
    out = {}
    for i in range(length // 9):
        entry = doff + i * 9
        code = struct.unpack_from(">I", data, entry)[0]
        goff = struct.unpack_from(">I", data, entry + 5)[0]
        w, h, x_ofs, y_ofs, dev = struct.unpack_from(">HhhhH", data, goff)
        out[code] = (w, h, x_ofs, y_ofs, dev, data[goff + 10:goff + 10 + (w * h + 7) // 8])
    return out


def draw_pf2_text(cr, glyphs, text, x, baseline, rgb, alpha=1.0):
    """Blit PFF2 glyph bitmaps the way grub_font_draw_string does."""
    rgba(cr, rgb, alpha)
    for ch in text:
        g = glyphs.get(ord(ch))
        if g is None:
            continue
        w, h, x_ofs, y_ofs, dev, bits = g
        top = baseline - (y_ofs + h)
        for row in range(h):
            base = row * w
            for col in range(w):
                idx = base + col
                if bits[idx >> 3] & (1 << (7 - (idx & 7))):
                    cr.rectangle(x + x_ofs + col, top + row, 1, 1)
        x += dev
    cr.fill()
    return x


def pf2_info(path: Path):
    data = path.read_bytes()
    info = {}
    for name, doff, length in pf2_sections(data):
        if name in ("ASCE", "DESC", "MAXW", "MAXH", "PTSZ"):
            info[name] = struct.unpack_from(">H", data, doff)[0]
        elif name == "NAME":
            info["NAME"] = data[doff : doff + length].rstrip(b"\0").decode()
    return info


def make_font(outdir: Path, ttf: Path, family: str, size: int, tracking: int):
    out = outdir / f"{family}-{size}.pf2"
    # PFF2 glyphs are 1 bit per pixel -- grub-mkfont renders with
    # FT_LOAD_RENDER | FT_LOAD_MONOCHROME and there is no antialiasing anywhere
    # in GRUB. That makes hinting the only lever on how the type reads.
    # IBM Plex's own TrueType hints leave uneven stems at these sizes; the
    # autohinter is more consistent at every size we build, and unhinted
    # rendering blobs together below ~14px.
    subprocess.run(
        ["grub-mkfont", "-s", str(size), "-n", family, "-r", GLYPH_RANGE,
         "--force-autohint", "-o", str(out), str(ttf)],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    pf2_add_tracking(out, tracking)
    info = pf2_info(out)
    expected = f"{family} Regular {size}"
    if info.get("NAME") != expected:
        raise SystemExit(f"{out}: font name is {info.get('NAME')!r}, expected {expected!r}")
    return expected, info, out


# --------------------------------------------------------------------------
# theme.txt
# --------------------------------------------------------------------------

THEME = """\
# YoRHa Boot Manager -- {variant} layout, {w}x{h}, {rows} rows
# GENERATED by yorha_theme.py from design/'{page}'.
# Do not edit; re-run ./build.sh instead.

# GRUB defaults title-text to "GRUB Boot Menu" and paints it centred at y=40.
# The design has its own header, so blank it out.
title-text: ""

desktop-image: "background.png"
desktop-image-scale-method: "stretch"
desktop-color: "#0c0a08"

terminal-font: "{term_font}"
terminal-box: "term_*.png"
terminal-left: "{term_left}"
terminal-top: "{term_top}"
terminal-width: "{term_w}"
terminal-height: "{term_h}"

+ boot_menu {{
    left = {menu_left}
    top = {menu_top}
    width = {menu_w}
    height = {menu_h}
    item_height = {item_height}
    item_spacing = {item_spacing}
    item_padding = 0
    item_icon_space = 0
    icon_width = 0
    icon_height = 0
    item_font = "{item_font}"
    selected_item_font = "{item_font}"
    item_color = "{item_color}"
    selected_item_color = "{sel_color}"
    item_pixmap_style = "item_*.png"
    selected_item_pixmap_style = "sel_*.png"
    scrollbar = false
}}

+ circular_progress {{
    id = "__timeout__"
    left = {ring_left}
    top = {ring_top}
    width = {ring_box}
    height = {ring_box}
    center_bitmap = "center.png"
    tick_bitmap = "tick.png"
    num_ticks = {num_ticks}
    ticks_disappear = true
    start_angle = "-90 deg"
}}

+ label {{
    id = "__timeout__"
    left = {digit_left}
    top = {digit_top}
    width = {digit_w}
    height = {digit_h}
    align = "center"
    font = "{digit_font}"
    color = "#f3ecdd"
}}
"""


def validate_theme(path: Path):
    """Check theme.txt against theme_loader.c's parsing rules.

    Global properties go through read_property(), which hard-errors unless the
    value starts with a quote -- and one bad line aborts the whole theme. The
    `key = value` properties inside a `+ component { }` block go through
    read_expression() instead, which does accept bare words.
    """
    depth = 0
    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        depth += line.count("{") - line.count("}")
        if depth > 0 or line.startswith("+") or line in ("{", "}"):
            continue
        if ":" in line:
            name, _, value = line.partition(":")
            if not value.strip().startswith('"'):
                raise SystemExit(
                    f"{path}:{lineno}: global property {name.strip()!r} value must be "
                    f'quoted -- GRUB rejects `{line}` and drops the whole theme'
                )
    if depth != 0:
        raise SystemExit(f"{path}: unbalanced braces")


def digit_geometry(g: Geo, digit_info):
    """Place the __timeout__ label so its baseline matches the design."""
    asc = digit_info["ASCE"]
    desc = digit_info["DESC"]
    box_top = g.u(g.digit_top_c)
    baseline = box_top + (g.u(4.8) - (asc + desc)) / 2 + asc
    width = g.u(RING_SIZE)
    return (
        int(round(g.ring_cx - width / 2)),
        int(round(baseline - asc)),
        int(round(width)),
        int(round(asc + desc)),
    )


# --------------------------------------------------------------------------
# preview
# --------------------------------------------------------------------------

SAMPLE = [
    "Arch Linux",
    "Advanced options for Arch Linux",
    "Windows Boot Manager",
    "UEFI Firmware Settings",
    "System setup",
]


def render_preview(g: Geo, outdir: Path, opts, item_info, digit_info,
                   item_pf2=None, digit_pf2=None):
    """Composite what GRUB will draw, using GRUB's own layout arithmetic."""
    remaining = opts.preview_remaining
    if remaining is None:
        remaining = opts.timeout
    surf = cairo.ImageSurface(cairo.FORMAT_RGB24, g.w, g.h)
    cr = cairo.Context(surf)
    cr.set_source_surface(cairo.ImageSurface.create_from_png(str(outdir / "background.png")), 0, 0)
    cr.paint()

    boxes = {s: reassemble(g, outdir, s) for s in ("item", "sel")}
    asc, desc = item_info["ASCE"], item_info["DESC"]
    text_top_offset = (g.item_height - (asc + desc)) // 2 + asc

    item_glyphs = pf2_glyphs(item_pf2)
    entries = SAMPLE[: g.rows]
    for i, title in enumerate(entries):
        item_top = i * (g.item_height + g.item_spacing)
        y = g.menu_top + item_top
        cr.set_source_surface(boxes["sel" if i == 0 else "item"], g.menu_left, y)
        cr.paint()
        # GRUB clips the title to the item's text viewport; no ellipsis.
        cr.save()
        cr.rectangle(g.menu_left + g.pad_w, y, g.content_w, g.item_visual_h)
        cr.clip()
        draw_pf2_text(cr, item_glyphs, title, g.menu_left + g.pad_w,
                      y + g.pad_n + text_top_offset, FG,
                      1.0 if i == 0 else DIM)
        cr.restore()

    # The countdown cluster -- center bitmap, ticks and digits -- is drawn only
    # while the timeout is live. Any arrow key cancels it and GRUB hides all
    # three, which is what remaining < 0 renders here.
    if remaining >= 0:
        cr.set_source_surface(
            cairo.ImageSurface.create_from_png(str(outdir / "center.png")),
            g.ring_left, g.ring_top,
        )
        cr.paint()

        tick = cairo.ImageSurface.create_from_png(str(outdir / "tick.png"))
        total = max(1, opts.timeout)
        nticks = (g.num_ticks * (total - remaining)) // total
        for i in range(nticks, g.num_ticks):
            angle = -math.pi / 2 + i * 2 * math.pi / g.num_ticks
            x = g.ring_box // 2 + math.cos(angle) * g.grub_ring_r - g.tick // 2
            y = g.ring_box // 2 + math.sin(angle) * g.grub_ring_r - g.tick // 2
            cr.set_source_surface(tick, g.ring_left + int(x), g.ring_top + int(y))
            cr.paint()

        dl, dt, dw, dh = digit_geometry(g, digit_info)
        digit_glyphs = pf2_glyphs(digit_pf2)
        secs = str(remaining)
        # label align=center uses grub_font_get_string_width, i.e. advances
        width = sum(digit_glyphs[ord(c)][4] for c in secs if ord(c) in digit_glyphs)
        draw_pf2_text(cr, digit_glyphs, secs, dl + (dw - width) // 2,
                      dt + digit_info["ASCE"], DIGIT)

    suffix = "-cancelled" if remaining < 0 else ""
    surf.flush()
    surf.write_to_png(str(outdir.parent / f"preview-{g.w}x{g.h}{suffix}.png"))


# --------------------------------------------------------------------------
# driver
# --------------------------------------------------------------------------


VARIANTS = {"left": "yorha", "centered": "yorha-centered"}
DESIGN_PAGE = {
    "left": "YoRHa Boot Manager.dc.html",
    "centered": "YoRHa Boot Manager - Centered.dc.html",
}


def build(w: int, h: int, opts, variant: str = "left") -> Path:
    centered = variant == "centered"
    g = Geo(w, h, opts.rows, opts.menu_width, centered)
    outdir = Path(opts.out) / VARIANTS[variant] / f"{w}x{h}"
    outdir.mkdir(parents=True, exist_ok=True)

    # fonts first: the item font's ascent/descent constrains the item box pads
    item_font, item_info, item_pf2 = make_font(
        outdir, VENDOR_FONTS / "ibmplexmono" / "IBMPlexMono-Light.ttf",
        "yorha-item", g.item_font_px, int(round(0.08 * g.item_font_px)),
    )
    digit_font, digit_info, digit_pf2 = make_font(
        outdir, VENDOR_FONTS / "chakrapetch" / "ChakraPetch-Regular.ttf",
        "yorha-digit", g.digit_font_px, int(round(0.04 * g.digit_font_px)),
    )
    term_font, _, _ = make_font(
        outdir, VENDOR_FONTS / "ibmplexmono" / "IBMPlexMono-Regular.ttf",
        "yorha-term", g.term_font_px, 0,
    )

    text_h = item_info["ASCE"] + item_info["DESC"]
    if g.item_height < text_h:
        raise SystemExit(
            f"{w}x{h}: item_height={g.item_height}px cannot hold {text_h}px of text; "
            "the design's 7cqh row is too short at this resolution."
        )

    bg = cairo.ImageSurface(cairo.FORMAT_RGB24, w, h)
    cr = cairo.Context(bg)
    paint_background(cr, g, opts)
    bg.flush()
    bg.write_to_png(str(outdir / "background.png"))

    for state, selected in (("item", False), ("sel", True)):
        authored = render_item(g, selected)
        write_slices(authored, g, outdir, state)
        # GRUB scales n/s to the content width and w/e to the content height,
        # both of which we authored at exactly those sizes, so its
        # reassembly must be pixel-identical to what we drew.
        rebuilt = reassemble(g, outdir, state)
        if bytes(authored.get_data()) != bytes(rebuilt.get_data()):
            raise SystemExit(f"{w}x{h}: {state}_*.png do not reassemble losslessly")
    write_tick(g, outdir)
    write_center(g, outdir)
    write_terminal_box(g, outdir)

    dl, dt, dw, dh = digit_geometry(g, digit_info)
    theme_path = outdir / "theme.txt"
    theme_path.write_text(
        THEME.format(
            variant=variant, page=DESIGN_PAGE[variant], w=w, h=h, rows=opts.rows,
            term_font=term_font,
            term_left=g.px(INSET_L), term_top=g.px(28.0),
            term_w=w - g.px(INSET_L) - g.px(INSET_R), term_h=g.px(56.0),
            menu_left=g.menu_left, menu_top=g.menu_top,
            menu_w=g.menu_w, menu_h=g.menu_h,
            item_height=g.item_height, item_spacing=g.item_spacing,
            item_font=item_font,
            item_color="#cfc8ba80", sel_color="#cfc8ba",
            ring_left=g.ring_left, ring_top=g.ring_top, ring_box=g.ring_box,
            num_ticks=g.num_ticks,
            digit_font=digit_font,
            digit_left=dl, digit_top=dt, digit_w=dw, digit_h=dh,
        )
    )
    validate_theme(theme_path)

    if opts.preview:
        render_preview(g, outdir, opts, item_info, digit_info, item_pf2, digit_pf2)

    size = sum(p.stat().st_size for p in outdir.iterdir())
    advance = pf2_advance(item_pf2)
    chars = g.content_w // advance if advance else 0
    ring = f"ring r={g.grub_ring_r} ticks={g.num_ticks}" if g.num_ticks else "no ring"
    print(
        f"{VARIANTS[variant]:14s} {w}x{h}: rows={opts.rows} item={g.item_visual_h}px "
        f"(box {g.item_height}+2x{g.pad_n}) font={g.item_font_px}px "
        f"title fits {chars} chars  {ring} -> {size / 1024:.0f} KiB"
    )
    return outdir


RESOLUTIONS = [
    (1920, 1080), (1920, 1200), (2560, 1440), (1600, 1200), (3840, 2160),
    (2256, 1504), (1280, 1024), (1024, 768), (800, 600), (640, 480),
]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("resolutions", nargs="*",
                    help="WxH to build (default: all ten supported modes)")
    ap.add_argument("--out", default=str(HERE / "dist"))
    ap.add_argument("--variant", choices=("left", "centered", "both"), default="both",
                    help="'left' is the base design page, 'centered' is the "
                         "'YoRHa Boot Manager - Centered' page (centred menu, no "
                         "countdown ring). Default builds both.")
    ap.add_argument("--rows", type=int, default=5,
                    help="menu rows to reserve space for (3-6, default 5)")
    ap.add_argument("--menu-width", type=float, default=MENU_W,
                    help="menu width in cqh (percent of screen height). The design "
                         f"uses {MENU_W:g}; widen it if your entry titles get clipped")
    ap.add_argument("--version", default="2.14", help="version string in the header")
    ap.add_argument("--default-target", default="ARCH LINUX")
    ap.add_argument("--timeout", type=int, default=10,
                    help="GRUB_TIMEOUT, only used to render the preview")
    ap.add_argument("--preview-remaining", type=int, default=None,
                    help="seconds left to draw in the preview (default: --timeout); "
                         "a negative value renders the state after the user has "
                         "pressed a key and GRUB cancelled the countdown")
    ap.add_argument("--no-grain", dest="grain", action="store_false")
    ap.add_argument("--no-crt", dest="crt", action="store_false")
    ap.add_argument("--no-grid", dest="grid", action="store_false")
    ap.add_argument("--no-preview", dest="preview", action="store_false")
    opts = ap.parse_args(argv)

    if not 3 <= opts.rows <= 6:
        ap.error("--rows must be between 3 and 6")
    if not EMBLEM.exists():
        ap.error(f"missing {EMBLEM}")
    if not (VENDOR_FONTS / "ibmplexmono" / "IBMPlexMono-Light.ttf").exists():
        ap.error("fonts not vendored yet -- run ./fetch-fonts.sh")

    if opts.resolutions:
        modes = []
        for spec in opts.resolutions:
            try:
                w, h = (int(v) for v in spec.lower().split("x"))
            except ValueError:
                ap.error(f"bad resolution {spec!r}, expected WxH")
            modes.append((w, h))
    else:
        modes = RESOLUTIONS

    variants = ("left", "centered") if opts.variant == "both" else (opts.variant,)
    for variant in variants:
        for w, h in modes:
            build(w, h, opts, variant)
    return 0


if __name__ == "__main__":
    sys.exit(main())
