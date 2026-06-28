#!/usr/bin/env -S fontforge -script
# Build a tiny single-glyph font from YORHA_clear.svg so kitty can map a
# codepoint to it via symbol_map. Keeps the YoRHa emblem out of the Nerd Font
# itself (survives font-package updates).
import fontforge
import psMat
import os

SVG = "/home/koios/Downloads/YORHA_clear.svg"
OUT_DIR = os.path.expanduser("~/.local/share/fonts")
OUT = os.path.join(OUT_DIR, "YoRHaSymbols-Regular.ttf")
CODEPOINT = 0x100000  # Plane-16 PUA, unused by Nerd Fonts

EM = 1000
ASCENT = 800
DESCENT = 200
FILL = 1.0  # fraction of the em the emblem fills (bump up to enlarge the logo)

os.makedirs(OUT_DIR, exist_ok=True)

font = fontforge.font()
font.em = EM
font.ascent = ASCENT
font.descent = DESCENT
font.familyname = "YoRHa Symbols"
font.fontname = "YoRHaSymbols-Regular"
font.fullname = "YoRHa Symbols"
font.encoding = "UnicodeFull"

g = font.createChar(CODEPOINT, "yorha")
g.importOutlines(SVG)

# Clean up the emblem so TrueType fills/holes render correctly.
g.removeOverlap()
g.correctDirection()
g.round()

# Fit the glyph into ~78% of the em, centred in a 1-em advance.
xmin, ymin, xmax, ymax = g.boundingBox()
w = xmax - xmin
h = ymax - ymin
if max(w, h) > 0:
    scale = (FILL * EM) / max(w, h)
    g.transform(psMat.scale(scale))

xmin, ymin, xmax, ymax = g.boundingBox()
w = xmax - xmin
h = ymax - ymin
g.width = EM
midline = (ASCENT - DESCENT) / 2.0   # optical centre of the text line
dx = (EM - w) / 2.0 - xmin
dy = midline - (ymin + h / 2.0)
g.transform(psMat.translate(dx, dy))
g.width = EM

font.generate(OUT)
print("Wrote", OUT)
