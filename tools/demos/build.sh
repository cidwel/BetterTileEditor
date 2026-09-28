#!/bin/sh
# Draws the demo tilesets and builds their scenes into addons/better-tile-editor/demos.
# Usage: tools/demos/build.sh [path/to/godot]   (DEMO=<name> builds only that demo)
set -e
REPO=$(cd "$(dirname "$0")/../.." && pwd)
GODOT=${1:-godot}
python3 "$REPO/tools/demos/make_demo_art.py"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/addons" "$WORK/tools"
ln -s "$REPO/addons/better-tile-editor" "$WORK/addons/better-tile-editor"
cp "$REPO/tools/demos/build_demos.gd" "$WORK/tools/"
cat > "$WORK/project.godot" <<EOF
config_version=5
[application]
config/name="Demo builder"
[autoload]
BetterTerrain="*res://addons/better-tile-editor/BetterTerrain.gd"
EOF
export XDG_CONFIG_HOME="$WORK/config" XDG_DATA_HOME="$WORK/data" XDG_CACHE_HOME="$WORK/cache"
"$GODOT" --headless --editor --import --path "$WORK" >/dev/null 2>&1 || true
"$GODOT" --headless --path "$WORK" -s res://tools/build_demos.gd
