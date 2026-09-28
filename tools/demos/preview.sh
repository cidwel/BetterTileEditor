#!/bin/sh
# Renders every demo scene to <out>/<scene>.png, to check them without opening Godot.
# Usage: tools/demos/preview.sh <out dir> [path/to/godot]
set -e
REPO=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$1
GODOT=${2:-godot}
mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/addons" "$WORK/tools"
ln -s "$REPO/addons/better-tile-editor" "$WORK/addons/better-tile-editor"
cp "$REPO/tools/demos/render_demo.gd" "$WORK/tools/"
printf 'config_version=5\n[autoload]\nBetterTerrain="*res://addons/better-tile-editor/BetterTerrain.gd"\n' > "$WORK/project.godot"
export XDG_CONFIG_HOME="$WORK/config" XDG_DATA_HOME="$WORK/data" XDG_CACHE_HOME="$WORK/cache"
"$GODOT" --headless --editor --import --path "$WORK" >/dev/null 2>&1 || true
for scene in "$REPO"/addons/better-tile-editor/demos/*.tscn; do
	name=$(basename "$scene" .tscn)
	SCENE="res://addons/better-tile-editor/demos/$name.tscn" "$GODOT" --headless --path "$WORK" -s res://tools/render_demo.gd 2>/dev/null | grep '^C ' > "$WORK/$name.txt" || true
	python3 - "$WORK/$name.txt" "$REPO" "$OUT/$name.png" <<'PY'
import sys
from PIL import Image
cells = [l.split() for l in open(sys.argv[1])]
if not cells:
    sys.exit()
xs = [int(c[1]) for c in cells]; ys = [int(c[2]) for c in cells]
x0, y0 = min(xs) - 1, min(ys) - 1
im = Image.new("RGBA", ((max(xs) - x0 + 3) * 16, (max(ys) - y0 + 5) * 16), (60, 60, 70, 255))
sheets = {}
for c in cells:
    path = c[7].replace("res://", sys.argv[2] + "/")
    sheets.setdefault(path, Image.open(path).convert("RGBA"))
    rx, ry, rw, rh = map(int, c[3:7])
    tile = sheets[path].crop((rx, ry, rx + rw, ry + rh))
    # Bigger tiles hang up from their cell's bottom, centred, as Godot draws them
    px = (int(c[1]) - x0) * 16 + 8 - rw // 2
    py = (int(c[2]) - y0) * 16 + 8 - rh // 2
    im.alpha_composite(tile, (px, py))
im.resize((im.width * 2, im.height * 2), Image.NEAREST).save(sys.argv[3])
PY
	echo "$name"
done
