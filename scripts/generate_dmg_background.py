#!/usr/bin/env python3
"""Generates a DMG background image with a drag-to-Applications arrow."""
import sys
import subprocess

try:
    from PIL import Image, ImageDraw
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow", "-q"])
    from PIL import Image, ImageDraw

W, H = 660, 400
BG = (72, 72, 74)          # mid-dark — dark enough to look intentional, light enough for Finder's black labels
ARROW = (40, 40, 42)
LABEL = (255, 255, 255)

img = Image.new("RGB", (W, H), color=BG)
draw = ImageDraw.Draw(img)

# Subtle separator line
draw.line([(0, H - 80), (W, H - 80)], fill=(55, 55, 58), width=1)

# Right-pointing arrow centered between icon (x=180) and Applications (x=480)
cx, cy = W // 2, H // 2 - 10
aw = 40   # half-width of shaft
sh = 8    # shaft half-height
hh = 22   # arrowhead half-height
hp = 30   # arrowhead depth

draw.rectangle([cx - aw, cy - sh, cx + hp // 2, cy + sh], fill=ARROW)
draw.polygon([
    (cx + hp // 2,       cy - hh),
    (cx + hp // 2 + hp,  cy),
    (cx + hp // 2,       cy + hh),
], fill=ARROW)

# Labels
try:
    from PIL import ImageFont
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 13)
except Exception:
    font = None

def centered_text(text, x, y):
    if font:
        bbox = draw.textbbox((0, 0), text, font=font)
        w = bbox[2] - bbox[0]
        draw.text((x - w // 2, y), text, fill=LABEL, font=font)
    else:
        draw.text((x, y), text, fill=LABEL)

centered_text("Drag to install", cx, H - 65)

out = sys.argv[1] if len(sys.argv) > 1 else "dmg_background.png"
img.save(out, "PNG")
print(f"Background saved → {out}")
