"""Shared pixel-art helpers for the demo tilesets. Textures repeat every 16 px so tiles line up."""
from PIL import Image

T = 16

# Materials: base colour, dark and light speckle, border colour
MATERIALS = {
    "grass": ((96, 170, 62), (74, 142, 48), (128, 196, 84), (52, 104, 36)),
    "lush": ((70, 150, 70), (54, 124, 56), (98, 176, 90), (36, 92, 40)),
    "dirt": ((168, 120, 74), (142, 98, 58), (190, 142, 94), (110, 74, 44)),
    "sand": ((222, 200, 142), (200, 176, 120), (238, 222, 170), (170, 146, 94)),
    "water": ((66, 132, 204), (54, 112, 186), (110, 170, 226), (40, 84, 150)),
    "stone": ((138, 138, 146), (112, 112, 122), (166, 166, 174), (78, 78, 88)),
    "snow": ((236, 242, 248), (212, 222, 234), (255, 255, 255), (150, 170, 196)),
}


def texel(material, x, y):
    """The material's colour at a pixel, patterned with a 16 pixel period."""
    base, dark, light, _ = MATERIALS[material]
    x %= 16
    y %= 16
    if material == "water":
        if (x + 2 * y) % 16 in (0, 1) and y % 4 == 1:
            return light
        return dark if (y // 4) % 2 and (x * 3 + y) % 16 == 5 else base
    if material == "lush" and (x * 7 + y * 11) % 16 == 3 and y % 3 == 0:
        return (236, 150, 186) if x % 2 else (250, 230, 120)
    if (x * 5 + y * 3) % 16 == 0 or (x * 3 + y * 7) % 16 == 5:
        return dark
    if (x * 7 + y * 5) % 16 == 9:
        return light
    return base


def _open_close(region, size, r):
    """Rounds the corners of a boolean region (list of rows) with radius r."""
    def morph(src, grow):
        out = [[False] * size for _ in range(size)]
        for y in range(size):
            for x in range(size):
                hit = False
                for dy in range(-r, r + 1):
                    for dx in range(-r, r + 1):
                        if dx * dx + dy * dy > r * r:
                            continue
                        yy, xx = min(max(y + dy, 0), size - 1), min(max(x + dx, 0), size - 1)
                        if src[yy][xx] == grow:
                            hit = True
                            break
                    if hit:
                        break
                out[y][x] = grow if hit else not grow
        return out
    # Only outer corners are rounded; inner corners stay sharp so their tile shows them
    return morph(morph(region, False), True)


def cell_region(grid, r=4):
    """A 48x48 region from a 3x3 grid of '#' (inside) and '.' (outside) cells."""
    region = [[grid[y // 16][x // 16] == "#" for x in range(48)] for y in range(48)]
    return _open_close(region, 48, r) if r else region


def corner_region(corners, r=4):
    """A 48x48 region for a vertex tile: corners is 'tl tr bl br' as four '#'/'.' chars.
    Each corner of the middle tile owns the 16x16 square centred on it."""
    tl, tr, bl, br = corners
    def at(x, y):
        cx = 0 if x < 24 else 1
        cy = 0 if y < 24 else 1
        return [[tl, tr], [bl, br]][cy][cx] == "#"
    region = [[at(x, y) for x in range(48)] for y in range(48)]
    return _open_close(region, 48, r) if r else region


def render_region(region, inside, outside=None, border=2):
    """Middle 16x16 of a 48x48 region: inside material with a darker rim, outside elsewhere."""
    img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    rim = MATERIALS[inside][3]
    for py in range(16, 32):
        for px in range(16, 32):
            if region[py][px]:
                near = any(not region[min(max(py + dy, 0), 47)][min(max(px + dx, 0), 47)]
                           for dy in range(-border, border + 1) for dx in range(-border, border + 1)
                           if abs(dx) + abs(dy) <= border)
                edge = any(not region[min(max(py + dy, 0), 47)][min(max(px + dx, 0), 47)]
                           for dy in (-1, 0, 1) for dx in (-1, 0, 1))
                col = rim if edge else (MATERIALS[inside][2] if near and inside != "water" else texel(inside, px, py))
                img.putpixel((px - 16, py - 16), col + (255,))
            elif outside:
                img.putpixel((px - 16, py - 16), texel(outside, px, py) + (255,))
    return img


def fill(material):
    img = Image.new("RGBA", (T, T))
    for y in range(T):
        for x in range(T):
            img.putpixel((x, y), texel(material, x, y) + (255,))
    return img


# The 3x3 contexts of a blob-lite set: edges, corners, inner corners
BLOB = {
    "tl": ["...", ".##", ".##"], "t": ["...", "###", "###"], "tr": ["...", "##.", "##."],
    "l": [".##", ".##", ".##"], "c": ["###", "###", "###"], "r": ["##.", "##.", "##."],
    "bl": [".##", ".##", "..."], "b": ["###", "###", "..."], "br": ["##.", "##.", "..."],
    "itl": [".##", "###", "###"], "itr": ["##.", "###", "###"],
    "ibl": ["###", "###", ".##"], "ibr": ["###", "###", "##."],
    "one": ["...", ".#.", "..."],
}

# Match Tiles peering for each piece, as sides that must be the same terrain
BLOB_SIDES = {
    "tl": ["r", "b", "br"], "t": ["l", "r", "b", "bl", "br"], "tr": ["l", "b", "bl"],
    "l": ["t", "b", "r", "tr", "br"], "c": ["r", "br", "b", "bl", "l", "tl", "t", "tr"],
    "r": ["t", "b", "l", "tl", "bl"], "bl": ["r", "t", "tr"], "b": ["l", "r", "t", "tl", "tr"],
    "br": ["l", "t", "tl"],
    "itl": ["r", "br", "b", "bl", "l", "t", "tr"], "itr": ["r", "br", "b", "bl", "l", "tl", "t"],
    "ibl": ["r", "br", "b", "l", "tl", "t", "tr"], "ibr": ["r", "b", "bl", "l", "tl", "t", "tr"],
    "one": [],
}
BLOB_LAYOUT = {
    "tl": (0, 0), "t": (1, 0), "tr": (2, 0), "itl": (3, 0), "itr": (4, 0),
    "l": (0, 1), "c": (1, 1), "r": (2, 1), "ibl": (3, 1), "ibr": (4, 1),
    "bl": (0, 2), "b": (1, 2), "br": (2, 2), "one": (3, 2),
}

# The 16 vertex tiles, as corner strings "tl tr bl br"
VERTEX = ["".join("#" if (i >> b) & 1 else "." for b in range(4)) for i in range(16)]


def sprite(pixels, palette):
    """A sprite from rows of palette keys ('.' is transparent)."""
    h, w = len(pixels), len(pixels[0])
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y, row in enumerate(pixels):
        for x, ch in enumerate(row):
            if ch != ".":
                img.putpixel((x, y), palette[ch] + (255,))
    return img


def tree(w, h, leaves=(62, 128, 58), dark=(40, 92, 44), light=(98, 168, 84), trunk=(112, 76, 48)):
    """A round-crowned tree w x h tiles, trunk at the bottom centre."""
    W, H = w * T, h * T
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cx, cy = W / 2, (H - 10) / 2
    rx, ry = W / 2 - 1, (H - 10) / 2
    for y in range(H):
        for x in range(W):
            nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            d = nx * nx + ny * ny
            if d <= 1:
                col = dark if d > 0.82 else (light if nx < -0.2 and ny < -0.25 and d < 0.55 else leaves)
                if (x * 3 + y * 5) % 11 == 0 and d < 0.8:
                    col = dark
                img.putpixel((x, y), col + (255,))
    for y in range(H - 12, H - 1):
        for x in range(int(cx) - 2, int(cx) + 2):
            if img.getpixel((x, y))[3] == 0 or y > H - 8:
                img.putpixel((x, y), (trunk if x < cx else tuple(max(c - 30, 0) for c in trunk)) + (255,))
    return img


def small(kind, seed=0):
    """A 16x16 prop on a transparent background: flower, tuft, pebble, bush, mushroom."""
    img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    put = lambda x, y, c: img.putpixel((x % T, y % T), c + (255,))
    if kind == "flower":
        petals = [(236, 96, 120), (250, 214, 90), (170, 130, 230), (250, 250, 250)][seed % 4]
        for fx, fy in [(4, 5), (10, 9), (6, 12)][: 2 + seed % 2]:
            put(fx, fy + 1, (60, 120, 50))
            put(fx, fy + 2, (60, 120, 50))
            for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                put(fx + dx, fy + dy, petals)
            put(fx, fy, (240, 190, 60))
    elif kind == "tuft":
        for bx in [(4, 3), (9, 4), (12, 2)][seed % 3 : seed % 3 + 2]:
            x0, hgt = bx
            for i in range(hgt + 2):
                put(x0 - 1, 13 - i // 2, (74, 142, 48))
                put(x0, 13 - i, (98, 168, 64))
                put(x0 + 1, 13 - i // 2, (74, 142, 48))
    elif kind == "pebble":
        for x, y, r in [(5, 10, 2), (10, 6, 1), (11, 12, 1)][: 2 + seed % 2]:
            for dy in range(-r, r + 1):
                for dx in range(-r - 1, r + 2):
                    if dx * dx / (r + 1) ** 2 + dy * dy / r ** 2 <= 1.1:
                        put(x + dx, y + dy, (150, 150, 158) if dy < 0 else (112, 112, 122))
    elif kind == "bush":
        for y in range(T):
            for x in range(T):
                nx, ny = (x + 0.5 - 8) / 7, (y + 0.5 - 9) / 6
                d = nx * nx + ny * ny
                if d <= 1:
                    col = (40, 92, 44) if d > 0.75 else ((98, 168, 84) if nx < -0.2 and ny < -0.2 else (62, 128, 58))
                    put(x, y, col)
    elif kind == "mushroom":
        for x in range(5, 12):
            for y in range(5, 9):
                if (x - 8) ** 2 / 12 + (y - 8) ** 2 / 9 <= 1:
                    put(x, y, (200, 60, 50) if (x + y) % 4 else (250, 240, 230))
        for y in range(9, 13):
            put(8, y, (236, 226, 206))
            put(7, y, (236, 226, 206))
    return img


def canopy(w, h, leaves=(62, 128, 58), dark=(40, 92, 44), light=(98, 168, 84)):
    """Leaves that run off every edge, for trees that touch: repeats every 32 pixels."""
    img = Image.new("RGBA", (w * T, h * T))
    for y in range(h * T):
        for x in range(w * T):
            u, v = x % 32, y % 32
            cx, cy = (u // 16) * 16 + 8, (v // 16) * 16 + 8
            d = ((u - cx) ** 2 + (v - cy) ** 2) / 64
            col = dark if d > 0.9 else (light if u - cx < -2 and v - cy < -2 and d < 0.5 else leaves)
            if (x * 3 + y * 5) % 11 == 0 and d < 0.8:
                col = dark
            img.putpixel((x, y), col + (255,))
    return img


def rock_wall(w, h, part):
    """A cliff face piece: 'body', 'left', 'right', 'bottom', 'bottom_left', 'bottom_right'."""
    img = Image.new("RGBA", (w * T, h * T))
    W, H = w * T, h * T
    for y in range(H):
        for x in range(W):
            band = (y // 5) % 2
            col = (126, 112, 98) if band else (140, 126, 110)
            if (x * 7 + y * 3) % 13 == 0 or x % 16 in (5, 11) and (y + x // 16 * 3) % 7 < 3:
                col = (98, 86, 76)
            if "left" in part and x < 2 or "right" in part and x >= W - 2:
                col = (74, 64, 56)
            if "bottom" in part and y >= H - 4:
                col = (58, 50, 44) if y >= H - 2 else (86, 76, 66)
            img.putpixel((x, y), col + (255,))
    return img
