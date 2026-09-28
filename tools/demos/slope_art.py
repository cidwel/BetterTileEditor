"""Draws the 16x16 platformer slope tileset used by the slopes demo."""
from PIL import Image

T = 16

# Floor lines (surface y in pixels, local to the slope's own cell) and ceiling lines
FLOOR = {
    "steep_tl": lambda x: 16 - x, "steep_tr": lambda x: x,
    "g1_tl": lambda x: 16 - x / 2, "g2_tl": lambda x: 8 - x / 2,
    "g1_tr": lambda x: 8 + x / 2, "g2_tr": lambda x: x / 2,
}
CEIL = {
    "steep_bl": lambda x: x, "steep_br": lambda x: 16 - x,
    "g1_bl": lambda x: x / 2, "g2_bl": lambda x: 8 + x / 2,
    "g1_br": lambda x: 8 - x / 2, "g2_br": lambda x: 16 - x / 2,
}

GRASS_DARK = (47, 107, 37, 255)
GRASS = (108, 198, 68, 255)
GRASS_LIGHT = (150, 222, 96, 255)
ROCK_DARK = (74, 50, 32, 255)
ROCK = (122, 82, 48, 255)
SIDE = (94, 61, 34, 255)
DIRT = (176, 116, 64, 255)
DIRT_DARK = (146, 89, 47, 255)
DIRT_LIGHT = (201, 138, 82, 255)


def cells(grid):
    """grid: 3 strings of 3 chars, '#' solid."""
    return lambda x, y: 0 <= x < 48 and 0 <= y < 48 and grid[int(y // 16)][int(x // 16)] == "#"


def floor_at(role, oy):
    f = FLOOR[role]
    return lambda x, y: y >= oy + f(x - 16)


def ceil_at(role, oy):
    c = CEIL[role]
    return lambda x, y: y <= oy + c(x - 16)


def thin_top(role):
    f = FLOOR[role]
    return lambda x, y: 16 + f(x - 16) <= y <= 16 + f(x - 16) + 16


def thin_under(role):
    c = CEIL[role]
    return lambda x, y: 16 + c(x - 16) - 16 <= y <= 16 + c(x - 16)


def render(m):
    img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    for py in range(16, 32):
        for px in range(16, 32):
            if not m(px + 0.5, py + 0.5):
                continue
            s = lambda dx, dy: m(px + dx + 0.5, py + dy + 0.5)
            if not s(0, -1):
                col = GRASS_DARK
            elif not s(0, -2):
                col = GRASS_LIGHT
            elif not s(0, -3) or not s(0, -4):
                col = GRASS
            elif not s(0, 1):
                col = ROCK_DARK
            elif not s(0, 2):
                col = ROCK
            elif not s(-1, 0) or not s(1, 0) or not s(-1, -1) or not s(1, -1):
                col = SIDE
            elif (px * 5 + py * 3) % 16 == 0 or (px * 3 + py * 7) % 16 == 5:
                col = DIRT_DARK
            elif (px * 7 + py * 5) % 16 == 9:
                col = DIRT_LIGHT
            else:
                col = DIRT
            img.putpixel((px - 16, py - 16), col)
    return img


# slot -> (atlas cell, mask)
TILES = {
    "ground:tl": ((0, 0), cells(["...", ".##", ".##"])),
    "ground:t": ((1, 0), cells(["...", "###", "###"])),
    "ground:tr": ((2, 0), cells(["...", "##.", "##."])),
    "ground:l": ((0, 1), cells([".##", ".##", ".##"])),
    "ground:c": ((1, 1), cells(["###", "###", "###"])),
    "ground:r": ((2, 1), cells(["##.", "##.", "##."])),
    "ground:bl": ((0, 2), cells([".##", ".##", "..."])),
    "ground:b": ((1, 2), cells(["###", "###", "..."])),
    "ground:br": ((2, 2), cells(["##.", "##.", "..."])),
    "ground:itl": ((3, 0), cells([".##", "###", "###"])),
    "ground:itr": ((4, 0), cells(["##.", "###", "###"])),
    "ground:ibl": ((3, 1), cells(["###", "###", ".##"])),
    "ground:ibr": ((4, 1), cells(["###", "###", "##."])),
    "ground:barl": ((5, 0), cells(["...", ".##", "..."])),
    "ground:barm": ((6, 0), cells(["...", "###", "..."])),
    "ground:barr": ((7, 0), cells(["...", "##.", "..."])),
}
for i, role in enumerate(["g1_tl", "g2_tl", "g2_tr", "g1_tr", "steep_tl", "steep_tr"]):
    TILES[role] = ((i, 3), floor_at(role, 16))
    TILES["arrow:" + role] = ((i, 4), floor_at(role, 0))
for i, role in enumerate(["g1_bl", "g2_bl", "g2_br", "g1_br", "steep_bl", "steep_br"]):
    TILES["arrow:" + role] = ((i, 5), ceil_at(role, 32))
    TILES[role] = ((i, 6), ceil_at(role, 16))
for i, role in enumerate(["g1_tl", "g2_tl", "g2_tr", "g1_tr", "steep_tl"]):
    TILES["thin:" + role] = ((i, 7), thin_top(role))
TILES["thin:steep_br"] = ((5, 7), thin_under("steep_br"))
TILES["thin:steep_bl"] = ((6, 7), thin_under("steep_bl"))
TILES["thin:steep_tr"] = ((7, 7), thin_top("steep_tr"))
for i, role in enumerate(["g2_br", "g1_br", "g1_bl", "g2_bl"]):
    TILES["thin:" + role] = ((i, 8), thin_under(role))

def atlas():
    """The platformer atlas and its layout (piece -> [x, y, w, h])."""
    img = Image.new("RGBA", (8 * T, 9 * T), (0, 0, 0, 0))
    for slot, (cell, mask) in TILES.items():
        img.alpha_composite(render(mask), (cell[0] * T, cell[1] * T))
    return img, {slot: [cell[0], cell[1], 1, 1] for slot, (cell, _) in TILES.items()}
