# BetterTileEditor demos

One scene per kind of terrain, each with its own 16×16 tileset, already set up.
Open a scene, select one of its layers and the BetterTileEditor tab shows its
terrains; paint over what is there to see how each kind behaves. Each scene has a
short note at the top.

This folder is optional: the plugin does not use it, so you can delete it.

| Scene | Shows |
| --- | --- |
| `01_match_tiles` | Match Tiles: grass whose tiles declare which sides continue as grass |
| `02_match_vertices` | Match Vertices: water whose tiles declare which corners are water |
| `03_categories` | Categories: two grasses in one category, meeting without an edge |
| `04_decoration` | Decoration: tufts that fill the empty cells next to the grass |
| `05_objects` | Objects: 2×2 trees, alone and joined into a canopy where they touch |
| `06_forest` | Forest: a 2×3 tree painted as a mass, overlapping, with a clearing |
| `07_patch` | Patch: a pond read from one drawing, painted in any shape |
| `08_scatter` | Scatter: a bag of flowers, tufts and pebbles thrown over the grass |
| `09_single_tile` | Single tile: a sign and a 2×2 well placed as they are |
| `10_cliffs` | Cliffs: three levels of plateau with generated rock faces |
| `11_slopes` | Slopes: a platformer ground with steep, gentle and thin slopes (uses must-not rules) |

The tilesets are original art made for these demos and free to use. They are
drawn and set up by the scripts in `tools/demos` of the BetterTileEditor
repository.
