#!/usr/bin/env python3
"""Draws the demo chipset (demo/ChipSet/Demo.png) procedurally.

The image follows the RPG Maker 2000/2003 chipset layout (480x256, 16x16 tiles,
8-bit palette with colour 0 as the transparent key), but every pixel is generated
here, so it contains no RPG Maker assets. Requires Pillow.

    python3 tools/make_demo_chipset.py demo/ChipSet/Demo.png

Tile numbers used by tools/make_demo_project.cpp:
  lower (5000 + n): 0 grass, 1 yellow flowers, 2 red flowers, 3 tall grass, 4 sand,
                    5 dirt, 6 stone floor, 7 wood floor, 8 wall top, 9 brick wall,
                    10 darkness, 11 carpet
  upper (10000 + n): 0 empty, 1/7 tree top/bottom, 2 bush, 3 rock, 4 fence, 5 sign,
                     8/9/10 roof left/middle/right, 12 window wall, 13 wall, 14 door,
                     15 chest, 16 table, 17 barrel
  ground autotiles: D1 grass, D2 dirt path, D3 dark grass, D4 stone path
"""

import math
import random
import sys
from pathlib import Path

from PIL import Image

KEY = (255, 0, 255)
T = 16

C = {
    "grass": (88, 160, 64), "grass_d": (64, 132, 52), "grass_l": (120, 184, 80),
    "dgrass": (56, 120, 56), "dgrass_d": (40, 96, 44), "dgrass_l": (76, 144, 64),
    "water": (56, 112, 200), "water_l": (104, 156, 232), "water_d": (44, 92, 176),
    "foam": (208, 228, 248), "deep": (28, 60, 136), "deep_l": (48, 88, 168),
    "ice": (88, 168, 200), "ice_l": (150, 210, 232), "snow": (236, 240, 248), "snow_d": (196, 208, 224),
    "sand": (220, 196, 132), "sand_d": (188, 164, 100),
    "dirt": (164, 116, 68), "dirt_d": (128, 88, 48), "dirt_l": (188, 140, 92),
    "stone": (152, 152, 164), "stone_d": (108, 108, 120), "stone_l": (188, 188, 200),
    "wood": (176, 120, 64), "wood_d": (136, 88, 44), "wood_l": (204, 148, 88),
    "leaf": (44, 124, 52), "leaf_d": (28, 92, 36), "leaf_l": (80, 160, 68), "trunk": (112, 72, 36),
    "rock": (132, 132, 140), "rock_d": (90, 90, 100), "rock_l": (180, 180, 188),
    "roof": (180, 60, 52), "roof_d": (132, 40, 36), "roof_l": (212, 92, 76),
    "wall": (228, 212, 180), "wall_d": (188, 172, 140), "window": (124, 180, 228),
    "door": (124, 76, 36), "gold": (236, 196, 64), "yellow": (248, 216, 64),
    "red": (232, 72, 72), "white": (248, 248, 248), "black": (20, 20, 28),
    "carpet": (172, 40, 60), "carpet_l": (204, 72, 88), "shadow": (40, 72, 40),
}

img = Image.new("RGB", (480, 256), KEY)
px = img.load()


def put(x, y, color):
    if 0 <= x < 480 and 0 <= y < 256:
        px[x, y] = C[color] if isinstance(color, str) else color


def tile_origin(tx, ty):
    return tx * T, ty * T


def textured(ox, oy, w, h, base, light, dark, seed, density=0.12):
    rnd = random.Random(seed)
    for y in range(h):
        for x in range(w):
            r = rnd.random()
            put(ox + x, oy + y, light if r < density else dark if r < density * 2 else base)


# --- water (columns 0-5, rows 0-7) -------------------------------------------

def water_pixel(x, y, frame, deep=False, ice=False):
    if deep:
        return "deep_l" if (x * 3 + y * 5 + frame * 4) % 23 == 0 else "deep"
    base, light = ("ice", "ice_l") if ice else ("water", "water_l")
    wave = (y + frame * 2) % 8 == 0 and (x + y // 8 * 3 + frame) % 6 < 3
    return light if wave else base


def shore_tile(ox, oy, sides, inner, frame, ice=False):
    """sides: set of 'l','t','r','b' that border land; inner: draw land notches in corners."""
    land, rim = ("snow", "snow_d") if ice else ("grass", "sand")
    R = 6
    for y in range(T):
        for x in range(T):
            fx, fy = x + 0.5, y + 0.5
            dists = []
            if "l" in sides: dists.append(fx)
            if "t" in sides: dists.append(fy)
            if "r" in sides: dists.append(T - fx)
            if "b" in sides: dists.append(T - fy)
            e = min(dists) if dists else 99
            for cx, cy, a, b in ((R, R, "l", "t"), (T - R, R, "r", "t"), (R, T - R, "l", "b"), (T - R, T - R, "r", "b")):
                in_corner = (fx < R if a == "l" else fx > T - R) and (fy < R if b == "t" else fy > T - R)
                if a in sides and b in sides and in_corner:
                    e = R - math.hypot(fx - cx, fy - cy)
            if inner:
                for cx, cy in ((0, 0), (T, 0), (0, T), (T, T)):
                    e = min(e, math.hypot(fx - cx, fy - cy) - 3)
            if e < 1.5:
                color = land
            elif e < 3.5:
                color = rim
            elif e < 4.5:
                color = "foam" if not ice else "ice_l"
            else:
                color = water_pixel(x, y, frame, ice=ice)
            put(ox + x, oy + y, color)


def water_body(ox, oy, frame, kind):
    for y in range(T):
        for x in range(T):
            if kind == "shallow":
                c = water_pixel(x, y, frame)
            elif kind == "shallow_deep":
                c = "water_d" if (x + y) % 2 else water_pixel(x, y, frame)
            elif kind == "deep_shallow":
                c = "water_d" if (x + y) % 2 else water_pixel(x, y, frame, deep=True)
            else:
                c = water_pixel(x, y, frame, deep=True)
            put(ox + x, oy + y, c)


SHORE_ROWS = [({"l", "t", "r", "b"}, False), ({"l", "r"}, False), ({"t", "b"}, False), (set(), True)]
for frame in range(3):
    for row, (sides, inner) in enumerate(SHORE_ROWS):
        shore_tile(*tile_origin(frame, row), sides, inner, frame)            # A1
        shore_tile(*tile_origin(3 + frame, row), sides, inner, frame, True)  # A2
    for row, kind in enumerate(["shallow", "shallow_deep", "deep_shallow", "deep"]):
        water_body(*tile_origin(frame, 4 + row), frame, kind)

# --- animated tiles C1-C3 (columns 3-5, rows 4-7, one row per frame) ------------

for frame in range(4):
    ox, oy = tile_origin(3, 4 + frame)  # C1: waterfall
    for y in range(T):
        for x in range(T):
            put(ox + x, oy + y, "foam" if (y - frame * 4 + x * 7) % 12 < 2 else "water_l" if x % 5 == 0 else "water")
    ox, oy = tile_origin(4, 4 + frame)  # C2: flickering flowers
    textured(ox, oy, T, T, "grass", "grass_l", "grass_d", 40)
    for i, (fx, fy) in enumerate(((3, 3), (11, 5), (6, 11), (13, 12))):
        color = "yellow" if (i + frame) % 2 else "red"
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            put(ox + fx + dx, oy + fy + dy, color)
    ox, oy = tile_origin(5, 4 + frame)  # C3: sparkle on stone
    textured(ox, oy, T, T, "stone", "stone_l", "stone_d", 41)
    s = 2 + frame % 2 * 2
    for d in range(-s, s + 1):
        put(ox + 8 + d, oy + 8, "white")
        put(ox + 8, oy + 8 + d, "white")

# --- ground autotiles D1-D12 ------------------------------------------------------


def block_origin(block):
    if block < 4:
        return (block % 2) * 3, 8 + (block // 2) * 4
    return 6 + (block % 2) * 3, ((block - 4) // 2) * 4


def terrain_pixel(terrain, x, y, rnd):
    base, light, dark = terrain
    r = rnd.random()
    return light if r < 0.1 else dark if r < 0.2 else base


def autotile_block(block, terrain, border, outside, seed):
    tx, ty = block_origin(block)
    ox, oy = tile_origin(tx, ty)
    rnd = random.Random(seed)
    R = 7
    # rows 1-3: a framed 48x48 patch of the terrain
    for y in range(48):
        for x in range(48):
            fx, fy = x + 0.5, y + 0.5
            e = min(fx, fy, 48 - fx, 48 - fy)
            for cx, cy in ((R, R), (48 - R, R), (R, 48 - R), (48 - R, 48 - R)):
                if (fx < R or fx > 48 - R) and (fy < R or fy > 48 - R):
                    e = R - math.hypot(fx - cx, fy - cy)
            color = terrain_pixel(outside, x, y, rnd) if e < 1.5 else border if e < 3 else terrain_pixel(terrain, x, y, rnd)
            put(ox + x, oy + T + y, color)
    # row 0: preview, spare, inner corners
    for y in range(T):
        for x in range(T):
            put(ox + x, oy + y, terrain_pixel(terrain, x, y, rnd))
            put(ox + T + x, oy + y, terrain_pixel(terrain, x, y, rnd))
            fx, fy = x + 0.5, y + 0.5
            e = min(math.hypot(fx - cx, fy - cy) for cx, cy in ((0, 0), (T, 0), (0, T), (T, T))) - 3
            color = terrain_pixel(outside, x, y, rnd) if e < 1.5 else border if e < 3 else terrain_pixel(terrain, x, y, rnd)
            put(ox + 2 * T + x, oy + y, color)


GRASS = (C["grass"], C["grass_l"], C["grass_d"])
TERRAINS = [
    (GRASS, C["grass"]),                                             # D1 grass
    ((C["dirt"], C["dirt_l"], C["dirt_d"]), C["dirt_d"]),            # D2 dirt path
    ((C["dgrass"], C["dgrass_l"], C["dgrass_d"]), C["dgrass_d"]),    # D3 dark grass
    ((C["stone"], C["stone_l"], C["stone_d"]), C["stone_d"]),        # D4 stone path
    ((C["sand"], C["wall"], C["sand_d"]), C["sand_d"]),              # D5 sand
    ((C["snow"], C["white"], C["snow_d"]), C["snow_d"]),             # D6 snow
]
for block in range(12):
    terrain, border = TERRAINS[block % len(TERRAINS)]
    autotile_block(block, terrain, border, GRASS, 100 + block)

# --- lower tiles E (5000 + n) -------------------------------------------------------


def lower_origin(n):
    return tile_origin(12 + n % 6, n // 6) if n < 96 else tile_origin(18 + (n - 96) % 6, (n - 96) // 6)


def flowers(ox, oy, color, seed):
    rnd = random.Random(seed)
    for _ in range(5):
        x, y = rnd.randrange(1, 14), rnd.randrange(1, 14)
        put(ox + x, oy + y, color)
        put(ox + x + 1, oy + y, color)
        put(ox + x, oy + y + 1, "white" if color == "yellow" else color)


def lower_tile(n, ox, oy):
    if n == 0:
        textured(ox, oy, T, T, "grass", "grass_l", "grass_d", 200)
    elif n in (1, 2):
        textured(ox, oy, T, T, "grass", "grass_l", "grass_d", 200 + n)
        flowers(ox, oy, "yellow" if n == 1 else "red", 300 + n)
    elif n == 3:
        textured(ox, oy, T, T, "grass", "grass_l", "grass_d", 203)
        for x in range(1, 16, 3):
            for d in range(4):
                put(ox + x + (d % 2), oy + 12 - d - (x % 2) * 5, "leaf_d")
    elif n == 4:
        textured(ox, oy, T, T, "sand", "wall", "sand_d", 204)
    elif n == 5:
        textured(ox, oy, T, T, "dirt", "dirt_l", "dirt_d", 205)
    elif n == 6:
        for y in range(T):
            for x in range(T):
                put(ox + x, oy + y, "stone_d" if x % 8 == 0 or y % 8 == 0 else "stone_l" if (x + y) % 9 == 0 else "stone")
    elif n == 7:
        for y in range(T):
            for x in range(T):
                put(ox + x, oy + y, "wood_d" if y % 4 == 0 or (x == (y // 4 * 5) % 16) else "wood_l" if (x * 3 + y) % 11 == 0 else "wood")
    elif n == 8:
        for y in range(T):
            for x in range(T):
                put(ox + x, oy + y, "wall_d" if y > 12 else "wall")
    elif n == 9:
        for y in range(T):
            for x in range(T):
                mortar = y % 4 == 3 or (x + (y // 4) * 4) % 8 == 7
                put(ox + x, oy + y, "wall_d" if mortar else "roof_l" if (x + y) % 7 == 0 else "roof")
    elif n == 10:
        textured(ox, oy, T, T, "black", "black", "black", 210)
    elif n == 11:
        for y in range(T):
            for x in range(T):
                put(ox + x, oy + y, "gold" if y in (1, 14) else "carpet_l" if (x + y) % 4 == 0 else "carpet")


for n in range(12):
    lower_tile(n, *lower_origin(n))

# --- upper tiles F (10000 + n); colour 0 (KEY) is transparent --------------------


def upper_origin(n):
    return tile_origin(18 + n % 6, 8 + n // 6) if n < 48 else tile_origin(24 + (n - 48) % 6, (n - 48) // 6)


def disc(cx, cy, r, color, ox, oy, shade=None):
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if d <= r:
                c = color
                if shade and (x - cx) + (y - cy) > r * 0.6:
                    c = shade[1]
                elif shade and (x - cx) + (y - cy) < -r * 0.8:
                    c = shade[0]
                put(ox + x, oy + y, c)


def rect(ox, oy, x0, y0, x1, y1, color):
    for y in range(y0, y1):
        for x in range(x0, x1):
            put(ox + x, oy + y, color)


# Tree: n=1 (top) above n=7 (bottom) in the same column, drawn as one 16x32 picture.
ox, oy = upper_origin(1)
rect(ox, oy, 6, 22, 10, 30, "trunk")
rect(ox, oy, 4, 29, 12, 31, "shadow")
disc(8, 11, 7.5, "leaf", ox, oy, ("leaf_l", "leaf_d"))
disc(5, 16, 4.5, "leaf", ox, oy, ("leaf_l", "leaf_d"))
disc(11, 17, 4.5, "leaf", ox, oy, ("leaf_l", "leaf_d"))

ox, oy = upper_origin(2)  # bush
disc(8, 10, 5.5, "leaf", ox, oy, ("leaf_l", "leaf_d"))
disc(4.5, 12, 3.5, "leaf", ox, oy, ("leaf_l", "leaf_d"))
disc(11.5, 12, 3.5, "leaf", ox, oy, ("leaf_l", "leaf_d"))

ox, oy = upper_origin(3)  # rock
disc(8, 10, 5.5, "rock", ox, oy, ("rock_l", "rock_d"))

ox, oy = upper_origin(4)  # fence
rect(ox, oy, 0, 6, 16, 8, "wood")
rect(ox, oy, 0, 11, 16, 13, "wood")
for x0 in (2, 12):
    rect(ox, oy, x0, 3, x0 + 2, 15, "wood_d")

ox, oy = upper_origin(5)  # sign
rect(ox, oy, 7, 9, 9, 15, "trunk")
rect(ox, oy, 2, 3, 14, 10, "wood")
rect(ox, oy, 4, 5, 12, 6, "wood_d")
rect(ox, oy, 4, 7, 10, 8, "wood_d")

for i, n in enumerate((8, 9, 10)):  # roof left/middle/right
    ox, oy = upper_origin(n)
    for y in range(T):
        for x in range(T):
            edge = (i == 0 and x < 2) or (i == 2 and x > 13)
            put(ox + x, oy + y, "roof_d" if y % 4 == 3 or edge else "roof_l" if (x + y * 3) % 8 == 0 else "roof")

for n in (12, 13, 14):  # house front: window, plain wall, door
    ox, oy = upper_origin(n)
    rect(ox, oy, 0, 0, 16, 16, "wall")
    rect(ox, oy, 0, 0, 16, 1, "wall_d")
    if n == 12:
        rect(ox, oy, 3, 3, 13, 12, "wood_d")
        rect(ox, oy, 4, 4, 12, 11, "window")
        rect(ox, oy, 7, 4, 9, 11, "wood_d")
    if n == 14:
        rect(ox, oy, 3, 2, 13, 16, "door")
        rect(ox, oy, 4, 3, 12, 16, "wood")
        put(ox + 10, oy + 9, "gold")

ox, oy = upper_origin(15)  # chest
rect(ox, oy, 2, 5, 14, 14, "wood_d")
rect(ox, oy, 3, 6, 13, 13, "wood")
rect(ox, oy, 2, 8, 14, 9, "gold")
rect(ox, oy, 7, 8, 9, 11, "gold")

ox, oy = upper_origin(16)  # table
rect(ox, oy, 1, 4, 15, 10, "wood_l")
rect(ox, oy, 1, 10, 15, 11, "wood_d")
rect(ox, oy, 2, 11, 4, 15, "wood_d")
rect(ox, oy, 12, 11, 14, 15, "wood_d")

ox, oy = upper_origin(17)  # barrel
rect(ox, oy, 4, 3, 12, 15, "wood")
rect(ox, oy, 4, 5, 12, 6, "wood_d")
rect(ox, oy, 4, 11, 12, 12, "wood_d")
rect(ox, oy, 5, 3, 11, 4, "wood_l")

# --- save as an 8-bit indexed PNG with the key colour at index 0 -------------------

pixels = [px[x, y] for y in range(img.height) for x in range(img.width)]
colors = [KEY] + sorted(set(pixels) - {KEY})
assert len(colors) <= 256, len(colors)
index = {c: i for i, c in enumerate(colors)}
out = Image.new("P", img.size)
out.putpalette([v for c in colors for v in c] + [0] * (768 - 3 * len(colors)))
out.putdata([index[c] for c in pixels])
target = Path(sys.argv[1] if len(sys.argv) > 1 else "demo/ChipSet/Demo.png")
target.parent.mkdir(parents=True, exist_ok=True)
out.save(target, optimize=True)
print(f"Wrote {target} ({len(colors)} colours)")
