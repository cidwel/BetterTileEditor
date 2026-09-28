"""Draws the demo tilesets into addons/better-tile-editor/demos/tilesets.

Run from the repository root:  python3 tools/demos/make_demo_art.py
Each demo gets <name>.png and <name>.json (piece -> atlas cell); build_demos.gd reads both.
"""
import json
import os
import sys

from PIL import Image


sys.path.insert(0, os.path.dirname(__file__))
from demo_art import (texel, BLOB, BLOB_LAYOUT, T, VERTEX, canopy, cell_region, corner_region, fill,
                      render_region, rock_wall, small, tree)
import slope_art

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "addons", "better-tile-editor", "demos", "tilesets")


def sheet(name, cols, rows, pieces):
    """pieces: {piece: (cell, image)}; writes the atlas and its layout."""
    img = Image.new("RGBA", (cols * T, rows * T), (0, 0, 0, 0))
    layout = {}
    for piece, (cell, tile) in pieces.items():
        img.alpha_composite(tile, (cell[0] * T, cell[1] * T))
        w, h = tile.width // T, tile.height // T
        layout[piece] = [cell[0], cell[1], w, h]
    img.save(os.path.join(OUT, name + ".png"))
    json.dump(layout, open(os.path.join(OUT, name + ".json"), "w"), indent=1)
    print(name, len(pieces), "pieces", img.size)


def blob_set(inside, outside, offset=(0, 0), prefix=""):
    ox, oy = offset
    return {prefix + k: ((x + ox, y + oy), render_region(cell_region(BLOB[k]), inside, outside))
            for k, (x, y) in BLOB_LAYOUT.items()}


def edge_tuft(side):
    """Grass tufts hugging one side of an empty dirt cell, next to a grass cell."""
    img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    dark, base = (52, 104, 36), (128, 196, 84)
    for i in range(1, 16, 2):
        length = 3 + (i * 7) % 5
        for d in range(length):
            x, y = {"t": (i, d), "b": (i, 15 - d), "l": (d, i), "r": (15 - d, i)}[side]
            img.putpixel((x, y), (dark if d == length - 1 else base) + (255,))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)

    pieces = blob_set("grass", "dirt")
    pieces["dirt"] = ((5, 0), fill("dirt"))
    sheet("match_tiles", 6, 3, pieces)

    pieces = {"v_" + c: ((i % 8, i // 8), render_region(corner_region(c), "water", "sand"))
              for i, c in enumerate(VERTEX) if c != "...."}
    pieces["sand"] = ((0, 0), fill("sand"))
    sheet("match_vertices", 8, 2, pieces)

    pieces = blob_set("grass", "dirt")
    pieces.update(blob_set("lush", "dirt", (0, 3), "lush_"))
    pieces["dirt"] = ((5, 0), fill("dirt"))
    sheet("categories", 6, 6, pieces)

    pieces = blob_set("grass", "dirt")
    pieces["dirt"] = ((5, 0), fill("dirt"))
    for i, side in enumerate(["t", "b", "l", "r"]):
        pieces["tuft_" + side] = ((i, 3), edge_tuft(side))
    sheet("decoration", 6, 4, pieces)

    pieces = blob_set("grass", "dirt")
    pieces["dirt"] = ((5, 0), fill("dirt"))
    props = [("flower", 0), ("flower", 1), ("flower", 2), ("tuft", 0), ("tuft", 1), ("pebble", 0),
             ("pebble", 1), ("mushroom", 0), ("bush", 0)]
    for i, (kind, seed) in enumerate(props):
        pieces["%s_%d" % (kind, seed)] = ((i % 6, 3 + i // 6), small(kind, seed))
    sheet("scatter", 6, 5, pieces)

    pieces = blob_set("grass", "dirt")
    pieces["dirt"] = ((5, 0), fill("dirt"))
    pieces["tree_lone"] = ((0, 3), tree(2, 2))
    pieces["tree_joined"] = ((2, 3), canopy(2, 2))
    sheet("objects", 6, 5, pieces)

    pieces = blob_set("grass", "dirt")
    pieces["dirt"] = ((5, 0), fill("dirt"))
    pieces["pine"] = ((0, 3), tree(2, 3, leaves=(44, 116, 70), dark=(28, 80, 50), light=(78, 150, 96)))
    sheet("forest", 6, 6, pieces)

    pieces = {"grass": ((7, 0), fill("grass")), "pond": ((0, 0), pond(7, 6))}
    sheet("patch", 8, 6, pieces)

    pieces = blob_set("grass", None)
    pieces["dirt"] = ((5, 0), fill("dirt"))
    for name, cell, size in [("body", (1, 3), (2, 2)), ("left", (0, 3), (1, 2)), ("right", (3, 3), (1, 2)),
                             ("bottom", (1, 5), (2, 1)), ("bottom_left", (0, 5), (1, 1)), ("bottom_right", (3, 5), (1, 1))]:
        pieces["wall_" + name] = (cell, rock_wall(size[0], size[1], name))
    sheet("cliffs", 6, 6, pieces)

    img, layout = slope_art.atlas()
    img.save(os.path.join(OUT, "slopes.png"))
    json.dump(layout, open(os.path.join(OUT, "slopes.json"), "w"), indent=1)
    print("slopes", len(layout), "pieces", img.size)

    pieces = blob_set("grass", "dirt")
    pieces["dirt"] = ((5, 0), fill("dirt"))
    pieces["sign"] = ((5, 1), sign())
    pieces["well"] = ((0, 3), well())
    sheet("single_tile", 6, 5, pieces)


def pond(w, h):
    """A pond w x h tiles: water inside a sand shore, grass around, drawn as one picture."""
    img = Image.new("RGBA", (w * T, h * T))
    W, H = w * T, h * T
    for y in range(H):
        for x in range(W):
            # Distance outside a rounded rectangle that covers the inner cells and half the ring
            qx = max(10 - x, 0, x - (W - 11))
            qy = max(10 - y, 0, y - (H - 11))
            r = 6
            ix, iy = max(qx - 0, 0), max(qy - 0, 0)
            d = (ix * ix + iy * iy) ** 0.5 if ix and iy else max(ix, iy)
            inset = min(x - 10, W - 11 - x, y - 10, H - 11 - y)
            corner = min(x, W - 1 - x) < 10 + r and min(y, H - 1 - y) < 10 + r
            if corner:
                cx = 10 + r if x < W / 2 else W - 11 - r
                cy = 10 + r if y < H / 2 else H - 11 - r
                d = max(((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 - r, 0)
            if d == 0:
                col = texel("water", x, y) if inset > 1 or corner else (40, 84, 150)
                if corner and ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 > r - 1.5:
                    col = (40, 84, 150)
            elif d <= 3:
                col = texel("sand", x, y)
            elif d <= 4:
                col = (170, 146, 94)
            else:
                col = texel("grass", x, y)
            img.putpixel((x, y), col + (255,))
    return img


def sign():
    img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    for y in range(3, 9):
        for x in range(2, 14):
            img.putpixel((x, y), ((150, 104, 62) if 3 < y < 8 and 2 < x < 13 else (96, 64, 38)) + (255,))
    for y in range(9, 15):
        for x in (7, 8):
            img.putpixel((x, y), (112, 76, 48, 255))
    for x in range(4, 12, 2):
        img.putpixel((x, 5), (70, 46, 30, 255))
    return img


def well():
    img = Image.new("RGBA", (2 * T, 2 * T), (0, 0, 0, 0))
    for y in range(32):
        for x in range(32):
            nx, ny = (x + 0.5 - 16) / 13, (y + 0.5 - 20) / 9
            d = nx * nx + ny * ny
            if d <= 1:
                inner = d < 0.45
                col = (40, 84, 150) if inner and ny < 0.2 else ((120, 120, 128) if (x + y // 3) % 5 else (90, 90, 98))
                img.putpixel((x, y), col + (255,))
    for y in range(2, 14):
        for x in (4, 5, 26, 27):
            img.putpixel((x, y), (112, 76, 48, 255))
    for y in range(1, 5):
        for x in range(2, 30):
            if y < 4 - abs(x - 16) // 8:
                img.putpixel((x, y), (170, 60, 50, 255))
    return img


if __name__ == "__main__":
    main()
