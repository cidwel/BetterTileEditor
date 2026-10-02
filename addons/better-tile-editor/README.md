<p align="center"><img src="https://raw.githubusercontent.com/cidwel/BetterTileEditor/main/docs/logo.png" width="320" alt="Better Tile Editor for Godot"></p>

# Better Tile Editor

A fork of [BetterTerrain](https://github.com/Portponky/better-terrain) by
[Portponky](https://github.com/Portponky), with extra terrain modes and editor tools.

## What's added

- Patch terrains
- Multi-tile objects and forest painting
- Scatter painting
- Single-tile and tile-group brushes
- Automatic cliff faces
- Terrain groups, search and favourites
- Terrain thumbnails and previews
- Brush sizes from 1×1 to 8×8
- Map selection, copy, paste and stamping
- Fill by visible area or current layer
- Live terrain updates
- Floating editor dock
- Must-not-match peering, from [BetterTerrain PR #144](https://github.com/Portponky/better-terrain/pull/144)
- A slope tool for 2×1 and 1×1 slopes
- Quick tile animations from a selection of frames
- A Collisions tool: click tiles, in the atlas or on the map, to make them solid
- Complete terrain: builds the pieces a Match terrain is missing from quarters of the ones you drew
- A collision shape editor: detect shapes from the sprite or draw them by hand
- A Custom data tool to paint, inspect and pick tile custom data, with presets

## Highlights

- **Patch:** paint a region from a sample, keeping its borders and end pieces.
- **Multi-tile objects:** paint whole trees and other multi-tile objects. Separate
  and joined variants keep the pieces together, even when objects touch.
- **Forest painting:** paint an area to fill it with overlapping trees, including
  clearings. The trees keep their outlines and trunks around the edges.
- **Cliff faces:** paint the plateau and the rock faces follow its edges. Stack
  layers to build terraced hills.

## Must-not rules

A tile can say what may **not** touch one of its sides, not only what must. It
works in Match Tiles terrains, with the usual peering tool:

1. Pick the terrain in the list.
2. Click a side of a tile: it must match that terrain.
3. Click it again: it must **not** (a red crossed-out dot). Click again to go back.
4. Right click clears it.

Forbid a category to forbid every terrain in it, or Decoration to forbid an empty
cell. Use it for tiles defined by what they lack: a notch, a tip, or the corner on
top of a 2×1 slope.

## Slopes

Steep (1×1) and gentle (2×1) slopes for platformers, on floors and ceilings.

- Set them up from a Match tiles terrain's right-click menu, **Set up slopes…**: click each piece, then its tile. **Simple** asks for a few tiles and flips the rest.
- Drag with the slope tool to draw the ground's surface: it snaps to the nearest slope it can draw and fills the ground below.
- **Freehand** draws like a pencil, **Autofill** fills flat lines down to the ground and **Smooth** flattens small bumps.

## Install

1. Disable and remove the original BetterTerrain, if installed.
2. Download `better-tile-editor-vX.Y.Z.zip` from the
   [latest release](https://github.com/cidwel/BetterTileEditor/releases/latest).
3. Unzip it into your project folder. You should end up with
   `addons/better-tile-editor/` next to `project.godot`.
4. Enable **Better Tile Editor** in **Project → Project Settings → Plugins**.
5. Select a `TileMapLayer` with a `TileSet` and open the **Terrain** tab.

Keep the folder name `better-tile-editor`. Restart Godot if prompted.

To track the latest changes instead, copy `addons/better-tile-editor` from
[the source](https://github.com/cidwel/BetterTileEditor/archive/refs/heads/main.zip).

## Compatibility

- Godot 4.6+; tested on 4.6 and 4.7
- GDScript and C#
- Same `BetterTerrain` autoload and existing API
- Extra runtime steps for Object, Patch, Scatter and cliffs: see [technical notes](DESIGN.md)

## Changelog

### 0.2.0 (2026-10-02)

- Complete terrain: finds the pieces a Match terrain is missing and builds them from quarters of the ones you drew, inner corners included.
- Create quick terrain shows what it will make before creating it.
- Collisions tool: mark tiles solid on the atlas or the map, or detect shapes from the sprite and edit them by hand.
- Custom data tool: paint, inspect and pick tile custom data, with presets.
- Quick tile animations from a selection of frames.
- A simpler cliff face editor, and a whole face autoassigned from a block of the tileset.
- Atlases are labelled in the view, with their empty space trimmed.
- Renamed to Better Tile Editor.

## More

- [Technical notes](DESIGN.md)
- [Contributing](https://github.com/cidwel/BetterTileEditor/blob/main/CONTRIBUTING.md)
- [Report a bug](https://github.com/cidwel/BetterTileEditor/issues) — please include a small reproduction project.
- Copyright (C) 2026 cidwel, released under the [GPL v3](LICENSE.md) or any later version.
  Based on [BetterTerrain](https://github.com/Portponky/better-terrain) by Portponky, released under The Unlicense.
- Godot logo by Andrea Calabró, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
