#!/usr/bin/env python3
"""Draws the demo charset (demo/CharSet/Demo.png) procedurally.

RPG Maker 2000/2003 charset layout: 288x256, eight characters (4 across, 2 down) of
72x128, each with 3 walking frames (columns of 24 px) for 4 directions (rows of
32 px: up, right, down, left); 8-bit palette with colour 0 as the transparent key.
Every pixel is generated here, so it contains no RPG Maker assets. Requires Pillow.

    python3 tools/make_demo_charset.py demo/CharSet/Demo.png

Characters used by tools/make_demo_project.cpp: 0 hero, 1 villager.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

KEY = (255, 0, 255)
OUTLINE = (36, 28, 40)
SKIN = (248, 208, 168)
SKIN_D = (220, 168, 128)
EYE = (40, 32, 48)

CHARACTERS = {
    0: {"hair": (112, 64, 32), "hair_d": (84, 44, 20), "tunic": (56, 96, 200), "tunic_d": (36, 64, 152), "legs": (72, 56, 48)},
    1: {"hair": (236, 196, 88), "hair_d": (200, 156, 56), "tunic": (72, 152, 72), "tunic_d": (48, 112, 52), "legs": (120, 88, 56)},
}
UP, RIGHT, DOWN, LEFT = range(4)

img = Image.new("RGB", (288, 256), KEY)
draw = ImageDraw.Draw(img)


def rect(x0, y0, x1, y1, color, outline=True):
    if outline:
        draw.rectangle([x0 - 1, y0 - 1, x1 + 1, y1 + 1], fill=OUTLINE)
    draw.rectangle([x0, y0, x1, y1], fill=color)


def character(ox, oy, look, direction, frame):
    step = (-1, 0, 1)[frame]  # left foot forward, standing, right foot forward
    # Legs (drawn first, behind the body)
    if direction in (UP, DOWN):
        rect(ox + 9, oy + 24 + max(0, step), ox + 10, oy + 29 + max(0, step) - (1 if step > 0 else 0), look["legs"])
        rect(ox + 13, oy + 24 + max(0, -step), ox + 14, oy + 29 + max(0, -step) - (1 if step < 0 else 0), look["legs"])
    else:
        forward = 1 if direction == RIGHT else -1
        rect(ox + 11 + step * forward, oy + 24, ox + 12 + step * forward, oy + 29, look["legs"])
        rect(ox + 11 - step * forward, oy + 24, ox + 12 - step * forward, oy + 29, look["legs"])
    # Body and arms
    rect(ox + 7, oy + 16, ox + 16, oy + 24, look["tunic"])
    draw.rectangle([ox + 7, oy + 22, ox + 16, oy + 24], fill=look["tunic_d"])
    swing = step if frame != 1 else 0
    if direction in (UP, DOWN):
        rect(ox + 5, oy + 17 + swing, ox + 6, oy + 22 + swing, look["tunic_d"])
        rect(ox + 17, oy + 17 - swing, ox + 18, oy + 22 - swing, look["tunic_d"])
    else:
        x = ox + (13 if direction == RIGHT else 9)
        rect(x, oy + 17, x + 1, oy + 22, look["tunic_d"])
    # Head
    draw.ellipse([ox + 4, oy + 2, ox + 19, oy + 17], fill=OUTLINE)
    draw.ellipse([ox + 5, oy + 3, ox + 18, oy + 16], fill=SKIN)
    draw.ellipse([ox + 5, oy + 12, ox + 18, oy + 16], fill=SKIN_D)
    draw.ellipse([ox + 5, oy + 3, ox + 18, oy + 13], fill=SKIN)
    # Hair
    if direction == UP:
        draw.ellipse([ox + 5, oy + 3, ox + 18, oy + 16], fill=look["hair"])
        draw.rectangle([ox + 6, oy + 12, ox + 17, oy + 14], fill=look["hair_d"])
    else:
        draw.chord([ox + 5, oy + 2, ox + 18, oy + 14], 180, 360, fill=look["hair"])
        if direction == LEFT:
            draw.rectangle([ox + 13, oy + 7, ox + 18, oy + 12], fill=look["hair_d"])
        elif direction == RIGHT:
            draw.rectangle([ox + 5, oy + 7, ox + 10, oy + 12], fill=look["hair_d"])
    # Eyes
    if direction == DOWN:
        draw.rectangle([ox + 8, oy + 10, ox + 9, oy + 12], fill=EYE)
        draw.rectangle([ox + 14, oy + 10, ox + 15, oy + 12], fill=EYE)
    elif direction == LEFT:
        draw.rectangle([ox + 7, oy + 10, ox + 8, oy + 12], fill=EYE)
    elif direction == RIGHT:
        draw.rectangle([ox + 15, oy + 10, ox + 16, oy + 12], fill=EYE)


for index, look in CHARACTERS.items():
    cx, cy = (index % 4) * 72, (index // 4) * 128
    for direction in range(4):
        for frame in range(3):
            character(cx + frame * 24, cy + direction * 32, look, direction, frame)

# --- save as an 8-bit indexed PNG with the key colour at index 0 -------------------

px = img.load()
pixels = [px[x, y] for y in range(img.height) for x in range(img.width)]
colors = [KEY] + sorted(set(pixels) - {KEY})
assert len(colors) <= 256, len(colors)
index = {c: i for i, c in enumerate(colors)}
out = Image.new("P", img.size)
out.putpalette([v for c in colors for v in c] + [0] * (768 - 3 * len(colors)))
out.putdata([index[c] for c in pixels])
target = Path(sys.argv[1] if len(sys.argv) > 1 else "demo/CharSet/Demo.png")
target.parent.mkdir(parents=True, exist_ok=True)
out.save(target, optimize=True)
print(f"Wrote {target} ({len(colors)} colours)")
