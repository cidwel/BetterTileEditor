# BetterTileEditor, design notes

Why this addon is built the way it is: what was changed, what broke on the way,
and which decisions look odd but are not. The README says what it does; this says
why. If you are about to "simplify" something in here, read its section first,
most of the strange-looking parts are strange because the obvious version was
tried and failed.

## Baseline

| | |
|---|---|
| Upstream | https://github.com/Portponky/better-terrain |
| Forked from | `e93040e`, *Fix forward input in Godot 4.6 (#137)*, 2026-02-09 |

The fork started from a tree **identical byte for byte** to upstream's `e93040e`
(ignoring `.uid` and `.import`, which belong to whichever project holds the
addon). So the whole of this fork can always be seen with:

```bash
git remote add upstream https://github.com/Portponky/better-terrain.git
git fetch upstream
git diff e93040e -- addons/
```

As of 2026-09-19 upstream has not pushed code since 2026-02-09: `e93040e` is
still its head. It is not archived and still has open issues, so this may change.

## What is different

### A. The false "editor needs to be restarted" dialog (Godot 4.7.1)

`TerrainPlugin.gd` → `_autoload_is_loaded()`

Since 4.7.1 the editor's autoloads reach the tree **unnamed** (`@Node@22384`
instead of `BetterTerrain`), so looking one up by name failed and the dialog
appeared on every open even though the singleton had loaded perfectly. The fix
falls back to matching on the script.

Upstream has this open as [#148](https://github.com/Portponky/better-terrain/issues/148).
**It is the first thing that should disappear from this fork** once they fix it.

This bites more than once: anything that needs the singleton has to find it by
script, not by name. Writing `BetterTerrain` directly is worse still, that
identifier only exists where the editor plugin is running, so naming it stops the
file compiling anywhere else.

### B. A floating window

`TerrainPlugin.gd` (`_dock_to_floating_window`, `_dock_back_to_bottom_panel`),
`Dock.gd` (`make_floating_toggled` signal, `set_make_floating_pressed`),
`Dock.tscn` (`MakeFloating` button)

Takes the dock out of the bottom panel into a window of its own, and puts it back.

### C. A "Live test" button

`Dock.gd` (`layer_stale`, `auto_resolve_timer`, `_auto_resolve_layer`,
`_on_live_test_toggled`, the warning frame in `canvas_draw`),
`Dock.tscn` (`LiveTest` button)

With it on, editing the tileset's rules re-resolves the selected layer (debounced
by 0.25 s) and draws an orange frame around it while it is out of date.

### D. Zoom at the cursor, pan with the middle button

`TileView.gd` (`_zoom_at_cursor`, `_panning`)

**This changes existing behaviour.** Upstream zooms with `Ctrl`+wheel; here the
bare wheel zooms on the cursor and the middle button drags. It is the change most
likely to collide if upstream ever touches input handling.

### E. View modes are remembered

`Dock.gd` (`_restore_view_modes`, `_store_view_mode`)

`GridMode` and `QuickMode` are kept in `EditorSettings`
(`editors/better_terrain/grid_view`, `editors/better_terrain/quick_mode`) instead
of resetting every time the editor starts.

Quick mode also hides more than it used to. Upstream's filter let through Match
tiles and Match vertices only, and the three modes the fork adds are brushes just
like them: you pick one and you paint. So quick mode hid the terrain you had gone
into quick mode to paint with. Object, Patch and Scatter are in the list now.
What stays out is what does not paint: a category declares a matching type, and
decoration fills what is left over on its own.

### F. Terrain groups

`BetterTerrain.gd` (the `Display groups` region, the `0.2 → 0.3` migration,
`get_terrain_icon_texture()`),
`Dock.gd` (`rebuild_terrain_list`, headers, the chip bar, the filter,
`_group_thumbnail`, `_update_group_header_widths`),
`TerrainEntry.gd` (`terrain_id()`),
`TerrainProperties.gd` (the group picker),
`TerrainGroups.gd` (**new file**, the group manager)

Terrains in the list are gathered under headers with a rule across them, with a
bar of chips above to filter by group. Headers and chips are illustrated with the
thumbnail of whichever tile was chosen in the manager, not with a flat colour.

Four things that matter if this is ever merged with upstream work:

1. **It raises the tileset meta version to `0.3`.** If upstream publishes its own
   `0.3` with different contents, the two migrations collide and have to be
   reconciled by hand.
2. **It decouples an entry's position from its terrain id.** Upstream assumes in
   about twenty places that `get_index()` is the id. Here the id travels with the
   entry instead (`terrain_id()`), so any new upstream code that reads
   `get_index()` as an id has to be translated first.
3. **No group function may assume the `groups` key exists.** It only appears once
   `_update_terrain_data` has migrated the tileset to `0.3`, and the API is
   reachable before that, the manager dialog, a freshly created `TileSet`. Reads
   go through `_groups_of()` and writes through `_ensure_groups()`. Skipping that
   reproduces the `Invalid access to property or key 'groups'` failure.
4. **A group header must not have a large fixed minimum width.** An
   `HFlowContainer` measures at least as wide as its widest child, so a 2000 px
   header (the trick the entries themselves use in list mode) leaves grid mode
   unable to wrap, everything on one row. The header is measured against the
   panel's visible width and re-fitted in `_update_group_header_widths()` on the
   `resized` signal.

### G. The dock stops spilling over its neighbours

`Dock.tscn` (`Toolbar` goes from `HBoxContainer` to `HFlowContainer`),
`Dock.gd` (`clip_contents = true` in `_ready`)

The dock's root is a bare `Control` with `custom_minimum_size = Vector2(0, 100)`:
it pins the height and leaves the width at zero. A `Control` does not derive its
minimum from its children (only containers do) so the dock declared itself 0 px
wide while its contents needed **859 px**. Shrink the window and the children laid
themselves out past the rect and, without `clip_contents`, drew **on top of the
scene tree and the viewport**.

With the toolbar wrapping, the real minimum drops from 859 px to 299 px, and the
clipping stops anything painting outside again.

This is an upstream bug, not one introduced here: the two buttons this fork adds
to the bar account for only 124 px of those 859, and merely bring the moment it
shows forward. **A good candidate for a PR**, like A and E.

### G2. Type to search the terrain list

`editor/Dock.gd` (`_build_search_box`, `_on_search_changed`, `_close_search`,
`_unhandled_key_input`).

A tileset with sixty terrains in it is a scrolling problem. The search box opens
on the first keystroke with the focus anywhere in the list, which is the reflex
the editor's own scene tree already trained.

Two decisions worth writing down. It lives inside a **transparent `Control`**
rather than straight in the panel, because a `PanelContainer` stretches its
children and the box would deform instead of sitting in its corner. And the
keystroke is caught in `_unhandled_key_input` by checking **who has focus**, not
by putting a handler on every entry, the scroll container can hold focus too,
and an entry-by-entry handler misses that case.

Searching always looks **across every group**, and touching a group chip cancels
the search. Filtering within a group while searching hides the result you are
looking for, and leaving both on made the chip look inert.

### G3. Double-click an entry to open its properties

`editor/TerrainEntry.gd` (`_gui_input`, the `edit_requested` signal),
`editor/Dock.gd` (`_on_entry_edit_requested`).

What every other list in the editor does. The entry already takes focus on the
first click, so this only has to notice the second one.

### G4. Reload the plugin without restarting Godot

`editor/Dock.gd` (`_add_options_button`, `_on_reload_plugin_pressed`).

The toolbar's Options button opens a window (`_build_options_window`) where you can
show the refresh button, independently hide Godot's native Tiles, Patterns and
Terrains tabs, or rename BetterTileEditor to Tiles. The window also holds the tile
picker's modifier key and the cliff rebuild. The checkboxes apply as soon as they
are clicked; there is nothing to confirm. These preferences are saved in
EditorSettings and default to off. Hiding an active native tab
selects the plugin tab; native tab indices remain unchanged.
The refresh button re-enables the plugin, so the editor scripts are re-read;
the autoload is untouched. The editor may hand the selection to `_edit` before the
new dock exists, or not at all, so the plugin ignores early calls and picks up the
inspected layer or TileSet once the dock is built (`_resume_selection`).

### G5. One draw call for the terrain diamonds

`editor/TileView.gd` (`_queue_polygon`, `_flush_polygons`).

`draw_colored_polygon` emits one polygon command, and the RenderingDevice backend
creates and destroys a GPU buffer of its own for each one. Measured on a real
tileset: **1.78 ms per call × 3168 calls = 5.6 s of the 5.75 s** an atlas redraw
was taking. The whole of the rest of the function came to 100 ms.

The diamonds are convex, 3 or 4 vertices, so they fan-triangulate and go out
together in a single `canvas_item_add_triangle_array`: one buffer per redraw
instead of thousands.

The exception is the black outline of a decoration diamond, which has to sit on
top of its own polygon and so is still drawn on the spot. Batching it would put
every outline above every fill.

### G6. One name, one terrain

`editor/TerrainProperties.gd` (`_name_taken`, `_check_name`, the check in
`_on_confirmed`), `editor/Dock.gd` (`_warn_duplicate_name`)

Two terrains with one name were legal, and it was a trap for everything keyed
by name, cliff sheets first: a tileset with an Patch and a Match tiles both
called `mountain` had its sheet applied to the wrong one and drew nothing, and
nothing said why. Cidwel's answer was the right one, refuse it where the name
is typed. The properties dialog now greys its OK and turns the field red the
moment the name matches another terrain of the tileset (the one being edited
does not count as another), and refuses on confirm with a sentence saying
which name and why. The dock's warning after the fact stays as a net for
anything that creates terrains without the dialog. Not testable headless: that
dialog needs the editor to instantiate, so the check is the editor loading
clean and the code being nine lines.

### H. A new terrain type: `OBJECT` (objects of N×M cells)

`BetterTerrain.gd` (`TerrainType.OBJECT`, `_terrain_object_of()`, a seventh element
on the terrain, `object` in `get_terrain`/`add_terrain`/`set_terrain`, early
returns in `_update_tile_immediate` and `_update_tile_deferred`),
`ObjectTerrain.gd` (**new file**, the resolution),
`editor/TerrainProperties.gd` (the type option, its configuration rows, a preview),
`Dock.gd` (`set_object_data`, `terrain_object` on add and edit,
`perform_add_terrain`/`perform_edit_terrain`, a call after every paint mode)

BetterTerrain decides each cell by looking **only at the terrain of its
neighbours**. That works while the tileset's motif repeats every cell.

A tree spanning 2×2 has a period of 32 px on a 16 px cell, and there the model
breaks. Inside a filled wood, take the top-left cell of one tree and the top-right
cell of the tree beside it. Their **neighbours are identical**. They tie, and the
tie-break (`_weighted_selection_seeded`, `rng.seed = hash(coord)`) is random. You
get trees split down the middle.

What is missing is the **parity of the coordinate**, and a peering bit cannot see
it by construction. This is not a bug in the plugin, nor something better rules
would fix: the information is not in the model. A script has it.

You create an `OBJECT` terrain like any other. Same dialog, same list, same
groups, same brush. It adds three fields: the **size** N×M, and the atlas
coordinates of **two blocks** with a preview of each. The *joined* block is the
one whose drawing carries on outwards; the *lone* one has a closed silhouette.

That config travels as the terrain's **seventh element**, and it is optional.
Ordinary terrains have six elements and read `{}`. Nothing migrates, and the meta
version stays where it was.

**The rule.** A cell facing outwards on one side may only use the joined block if
there is another object on that side; otherwise the drawing is cut off in mid-air.
A corner needs more. If a cell faces outwards on two sides, the **diagonal**
neighbour has to be checked too. Go by the two sides alone and the fusion comes
out lopsided: one object fuses towards its neighbour, the neighbour does not
return the gesture, and the joint ends up with a straight cut across it. With the
diagonal, the
condition is identical for all four objects around that vertex, so either all of
them fuse or none does. Measured on a real map: **52 split cells and 2 asymmetric
joints → 0 and 0**.

Two details that cost time:

1. **A terrain's type travels by id now, not by index.** `TerrainProperties` used
   `%TypeOption.selected` as if it were the type, and it worked because the three
   types in the `.tscn` sit at indices 0-2. `OBJECT` is id 4 (3 is `DECORATION`,
   which is not in the dropdown), so index and id stop agreeing. It uses
   `get_selected_id()` now.
2. **Undo has to cover more than what was painted.** An object changes because of
   a neighbour nobody touched, so restore points are widened with
   `_restore_cells()` / `area.grow(2)`. Without that, undoing left debris behind.

If the `TileSet` defines no objects, `has_objects()` is false and none of this runs
at all. **A good candidate for a PR**: multi-cell objects in a terrain tileset are
not specific to any one game, and this is a real gap in the peering-bit model.

### H2. An object painted as a mass (a wood, a hedge)

`ObjectTerrain.gd` (`is_mass`, `has_mass`, `fix_mass`, `_stack`, `_is_opaque`,
`fix_mass_deferred`, `mass` and `offset` in `make_config`),
`editor/TerrainProperties.gd` (the *Mass* checkbox and the *Inside row offset*
row), `Dock.gd` (`_add_post_process` re-stacks on undo)

An object of 2×2 snaps to a grid of its own size, and that grid is what makes a
thicket line up. Try the same thing with tall art and it falls apart: a 2×4 tree
cannot sit half a step below the one beside it, so a wood tiles into bands and
the mass has no outline. Cidwel drew what it should look like by hand, 306 cells,
and that drawing is where the answer came from. Everything below was measured
against it.

**What a wood is.** One drawing. The tree with the closed silhouette, stamped on a
shingled lattice (columns a drawing apart, rows half a drawing apart, every other
row shifted by half) and painted back to front so each tree covers the one behind
it. The seamless "inside" block the artist also draws is nothing more than that
overlap, pre-baked: laid next to the tree stacked on that lattice, the two differ
by 20.8 per pixel and have every trunk in the same place.

So a mass takes the same two blocks an object does and nothing else, and the
buttons mean what they say: **Lone is the tree**, the drawing that stands on its
own, and the other block is the inside. For a while the resolver read it the
other way round, with Lone naming the inside block, and the demo hid it because
its generator set the config by hand. Nobody could set a wood up from the dialog:
marking the tree as Lone, the obvious thing, stacked the inside block as trees
and painted the tree as ground. Pick *Area*, paint a shape, and a tree is placed
only when its entire base fits inside that shape. Its crown may overhang. Uncovered painted cells remain invisible; overlapping trees use child layers named `Mass1`, `Mass2`...

**Base containment.** Every cell of the base must be painted. The base is the
rectangle configured per terrain using Base offset (x, y) and Base size (w, h)
in the Area properties. Coordinates are relative to the drawing, in tiles.
Without an explicit base the entire sprite is required: 2x4 for a 2x4 tree.
Scatter pieces use the same rule, with a Base button per bag entry so sprites
of different sizes can have different footprints. The base controls region and
spacing checks; the full drawing is still rendered, including its overhang. Previously one
painted cell under any part of that base was enough; now the whole base must fit,
including beside holes or narrow edges. The upper crown can still extend beyond
the painted shape. The editor preview uses the same rule.

**Stacking is cell by cell.** A tilemap layer holds one tile per cell, so a tree
laid over another replaces it rather than covering it. Put each whole tree one
layer above everything it overlaps and a wood this tight climbs one layer per
row: every row overlaps the one behind, and with six layers the seventh row is
missing and the trunks behind show through in a stripe. Only the see-through
cells need to climb. An opaque cell replacing what is under it on the same layer
is exactly right, and a cell is under two or three see-through corners at most.
The hand-drawn wood needs one child layer; the demo wood needs two.

The first tree to land on a painted cell goes into the painted layer itself,
replacing the inside block. Leave the block under there and every outline cell
reached only by a see-through tree cell shows it: foliage behind the trunks where
there should be grass. Cells outside the painted shape never go on the painted
layer, or the shape would grow with every pass.

**What has to be declared.** Whether a terrain is a mass or a set of objects.
Both want the same pair of blocks, a closed silhouette and one whose ink runs off
all four edges, so the art cannot tell them apart. So it is picked by hand, and
it is the only setting a mass has. There was a second one, a row offset for the
inside block, left over from the design that painted it: measured on two woods,
418 and 306 painted cells, not one was left showing that block, so the setting
changed nothing anyone could see and it went.

**The picture is the control** (`editor/ObjectPreview.gd`). A checkbox that
says *paint as an area* says nothing about what that is, and it went: two
buttons that pick the mode do not need a third. The dialog draws the choice
instead: two cards, *Objects* and *Area*, each showing what the terrain's own two
blocks turn into. One tree alone and four fused into a thicket on the left; a small
painted shape with the lone drawing stacked over it on the right, placed with
the same lattice and base containment rule as `fix_mass`, so what you see is what the map
gets. The active card is outlined, and clicking a card picks that mode. Before
the blocks are marked it draws the same two scenes with plain shapes, so the
explanation is there the first time the dialog opens. A real screenshot was
taken to check it, not a headless composite: the captions overflowed the cards
twice before they fit.

**The help and the list know about it too.** The `?` window for Object has two
more steps, *Or paint it as an area* and *Where its edge comes from*, drawn from
a real mass: the object example painted as a small shape with a hole in it and
resolved by `fix_mass` on a copy of the tileset with the flag on (a copy, so the
tileset borrowed from is never left changed). The second step outlines the cells
that were painted so the overhang is visible. The drawing is fitted to the canvas
rather than drawn at the zoom the other steps use: with the overhang a mass is
taller than a patch of objects, and at that zoom it ran under the buttons. And a
mass gets its own icon in the terrain list, `icons/ObjectMass.svg`, a shingled
row of blocks next to Object's one big block: in a list of sixty, the icon says
which it is before the name does.

**Undo.** The trees are derived from the painted cells, on layers the undo
manager knows nothing about, and undo methods run before the cells are put back.
The re-stack is deferred so it lands after them.

**What did not work, so nobody tries it again.** A separate terrain type that
chose a block per cell by neighbourhood and took the cell from the lattice
phase, with edge blocks declared by peering bits. Forcing the phase at the
boundary sliced trees on every diagonal; anchoring it to each column's run broke
the diagonal rhythm the art is built on; a band at each end sized by a measured
pitch fixed the top and put a strip of grass inside the wood, because the block
used for the top edge carried its own grass. Three blocks and 86% of the
hand-drawn cells, and the 14% that were left were interior cells placed by eye.
The stacked tree needs no edge blocks at all.

### I. Opening "Terrain" when a TileMapLayer is selected

`TerrainPlugin.gd` (`AUTO_OPEN_SETTING`, `_make_visible`, `_auto_open_enabled`)

When a `TileMapLayer` is selected, Godot's own tilemap editor shows its bottom
panel from its `_make_visible()`. The terrain dock only made its button visible,
so it always had to be clicked by hand. It now claims the panel with a deferred
`make_bottom_panel_item_visible()`, deferred because the built-in one has to have
done its part first.

It applies only to layers, not to a `TileSet` opened as a resource, and it can be
turned off in *Editor Settings → Editors → Better Terrain → Open Panel On Select*.

### I2. The toolbar shows only the tools a mode can use

`editor/Dock.gd` (`TOOL_MODES`, `_tool_button`, `_sync_buttons`).

Upstream keeps every tool in view at all times, which is like asking someone to
guess which of them goes with what they have selected. Peering and symmetry mean
nothing on an exemplar (the drawing decides, not the scoring) and an object is
marked in blocks, not cell by cell.

The first pass at this was a pile of `not is_object and not is_exemplar`, which is
the same knowledge written backwards: to find out what a mode offers you had to
read every tool and invert each condition. `TOOL_MODES` is that knowledge as a
table, one row per tool.

It is an **allowlist**, and deliberately so. A terrain type added later gets no
tools at all until someone writes it into the table. That is the direction that
fails safely: a missing button is a question somebody asks, a button that turns up
on a mode it cannot handle is a bug report.

**Where the cliff sits in that table**, and why it is the interesting row: a cliff
face needs a terrain that occupies cells *as a region*, because the generator walks
its south edge. A category declares a matching type and paints nothing; decoration
fills whatever is left over. Neither has an edge, so neither is in the list,
`MATCH_TILES` and `MATCH_VERTICES` are.

There is one exception, and it exists because narrowing a rule strands whatever
was set up under the old one. A terrain that **already has a sheet stored** keeps
the button whatever its mode. Otherwise there would be no way back to the window
that removes it.

The test for that is `all_configs(ts).has(name)`, not `config_of()`. `config_of`
fills in a default sheet, so it is never empty, and using it showed the button on
*everything*. Reading the code did not catch that. Measuring the change against 55
real terrains did.

### J. Cliffs: the south face of a terrain, generated

`CliffData.gd`, `CliffTerrain.gd`, `editor/CliffEditor.gd` (**new files**),
`CliffFacesLayer.gd` (**new**, the script on the generated layer),
`icons/CliffFace.svg`, `icons/CliffAdopt.svg` (**new**), `Dock.gd` (the `Cliff` and
`Adopt` buttons, `_hook_cliff_level_watch`, `_watch_layer_order`,
`_mark_cliffs_dirty`, `_rebuild_cliffs_now`, the hook in `_add_post_process`),
`editor/TerrainEntry.gd` (`_make_custom_tooltip`), `TerrainPlugin.gd` (one call to
`dock._watch_layer_order()` in `_edit`)

Paint a plateau with an ordinary terrain and its south face appears on its own. No
second wall terrain to keep in step with the first.

**Why this is not peering bits.** A face cell has to tell nine cases apart by what
is to its left and right: nothing, more face, or plateau. The model cannot reach
that, for the same reason as `OBJECT`: when the ground below and the plateau above
are **the same terrain**, "ground on my left" and "plateau on my left" are the same
bit on the same side. They tie. What separates them is height, and height is not
in the model. A script has it.

**The level is the height.** A layer at level N grows a wall N rows tall, so each
new layer adds a row and the bottom one, the base, grows none. Raising a layer's
`cliffLevel` by hand is what makes its wall taller.

`level_of()` walks the layers carrying `cliffLevel` in sibling order with a
counter: each is one level above the last, and a `cliffLevel` >= 0 pins the counter
instead of incrementing it. So forcing one layer **drags every layer above it up**
with it.

That counter is the only thing that changed here, and it fixes a bug you do not see
until you use the override. Counting by **position** among siblings instead meant
that setting the second layer to 3 left the third numbered 2: the upper layer at
z=4 and the lower one at z=6, drawn behind the thing it stands on. A counter cannot
produce that.

Two other models were tried on the way, and both were worse, in case anyone thinks
of them again. Taking the row count from the sheet instead of the level left
**every layer with the same wall**, which is precisely what the level exists to
tell apart. And making them proportional to each edge's real drop is more faithful
but not what anyone wants: the height belongs to the layer, not to whatever hole
happens to be underneath it.

**The generated cells live in a child layer** called `CliffFaces`, created on
demand with its parent's `owner` so it is saved with the map. This is not
convenience: it is the only thing that makes "which cells are mine?" answerable.
Face tiles need not carry any terrain, so you cannot read it back off them, and
deducing it from the terrain made the plateau **creep down one row on every
rebuild**. With a layer of its own the answer is "everything in here", and cleaning
up is `clear()`.

**It regenerates itself.** Four triggers: slots assigned in the window
(`config_changed`), the plateau painted (hooked onto `_add_post_process`, which
already existed for objects), `cliffLevel` edited in the inspector
(`property_edited`), and layers reordered (`child_order_changed`, debounced,
because that signal fires on any add or remove including loading the scene). All of them run with `overwrite = false`. Anything that fires on its own
must never be able to eat hand-painted work.

One button is left, `Adopt`, and it does the thing that cannot be automatic:
taking over faces painted before the generator existed. That is why it asks first,
and why it stays out of undo.

**The generated layer is the marker, and it holds the level and the height. Your
project declares nothing.** A ground layer having a `CliffFaces` child is what says
it takes part, and its position among the layers that have one is its level. That
node carries `CliffFacesLayer.gd`, with `cliffLevel` and `cliffRows` **exported**,
so they are edited in the inspector like any other node and saved with the scene.

Node metadata was tried first. It works and it also asks nothing of the project. It
became a script because an `@export` shows up in the inspector with its tooltip and
its range, and metadata is something you have to already know is there.

Deducing it from the painted terrain, with no marker at all, **does not work**: a
layer can be a level in its own right and paint zero cells of any terrain that has
a cliff sheet.

This is why `_drop_if_empty` had to go: it destroyed the faces layer once it was
empty, which would now quietly take the layer out of the system. Removing a layer
from it is a deliberate act, the button.

**A covered face is not generated.** Faces go to their layer's `z` **minus one**, so
they are hidden by any tile on a layer above and by their own layer's ground.
Invisible with a collision polygon is pointless on its own, but there is something
worse waiting for you, and it is the one thing this addon cannot do for you:

> **What your project has to do.** A generated face blocks the player from day one,
> because the tiles carry their own collision polygons. It does **not** block
> anything that builds its own navigation from a list of layers, bots, pathfinding,
> anything that asks "is this cell walkable". The faces layer hangs off its ground
> layer, not off your map root, and it carries no script of yours, so it will not
> match whatever filter you used to collect collision layers. Measured on a real
> map before fixing it: of 48 face cells, **40 came out navigable while being solid
> wall**.
>
> The fix is to insert each `CliffFaces` layer into that list **directly below its
> own layer**, in the same order they are drawn. Then a cell where the ground layer
> has floor and its face has wall resolves to floor, exactly as it looks. A map with
> no cliffs produces exactly the list it produced before, because the face is only
> added when the child exists.

Back inside the addon: faces whose own ground covers them are not emitted at all.

That goes against what the sheet wants. A wall carrying on where the plateau
reappears below it means the far side of a pit is hidden. But the `z` already
breaks that intention: at `z-1` the face is drawn **behind** its own ground, so it
hides nothing anyway. Generated and invisible is the worst of both.

Until faces get a `z` that puts them in front of their own layer, not emitting them
is the honest answer. The `Rebuild` report counts them separately.

**The case table is complete, and missing slots inherit.** Five things can sit
beside a face cell (`open`, `face`, `plat`, `step_hi`, `step_lo`), so there are
**25** possible pairs. All 25 now have a case.

They did not always. It started at 13. Three times running, a cell turned up
sharing a slot with one it had no business sharing, and always for the same
reason: a pair with no case of its own falling into another by its fallback.

Adding cases normally opens holes. An empty slot is a prohibition, so every cell
of a new case would stop being drawn until somebody gave it art.

`resolve_tile` falls back to the case the new one refines. `fallback_case` derives
that from the same `step_hi -> face` / `step_lo -> plat` rule instead of
tabulating it, so the two cannot drift apart. Filling a slot is an improvement,
never a repair. And the report of what is missing lists real holes only: a case
whose fallback is filled does not count, because it draws.

**"All cases (grid)" is a matrix, not a drawing.** The 25 cases are (left, right)
pairs over five values, so the shape lays them out on a 5x5 grid: **row = what is
on the left, column = what is on the right**. Where a cell sits tells you which
case you are looking at without reading the slot's name.

Each square is the **smallest** construction that produces that case, found by
brute force over the 4096 combinations of three columns by four rows, keeping
whichever had fewest cells. That comes to 65 plateau cells for the 25 cases.
"Every case" takes 172 and covers them heaped together and repeated.

The modules sit three cells apart so none can change its neighbour's case. That is
checked, not assumed: the assembled grid gives 25 out of 25 again.

**The two kinds of joint fall back in opposite directions.** `case_at` names a case
from the left/right pair. Pairs with a `step` neighbour, meaning a wall starting
from a different height, have almost no slots of their own, so they fall back. What
decides where is the **direction** of the joint:

- `step_hi`, the neighbour hangs off a **higher** plateau: at this row it is still
  wall mid-drop, so the wall carries on and needs no edge. Falls back to `face`.
- `step_lo`, the neighbour hangs off a **lower** one: the ground beside it drops
  another step, this wall ends and the next starts below. That seam does need an
  edge. Falls back to `plat`.

Both to the same place does not work, and two cells of the preview show it.

Send both to `plat`, the original behaviour, and a cell with continuous wall on
its left comes out as `notch`. That is the tile with an edge on **both** sides, so
you get an edge in the middle of a wall. Send both to `face` and it fuses a
continuous-wall cell with one that
has terrain falling away on both sides. Each rule was right about a different half.

**An empty slot in the sheet is not a hole, it is a prohibition.** If a map produces
that shape, the generator points at it instead of placing a tile that does not fit.

**Terrains can inherit a sheet.** One terrain can take another's and follow it live.
While inheriting, the sheet is read-only: writing there would go to an entry
`config_of()` ignores, and redirecting to the original would be editing someone
else's sheet without saying so. `inherit_source()` and `would_cycle()` cut loops,
and a broken chain degrades to "no inheritance" instead of being walked forever.

**Preview shapes are painted, not written.** Any `TileMapLayer` in the shapes scene
is a shape, named after the node; only which cells are filled matters. If the scene
exists it wins outright and replaces the built-in `CliffData.FIXTURES`, so you do
not end up with duplicates of the defaults. The scene is optional and lives in your
project, not in the addon; without it you get the built-ins.

**What a shape has to contain, and how it breaks.** It must produce the cases a
normal edge generates: straight runs with ends, and steps two cells or more. The
narrow ones (a one-cell step, a lone cell) are optional and added with
`narrow_block()`, because a tileset that never builds those shapes has no reason to
draw tiles for them. And the detail that took three attempts: a one-cell step only
produces `l_plat_end` / `r_plat_end` **while the column beside it keeps dropping for
as many rows as the face is tall**. Fall short and the neighbour grows a face of its
own, the side that should have been open stops being open, and those two cases
vanish without a word. Check it at heights 1 through 4, not at one.

**Where they are drawn, and why it is the most delicate part of all this.** If your
ground container is y-sorted, the sort only orders **within one z**. With three
ground layers on the same z there is no intermediate position for the faces: at
`z-1` they fall below all of them, and `show_behind_parent`, which looks like
exactly the mechanism for this, is ignored by the y-sort. Learned the hard way,
twice.

So z is the only lever. Each level takes its place in a band: the ground of level N
at `N*2`, its faces at the odd number below, that is in front of the whole previous
level and behind its own. `CliffTerrain` writes that z from `level_of()`, from the
**level**, never from the wall's height, and only when it differs from what is
already there.

**The regeneration trigger went through three mechanisms, and two were false.** The
dock's paint path (`_add_post_process`) does not cover undo: the undo manager
restores cells without going through it, so the terrain came back and the faces
stayed. And `TileMapLayer.changed`, which looks like the obvious signal, **never
fires** for `set_cell`, `erase_cell` or `clear`, measured; it only reports property
changes, `z_index` among them, which is the one thing that must not trigger a
rebuild. The good one is `EditorUndoRedoManager.version_changed`, which covers
painting, erasing, undo and redo. There is no loop because the generator writes
cells directly, without going through the undo manager.

**Painting a patch from code is not just `set_cells` + `update_terrain_area`.** The
`TerrainEntry` tooltip and the cliff editor's preview both draw a piece of terrain
by resolving it with BetterTerrain. Both were missing the step the dock takes after
every stroke: `ObjectTerrain.fix_cells()`.

Without it an `OBJECT` terrain comes out as a grid. Measured on a 6x6 patch of a
tree: **1 atlas coordinate repeated 36 times**, where the block is made of 8. Same
limitation as section H, and anyone adding another place that paints terrain from
code has to remember it.

Terrain tooltips now show the complete lone drawing for objects (including mass
objects), the original drawing for exemplars, and a 10x10 scatter zone generated
with the bag's density, weights, seed and edge margin. The scatter sample uses a
subtle checkerboard to show empty cells and includes any art extending beyond its
base. A fixed autotiled patch repeated exemplar placeholder tiles,
cut objects at the patch boundary, and could not show scatter's generated art.
Ordinary terrains still use the resolved patch with cliffs. Preview images retain
their aspect ratio and fit within 320 pixels on either axis.

**A setting written by hand keeps its layer alive.** `_drop_if_empty` deletes the
faces layer when it runs out of cells. That is what stops empty nodes piling up.

But `cliffRows = 0` means something: "this layer is a level, and right now I want
no wall". Under the plain rule, writing that zero **destroyed the very node you had
just written it on**, and took the layer out of the system with it. A layer is now
dropped only when it has no cells **and** no setting on it.

**Reading must not mutate the tree, and this one took the editor down.**
`faces_layer()` looks like a query and is not: it migrates loose layers from earlier
versions, puts the script on the node and rewrites its z. The dock called it from
the *setter* of `tilemap`, that is **while the editor is changing which object it
edits**, and a `set_script()` there is a textbook segfault, it crashed twice.
`find_faces()` exists for the things that only look, and `faces_layer()` is left in
two places, both inside `rebuild()`, which is a deliberate act.

**The window opens at the height that layer actually builds.** There were two
heights: the sheet's spin, which is per terrain, and what the layer really
generates. The window used the wrong one. You set 4 rows on the layer, opened the
sheet, and it drew 2.

`setup()` takes `rows_for(tilemap)` now. With no layer selected it falls back to
the terrain's, which is all there is to go on.

**Rebuild performance.** A full pass over a real layer (6933 input cells, 3223 face
cells) measured ~65 ms. Two wastes, both self-inflicted:

- `fallback_case` walked the table of 25 pairs **splitting a string per entry** on
  every call, and the generator asks for it once per face with an empty slot. It is
  a fixed calculation: it is cached now. `resolve_tile` x3404 went from 20.5 to
  10.7 ms.
- The terrain filter made **one full pass per configured terrain**. The cells do not
  change between passes: one pass hands them out. From 31.6 to 15.2 ms.

That leaves ~33 ms a pass. If it ever becomes a nuisance, the next lever is
rebuilding only the area touched instead of the whole layer, today, painting four
cells redoes all 3223 faces.

**"No cliffs came out" on a scene with one layer: three things, found in that
order.** Cliff sheets are keyed by terrain name, and the tileset had two
terrains called `mountain`, an Patch and a Match tiles; `_terrain_index()`
took the first by name, the Patch, which had no cell painted, and the Match
tiles one with thirty-eight never entered. `_terrain_indices()` now returns
every terrain by that name and the sheet reaches all of them, and the dock says
so the moment a name is given twice, because that is where the slip happens.
Then, with the right terrain, still nothing: the scene has a single layer, and
the lowest layer is level 0, the base, which grows no face by design. The way
out is the `level` control, and it was locked: it returned silently when the
layer had no faces node, on the idea that a setting must not conjure an empty
node, and a lone layer never gets one because level 0 creates none. The
handler now creates the node, which is what carries the setting, and
`_drop_if_empty` already keeps a node with an explicit setting. Measured on
that scene: level 0, nothing; level 1 set on the lone layer, 7 face cells and
a list of the two slots its sheet still lacks.

**The level and rows controls only show when there is a cliff to control.** The
four of them (level, rows, and an *auto* beside each) are settings of the cliff
generator, per layer. They used to sit in the toolbar for every tileset and only
go grey until the layer had faces, and on a tileset with no cliff at all they
read as noise: level of what, rows of what. First cut: hidden unless
`CliffData.all_configs(tileset)` had an entry. Not enough, Cidwel pointed out
from the cave sheet: it has three cliffs and dozens of other terrains, and the
controls showed for all of them. Now they show in exactly two situations, the
selected terrain has a cliff, or the layer already carries generated faces;
`_sync_cliff_rows()` runs on tileset change, on selection change, on the list
rebuild and when the cliff window saves.

**The window's left column: rules between sections, a toolbar that wraps, and
totals in view with the lists behind a hover.** Three things Cidwel saw at once
in a narrow window. There was no separator anywhere, so the toolbar, the
readout, the sheet and the palette ran into one another; three `HSeparator`s
now. The toolbar was one `HBoxContainer` holding ten controls, which overflows
the moment the split is dragged narrower than they are; it is an
`HFlowContainer` and wraps. And the readout listed every slot the shape never
asks for by name, thirty names in a line: the number stays in the text, "34 it
never asks for (hover for which)", and the names, with the per-row counts of
what is left to draw, live in the marker's tooltip. The legend under it is one
short line. Checked with a real capture of the window.

Two more from the same look, once the first fix was in. The rules were there
and could not be seen: a bare `HSeparator` in the editor's dark theme is one
pixel of nearly the panel's grey. And the split's grabber, the vertical rule
between the column and the preview, did not show at all, not even forced
visible: the theme draws it as a 48 px nub at mid-height. Both now come from
`editor/Chrome.gd`, shared with the exemplar window: `rule()` is two pixels,
lighter, with room around it; `dress_split()` draws the rule as the bar's
background, a 12 by 4 texture stretched over the gutter with a brighter core,
and a short bright handle at the middle as the grabber icon.

Why the background and not a tall grabber icon, which was the first try and
showed in a capture taken with the default theme: three things the editor's
theme does to a split. It sets the `autohide` constant to 1, which hides the
icon until the mouse crosses it whatever `dragger_visibility` says; it paints
`split_bar_background` empty; and since 4.5 the split draws its icon "only if it
fits", so a texture taller than the window is skipped and the theme's 48 px nub
is all that slot can ever give. Also the icon an `HSplitContainer` draws is
called `grabber` in its own theme type, not `h_grabber`: an override of the
latter alone changes nothing. `dress_split()` overrides all of it: the
constant, the background, the three icon names.

The window opens with the column at 30% of its width. It used to be a
`split_offset` of 700, which on a wide window handed the column three quarters
of it and left the preview a strip. `Chrome.open_at(split, 0.30)` does it with
the stretch ratios, 3:7 on two expanding panes, so it holds at any window size
and through a resize until the user drags the divider. The column's minimums
still win, and the palette row was the widest thing in it at 453 px, "Palette"
and two long buttons; it is a flow now and the buttons drop a line.
**The palette is under the sheet, not inside it.** Once the column scrolled,
the palette, its last row, was wherever the sheet ended: a page and a half
down with a tall sheet, and with the column at its minimum height it got no
height at all, since a `ScrollContainer` hands its child the child's minimum
and the palette had none. Cidwel opened the window and asked where the tileset
to pick from was. The pane is a `VSplitContainer` now, dressed like the other
split: the scrolling sheet on top, the palette row and the palette under it,
opened 3:2 and the divider the user's to drag, with a 200 px floor on the
palette so a tall sheet cannot squeeze it out. `Chrome` orients its bar and
handle by the split's direction, a `VSplitContainer` draws the theme's own
`grabber` name too. Measured: 349 px of palette in a 975 px window, 228 in
the default 760.
The left column also scrolls now, because with the sheet
in Advanced and a palette under it it is taller than any window. And the
exemplar window's left pane is sized to its grid: fixed at 260 px it showed
three and a half of a 5-wide block's columns and a scrollbar, and a slot you
cannot see is a slot you never fill.

**The Cliff button was closed to Patch terrains.** `TOOL_MODES["cliff"]`
listed Match tiles and Match vertices only, so with an exemplar selected there
was no button, and no button reads as "this type cannot have a wall". Cidwel:
"I don't know how to tell that terrain it should draw cliffs". It can: an
exemplar's painted cells are a region with a south edge like any other, and the
generator does not care who autotiles the top. Checked in memory on
`06_Exemplar` with the `mountain` sheet copied under `mountain_ring`: a 7 by 4
plateau at level 1 grew its 7 face cells. Patch is in the list now, for the
adopt button too, and the README walks through the setup in order, including
the single-layer case where the height has to be given in `rows`, which was the
other half of the confusion.

The first demo scene built for it showed the plateau with no wall at all.
The exemplar's rim, the ring the drawing puts around the painted cells, lives
on the `ExemplarEdges` child, and the generator walked the painted cells only:
a level-1 wall is one row, and that row is exactly where the rim sits, drawn
over it. The rim is the top of the hill as much as the cells inside it, so the
plateau the generator walks is now the painted cells plus the terrain's cells
on that child, and the wall hangs from the rim's south edge. `10_ExemplarCliff`
is the scene: the `test` exemplar (a grass top with a rock rim, all 21 roles)
painted as a blob with a notch and a ledge, inheriting the `mountain` sheet,
one layer at level 1 with `rows` at 2. Built by `Tools/DemoExemplarCliff.gd`.

**`rows` was greyed out at 0, which is the one control that lets a lone layer
have a wall.** The chain: a single layer is the lowest taking part, so level 0,
the base, which grows no wall; no wall means no faces node; and the rows box
was tied to that node being there, so it read 0 and would not take a number.
Cidwel: "the number of rows was at 0 and it wouldn't let me change it". The box is
editable now, `set_rows_override` makes the node the way the level control
already did, and an explicit `rows` builds a wall even at level 0: a stack
takes its heights from the levels and the base rule belongs there, while a map
with one layer has no stack and its hill hangs into the ground drawn beside it.
Measured on `06_Exemplar`: default level 0, no node, no wall; `rows` 2 gives 42
face cells; `rows` 0 takes all 42 back. The four demo stacks are untouched,
still 0/1/2/3 and 0/19/26/18 cells.

A first attempt made a lone layer level 1 outright. That was wrong and was
reverted: the default is level 0 and nothing drawn, exactly as before. What is
new is that after configuring a sheet in the cliff window, if the layer it
would build on is on its own and has no height of its own, the dock writes the
sheet's height once and says so. Once, because the setting it writes is what
stops it firing again, and a 0 typed afterwards is a setting too.

**The reload button toggled a plugin that no longer existed.** It called
`set_plugin_enabled("better-terrain", ...)` from the days before the addon was
`better-tile-editor`, so it disabled nothing, enabled nothing, and said nothing.
It reads the folder from its own script path now, and warns if there is no
enabled plugin there.

**A slot can hold a block of tiles, not just one.** A wall is a row where it
starts, a row where it ends, and something repeated in between, and that
something was one tile. Stamp it forty times and it reads as a stamp. Cidwel,
who draws these by hand: "what if, for example, you need to take a 2x2 frame
from the tileset that has to be the one that repeats?"

So a slot's entry grows an optional `size`, and `block_coord` says which tile
of the group a given face cell gets, from two phases.

**Across**, from the run: how far the cell is into the stretch of cells beside
it asking for the same slot, which `slot_runs` works out in one pass per line.
The first version took it from the map column and that was the mistake. A wall
starting at an odd x entered a 2-wide group on its second column, so the drawing
began mid-stride right against its own left edge, and it changed if the mountain
moved one cell sideways. Proved by its own test output: with the group's columns
called A and B, `L B A B A B A R` where it should read `L A B A B A B R`. A run
breaks where the case changes, which is exactly where the wall stops being
straight, so the pattern restarts at each straight stretch and never at a step
or a notch.

**Down**, from the band: how far the cell is into its own run of equal rows,
which `face_map` records. Absolute map y would have been wrong for the same
reason: the wall follows a jagged south edge and its rows are not at a fixed y.

Counting across from the run is also what makes the height take care of itself,
which was the second half of what Cidwel asked ("depending on how many levels
there are, it will have to be done one way or another"). Every row counts from the same
column, so the group on `top`, the one on `middle` and the one on `base` land on
the same columns and stack into one drawing. Two levels: fill top and base.
Four: fill the middle too. No arithmetic, and nothing to redraw per height.

Measured: a 3-wide group on `top` and on `base` of a height-2 wall gives
`23,24,25,23,24,25` on both rows, aligned; the same wall built at x=0 and at
x=7 is identical tile for tile; and the four demo stacks are untouched, still
0/19/26/18 cells.

The gesture is a drag in the palette, and the press/release pair is what makes
it possible: press remembers the tile, release reads the other corner. Same
source only, and a release off the atlas falls back to a plain click, so the
old single-tile gesture is untouched. The slot icon spans the whole block
(`AtlasTexture` over the merged region of the two corner tiles), because a
sheet where you cannot see which slots repeat a pattern is a sheet you have to
remember. `size` is written only when it is not 1 by 1, so a sheet of single
tiles keeps the shape it has always had on disk.

Verified on a 6-row wall with a 2 by 2 group on `middle/mid`: the four tiles
land in a checker that repeats every two columns and every two middle rows,
starting at the group's own first column right after the left end, the top and
base rows keep their own single tiles, and the wall's two ends keep their edge
slots.

**How the window's own code finally got tested.** Every capture of the cliff
window taken with `--headless -s` or `-s` had an empty palette, and not because
the layout was wrong: `TileView.gd` names the `BetterTerrain` autoload as a
global identifier, and in script mode the engine never registers it, so the
script fails to COMPILE and `_palette_view` stays null. `Engine.register_singleton`
before the `load()` does not help, the resolution happens from ProjectSettings
at engine start. The measurements taken on that window were measurements of an
empty box.

A second trap from the same afternoon, in a tool rather than in the addon:
`set_cells` does NOT autotile. It writes `cache[type].front()`, the terrain's
first tile, into every cell it is given, and the art comes from a separate
`update_terrain_cells`. A generator that called only the first stamped one tile
936 times, and the result did not read as "the paint is unfinished", it read as
"this terrain is terrible", which is what Cidwel asked about. Any tool that
paints terrain calls both.

What works is booting a real scene: `godot --path . res://scene.tscn` registers
the autoloads, `TileView` compiles, and the palette has its 3000 reachable
tiles. From there the window can be driven with events built by hand and read
back. That is how the drag was checked: press on (22,3), release on (23,4),
slot comes back `{coord: (22,3), size: (2,2)}`; press and release on the same
tile, slot comes back with no `size`. Anything claimed about that window and
not checked this way is a guess.

**Repeating a matrix, and where it is anchored.** A checkbox in the cliff
window's toolbar, "repeat from the bottom", off by default so nothing already
drawn moves. (Written without it the first time: the resolution changed, the
docs said there was a switch, and there was no switch. Cidwel opened the window
and could not find it.) In that mode a
slot's matrix repeats **upward from the wall's bottom row** (`face_map` records
a `rise` for that) instead of downward from the top, and a `top` slot with no
art of its own borrows the body's, so one matrix covers the whole wall rather
than being assigned twice.

**"Save as shape" wrote to a folder of another project.** The path was a
constant, `res://Maps/Tilesets/cliff_preview_shapes.tscn`, which is where the
game this fork grew out of keeps them. Anywhere else that folder does not
exist, so `ResourceSaver` returned ERR_CANT_OPEN and the window said "error 19"
and nothing about which file. Shapes are the project's data, so `shapes_scene()`
now answers: the `better_terrain/cliff/shapes_scene` project setting if it is
set; else the old path while it still exists, so dxlegends keeps its shapes with
nobody moving a file; else `res://cliff_preview_shapes.tscn`. The folder is
created before the save, and a failure names the file and the setting. Checked
both ways: the demos project saves to the root and lists the shape back, the
game project still resolves to its own file.

**Editing a shape had a way in and no way out.** "Edit shape" loaded a shape
into the canvas and turned Build on, and then went on saying "Edit shape" while
you were editing one, which is the one reading of it that cannot be true. The
only exits were Clear canvas, which throws the drawing away to leave a mode, or
saving, which put you straight back into editing what you had just saved, so the
canvas and the shape list disagreed about what you were looking at.

The button now says **Cancel edit** while a shape is loaded and leaves: `_editing_shape`
cleared, Build off, the canvas kept, because leaving is not throwing away and
Clear canvas is right there. Overwrite and Save as new both end the edit too and
point the shape list at what was written, so the preview shows the result.

**The marked unit was drawn under the marks it needed to beat.** It went first
in the overlay, on the idea that the tiles' own marks should stay on top.
Backwards: what it hid was the amber slot highlight and the red crosses of the
empty slots, and those are exactly the cells you are most likely to be marking,
so the one thing you needed to see was the one thing covered. Cidwel: "the blue
doesn't stand out over the other one, maybe it should be on top". It is drawn last
now, inset by two pixels, with a dark stroke outside a bright one so it reads
against amber, against red and against rock, its inner grid doubled the same
way, and its size written on it, since a rectangle on a grid of rock does not
say by itself whether it is 2 by 2 or 2 by 3.

**Three ways the gesture went quiet.** Cidwel, after the button went in: "now
I can't draw the matrix". The drag itself was fine in a harness, which
means the fault was in the states around it, and there were three.

**Build owns the preview's drag.** In Build mode a drag paints the canvas and
returns before the marking code is ever reached, so with both on the gesture did
nothing at all. Switching the matrix mode on now switches Build off.

**A refresh swallowed the instruction.** `_refresh()` rewrites the readout at
each of its three exits, so the "now pick its tile" line disappeared on the next
hover or height change while the marked unit was still pending. The line is
rebuilt by `_pending_unit_text()` and put back at every exit.

**And a drag with the mode off said nothing.** Silence is what makes a window
feel broken: a drag that goes nowhere now answers with where the gesture lives.

**A matrix needs to know where its own bottom row sits.** The first version
counted the vertical phase as `rise - 1` and clamped it at zero, which made the
ground row and the row above it land on the SAME row of the matrix: two
identical rows at the foot of every wall, which is what Cidwel saw after marking
a 2 by 2 and picking its tiles. The phase is counted from the matrix's foot
instead: `rise - foot`, where `foot` is how many rows above the ground the
matrix's bottom row belongs. Marking the unit on the preview records it from the
rectangle's bottom row; a matrix assigned the plain way guesses it from the slot
(0 for the ground row, 1 for the body). Checked both ways on a four-row wall: a
body matrix gives 5,4,3,4 from the ground up, one marked over the ground row
gives 5,4,5,4, and in neither do the bottom two rows match.

**And the palette says which tile the slot is on.** There was no mark at all
once the drag ended, so after picking a matrix nothing pointed at it. The slot's
tile, or its whole matrix, is framed in the palette with its size, dimmer when
the slot is borrowing from a coarser case. `_palette_rect_of` walks TileView's
own source stacking to find the rect rather than probing for it; checked against
`tile_part_from_position`, which maps the middle of the computed rect back to
the same tile.

**Behind a button of its own, and visible while you do it.** Cidwel, after
using it: "it works but I don't get how it goes... when you select several
tiles you can't see what you selected, and it doesn't explain how to use it
either". Three
separate faults, all fair.

A whole editing gesture that fires whether or not you meant it is how a window
stops being trusted, so the preview drag now lives behind a **Repeating
matrix** toggle. Off, the preview behaves exactly as it always did and a drag
does nothing. On, the readout spells out the two steps and says you can change
the shape and the height to see the result on another wall, which the fixture
picker and the height spinner already did and nothing said so.

And the palette drag draws itself: the rectangle snapped to whole tiles, its
inner grid so a 2 by 2 reads as four tiles, and its size written in the corner.
Picking four tiles and seeing nothing move is indistinguishable from picking
none, which is what he was describing.

**The unit is marked on the preview, where you can see it.** Dragging a
rectangle in the palette says which tiles; dragging one over the wall in the
preview says what shape they repeat in and over which slots, and that is the
half you can actually look at. Cidwel pointed at two cells of the preview: "those
two tiles should be a kind of tile group that can be duplicated, and
the two above as well". So: drag over the preview, the rectangle lights up
with its own grid so a 2 by 2 reads as four cells, the readout names the slots
it covers, and the next pick in the palette fills every one of them at once. A
unit taller than one row spans rows that are different slots, and those only
line up against a fixed end, so marking one turns `from_bottom` on and says so
before you pick. A drag of a single cell is still the old gesture: select that
slot.

It exists because of a lab Cidwel painted by hand: sixty specimens, fifteen
geographies by four heights, generated with his own sheet and repainted with
what the tiles should really be (`Tools/BuildCliffLab.gd` and
`Tools/ReadCliffLab.gd` in the demos project). Read back, a straight run came
out like this, counting atlas rows from the ground up:

| height | bottom to top | his | what the sheet gave |
|---|---|---|---|
| 2 | base, top | 5, **4** | 5, 3 |
| 3 | base, middle, top | 5, 4, **3** | 5, 4, 3 |
| 4 | base, mid, mid, top | 5, 4, **3, 4** | 5, 4, 4, 3 |

The top row has no art of its own: its tile depends on how tall the wall is,
which no per-row slot can say. That is a two-row matrix counted from the ground,
and it is why the anchor had to become a choice rather than a rewrite: walls
drawn with a distinct lip still want the old behaviour, and they keep it.

Configured against his painting, 136 of 184 cells come out exactly right. Of
the 48 that do not, **28 differ only in which atlas column the case uses**,
which is sheet configuration and not resolution. The remaining 20 are one
geography at one height where he kept the classic order.

**The `mountain` sheet had four holes, all of the same family.** `l_plat_end`
is "plateau on the left, open on the right", which is the wall's right edge
whatever stands behind it, and `r_plat_end` is its mirror. Neither has a
fallback, because `_step_fallback` only coarsens `step_hi` and `step_lo`, so an
empty one draws nothing at all. The sheet is a three-wide strip per row (left
edge, middle, right edge), so each `l_plat_end` took its row's right edge and
each `r_plat_end` its left. All eight were filled, not only the four the demo
shape asked for, so the same hole cannot turn up on another shape. `06_Exemplar`
went from 42 face cells of 46 to 46 of 46.

**A wall stopped at the first row where its own terrain came back.** Cidwel,
pointing at four cells of `06_Exemplar`: "the tiles to the north should affect the
terrains to the south". All four read the same way:

```
(4,7):  mountain=true  face_map=true  CliffFaces=false  Ground=true
        north (4,6):   mountain=false face_map=true
```

The cell to the north is not plateau and does generate a face, so the wall comes
down from there. The cell itself is in the face map too, so the generator asks
for it. And it never reaches the layer, dropped exactly where the terrain
resumes underneath.

Two rules put it there, and they had always disagreed with a third. The faces
layer sat one z BELOW its own ground, and `_covering_layers` counted that ground
as a coverer, so any face over it was skipped rather than written invisible: an
invisible tile still carries a collision polygon, and a bot walks into a wall it
cannot see. Meanwhile `face_map` had always said the opposite about what a wall
is: "a face keeps going for its full height even where the region resumes below
it... the wall of a pit covers the ground on its far side", which is only true
if the wall draws in FRONT.

The collision argument turned out not to hold either: Cidwel takes collision
from the visible ground above, not from the faces, so a face behind a floor was
never a hidden wall to walk into. It was just a missing wall.

The first fix moved the faces in FRONT of their own ground, on the strength of
that `face_map` comment, and it was wrong. A wall ten rows tall then ran
straight down over the grass top of the next mountain and buried it: "you're
painting over the surface". **They were never the same question.**
Whether the face is written is one; whether it is drawn over the ground is
another, and the answer differs. It is written, and it stays behind: the
terrain's own surface is nearer the eye than a wall hanging from something
further back, and where that surface has a hole the wall shows through it,
which is the whole point of having written it.

So `_covering_layers` drops the self-entry and the z is left alone. On
`06_Exemplar`, 111 dropped cells became 0 with both mountains keeping their
grass. The four stacked demo layers write the same 0/19/26/18 cells and
`07_CliffFaces_SoM` renders pixel for pixel identical to before any of this.

### J2. A second kind of cliff face: the pattern

The sheet in section J describes a wall cell by cell: for every combination of
what stands to its left and to its right, which tile. Sixty-six slots. It is
exact, it survives shapes nobody planned for, and it is an afternoon of work
before anything appears on the map.

Cidwel asked for a different one and then drew it: a frame of nine buttons laid
out the way they sit on a wall. Four corners at 1x1, a top and a bottom edge at
?x1, a left and a right at 1x?, and in the middle the rectangle that repeats,
?x?. Press a piece, select the tiles, they go there.

So `CliffPattern` reads a wall as nine regions rather than as a table of cases.
Three bands of rows and three of columns; the bands are decided first and the
piece second, so a corner is a piece of its own and not something the top row
happens to cover. Nothing at all is asked about neighbours: a cell's tile comes
from where it sits, how far along its run and how far from the plateau and from
the ground.

**A piece left empty is not a hole.** It asks its row band first, then its
column band, then the body: the top-left of a wall looks more like the rest of
the top than like the rest of the left. So a sheet with nothing but a body
already draws, and every piece filled in after that narrows it. The panel says
which pieces have their own art and which are falling back, because that is the
question you have while filling it in.

Two rules for walls that do not fit. Too short for both row bands and the one
at the **ground** wins: a cliff with no footing reads as unfinished, one with no
cap reads as a cliff that carries on upward, which is usually true. Too narrow
for both column bands and the **left** wins, for symmetry with reading order.
Plus the two offsets, which say which column and which row of the body the
repeat starts on. They move the **body** and leave the ends alone: it is the
body's repeat they shift, and an end is not repeating along the wall, it is
pinned to it. For a while the column one moved all four bands, on a misreading
of a report that turned out to be about the row offset; that is out again.
Measured on a run of eight with two-wide ends and body: at offset 0 the row
reads `0 1 | 10 11 12 10 11 | 5 6`, at offset 1 `0 1 | 11 12 10 11 12 | 5 6`.

**It lives in the same window as the other two.** It was built as a window of
its own with its own button in the dock, and that was wrong: from where the user
sits it is a third way of describing the same face, so it belongs in the same
list as Simple and Advanced. The `Advanced` toggle is now a three-way picker,
and picking Pattern swaps the middle of the window. Everything that belongs to
the slot sheet hides with it, the readout included, because leaving a report
about 66 slots on screen while the map is built from nine pieces buries the
panel and reads as an afterthought bolted on.

Switching away keeps the pattern's rectangles in the sheet, and switching back
finds them where they were. The two never share a resolution path: `rebuild`
branches once on the sheet's `mode` and the case machinery never runs for a
pattern.

**An end is structural; air only settles ties.** This took three passes and two
of them were wrong, so both are worth keeping.

The first read the bands off the index alone: column 0 of a run is its left end,
the last is its right. A run breaks wherever the plateau steps, so a one-column
run with a step on its left and open sky on its right came out as a LEFT end
when what you see is a right one. Cidwel: "every algorithm classifies that one
as corner LEFT, and it's really more of a corner RIGHT".

The second swung the other way and made the test open air on each side. That is
decided row by row, while the end of a run is the same all the way down: where a
wall steps, the taller one beside it finishes a row earlier, so the bottom cell
of a column was an end and the two above it were not. One corner right and the
rest of its own column wrong, which Cidwel reported by coordinate: "why are 4,4
and 4,5 not LEFT, but 4,6 is?".

The third missed a case the first two never reached, reported the same way:
"why are 18,4 and 18,5 considered LEFT and not RIGHT?". That column has plateau
immediately to its left, at its own level. **A side where the terrain carries on
is not an end at all**: you are the other edge of the mass behind you. It is
read at the plateau row the run hangs from, so it holds all the way down
the wall rather than flickering per row.

What holds is all three at once. **The end is structural**: first column of the run is
the left end, last is the right, whatever stands beside them. **Ground beside you
cancels that side.** And **air decides only the tie**, when the run is too narrow
for both bands and both still claim it: a run one column
wide with a step on one side and sky on the other is an end of the side you can
see. Checked on all six cells of the report plus the two earlier ones: (4,4),
(4,5), (4,6) are the whole left column of their run; (8,6), (8,7), (8,8) the
whole right column; the lone mountain is still a tower; and the rightmost cell
of the wall, a run of one with a step to its left, is still a right end.

**A tower is not a narrow wall.** A run with air on
both sides is not a wall with ends, it is a tower, and it gets three pieces of
its own shown as a column beside the frame: `alone_top`, `alone`,
`alone_bottom`. The wall's own cap was tried first and it is wrong, because the
cap of a pillar is not a slice of the cap of a cliff. Each is 1 to n rows tall
and the bands are measured against the tower's pieces, not the wall's, so a
tower with a one-row cap beside a wall with a two-row one comes out right.
Verified: a six-row tower with a 1x1 cap, a 1x3 body and a 1x1 foot uses its cap
on the top row, repeats its body 3,1 down the middle and puts its foot on the
ground, while a five-wide wall beside it uses its own two-row cap.

Left empty, each falls back to the tower's body first and to the wall's piece
after that.

**And the band must not depend on the art existing.** The first version only
filed a run as a tower once the tower had tiles, which is a circle: you could
not give it tiles because you could not find it, since nothing on the wall ever
said "this bit is a tower". The lone mountain at the left of the preview kept
coming out as a left end and Cidwel kept pointing at it. The band is geometry
now and the missing art is what the fallbacks are for, so the region exists from
the first time the window opens, the preview lights it, and clicking it arms the
piece that owns it. Measured on the Compact shape at height one with the tower
left empty: one cell filed as tower, at x=1, which is the lone mountain, and a
click on it arms `alone_bottom`.

**Which end the middle is anchored to is a switch**, "build the middle from the
ground up". It cannot be worked out from the drawing, which is why it is a
control and not a rule, and the top and ground rows are unaffected, being
anchored already.

What it is for took three tries to state, and the statement is Cidwel's:
"if you always generated the series from above bottom, it would always come out
in the right order, I could always create new heights and they would paint
correctly". With
the middle counted from the top, **the row just above the ground depends on how
tall the wall is**: with a two-row body and a row offset of one it alternates
`4 3 4 3` as the height climbs, so a sheet tuned at three levels is wrong at
four. Built from the ground up it is the same row at every height, and each new
height stacks on top of what already worked.

That invariant is what the test asserts, over heights two to eight, rather than
any one sequence of rows: it is the stronger claim and it is the reason the
switch exists.

One wrong turn worth keeping: in between, this was implemented as flipping each
piece's own rows, because at the height Cidwel happened to be on the anchor made
no difference and the switch looked dead. Flipping changes something at every
height, which is why it seemed right, but the row above the ground still
alternates under it. Doing something is not the same as doing the thing.

The negative index in the branch is not a trick for its own sake:
`posmod(-(u + 1), n)` is `n - 1 - posmod(u, n)`, the body read upward, through
the same wrap as everything else rather than a second path that could drift
from it.

**"Clear the sheet" cleared the wrong sheet.** It counted slots and only slots,
so in pattern mode it read a sheet nobody had filled, announced that it was
already empty and left all nine pieces standing. It clears whichever sheet is on
screen now, and the old five-piece names are erased along with the new ones, or a
sheet written before they were renamed would come back the moment a piece fell
through to one of them. "Empty the slot (forbid this shape)" is hidden in pattern
mode instead of meaning nothing there: a piece is emptied by right-clicking it.

**A second click lets go.** Clicking a piece, on the wall or on its button,
armed it; clicking it again armed it a second time. A selection you can only
swap and never drop is one you cannot get out of except by arming something you
did not want, and with nothing armed the palette says so rather than writing
into whatever was last touched.

**And it says which pieces each offset can move.** An offset rotates a piece's
own tiles, so it can only touch pieces with more than one of them in that
direction. Cidwel's LEFT is 1 by 2: one column, two rows. The column offset
cannot move it and the row offset can, and neither the control nor anything else
said so, so the column one read as broken. The panel now prints both lists,
`Column offset moves body, bottom. Row offset moves left, body, right, alone.`,
which answers the question people actually ask: not "does this control work" but
"why is it not moving the piece I am looking at".

**The Rebuild button, and why it looked pointless.** It works out the faces a
layer should have, shows the difference and writes it only on a confirmation,
listing what would change, what stands over painted ground and which empty slots
the shape asks for. The faces follow the terrain, the sheet and the level on
their own, so it is for what those cannot see: a scene whose faces were built by
an older version of the addon, a tileset edited outside these windows, a map
whose faces were painted by hand.

What made it feel dead is that its commonest answer went to the console. Press
it with nothing to do, watch nothing happen, conclude it is broken. It now says
so in the dock, and says which of the three reasons applies: no terrain with a
sheet on this layer, a wall zero rows tall, or the faces already matching.

**A wall is one drawing, so its columns line up all the way down.** A cell that
sits below two south edges belongs to the nearer one, so a wall can lose columns
to a lower plateau partway down. Read row by row, its run then starts further
along, the body's repeat restarts two columns over, and the face carries a
horizontal seam. Cidwel found one at `(30,17)` and `(30,18)`: the same wall,
hanging from the same plateau row, with runs beginning at x=26 and x=28.

Every row takes its place from the wall's TOP row now, the one directly under
the plateau, so the column, the width and the two ends are the same from top to
bottom. The regression is synthetic rather than a scene: a strip five wide with
two plateau cells two rows under its left end, which claims the wall's bottom
row at x 0 and 1 and reproduces the split exactly.

**And it says where you are.** The readout under the pieces names the cell the
mouse is over, which of the twelve drew it, the run it belongs to (which column
of how many, and whether each side is air), how far down the wall it is, and the
tile that came out, plus which piece answered when a fallback did. It is a
read-only field you can select and copy, which is the point: Cidwel asked for it
so a fault could be pointed at by coordinate instead of by pointing at a
screenshot. It updates on hover, written straight into the field rather than
through a refresh, because it changes on every mouse move.

```
mountain  cell=(3, 4)  piece=left  run: col 0 of 1, air left=yes right=no
          row 2 of 3 from the top  tile=source:0 atlas:(22, 4)
```

**And all of it is a test now.** Every rule above was fixed by hand, checked by
hand, and then put at risk by the next fix to the same forty lines; by the
fourth, Cidwel stopped believing the answers: "who knows if you did it right... or
worse, what you changed". Fair. `tests/cliff_pattern.gd` asserts the lot, including
the cells reported by coordinate, and runs in one command against the demos
project:

```
godot --headless --path <demos> -s <repo>/tests/cliff_pattern.gd
```

Twenty-two assertions: the six cells of the structural-ends report, the narrow run
that takes the open side, the lone tower with its art missing, a tower whose
bands differ from the wall's beside it, both offsets, the short wall keeping its
ground row, the fallback chain, and the three slot-mode demo scenes still
writing 0/19/26/18 and 44 cells. It exits non-zero when one breaks.

**The preview answers both ways round.** Click a cell of the wall and the piece
that drew it arms itself; press a piece and every cell it owns lights up. The
arithmetic for it already existed, it was just buried inside `tile_for`, so
`bands_at` came out of it and both the tile and the piece name come from one
calculation, which is the only arrangement in which they cannot disagree.
Reading a wall and working out in your head which of nine buttons a bit of rock
came from is exactly the step a preview is there to remove. Checked by clicking
one cell of each of the nine regions: nine out of nine arm the right piece.

Checked by filling all nine from the `mountain` art and reading the wall back:

```
22,3  23,3 23,3 23,3 23,3  24,3
22,4  23,4 23,4 23,4 23,4  24,4
22,4  23,4 23,4 23,4 23,4  24,4
22,4  23,4 23,4 23,4 23,4  24,4
22,5  23,5 23,5 23,5 23,5  24,5
```

Corners in the corners, edges along the edges, the body repeating between them.
The nine existing demo layers are untouched, still 0/19/26/18 and 44 cells.

### J3. Moving a terrain between groups, and folding a group away

Groups were a filter: chips along the top, a header line where the list changes
group, and no way to change a terrain's group except by opening its properties
dialog and picking from a dropdown. Both of the things you actually do with a
list of sixty terrains, sorting them and getting the ones you are not using out
of the way, went through that dialog or not at all.

**Drag an entry onto a group to move it there.** `TerrainEntry` answers
`_get_drag_data` with its id and a small preview; a group header and any other
entry accept the drop. Dropped on a header the terrain joins that group; dropped
on an entry it joins whatever group that entry is in, which may be none, so
there is a way back out of a group without a header to aim at. It goes through
the same `perform_edit_terrain` the properties dialog uses, with everything else
about the terrain carried across untouched, so one undo takes it back. A drop
that changes nothing is not an edit and commits nothing. The decoration
pseudo-terrain neither drags nor accepts: it is not a terrain and has no group.

**The empty space belongs to a group too.** Entries and headers between them
left most of the panel dead: the space to the right of the last entry in a row,
the gap under a short group, everything below the last one. Aiming at a 40 pixel
square with half a panel of room going spare is a worse gesture than it needs to
be, and Cidwel said so. The list itself answers for that space now and works out
the group from the height: a row first, so the empty half of a row belongs to
the group filling the other half; failing that the nearest thing above, because
a group owns the space under it down to the next header; above everything, the
ungrouped terrains, which is where the list starts.

Godot asks the control under the cursor and walks up, so this is only consulted
where no entry or header answered. Hovering one of those still lights that one
and nothing else.

**The target draws where the terrain will land.** A square, lit on whichever
header or entry is under the cursor and answering for the drop, so the group you
are about to join is the row that says so. `_can_drop_data` fires while the
mouse is over a control and never once it leaves, so `NOTIFICATION_MOUSE_EXIT`
and `NOTIFICATION_DRAG_END` are what actually put the mark away.

And no dialog afterwards. It said "flowers moved to no group" and waited for an
OK, which is a toll on a gesture whose whole point is that you watched the thing
land.

**Fold a group with the arrow on its header.** Only the entries hide; the header
stays, or there would be nothing left to unfold. A running search overrides it,
because a result you cannot see is worse than a group you asked to fold. The
folded set is a view preference, so it lives in EditorSettings beside the grid
mode and not in the tileset: folding a group is something you do while working,
not something the terrain set should remember about itself.

The header had to stop being a plain `HBoxContainer` that ignored the mouse. A
row you want to fold and drop onto is a node with behaviour, so it is
`GroupHeader`, and its children ignore the mouse so the whole row is the target
rather than the gaps between the label and the rule.

### K. Using one of a terrain's own tiles as its icon

`editor/TerrainProperties.gd` (the "Tile" row, built from code),
`editor/Dock.gd` (`_on_add_terrain_pressed`, `_on_edit_terrain_pressed`)

In the properties dialog, under "Icon", a button opens a grid of **that terrain's
own tiles** and lets you pick which one stands for it in the list. It is an
alternative to the image path, not an addition: the icon is a dictionary and can
only be one thing, so typing a path drops the tile and picking a tile clears the
path. The `x` beside it goes back to no tile.

The tiles it offers are the ones already marked with that terrain, not the whole
atlas: an icon taken from elsewhere would show something the terrain does not
paint. A freshly created terrain has none yet, and the button says so instead of
opening an empty grid.

**It fixes an existing bug on the way.** The model stored icons both ways,
`{path}` or `{source_id, coord}`, and the toolbar knew how to pick a tile from
`TileView`, but this dialog wrote `{path = ...}` **every time**. So having a tile
icon and opening the properties to change anything else erased it on OK. The dialog
now loads the icon however it comes and hands it back the same way.

The `source_id` has to be recovered by hand: `get_tile_sources_in_terrain` returns
the `TileSetAtlasSource` object but not its id, so the row builds a source -> id map
from the tileset. Checked with two different sources in one tileset.

### L. Selecting part of the map

`editor/Dock.gd` (`_add_map_select_button`, `canvas_input`, `canvas_draw`),
`icons/MapSelect.svg`

A tool the plugin did not have: selecting an area **of the map**. Drag a rectangle
and the painted cells inside it are marked. With a selection up, dragging it moves
it, and right-click offers cut, copy, paste here, duplicate here, delete and
deselect. All of it goes through `EditorUndoRedoManager` with a restore point over
the area, so `Ctrl+Z` undoes the whole thing.

It also feeds the cliff window's preview: what you captured shows up as the shape
**"From the map"**, first in the list and selected. The built-in preview shapes are
invented, and the slots that come out wrong are the ones your own map asks for; an
arbitrary patch of a real map claimed all four empty joint slots within ten cells.

**Not to be confused with the `Select` in the toolbar**, which is upstream's and
acts on the **atlas**: it picks tiles from the tileset to copy their terrain
configuration onto others. It never touched a map cell, which is why using it and
then drawing carried on painting. It got the same icon as this one at first and
that was indefensible; it has its own now.

**Godot's own selection is no use.** `EditorInterface` exposes the selected
**nodes**, not cells, and the layer editor is internal C++: rooting around in its
nodes would break on every update. The plugin already receives canvas input through
`_forward_canvas_gui_input`, so it keeps its own selection.

**Two details that each cost a bug.** `Rect2i.has_point` treats `end` as one cell
past the last, so a box built only with `expand()` claims its own bottom row is
outside it: grabbing the selection there failed. Boxes are inclusive (`hi - lo +
ONE`) now, and the grab asks whether the cell is one of the marked ones rather than
whether it is in the box, which also respects holes inside. And capturing no longer
opens a dialog: a modal telling you a drag worked is noise, and it steals the focus
you need for the next one. There is a label in the bar with what you have instead.

### M. A multi-cell brush, and the status line on the canvas

`editor/Dock.gd` (`_hook_brush_menu`, `_brush_cells`, `_place_brush_badge`,
`_map_status_line`)

**The pencil paints blocks.** Right-click it and pick anything from 1x1 to 8x8.
Whenever the multiplier is not 1 it shows as a badge on the icon, because a tool
that does not behave the way it looks has to say so on itself. The menu you changed
it in is long gone by then.

Odd sizes centre on the cursor, even ones lean top-left, as in any pixel editor.
The size belongs to **the pencil only**. Line, rectangle, bucket and the selection
still show one cell.

The first attempt offered 1, 4, 9 and 16. That scale is useless: between a single
cell and a 4x4 block there is no way to paint a ledge two cells wide, and half of
every wall is made of those.

**The status line goes on the canvas, not in the bar.** Bottom left of the 2D
viewport, in screen coordinates, so it does not move when you pan or zoom:

```
Ground2  (13, 7)
Ground2  (13, 7)   22 tiles  8x4   22 copied
```

The layer, the coordinate under the cursor and, only when they exist, the selection
and the clipboard.

It used to live in the dock's bar, where nobody reads it. While you are dragging
across the map you are not looking at a panel at the bottom. And it was taking
width from a bar that has none to spare.

**Shortcuts go in `canvas_input`, not `_shortcut_input`.** With the Scene panel
focused, `Ctrl+X` is Godot's own "Cut Node(s)", and a plugin does not win that
fight from there. **It took a whole layer out of the tree.** From outside, that
looked like "the map got cut".

`canvas_input` is input forwarded from the 2D viewport, so it only fires with the
canvas active, and returning `true` eats the event before the editor sees it.

Godot 4.7's Scene Paint tool also binds B, the terrain bucket shortcut. Its
viewport listener runs outside the plugin forwarding chain, so activating both
tools produces a "No scene selected for painting" dialog and can swallow a mouse
release. The plugin intercepts the bucket shortcut in `_input` while the canvas
or terrain panel has focus, before editor shortcuts run. Text fields and other
editor contexts keep their normal input. Selecting the bucket also exits an
already-active Scene Paint tool and finishes the terrain stroke. A mouse motion
without the stroke's button held cancels leftover painting state after a lost
release.

While the map selection tool is active, `Delete`, `Ctrl+C`, `Ctrl+X` and `Ctrl+V`
are blocked in the atlas panel too. Over there `Ctrl+X` means "strip the terrain
bits off these tiles". That is nothing like what someone holding a map selection
expects, and it is both silent and wide.

### N. A new terrain type: `EXEMPLAR` (read the drawing instead of scoring)

`BetterTerrain.gd` (the `TerrainType` enum, two early returns), `ExemplarData.gd`,
`ExemplarTerrain.gd`, `editor/ExemplarEditor.gd`, `editor/ModeHelp.gd`,
`editor/Dock.gd`, `editor/TerrainProperties.gd`, `icons/Patch.svg`

#### The problem

BetterTerrain picks a tile by **scoring**. Every tile declares what it accepts on
each side, and the engine keeps whichever adds up best. That works as long as the
art has a tile for every shape the terrain can take.

A hand-drawn set piece does not. A pond is drawn once, as a rectangle with its
corners cut. Forcing it through scoring means splitting every answer into pieces
the score can express, and on a real pond that came to **279 alternative tiles
over 24 drawings**. Nobody maintains that by hand. And it still could not say the
one thing most needed: "nothing goes here".

#### What this type does

It does not score, and it does not ask anyone to fill in a table of 511
neighbourhoods either. **It reads the drawing.** A set piece like a pond already
*is* the terrain laid out: a patch of water with its bank around it. Every cell has
a **role** given by where it sits, the top bank, the left one, the corner where
they meet, open water, and those roles are **seventeen**, the whole vocabulary.
Painting is then a rule: work out which role each cell of the painted shape plays,
and put that role's tile there.

**Measured**, not asserted. The test was a pond finished by hand cell by cell: six
free-drawn shapes, 598 cells.

Reading the drawing **and nothing else** paints all of them, **with no holes and no
corrections**, and **539 of 598 come out pixel for pixel** the same as the
hand-placed ones. The remaining 59 are the same role drawn with a sibling variant.
A choice, not a mistake.

**Four more roles when the drawing has corners.** `CORNER_NW/NE/SW/SE`,
kept apart from the seventeen in `ExemplarData.CORNERS`. The seventeen never
claim the block's four corner cells: on a pond whose bank turns with a diagonal
they are empty, and the map cell that touches the water only corner to corner
gets nothing, which is right. But a bank can wrap the corner instead, a wedge
of snow outside the diagonal, and then those four cells are art with nowhere to
go. Now `learn_from_block` reads them, and drops them again when they carry no
ink, so a drawing without them is read exactly as before; `role_for` gives the
diagonal-only cell the corner whose water it touches; `tile_for` needs no
change, a role the table lacks was always "nothing". Tables written before this
have no `corners_read`, and `rebuild` reads such a drawing again once and
stores it, so nobody has to re-mark anything. Measured on the demo tileset: the
pond, corners empty, gets no corner roles; a frozen lake with 64 to 72 opaque
pixels in each corner gets all four, and its ring goes from 28 cells to 32.

The mistake that hid it for a while: I rendered the block on a dark background
and read the corners as empty. They were a light wedge of snow on a dark
square, and a count of opaque pixels said so at once. Render on a checkerboard,
or count.

**When roles are missing, the window says what to draw, not which codes are
absent.** A 4x6 ring, a rocky crater on snow, reads as water 2x4: two columns,
none of them in the middle, so `IN_N`, `IN_C`, `IN_S`, `OUT_N` and `OUT_S` never
occur and any shape painted wider than two comes out with holes across its
middle. The old message listed those five codes. Now `_why_missing()` looks at
the water rectangle and says it in words: the inside is only 2 wide, there is
no middle column, draw it at least 5 wide with a straight run of bank along the
top and bottom. Same for too short. The list of role names is the fallback for
anything else.

**The drawing is pinned as a rectangle, and read from it whoever owns the
tiles.** Membership is one field per tile. While the drawing was "whatever is
marked", another terrain taking one tile of the pond by a stray stroke took a
cell out of the drawing: the reading bent and the map got holes, silently.
Measured: one tile marked as grass, 5 cells blank and 5 edge cells gone. Now
the first reading pins the drawing, source and rectangle, on the terrain
itself (`ExemplarData.record_drawing`, in the seventh element an object keeps
its size in), and every reading after that takes the pixels inside that
rectangle whoever the tiles belong to. Map cells are the terrain's if their
tile lies in its rectangle, before asking the tile, so a stolen tile does not
turn pond cells into grass cells either. The same theft after the change: 35
region cells, 28 edge cells, 0 blank, exactly as before it.

Moving or extending the drawing still needs no button. `stale()` adopts the
marked tiles as the new rectangle only when they form a complete box: a
bigger complete box is someone extending it, a box with a hole is what a
stolen tile leaves and changes nothing. Measured: mark 6x5 complete and the
pin follows; unmark the centre and it stays. The atlas draws the pinned box
labelled as such, and crosses out in red any tile inside it that another
terrain has taken, with a line saying it is read anyway and to re-mark it if
that was a slip.

**The drawing is read by the map itself, not by a button.** `rebuild` used to
return at once when the tileset had no tables, and the only thing that ever
wrote one was the window's *Read the drawing*. So marking the tiles and
painting did nothing until you knew a window existed and pressed a button in
it: a hidden step, and the real reason the mode read as arbitrary. Now
`rebuild` asks `ExemplarData.stale()` whether the stored reading still matches
what is marked, by shape only (which source, the box round the marked tiles,
how many; no pixels, it runs on every stroke), and reads the drawing again when
it does not, or when there is none. Measured on a tileset with its tables
wiped: paint, and the pond comes out whole with 21 roles read; unmark a row of
the drawing, and the next stroke reads it again. The window stays for what a
button is good for, looking at the reading and overriding one role by hand.

**Where the drawing is defined, and why there is no rectangle tool.** The drawing
is nothing more than the tiles marked with the terrain: their bounding box is
the block, and what survives eroding it by one is the water. There is no
separate "select the exemplar" gesture because marking already is one. That
was invisible, and it read as arbitrary: sometimes the window opened with the
drawing well placed and sometimes not, depending on what had been marked.
Now `TileView._draw_exemplar_outline()` draws it live while an exemplar terrain
is selected: a yellow box round the marked tiles labelled *drawing*, a blue
box inside it labelled *inside WxH*, and a red note when the inside is under 3
either way or when nothing is inside yet. Coordinates only, no pixels, because
it runs on every redraw. The window's "nothing to read" message and the
button's tooltip say the same thing in words. This cannot be screenshotted
outside the editor: `TileView.gd` names the `BetterTerrain` autoload, so it
compiles only where the plugin runs (see A).

**The minimum is 21 tiles.** The smallest block the reader accepts is 5x5 with the
four corners empty. A 3x3 of water, so that "open water" comes out distinct from
the four edges, plus its ring. That is the whole pond, with **no alternative tiles
at all**.

A bigger block changes nothing except how much material there is to taper the
banks with. The original 44-tile pond scored 564 of 598.

**And that material is what the minimum runs out of.** In a 5x5 block the water is
a 3x3, so the inner column is `IN_NW`, `IN_W`, `IN_SW`: one cell each. `IN_W` has
a run of one. There is nothing to stretch, so a pond taller than the block repeats
that single tile down its whole side.

Whether you notice depends on the art. If the pond was drawn as an octagon, that
one tile carries the shore as a diagonal, and stacking it gives a zigzag instead
of a straight bank. Traced on a pond eight rows tall, the outer ring stretched
correctly and the inner one did not:

```
5x5 block   IN_NW (7,1)   IN_W (7,2)  (7,2)                      IN_SW (7,3)
8x6 block   IN_NW (35,14) IN_W (35,15) (35,16) (35,16) (35,16)   IN_SW (35,17)
```

The 8x6 block has two cells for `IN_W`, so the run has a first and a last and the
side comes out straight.

So the minimum is genuinely the minimum: it draws any shape, with no holes, and
for a pond about the size of the block it is all you need. Draw a bigger lake with
it and the sides are where it shows. This is a property of the drawing, not a bug
in the reader, and the fix is to draw one more ring rather than to change any code.

#### Two things the drawing teaches that a naive reading misses

Both measured.

- **The diagonals live at the ENDS of the top and bottom runs**, not in the corner
  cells, which a pond block leaves empty. So a bank takes its diagonal where **its
  run stops**, not where something touches it cornerwise. With the naive rule, the
  top bank came out looking like a comb.
- **The left and right banks are STRETCHED** over their run instead of repeating:
  the block's first cell at the top, its last at the bottom, the middle filling the
  rest. That is what makes a bank taper into a corner. The top and bottom ones are
  drawn irregular **on purpose** (a scalloped edge), so there is nothing to stretch
  there and the representative simply repeats.

**Choosing a representative for each role.** A block brings several cells per role,
and some carry decoration (lily pads) or the tail of a cut corner. For the vertical
roles it takes **whichever varies least from row to row**, which is the straight
one; for the rest, **the most typical of the run**, which is what leaves the
decorations out. Without this, the north bank came out with a lily pad repeated
along its whole length.

**Cells that only touch the terrain cornerwise get nothing.** That is an answer,
not a hole: the block leaves its four corners transparent, and the hand-finished
map had those cells deleted on purpose.

#### Where it lives

The sheet goes in the TileSet's meta (`_better_terrain_exemplar`), beside the cliff
ones, keyed by terrain name: `{source, roles, lines, block}`. Nothing in
`BetterTerrain.gd` changes shape, and a tileset with no exemplar terrains never
notices.

**Two early returns in the scorer** so it never places a tile of this type, because
`ExemplarTerrain` is what decides.

**The ring goes on a child layer** (`ExemplarEdges`, `show_behind_parent`), because
nobody paints the bank: it is cleared and rewritten whole on every pass. Deducing
it from the tiles instead is what made the cliff faces creep a row on every
rebuild, and the trap here is the same one.

**The rebuild is immediate**, in `_add_post_process`, not hung off the cliff
timer: with the timer you saw the raw tile for 100 ms before it resolved.

**Reading pixels goes through the region the ATLAS gives**, not through
`coord * texture_region_size`. The latter skips the atlas's margins and separation,
and on one that has them the reads run off the end of the image, which is not an
error that stops anything, it is a crash. And comparing two tiles of different
sizes counts as "as unlike as possible" rather than walking them cell by cell,
which would read past the end of the shorter one.

#### The name

It was called `LOOKUP` while it really was a table of 511 cases. When that went
away the name was left lying, so it became `EXEMPLAR`: in texture synthesis,
*exemplar-based* means exactly "derive all the rules from a single example", which
is what this does. Scenes saved under the old name adopt themselves:
`edges_layer()` looks for `ExemplarEdges` first and `LookupEdges` second, and
renames the old one rather than adding a second layer beside it that would be left
drawn and never cleared.

#### The configurator

The window opens from a button that lives **in the slot the per-type configuration
buttons use**, right behind "paint terrain types", the same place the object
terrain's two buttons sit, not at the end of the bar with the tools. A button that
configures the selected terrain belongs beside the ones it replaces, which is where
you look after choosing a type. It only appears with a terrain of this type
selected, and then "paint terrain types" and "paint symmetry" disappear, because
there is no peering or symmetry to paint here.

There is nothing to fill in. The window shows **the drawing**: one square per cell
of it, laid out in its shape.

Not one per role. That meant showing seventeen squares for a drawing of twenty-one,
and it was exactly what stopped you reproducing it, because the left and right
banks are several cells each and got collapsed into one.

A button **"Read the drawing"** reads the lot in one go. A **live preview** paints a
pond with cut corners, a long bank, a **concave corner** the block never draws, and
a staircase running off one side, so you see it before touching a map. No
one-cell necks: those cannot be built out of any tileset, so they say nothing about
this one and only make the generator look broken. A role can still be overruled by
hand: click it, then click a tile in the palette.

**When it reads, the window says what shape it understood**: "21 tiles, block 5x5,
water 3x3". A drawing read with the wrong shape gets every role wrong at once, and
from the roles alone there is no way to spot it.

It also looks in the atlas it read last time first, then in the others. Trying only
the stored one meant that moving the drawing to another atlas reported "nothing to
read" with the tiles sitting there in plain sight.

**The selection shows in both places.** On the square, drawn ON TOP of the tile:
the tile covers the whole square, so the button's own pressed background is left as
a five-pixel rim nobody sees. And on the **palette**, over the tile that answers the
chosen role, in the same amber, without it, clicking a tile shows nothing and reads
as though you had not clicked. Where each tile falls inside the `TileView` is worked
out by repeating the walk it does when drawing (sources stacked downwards, skipping
disabled ones), so the mark follows the tile through zoom and pan. Changing role
scrolls the palette to show its tile, but only then: doing it on every refresh would
undo your panning the moment you assign one.

The palette pans with the middle drag and zooms with the wheel, like the others.
Three things were needed for that.

The overlay that captures the mouse goes **inside** the `TileView`, not beside it.
A `ScrollContainer` lays out its own children, so an overlay put beside the view
ends up anchored to the container instead.

The zoom the `TileView` asks for through `change_zoom_level` has to be clamped and
handed back by somebody. In the dock, that somebody is the slider.

And `split_offset` on an `HSplitContainer` **is not where the divider goes**. It is
what gets ADDED to the first pane's own minimum. Set to 420 over a grid that
already asked for 382, the palette was left with a hundred pixels and the tileset
sat jammed against the edge,
with nothing to pan.

**In the terrain list**, the type has an icon of its own. The `match` had no case
for it, and because entries are reused, what showed was the previous terrain's
icon. There is a case now, plus a `_` that clears, so the next type anyone adds
cannot hit this.

The thumbnail is **the whole drawing**, not a lone tile. You recognise a pond by
the pond, not by the corner of its bank.

#### The help window

**There are two `?` buttons, and they answer different questions.**

One sits **against the Mode dropdown** in the terrain's properties, and it appears
for **every** mode, not just this one. "Which of these six do I want" is the
question a terrain starts with, and the dropdown answers none of it.

Each mode gets its own steps. The eight sides of match tiles. The four corners of
match vertices. The name several terrains answer to, for category. The empty cells
decoration fills. The lone and joined blocks of object, and the four of the
exemplar drawing.

It works on a terrain created a second ago with not one tile in it, drawing
coloured squares instead of art. A terrain with no drawing still has an algorithm
to explain, and refusing to open exactly when it is most needed is the opposite of
helping.

The other rides on the chosen square of the drawing rather than sitting in the
bar. The question it answers is about THAT square, and a button somewhere else does
not look like it is about anything in particular.

It animates the one thing you cannot see: how a square of the drawing turns into a
decision on the map. Where it is in the drawing, the neighbourhood that asks for
it, where it lands when you paint, and the result.

**The `?` goes AFTER the dropdown**, not before it: the reading order is "this mode
and what is that?", and a question mark in front of the thing it asks about reads
as a label.

**The steps are stepped by hand**, with *Next* and *Previous* and a counter between
them. No timer: a step you are reading must not be taken away from you. The window
is headed "How does it work:".

**The steps go in the order you work in:** how ONE tile is configured, how ALL of
the terrain's tiles end up configured, and then what it paints. Match tiles, match
vertices and object have three; starting from the result explains what comes out but
not what you have to do.

**Each step carries its text beside it, not a caption underneath.** A picture of an
algorithm on its own is a rebus. Text on its own is what these documents already
are. So each step says what is on screen and what it means, in a 250 px panel that
scrolls itself.

In the single-square view, underneath go **the facts about that particular
square**. Which role it is. How many squares of the drawing carry it. The
neighbourhood that asks for it, spelled out. How many times it comes up in the
example shape. All of it computed, none written by hand.

#### Real tiles, and which ones

**The last step of every mode is painted with REAL TILES.** From the open tileset
if it has a terrain of that type, and **borrowed from the project if not**. A mode
needs explaining precisely when the tileset has no terrain of its own yet, so
giving up there is failing where it matters.

It goes through the project's `.tres` files, reading each file's header and loading
nothing that is not a TileSet, then says where it took it from. The first step too:
the nine squares of match tiles and the four
corners of match vertices sit on real tiles, and the lone block of object is a real
painted object.

Schematics say what a mode DECLARES: eight sides, four corners, a block. Only tiles
say what it looks like. The painting is done by **the engine, not this window**, so
what you see is what the mode really does, including whatever this window does not
know about.

Each type is finished by whoever resolves it. The scorer places **nothing** for the
two types this fork added. Read the layer without going through `ObjectTerrain` or
`ExemplarTerrain` and you get back the raw placeholder `set_cells` left behind. A
pond came out as a repeated diagonal until its resolver was called.

**Which terrain gets borrowed is chosen, not taken first.** The first of its type in
a real project turned out to be a wall: half-transparent tiles, vertical faces, art
that is noise at thumbnail size.

So it is scored on three things. How much solid art it has. Whether a tile exists
that accepts on every side, which is another way of asking whether the terrain is an
AREA rather than a line like a bridge or a rail. And how many distinct declarations
there are.

Variety is counted absolutely, not as a fraction. Nine tiles saying nine things is
not richer than twenty-three saying thirteen, only smaller. As a fraction, the tiny
terrain won every time.

**Which tile to show is the whole difference between a step that teaches and one nobody
can read**, and it is not a question about the declaration: it is about WHERE THE TILE
SITS in the shape. The one in the middle of a patch accepts on all eight sides and says
the same thing eight times. A cut corner is a dark diagonal with three loose wedges on
it, that was the first attempt and it was unreadable. And "the largest unbroken arc"
lands on a CONCAVE corner, seven of eight, which covers everything again.

The one that teaches is the tile halfway along a straight edge. It is found on the
shape: a border cell whose left and right neighbours are border cells of the same
edge. Then it is read for whatever it declares, which comes out five of eight on a
side terrain and two of four on a vertex one. Its marks cover one clean half, and
the art underneath shows that same edge.

**The first step of match tiles used to show the wrong thing.** A 3x3 neighbourhood with
the eight directions written over it says WHERE the neighbours are, which is not what a
tile declares, and the title promised the second. The first attempt at fixing it put
flat "yes" and "no" squares around the tile, and that was unreadable too: a green square
beside a tile looks like a green NEIGHBOUR, the opposite of what it meant.

What is drawn now are **the same marks the atlas panel draws**, the terrain's colour
over the middle and over every side it accepts, because those are the ones the user
already reads every day. Beside it goes the same tile unmarked, so the art can be told
apart from the mark. Behind both goes a **chequer**. A tile with transparent corners
on a dark panel looks like a tile that was drawn dark there, and then the marks seem
to sit on art that is not present.

The centre polygon is **outlined only**. All it says is "this tile belongs to the
terrain", and filling it buries the drawing. On a vertex terrain, where it runs
corner to corner, it buries all of it.

**The middle step shows one tile per DECLARATION, the fullest last.** A terrain's
fill tiles all say the same thing, accepted on every side, and there are usually a
dozen of them. Taken as they come, they filled the first two rows with what looked
like blank squares: the marks cover them completely and they are identical to each
other.

One real terrain has thirteen distinct declarations across twenty-one tiles. On that
sheet the centre polygon is **not drawn at all**. It is identical on every tile, so
it distinguishes none of them, and at thumbnail size on a vertex terrain it was the
only thing visible.

What differs from tile to tile is the sides, so only those are painted. They go
lighter, with a thinner outline than on the single tile. There the mark is the
subject and has a whole panel to itself; here there are dozens the size of a
fingernail, and the subject is the sheet.

**And it shows the gesture, not the result.** A tile's marks are not a property
anyone types. They are something you click on, and a still picture of the result
says that nowhere.

So the step is animated. The pointer moves in, clicks, and the wedge appears, one at
a time until the tile is done, with the mouse drawn. Match tiles and match vertices
work the same way: same lesson, different shape of mark. The tile already knows
which it has, so neither needs a diagram of its own when there is a real terrain to
read.

**The steps still do not move on their own.** What moves is inside one. A step you
are reading must not be taken away from you, and a gesture cannot be drawn standing
still.

#### Four traps, for whoever comes next

**The singleton is found by SCRIPT, not by name.** Since Godot 4.7.1 this kind of editor
autoload reaches the tree **unnamed** (`@Node@22384`), the same thing
`TerrainPlugin._autoload_is_loaded()` already tripped over. Looking it up by name
returns `null` every time and every example falls back to the schematic in silence,
which is exactly what looks like "working" until somebody checks. Writing `BetterTerrain`
is no good either: that name only exists where the plugin is running, and naming it would
stop the file compiling anywhere else. And the test for this has to add the node
**without renaming it**, giving it the name in the test reproduces a condition the
editor never has, and then the test passes while the window does not work.

**Reparenting a node that belongs to the packed scene corrupts the tree.** Put
`%TypeOption` inside a box without touching its owner and the tree is left
inconsistent. Godot says so out loud, "will make owner 'TerrainProperties'
inconsistent", every time the dialog opens. Which is every time a terrain is added.

The fix is to take the owner off for the move and give it back afterwards, with the
box inheriting the grid's owner.

That box has a second consequence, and it breaks the layout if you miss it.
`%TypeOption` loses two things. Its **index** in the grid, which is what positioned
the rows below it. And its **parent**: `%TypeOption.get_parent()` is now the box, so
every label and control added "to the grid" landed INSIDE the mode's own line.
`_type_cell()` and `_rows_grid()` give both back.

**A `RichTextLabel` with `fit_content` inside a `ScrollContainer` is a layout loop:** the
label grows to fit, the container grows to fit the label, and the frame never settles,
the window simply hangs. The `RichTextLabel` scrolls itself instead.

**A claim that did not survive contact with a bigger drawing.** The single-square
panel said "stretched over the run" for ANY role with more than one square. But
`tile_for` only stretches the four vertical ones: `IN_W`, `IN_E`, `OUT_W`, `OUT_E`.

On the minimal block the lie never showed, because no horizontal role there has more
than one square. On the 44-tile pond the north bank has four, and the panel asserted
of it the exact opposite of what the code does, and of what the screen next door was
showing. The message is split in two now and goes by role.

One API note: `get_tile_sources_in_terrain` returns the **source object and the
TileData**, not their ids.

### O. A new terrain type: `SCATTER` (a bag of tiles thrown over a region)

`BetterTerrain.gd` (the `TerrainType` enum, two early returns), `ScatterTerrain.gd`,
`ScatterLayer.gd`, `editor/ScatterBag.gd`, `editor/Dock.gd`, `editor/TileView.gd`,
`editor/TerrainProperties.gd`, `editor/TerrainEntry.gd`, `editor/ModeHelp.gd`,
`icons/Scatter.svg`, `tests/scatter.gd`

#### The problem

Weeds, pebbles, mushrooms, the odd flower. Things with no rules at all: they do not
match their neighbours, they do not tile, and the only question they answer is "how
often". Every mode in the addon before this one picks a tile by looking at what is
around it, which is exactly the wrong question here.

There is already a `DECORATION` type, and it is not this. It is a single reserved
pseudo-terrain, id -1, always last in the list, and `add_terrain` and `set_terrain`
refuse to make another. What it does is fill empty cells by matching their
neighbours, the same scoring as `MATCH_TILES` with the mismatch penalty at -2000
instead of -10 so it only lands where the neighbourhood really fits. The one thing
the two modes share is the machinery for a weighted pick with a chance of nothing:
`_weighted_selection` and `rng.seed = hash(coord)`.

#### What this type does

A scatter terrain is a **bag** of entries, each with a weight, plus the weight of
drawing **nothing**. You paint a **region** and every cell of it throws the bag once.

**Two scales, and they are not the same question.** Nothing is a PERCENTAGE: it
sets the density of the whole thing, and it has to still mean that tomorrow, when
the bag has two more things in it. The entries are RAW WEIGHTS against each other,
sharing out whatever is left: 4 and 1 is four times as much grass as rocks however
dense it is, and putting a third thing in does not force the other two to be
retyped.

Nothing was a raw weight like the entries at first, which is tidier and wrong:
"50" for nothing changes meaning on its own every time something goes into the
bag. Cidwel: "maybe nothing should be percentages instead of weights", which is
also how he asked for it on day one ("so that 90% of the time no tile gets painted,
and of the remaining 10%..."). Bags written before this have their old weight read as the share
it came to, so a region keeps the density it was given.

Two throws per cell, in this order: whether the cell gets anything, then which
thing. That is what keeps the density and the proportions independent.

#### Three decisions, and why

**The region lives on the painted layer as meta, not as tiles.** A cell that throws
"nothing" has to stay part of the region, or the weights could never be changed
afterwards: there would be nothing left to say that cell was ever painted. Writing a
marker tile instead would put art in the layer that nobody asked for. So
`_better_terrain_scatter` on the layer holds `{terrain id: PackedVector2Array}`, and
the map draws the region as an overlay while a scatter terrain is selected, because
otherwise you would be painting blind.

**The art goes to a generated child layer**, `ScatterDecor`, wiped and rewritten on
every rebuild. That is what lets a weight change repaint the whole region, which is
the "Live change" button. It is drawn in FRONT of its parent, unlike a cliff face:
decoration sits on the ground.

**The throw is seeded from the coordinate**, `hash(Vector3i(x, y, seed))`, so a saved
map comes back the way it was left and a rebuild is not a reshuffle. Reroll changes
the terrain's seed, and that is the only thing that moves it.

#### Pieces bigger than one cell

A bag entry can be a block: drag a box over the atlas and the whole box goes in as
one piece. A block goes down **whole or not at all**. Every one
of its cells has to be inside the region and not already taken, so a bush never comes
out sawn in half at the edge of what you painted.

Which means the reading order matters, because whether a 2x2 fits depends on what was
placed before it. The cells are sorted by row and then by column before the first
throw. Dictionary order is not a promise, and a region that came back different every
time it was rebuilt would be worse than one that is occasionally unlucky.

Where two regions overlap, the lower terrain id wins, for the same reason.

#### What painting had to give up

`set_cells` writes `cache[type].front()` into every cell it touches, and the solver
then refines it. Neither is any use here: the mode marks no tiles in the tileset, so
the cache is empty, and there is nothing to solve. The four tools (brush, line, box,
bucket) are routed away from both in `Dock._forward_canvas_gui_input`, and what they
edit is the region.

The undo of a stroke is **the cells that stroke actually added**, worked out before
the action runs. Snapshotting the whole region on every mouse move would copy a
10000-cell array sixty times a second and keep every copy in the history; and a
stroke that crosses its own trail would otherwise undo a hole in the middle of the
region.

Erasing asks the layer, not one terrain: the right button takes out whatever region
is under it, and its undo puts back exactly what it found, per terrain.

#### Keeping off the edge

Art drawn to the edge of its tile hangs over whatever the region ends against: a
tuft on the last cell of a meadow sits half on the shore. So the bag has a rim:
how many cells of the region's outline to leave empty.

In CELLS, though it was asked for in pixels ("how many pixels from the edge"). The
scatter decides cell by cell, so eight pixels of margin on a sixteen pixel grid
would be either no margin or a whole one, and a box saying "8 px" would be lying
about what it does.

A cell counts as inside when every cell within the rim's reach of it, diagonals
included, is also in the region. So a rim of 1 drops the outline, 2 drops the ring
behind it as well, and a region thinner than twice the rim keeps nothing, which is
the honest answer: it has no middle.

Blocks have to fit ENTIRELY inside what is left, not merely start there. A 2x2
placed one cell in would hang over the edge anyway, which is the thing the rim
exists to stop.

#### The editor

The bag is edited in a **column of its own**, between the terrain list and the atlas,
in view only while a scatter terrain is selected. The bag and atlas share an inner
splitter, while the outer splitter controls the terrain list. Putting all three
in the same splitter made showing the bag change the list's width (325 to 296
pixels in the reproduction), reflowing its icons on selection. The list also
reserves scrollbar space so changes in available height do not change its columns.

What it does not have is a line of prose summarising the numbers. It said what
share each thing took, and the column above it was already showing exactly that,
one weight per row; then it said how much of the region got painted, which is one
minus the percentage in the box below it. Both came out. A readout that restates
the control next to it is furniture.

It is not in the properties dialog, and that was a deliberate change of mind: Live
change takes effect as the numbers are typed, and a modal with an OK and a Cancel
promises the opposite. The dialog had a row saying so for a while, and that came out
too: a paragraph explaining where the real control is, read on the way to the OK
button, is worse than the column simply being there.

While a scatter terrain is selected the atlas answers to its bag and to nothing
else, before every other tool, so a click there cannot also mark a terrain type on
the tile. And the mode forces the Select tool on when it is picked, because the
marking tools would otherwise stay armed under a hidden button and write a type
nothing reads.

There was an "Add tiles" toggle arming that, and it came out: a scatter terrain
marks no tiles, so a click in the atlas has nothing else it could mean, and the
button was one more thing to press before anything happened, with nothing on screen
to say that it was what you had missed. Cidwel, having clicked tiles at an atlas
that was ignoring him: "well, I select them.. and no loose tiles go in".

#### Nothing is scattered onto a cliff face

A face is a WALL. Tufts, pebbles and flowers stand on ground, and a region painted
on a plateau runs on under the faces below it without anyone meaning it to: with
the bucket it is almost guaranteed, because the shape comes from the ground layer
and that ground carries on behind the rock.

Measured on one of Cidwel's scenes when he reported it: a zone of 338 cells with
269 of them over a face, and 49 of the 63 flowers planted on the rock. After the
rule: 14 flowers, none of them on it.

The face cells are collected from every `CliffFaces` layer in the family and
handed to the roll as ALREADY TAKEN, which is what they are. That way the same
line also stops a 2x2 block from reaching onto one, and costs a read of some used
cells per rebuild.

#### Painting a region that is already painted

It changes nothing about the zone, and it used to change nothing at all: the
stroke did nothing visible, which from the outside is exactly what a broken mode
looks like. And it is easy to get into: paint the region first, fill the bag
afterwards, and the art is empty until something rebuilds it. Cidwel, painting
flowers over a region he had already painted: "when I paint, it paints nothing".

Painting it again REGENERATES it now. That is the useful reading of painting
something twice, and the only one that leaves the art agreeing with the bag.

#### The limits, stated

With Live change off, the weights are stored and the region is left alone, but the
next rebuild of that layer uses them: painting one more cell anywhere repaints the
lot. That is the price of a layer that is regenerated rather than patched, and Apply
is there to do it on purpose.

The config lives on the tileset, so a region painted on another layer keeps its old
art until that layer is rebuilt. Live change and Apply work on the layer you have
selected.

### O2. The oven: baking an object's second block

`ObjectBake.gd`, `editor/ObjectOven.gd`, `editor/Dock.gd`, `tests/object_bake.gd`

An object needs two drawings and the second is the expensive one. It is also not
new information: it is what the first looks like stacked against itself. So the
Bake button beside Lone and Joined stacks it and cuts out the piece that repeats.

**A measurement that was too kind, and the correction.** The first claim here was
that an overlapping lattice reproduces a hand-drawn joined block with "every
opaque pixel in the same place". That metric was worthless: a joined block is
opaque everywhere, so any lattice dense enough scores 100% on it. The number that
meant something was the colour, 15 to 21 per pixel, and that is not "the same
picture": put side by side, the baked bush had trunks running through the middle
of the mass and the hand-drawn one did not.

What was missing was not a lattice at all. **A tree is two things in one picture**:
a canopy, which is what a wood is made of, and a trunk, which is what stands on
the ground. Stack the whole drawing and the trunks stack too. Stack only the top
of it and they do not. Measured on the demo bush, against the block the artist
drew: the whole 32 pixel drawing lands 20.5 per pixel away, its top 20 pixels land
**6.3**, a 2.5% difference on a 255 scale. The pitch that wins is the same one in
both cases, 16 with the odd rows shifted 16.

So the window has three knobs and they are three different questions: what gets
stacked (the top N pixels), where the cut falls (the offset), and how much the
copies overlap (how many fit in the piece).

#### The two cards say which art they are for

They were named after what they do to the art: `Objects` places one by one on a
grid, `Area` plants each one where its feet land. Both correct, and both answering
a question nobody has. What anyone has in front of them is a drawing and the
question "which of these two is mine", and an afternoon went into finding out the
hard way that a 2x2 tree is one and a 2x4 tree is the other. Cidwel: "why does it
work with the 2x2 tree and not with this 2x4 one... it's supposed to be the same,
right?".

So each card now carries the answer as well as the description: art that fits the
grid (a 2x2 tree, a rock) against tall art, which no grid fits. And when the
drawing IS tall and the card is Objects, the status line says what will happen:
placed one by one it can only step its own height at a time, so it tiles into
bands and the wood has no edge.

The other half of it: **an area no longer asks for a second drawing.** Its second
block goes under the trees and is never seen, and now that the oven exists it is
baked rather than drawn. The status says so and points at the button. The bake is
NOT done silently when the card is picked: a source appearing in the tileset
because someone clicked a picture is the kind of magic that cannot be traced back
afterwards.

#### The bucket on empty space

A flood over empty cells has nothing to stop it, so upstream bounds the bucket by
the layer's used rect. Which means it does nothing at all outside what is already
painted, and that is exactly where anyone reaches for it: Cidwel, of the
single-tile brush, "the bucket still doesn't work".

It is bounded by what is ON SCREEN now, merged with what is painted. Finite, and
it is what "fill this" means when you are looking at it. Capped at 20000 cells as
well, because a view zoomed far out is a lot of them. The view is measured in
`canvas_draw`, which is the one place that has the overlay and the transform in
hand.

This changes the bucket for every mode, not just the brush. It only ever adds
cells to a fill that would have done nothing.

#### The brush shows the tile, not a colour

Every other mode draws its hover as a wash of the terrain's colour, because that
is all it knows: which tile lands on a cell is decided by the neighbours, at paint
time. The single-tile brush knows exactly what it is about to put down, so it
draws THAT, ghosted at 70%, which is the whole point of the mode: you picked a
tile, you want to see the tile. With a group, the whole group.

Drawn through the canvas transform (`draw_set_transform_matrix`) rather than by
transforming a rect, so it follows the view at any zoom and on any grid shape
without a second code path. It falls back to the colour wash when the tile cannot
be drawn, and erasing keeps the red wash: a ghost of what you are about to remove
would say the opposite of what is happening.

#### Two buckets, and the one that goes by sight is the default

The question turns up the moment there is more than one layer: you look at a map
and see a PICTURE, not a stack, and the region you mean is the one you can see.
Cidwel, filling a mountain that has a patch of dirt painted over part of it on the
layer above: "I want flowers painted on all those tiles, but I don't want them
to touch the ground tiles at 8,21".

So two buttons beside the bucket, shown only while it is the chosen tool:

**What you see.** Two cells belong to the same region when the same layer is
showing at both and it holds the same terrain (or the same tile, where there is
none). A patch painted above breaks the ground below it in two, and the fill stops
at it.

**This layer.** The region on the layer being edited, ignoring what any other has
there, which is where the shape-from-below rule above still applies.

Measured on 06_Exemplar, bucket at (5,22) of Ground2, which is empty there while
Ground below it is mountain and a patch of `som_dirt` sits at (8,21):

| | cells | takes the dirt? |
|---|---|---|
| what you see | 109 | no |
| this layer | 213 | yes |

By sight is the default: it is what the screen was already telling you. Asked of
the OTHER button, though: by sight unless someone has said this layer. A pair of
toggles can end up with neither of them down, and the answer to that has to be
the default rather than the odd one out.

Icons, not words. They sit in a row of icons, and a button with a sentence on it
in the middle of that reads as a different kind of thing; what they say is in the
tooltip. Cidwel: "I need icons, not text, maybe with a tooltip if anything".

#### The shape can come from the layer below

An upper layer is usually empty where you want to fill: you are painting detail
ON something. The bucket saw an empty cell and could only offer "everything empty
in view", which is not a shape.

So when the cell under the cursor is empty on the layer being edited, the shape
comes from the nearest sibling drawn UNDER it that has a tile there, and the cells
are painted on the layer you are editing. Cidwel: "if I use the bucket at 25,25 on
Ground2, it should be able to pick the tile group from the neighbouring tileset
Ground... it's the visible tile that matches the center of mountain". Measured on that exact scene
and cell: the layer below is `Ground`, the terrain there is `mountain`, and the
region is 191 cells from (17,18) to (49,32).

Siblings only, and only the ones before it, which is what "under" means in a
scene. Hidden ones do not count, because the point is what you can SEE. The
generated children (faces, edges, scattered decoration) are not offered either:
they belong to their own layer and are not somewhere anyone paints.

#### And what the bucket is allowed to run over

By terrain where there is one, which is what a terrain is for: a shore tile and a
middle tile of the same water are one region, and that is how it always worked.

But `get_cell` says `NON_TERRAIN` for every unmarked tile, so a fill starting on
one of those believed the whole map was its region and ran over every loose tile
on it. Those now go by THE TILE ITSELF. Cidwel: "shouldn't it try to limit itself to
the group of tiles similar to the selected tile? So I can paint sectors".

The single-tile brush keeps going by terrain and not by tile, because its own id
covers the whole of a group it painted: matching tile by tile would fill every
other cell of a 2x2 pattern and leave the rest.

The decision lives in `BetterTerrain.same_fill_region` rather than in the dock,
which is what makes it testable at all: `Dock.gd` names the autoload and cannot be
loaded headless.

#### The picture has a wheel and a hand

A `TextureRect` can fit or fill, and pixel art wants a whole number: a 2x4 object
tiled three by three is 96x192, and "fit" drew that at 1:1 in a corner of a panel
five times its size. Cidwel: "look how small that is".

So the preview is its own control. Wheel zooms on the cursor, whole steps only,
and a drag moves it. It frames itself on every resize UNTIL the user takes over,
and then leaves the view where they put it; a picture of another size is another
picture and gets framed afresh.

The bug worth remembering: fitting once on the way in put the picture off screen
and left the panel black. A window that has not been laid out yet reports whatever
size it was built with, so the fitting has to happen on the resize, not on the
build.

#### The window shows what gets painted, not what gets written

An object painted as an AREA does not put the piece on the map. It writes the
piece into the painted cells and then stamps whole drawings over it on child
layers, and the trees cover all of it: measured when the area mode was written,
418 and 306 painted cells and not one left showing. So a window that showed the
piece on its own was showing the one half you never see, and Cidwel, quite
reasonably: "why does it look wrong when I see it in the baker... and when I place
the trees on the map they look perfect. Something is off in your viewer there".

Nothing failed. It was the wrong half. For a mass the preview now stamps the
drawings over the piece the same way `fix_mass` does, which is what will be on the
map; for an object it stays the piece tiled, which is also what will be on the map.

One detail that bites: the stamps here are **not** wrapped, unlike everywhere else
in this file. On a map the rows carry on past what you are looking at, and a
wrapped stamp lands above the row it should be in front of and puts its trunk
through a canopy. The preview is stamped on a bigger sheet and cropped.

#### The gaps are closed by the neighbours, not by more drawing

Stacking leaves the piece open wherever the drawing is narrow: the rounded top of
a canopy covers nothing at its sides, and what shows through there is the drawing
BEHIND it, which is its own shaded underside. That is the dark seam between rows,
and it is the whole difference between a baked block and a drawn one. Measured on
the bush against the block the artist drew: 108 pixels of 1024 differ, every one
of them in that band, and all of them darker than his.

He did not paint the underside there. He painted more leaves, as if the canopies
below reached up. So the oven does the same with the pixels it has: after
stacking, whatever is still transparent takes the colour of its neighbours,
looking DOWN first and then sideways, which is a canopy growing upwards rather
than a smear. It only ever touches transparent pixels, so a lattice that already
covers the piece comes out untouched. On the bush that goes from 6.3 per pixel at
its best to **4.0**.

**It opens on the mosaic**, not on a blank setting: rows half a drawing apart,
every other row shifted half a drawing, and the crop chosen from two facts about
the art. Never past where the drawing stops being a mass (the silhouette narrows,
and below that is a trunk); and within what is left, the crop that leaves the
**least shadow** in the piece, because what lives below the visible band is the
shaded underside and less of it in the gaps is closer to what a person draws. The
floor is the pitch itself. On the three hand-drawn blocks in the demo tileset it
picks 16, 20 and 18 of 32, scoring 4.1, 4.4 and 3.6, against best-possible picks
of 16, 18 and 18 scoring 4.1, 4.0 and 3.6.

Four defaults were written and thrown away before that one. "Where the silhouette
gets narrow", on its own, fails on a bush standing on three fat roots. "Where the
ink falls off a cliff" fails on the same bush, whose ink never drops below 19 of
32 on any row. Five eighths of the height left forty transparent pixels in the
piece. And "the least crop that leaves no holes" closed them with the drawing's
own shaded underside, which is what put the dark seam there: it came out at 24 of
32, and Cidwel, looking at it in the window: "this is what I get by default on tree1.
Do you think this is what I want?".

The lesson, written down because it cost five tries: the crop is not a fact about
where the trunk is. It is how much of each drawing shows before the row below
covers it, and what to do with the rest is a question about the GAPS, not about
the drawing.

The offset is its own knob, and confusing it with the pitch is what made the first
window useless for the job it was asked for. Cidwel asked for an offset on day one
("the idea is that you set the offset on it") and got an overlap instead; with the
pitch at the drawing's own size there is exactly one stamp and the result is the
drawing again, so nothing he did produced a mosaic. Pitch decides how much the
copies overlap. Offset decides where the piece is cut out of the arrangement, and
on its own it is the classic way of making a motif tile: shift by half and the
drawing's four edges meet in the middle, where they can be judged.

The other thing the measurement killed. The joined block of an object is
NOT the drawing stamped at its own size: at that pitch the copies touch and never
overlap, one stamp lands, and the result is the lone drawing again (25 to 108 per
pixel away from the hand-drawn joined one). What makes a joined block joined is
that the neighbours PISAN, and the good pitches turn out to be well under the
drawing: 16 and 21 and 10 pixels against drawings 32 and 64 tall.

#### The window

Two numbers, a checkbox and a picture: how many copies fit across the piece, how
many down, whether the odd rows are shifted half a drawing. The picture is the
arrangement, three by three, with the piece that gets cut marked in red, which is
the drawing Cidwel sent when he asked for it.

**The piece is always the drawing's own size.** The first version let you set it in
cells and set the pitch in pixels, and he threw it out on sight: "I don't think that
editor is right. It makes no sense. Let's reduce the complexity, and for now only
allow creating mosaics that match the same size as the tile". He was
right, and fixing the piece is what collapses the rest. The pitch stops being a
free number and becomes a whole fraction of the piece, so every setting repeats
itself and there is nothing left to warn about. A count that does not divide the
piece exactly is snapped to the nearest one that does, and the box shows what it
got: three copies of a 32 pixel drawing would be a pitch of 10.67, and integer
pixels then space them 10, 10, 12.

The cost, stated: a lattice that is not a whole fraction can no longer be asked
for. The wood of `mass.tres` matched its hand-drawn block best at 21 pixels, and 21
is not a fraction of 64, so the window offers 32 or 16 instead. The oven underneath
still takes any pitch and any piece size; none of it is on screen, because a piece
of another size drags the object's size along with it, and that is a second thing
to understand before the first one works.

#### What baking writes

One source of its own, holding BOTH blocks side by side: the drawing re-boxed into
the new size on the left, the baked inside on the right. In one source because the
object's configuration stores the lone block's coordinate and not its source, so a
pair split between two sources could not say which was which; and `detect_blocks`
already cuts a 4x3 group into two 2x3 blocks, because that is how the pair is drawn
by hand.

Re-boxing is what would make a piece of another size free, and it is written and
tested even though the window does not offer it yet. If the piece that tiles is taller than
the drawing, the OBJECT becomes that size and both its blocks are that shape again,
so the placement arithmetic never learns anything happened. No second period, no
`posmod` with two sizes.

**Every tile the terrain was marked on is cleared**, not just the lone block. A
tileset whose object was drawn by hand has the joined one marked too, and leaving
it gives the detector three blocks where it wants two: the object stops resolving
and nothing says why. The list is taken before the bake and handed to both halves
of the undo, so stepping back puts every mark exactly where it was.

The pixels live in the tileset resource: an `ImageTexture` is written into the
`.tres` whole and comes back with its content, which a `PortableCompressedTexture2D`
does not (it saves, and reloads 0x0). No file to import, nothing to lose track of,
at the price of a sheet nobody can open in Aseprite. Export PNG is there for that.

### P. The atlas draws what you can see

`editor/TileView.gd` (`_seen_window`, `_visible_window`, `_watch_scroll`, `_draw`)

Panning around a big tileset felt slow, and it was: **14 frames a second, with
nobody touching anything.**

`_draw` walked every tile of every source and emitted its commands into ONE canvas
item. Godot culls per canvas item, not per command, so nothing was culled: the
renderer walked ten thousand tiles worth of commands on every frame, whether the
atlas was showing two hundred of them or all of them. Measured on the demo
tilesets, idle:

| tiles | frame | one redraw |
|---|---|---|
| 77 | 12.9 ms | 3.9 ms |
| 9144 | 59.2 ms | 152.0 ms |
| 10398 | 70.8 ms | 178.8 ms |

Two changes, and the second is the one that is easy to get wrong.

**Skip what is outside the window.** The tile loop and the blank-out grid walk
(which on a 1408x1104 atlas of 16px tiles is 6072 cells of its own, every redraw)
both take a visible rect and leave early. A source whose whole band is off screen
is never asked for a single tile.

**Draw a margin, and redraw only when the view leaves it.** Scrolling now has a
reason to redraw, which it did not have before, and redrawing on every scroll step
costs 20 ms a frame. It does not have to: the window is in the control's own
coordinates and the control moves with the view, so tiles drawn a moment ago are
still in the right place. 64 pixels of margin, and the redraw comes once per
crossing.

The margin was picked by measuring, panning at 15 pixels a frame on the 10398 tile
atlas:

| margin | idle | panning | redraws in 60 frames |
|---|---|---|---|
| 64 | 15.9 ms | 18.8 ms | 10 |
| 128 | 17.1 ms | 20.2 ms | 5 |
| 256 | 20.6 ms | 26.3 ms | 2 |

Past 64 the drawn set gets big enough to cost more on every frame than the redraws
it saves. With a terrain selected, which is how anyone actually works, the same
atlas now pans at 13.3 ms a frame: the screen refresh, not the addon.

What is still on the list: `_draw_exemplar_outline` walks the whole source to find
the marked tiles, about 5 ms per redraw while an exemplar terrain is selected, and
the walk over every tile to test its rect is 3 ms of the redraw. Both are now small
against a redraw that only happens when you cross the margin.

### Q. The single-tile brush: one tile, no rules, no terrain

`BetterTerrain.gd` (the enum, `single_tile_of`, `set_cell`, `set_cells`,
`get_cell`, two early returns), `editor/Dock.gd`, `editor/TileView.gd`,
`editor/TerrainProperties.gd`, `editor/TerrainEntry.gd`, `editor/ModeHelp.gd`,
`icons/SingleTile.svg`, `tests/single_tile.gd`

Not everything on a map is terrain. A signpost, a doorway, one rock exactly there.
Godot's own TileMap editor paints those, and switching tools to place one thing
loses the terrain you had selected and the shape you were working on.

So: pick the brush, click a tile in the atlas, paint. There is nothing else.

**It is a reserved entry, not a type anyone creates**, and that was the second
try. The first made it a terrain type like the others, which meant naming a
terrain and choosing a mode for it before you could put one tile down, and two of
them would each want their own name and their own place in the list. Cidwel:
"I want you to create a special terrain type like the Decoration one, one with no
terrain". Both reserved entries appear at the beginning of the list, Decoration
first and Single tile second, before custom terrains and group headers. Each is
one per tileset, never created, never renamed, never deleted. Its id is
`TileCategory.SINGLE`, -4, next to the decoration's -1, and like the decoration it
lives in its own key of the tileset's meta rather than in the terrains array.

The type enum keeps `SINGLE` because that is what the entry is made of, and the
engine paths key off it; the properties dropdown does not offer it.

**No tile is marked.** Marking writes the terrain onto the tile's meta, and a tile
can only belong to one, so a mode whose whole point is "paint me the tile I am
pointing at" would quietly steal it from whatever terrain already had it. The
terrain remembers the tile instead, in the same seventh-element dictionary the
other fork types use, and the atlas outlines it.

Which costs two small things, both paid in the engine rather than in the editor:

**A group is laid WHOLE.** The first version laid it as a repeat anchored to the
map origin, which meant painting a cell of a 2x2 group put one quarter of it down
and you had to paint the other three to see the thing. Cidwel: "when I paint a
group, I want to be able to paint that group, not individual tiles until the
group is complete".

So each painted cell drags in the rest of its block, snapped to the grid the
ANCHOR sets, and the anchor is the cell the stroke started on. One click lays one
whole group; a drag lays whole groups beside it rather than halves; and every tool
gets the same treatment, the bucket counting from the cell you clicked.

That anchor is why `set_cell`, `set_cells`, `replace_cell` and `replace_cells`
grew a fourth argument. It defaults to the map origin and every other mode ignores
it.

**Painting** cannot go through the cache, because the cache is built from marked
tiles and this mode has none: `set_cell` and `set_cells` would fail the
empty-cache test and paint nothing. They check for a single tile first.

**Reading a cell back** cannot go through the tile's meta either. `get_cell` falls
back to asking whether the brush paints that exact tile, which is what the
bucket and the picker need to recognise what is under them. Only reached for tiles
nothing else claims, and only walked over the single terrains.

**"Nothing chosen" is not "id below zero", and the dock said it was in several
places.** Two of them turned the brush off: one refused the stroke before it
started, the other refused the hover, so nothing appeared under the cursor either.
From the outside both read as "the brush does nothing", which is why the first fix
looked like no fix at all. Cidwel, twice: "I select single tile... and I don't see the
tile", and then "the tile to paint doesn't show up on the map".

The other guards of that shape are right to keep it out, because they are about
editing a terrain and this is not one: rename, move, delete, pick an icon, open
the cliff window. So the test counts both kinds, the two that let it through and
the four that do not.

The same shape of hole in the engine: `replace_cell` and `replace_cells` went
straight to the cache with the brush's negative id. For this mode "replace" can
only mean one thing, since there is no peering to match against: put the tile
where a tile already is, and leave the empty cells empty.

The atlas picking is the same machinery the scatter bag uses, renamed to say so:
`pick_tiles`, `tile_picked`, `marked_blocks`. Two modes now take the atlas over
while they are selected, neither of them marks anything, and in both a click there
has nothing else it could mean.

## Taking the cliff generator into your own project

The face generator **asks nothing** of the project that hosts it: not a property,
not a script, not a class, not that it be C#. Everything it needs, it makes.

A ground layer joins the system the moment it paints a terrain that has a cliff
sheet. The generator hangs a `CliffFaces` child off it with its own script.

That one node does three jobs. It is the marker. It is where the level and the
height are kept. And it is where the cells are written.

A layer's position among the ones that have such a child is its level. Checked from
scratch with four bare `TileMapLayer` nodes.

It used to require a `cliffLevel` property on the project's layers, and that was
taken out: a layer that **has** the face is the one that can describe it, and with
that the contract stops existing.

The only rule left is structural: elevation layers have to be **siblings** of each
other, because the level counter walks `get_parent().get_children()`.

**The configuration travels with the TileSet.** It lives in the resource's own
`_better_terrain_cliffs` meta, so handing over the `.tres` hands over the
configured cliffs. There is no separate file to keep in step.

**The only thing the addon points at outside itself** is the preview shapes scene,
and that degrades on its own: if it does not exist, `shapes()` falls back to the
built-in fixtures. Whoever installs this can create that scene or not.

**What does NOT come with it**, worth knowing before copying the folder:

- **Navigation.** Making generated faces block for your own pathfinding is your
  project's job, see the note in section J. Without it the faces still collide for
  the player, because the polygon is in the tile, but anything that builds its own
  walkability from a list of layers will walk straight through them. A project
  with no such system needs nothing.
- **The z band.** `LEVEL_Z_BASE = 0` and `LEVEL_Z_STRIDE = 2` are one project's
  convention. A different layout of z is those two numbers, in `CliffTerrain.gd`.

## Giving something back upstream

Sections A and E are generic and depend on nothing in particular: they would work
as pull requests as they stand, and A closes an issue upstream already has open.
Anything they take is one thing fewer to reconcile here forever.


### Explicit Area objects in the editor

The editor places complete objects, snapped to a grid of their configured base
size, with alternating rows shifted half a base width to preserve the staggered
forest pattern. Pencil, line, rectangle and bucket strokes submit those bases directly;
the region fill solver does not decide how many trees a click creates. Existing
objects keep their origins, and new bases cannot overlap them.

`_better_terrain_mass_placements` stores the origins, configuration, base cells
and an `explicit` flag. On an edited terrain, cells outside the retained object
bases are removed, including invisible markers left by older versions. Markers
may still represent a base under generated artwork; they cannot represent an
unplaced tree waiting for a later stroke. The generic region fill API and the
properties preview retain the lattice solver for generating an initial forest.

The eraser finds the visible tree under the cursor and removes its complete base,
including when the cursor is over its crown. Rebuilding explicit placements never
adds replacements. Undo snapshots include the original layer cells and placement
metadata so that converting an old region remains reversible.

### Local erasing of explicit objects

Once a placement state stores its marker tile, erasing touches only the drawings
of the removed objects. Surviving trees whose drawings intersect that region are
composited again, clipped to the affected cells. Other generated cells are left
alone. The undo snapshot captures the affected cells and placement metadata;
undo may still use a full rebuild to reconstruct generated layers.

Old placement states without marker metadata use the full path once. Mixed
terrain operations also retain the full path. Erasing only explicit objects
skips Patch rebuilding, and erasing already empty cells skips post-processing.

### R. The tile picker

`editor/Dock.gd` (`_add_picker_button`, `_is_pick_click`, `_pick_at`).

A picker (eyedropper) button sits first in the per-type tool box, in the same
group as Draw, Line, Rectangle and Fill, with `I` as its shortcut. One click on
the map picks, and then the previous tool comes back. What it picks depends on the
brush:

- a cell that belongs to a terrain (or is marked as decoration) selects that
  entry, whatever brush is on, so picking grass from the single-tile brush
  switches to the grass terrain;
- a plain tile, with no terrain, switches to the single-tile brush and takes that
  exact tile (source, atlas coordinates and alternative), as if it had been
  clicked in the atlas;
  if the tile sits inside a whole block painted with a multi-tile favourite
  (or the current brush), the whole block is taken instead of the one tile;
- an empty cell picks nothing.

If the current layer is empty there, it reads the topmost visible layer that uses
the same tileset. A right click with the picker armed does nothing, so it cannot
erase by accident. While a pick is armed the brush preview is not drawn on the
map, because the click will not paint.

While the picker is on, or its modifier is held, a "Select Layer" checkbox shows
right after the picker button (`editors/better_terrain/picker_select_layer`, off
by default). With it ticked, a pick (by the button or by the modifier) reads the
topmost visible TileMapLayer of the edited scene at that point, whatever its
tileset, and selects that layer in the scene tree, so painting carries on where
the tile came from. "Topmost" follows drawing order: effective `z_index` first,
tree order after. A generated support layer (cliff faces, scatter decor, mass
layers) answers for the layer that owns it, and layers inside instanced scenes
are skipped because they cannot be selected. The pick runs deferred after the
selection, because the dock may have to switch tileset and rebuild its terrain
list first.

Holding a modifier turns a left click into a pick with any tool. The default is
Alt, and Options can change it to Shift (`editors/better_terrain/picker_modifier`).
This replaces the old fixed Ctrl+click, which now paints like a plain click. With
Shift, Shift+click with Draw picks instead of drawing a line (the Line tool still
draws lines), and Ctrl+Shift is still the draw tool's rectangle.

While a pick is armed (the picker tool is on, or its modifier is held) and the
mouse is over the 2D viewport, the cursor becomes an eyedropper
(`TerrainPlugin._process`, `Dock.picker_cursor`). Godot has no such cursor
shape, so it is an SVG in the script, rasterised at the editor scale, with its
hotspot on the tip. It goes through `DisplayServer.cursor_set_custom_image`,
because `Input.set_custom_mouse_cursor` returns early when it runs in the editor.
While armed it replaces every cursor shape, because the 2D editor picks arrow,
move, cross or drag by its own tool; they are all put back as soon as it is not.
Holding the modifier also turns the picker button's icon blue, so the key visibly does something even
before the mouse reaches the map.

### Q2. Blocks with gaps, and blocks that leave their atlas

`editor/TileView.gd` (`_pick_target`, `_trim_to_tiles`),
`BetterTerrain.gd` (`_set_single_cell`), `editor/Dock.gd` (`_painted_block_at`).

A block dragged in the atlas can cover cells that hold no tile: a gap in the
sheet, or the body of a bigger tile. Painting those used to write the empty atlas
coordinate and the map showed an unknown tile. Now such cells are skipped when
painting, and the dragged rectangle is trimmed to the rows and columns that hold
tiles before it becomes the brush (or a scatter entry). The picker and the
single-tile eraser recognise a painted block with gaps, since the gaps were never
painted.

A drag can start or end on an atlas cell that holds no tile (the empty corners
around a rounded drawing); only the cells with tiles end up in the block.

A block belongs to one atlas source. Dragging out of it (onto another source, or
onto empty space) used to collapse the pick to the first tile; now it keeps the
last corner reached inside the source the drag started in.

### S. TileMap nodes are refused, with a way out

`TerrainPlugin.gd` (`_handles`, `_edit`), `editor/Dock.gd` (`show_unsupported`).

The plugin works on `TileMapLayer`, one layer per node, everywhere: painting,
solving, cliffs, support layers, the picker. The deprecated `TileMap` node packs
several layers behind an index API, so supporting it would mean a second path
through all of that for a node Godot itself is phasing out. Instead, selecting a
`TileMap` shows a warning toast and covers the dock with a notice saying it is
not supported, and pointing at Godot's own converter (TileMap bottom panel,
toolbox icon, "Extract TileMap layers as individual TileMapLayer nodes"). The
native TileMap panel keeps working, so the conversion is one click away.

### T. Generated layers: locked by default, the user's once unlocked

`SupportLayers.gd` (`prepare`, `is_locked`, `is_frozen`, `unlock`),
`editor/Dock.gd` (`_ask_unlock`, `_unlock_support`).

The support layers (`_CliffFaces`, `_ScatterDecor`, `_ExemplarEdges`, `_MassN`)
are written by generators, so they start locked. The lock is set once, when the
layer is created or first seen (a `_better_terrain_support` meta marks that);
after that it belongs to the user, and unlocking one in the Scene tree sticks.

They can always be selected and inspected. Clicking to paint on a locked one
opens a dialog that says which generator owns it and what unlocking costs, with
"Unlock and edit" and Cancel; unlocking is undoable. While a support layer is
unlocked the generators leave it alone: the cliff and scatter rebuilds return
early (with `frozen` in their report), Patch edges are not rewritten, and a
frozen mass layer is neither cleared nor written. Locking it again (from the
Scene tree, or by undoing the unlock) hands it back and regenerates it on the
spot, discarding the hand edits: `editor/SupportLayerEditor.gd` listens to the 2D
editor's `item_lock_status_changed`, remembers which support layers were frozen,
and rebuilds the owner of any that comes back locked (`_regenerate`). That
rebuild is not in the undo history, so undoing the lock afterwards unlocks the
layer but does not bring the hand edits back. The canvas status line says which of the two states the layer is in.

### U. Quick terrains from a single-tile selection

`editor/Dock.gd` (`_build_quick_terrain_buttons`, `_quick_refusal`,
`_create_quick_terrain`, `perform_quick_terrain`, `_nine_slice_table`,
`_object_halves`).

With the single-tile brush on, four buttons sit after the pin: Create quick
terrain, Create Patch, Create Object and Create Scatter. Each makes a terrain of
that type from the selected block, named after the atlas texture, in the group
being shown, and selects it. They are always there in single-tile mode; a button
is disabled, with the reason in its tooltip, when the selection cannot make that
type:

- **Quick terrain** (Match tiles): any block of two tiles or more, square tiles
  only; each tile only needs a neighbour to join, so a 3×2 strip or a 1×3 path
  works as well as a 3×3.
  Gaps are allowed and read as outside the block, so a rounded drawing (a pond
  with empty corners) works. Every tile joins, in its side peering bits, the neighbours that
  are inside the block, so the block reads as a 9-slice: corners join inwards,
  edges along and inwards, the middle on its four sides. The corner bits stay
  unset, as a hand-made 9-slice has them; marking the diagonals too filled the
  whole interior.
- **Patch**: a block of 5×5 or more, read the way the Patch editor reads a
  drawing, like a pond: the outer ring is the bank drawn around the painted
  shape (`OUT_*`, and `CORNER_*` where the corners have ink), the inside is the
  water and its rim (`IN_*`). That is the structure of the demo's `lake`; the
  8×6 lake block, run through this button, gives the same table role for role.
  The minimum is what leaves 3×3 of water, so every inner rim role exists.
  Empty cells in the block (the corners around a rounded drawing) are first made
  into atlas tiles, so the whole rectangle is the drawing; transparent ones are
  then dropped by the reading, as the lake's are. Undo removes those tiles again.
  It is refused only when a gap is part of a bigger tile, or the brush is an
  alternative tile. (An earlier version read the block as a 9-slice with no
  bank; that was not what a Patch is for.)
- **Object**: the whole selection is the drawing, at its size (a 2×8 tree
  makes a 2×8 object), with empty cells made into tiles first, as for a Patch.
  An earlier version split the selection into two halves, a lone and a joined
  block; that turned one tall tree into two short objects. An object with only
  one drawing now works (`ObjectTerrain.get_objects` uses it as its own joined
  block, so each object is drawn whole); mark a joined block later with the
  Joined button to let neighbours fuse.
  The same holds for an Area (mass) object: `is_mass` used to require two blocks,
  so an Area with only the tree fell back to a plain object and a stroke placed
  one tree per 2×4 slot. Now the tree alone is enough, its own tile marks the
  region (with the invisible marker), and Bake is an optional improvement.
- **Scatter**: any selection; every tile goes in the bag.

Before creating a Match tiles, Patch or Object terrain, the selected tiles are
checked: if any already belongs to a terrain (or is marked as Decoration),
nothing is created and a dialog names the terrains they belong to, since a tile
can be part of one terrain only. A Scatter only lists tiles in its bag, so it
takes any.

The whole creation is one undo step; undo puts back the terrain list, the
tiles' terrain metadata and the Patch tables as they were.

### V. Shift in the middle of a pencil stroke

`editor/Dock.gd` (`canvas_input`).

Shift held when the pencil stroke starts has always drawn a line. Now pressing
it during a freehand stroke does too: the part painted so far stays, and from
where the pencil was when Shift went down the rest becomes a straight line to
the cursor, previewed while dragging and drawn on release. Because it switches
on a motion event and not on the press, it also works when Shift is the
picker's modifier, which only acts on the press. While a stroke is in progress the modifier does not arm
the picker at all (no eyedropper cursor, no blue icon, the line preview stays).

### W. Pattern cliffs: clicking the wall arms its piece, even on an empty sheet

`editor/CliffEditor.gd` (`_pattern_pick_config`).

In Pattern mode, clicking a wall cell in the preview arms the piece that draws
it, and the palette then fills that piece. But which piece a cell belongs to
depends on the pieces' sizes (`CliffPattern.bands_at`), a piece with no tiles
has no size, and with no body at all nothing maps anywhere: on an empty sheet
the wall could not be clicked, which is exactly when it is needed. For clicking
only, a piece without tiles counts as one tile, so the top row arms TOP and its
corners, the sides LEFT and RIGHT, the bottom row BOTTOM, a lone column the
tower pieces, and the rest BODY. The preview is still drawn from the real sheet.

The same trap was in the drawing. `bands_at` returned nothing while the body was
empty, so pieces filled before it (corners, bottom, the tower's top and foot)
were not drawn in the preview or on the map. It no longer needs the body: the
filled pieces draw, and cells only the body could draw stay empty. And a corner
filled without its side or its top/bottom row still makes that end column one
tile wide and gives it that row (`_end_width`, `_corner_used`); before, a corner
never showed until LEFT or RIGHT, and TOP or BOTTOM, had tiles too.

### X. Preview shapes: the project's, then the built-in ones it does not redraw

`CliffData.gd` (`shapes`, `FIXTURES`).

The cliff editor's preview shapes come from the project's shapes scene
(`better_terrain/cliff/shapes_scene`, else `res://cliff_preview_shapes.tscn`),
one TileMapLayer per shape. When that scene did not exist the built-in
`FIXTURES` were used, but as soon as one shape was saved the scene existed with
that one layer and every other built-in shape vanished from the list. Now the
list is the project's shapes followed by the built-in ones it does not redraw; a
project layer still replaces the built-in shape of the same name. The built-in
"Compact" is the one drawn in the demo project. The preview is shared by the
Simple, Advanced and Pattern modes.

### Y. Scatter's Live change without the stutter

`ScatterTerrain.gd` (`_scatter_one`, `set_config`), `editor/Dock.gd`
(`_on_scatter_config_changed`, `_queue_scatter_rebuild`).

Dragging a weight sent dozens of edits a second and each one rebuilt every
region (about 125 ms on a 150×150 region) and emitted `TileSet.changed`, which
makes every layer on that TileSet reprocess all its cells (another ~80 ms). Twenty
ticks froze the editor for almost three seconds. Now an edit only stores the
config; the TileSet is told once and, with Live change on, the regions are
repainted once, 150 ms after the last edit. The undo step keeps the value from
before the first edit and the last one (`MERGE_ENDS`) instead of every tick. The
rebuild itself is about twice as fast: the placement order is sorted as packed
integers by the native sort instead of a scripted comparison, and one-tile pieces
skip the block bookkeeping. The painted result is the same.

### Z. Must-not-match peering

`BetterTerrain.gd` (`_get_cache`, `_update_tile_tiles`, `_update_tile_vertices`,
`add_tile_not_peering_type`), `editor/TileView.gd`, `editor/TerrainUndo.gd`.

Ported from [BetterTerrain PR #144](https://github.com/Portponky/better-terrain/pull/144)
by bitbutter. A side of a tile can forbid terrains as well as require them. It is
not a new terrain type. Match Tiles is tested; Match Vertices scores it the same
way but has no test. The
forbidden types sit in the tile metadata under `"not"`, a dictionary from side to
types, so tilesets made on the PR branch load unchanged. The API mirrors the
existing calls: `add_tile_not_peering_type`, `remove_tile_not_peering_type` and
`tile_not_peering_types`. A type can't be required and forbidden on the same side.

In the editor, clicking a set peering side flips it between match and must-not;
dragging only sets unset sides; right click clears both. A must-not side is drawn
as a disc in the terrain's colour crossed out in red (`BetterTerrainData.not_marker`),
so it can't be mistaken for a match fill. The Match Tiles help has a step for it,
and its tile sheet shows the marks. Quick terrains clear old must-not rules along
with the match ones.

One change from the PR. There, a kept must-not rule always earns the match reward,
so a redundant rule decides ties: an interior tile with "no slope below" beat the
bottom edge where the cell below was empty, because the failed "Ground below" was
paid back by the kept "no slope below". Here a kept rule only earns on a side
that has no match rule; a broken one always costs the penalty.

For the Mario Maker style slope tileset (`BetterTerrainMRP`), the same map comes
out identical either with must-not rules or with Decoration ("empty") peering.
`tests/not_peering.gd` covers scoring, categories, Decoration, the API, symmetry,
undo, type changes, terrain swaps and removal, and quick terrains.

### AA. The slope tool

`SlopeTerrain.gd`, `editor/SlopeEditor.gd`, `editor/Dock.gd` (`_add_slope_button`,
`_slope_plan`, `_slope_offset`, `_apply_slope`, `_draw_slope_preview`, `_slope_result`).

Made for the SMB1 Remaster tileset: steep slopes one cell per row, gentle ones two
cells per row (a low half `g1` and a high half `g2`), each for floors rising right
(TL) or left (TR) and ceilings (BL, BR), plus one Ground terrain. It is a tool, not
a terrain type: it writes terrains into cells and the usual matching picks tiles.

**Set-up is done on the atlas** (the first version; section AD replaced it with piece cards).
`SlopeTerrain.sample()` builds a small landscape
with every piece in it: a gentle island and a steep island (the 12 slopes, Ground,
and the Ground right under or over each slope, its "arrow"), and thin diagonals.
The window paints it with the real matching on a layer that never enters the tree.
Behind each piece a faint outline (`SlopeTerrain.blueprint`) shows the shape it
should have, and a piece without a tile shows only that and a "?". Each piece is
drawn with the tile picked for it, not the one the matching would choose: before
the rules are added an arrow can lose to another Ground piece, and the sample then
looked as if the click had picked the wrong tile. Plain Ground uses the matching.
The atlas hides the terrain marks and the dimming (`TileView.show_terrain_marks`). The atlas is the
dock's own `TileView` in a scroll container, so every source is there and the wheel
zooms at the cursor and the middle button pans, as in the other editors. **Clear
slopes** (`SlopeTerrain.clear`) takes every piece off its tile, arrows included, and
removes the slope terrains, leaving Ground; it is one undo step.
Click a piece, then its tile in the atlas: `SlopeTerrain.assign` makes the slope
terrain if missing (named like `GentleSlope1TL`, in a `SlopeSolid` category of its
own that Ground joins), gives the tile its terrain and rules, and takes the piece
away from the tile that had it. Every tile it takes is remembered as it was
(`_better_terrain_slopes_taken`), and when it lets the tile go, or on **Clear
slopes**, the tile gets that back: trying a Ground tile for a slope and moving on
used to leave it with no terrain, and the Ground in the sample changed with it. An arrow gets its slope on one side and the
category along the others, leaving the corners beside the slope free; a thin half
names its other half (`THIN`). `slot_tile` reads the pieces back, so tilesets set
up by hand, like the MRP one, show as they are. Roles are stored by terrain name in
the `_better_terrain_slopes` meta; each click is one undo step that restores the
tile and TileSet metadata. The tool shows once all 12 slopes have a terrain.

**Drawing follows the mouse.** The drag starts at the pressed cell and `snap()`
takes the angle to the mouse from its centre: the nearest of flat, gentle (26.6°),
steep (45°) and vertical, long enough to end by the mouse. Flat and vertical are a
line of Ground. A gentle slope of one step has both halves on one row, which is why
the mouse position is read in fractions of a tile rather than cells. A slope is a
ceiling slope when it starts under something and has nothing under its low end;
otherwise a floor slope, filled with Ground down to whatever it stands on (at most
64 cells, else down to its own base), with the slope-set cells touching it above
cleared; the clearing stops at the first empty cell, since a ceiling slope drawn over
a hill used to carve the hill's top across the gap. Shift
makes a thin diagonal: each slope cell with its underside half, no Ground. Thin
pieces are optional: the window labels them so and counts them apart, and without
all 12 Shift draws nothing and the label says where to set them up (`thin_ready`). Guessing
"thin" from empty space turned a slope drawn off the top of another into a thin one.
Slopes that started or ended one row off the ground beside them left a step the
tileset has no piece for (a corner, a notch), so `shape()` aligns both ends: pressed
on the top row of ground, a slope up starts just above it and a slope down starts
beside its edge on the same row (on the bottom row of a ceiling, just below; deeper
inside it carves where pressed), and the far end is stretched or
shortened by up to two steps until it meets the ground beside it at its own row.
Erasing, lines and thin diagonals are drawn exactly as dragged. While dragging,
`_slope_result` applies the plan to a copy of the cells around it and the overlay
draws the resulting tiles and a label.

**Add slope rules to tiles** (`SlopeTerrain.add_rules`): Ground pieces with ground
on both sides (rules on left and right) forbid slopes above and below, so the
arrows win under a slope; a left or right edge has no arrow of its own and keeps
taking slopes, or an island's side under a slope got a bottom corner; Ground pieces accept slopes beside them; steep slopes and
their arrows accept the other half of a peak. Corner pieces are left alone, since a
thin diagonal may rest on them. On the MRP tileset the author's map comes out
unchanged with these rules, and a tileset set up from scratch in the window, plus
this button, paints hills, valleys, chained slopes, ceilings and thin diagonals.

Slopes that end in the air, or run off the edge of a block, have no piece in that
tileset. `tests/slope_tool.gd` covers the roles, the button, drawing, snapping,
lines, filling, carving, ceilings, thin diagonals, erasing, undo and the rules.

### AB. A layer without a TileSet

`editor/Dock.gd` (`show_missing_tileset`, `_create_tileset`), `TerrainPlugin.gd`
(`_on_tileset_created`).

A TileMapLayer with no TileSet used to open an empty dock. Now the dock says so and
offers **Create TileSet**, one undo step. Once the layer has a TileSet, from the
button or from the inspector (the dock listens to the layer's `changed`), the dock
comes back and Godot's TileSet tab opens, since a new TileSet needs an atlas before
anything else. In Godot 4.7 the bottom panel is a `TabContainer` holding the
`TileSetEditor`, so the plugin selects its tab; elsewhere it falls back to
`make_bottom_panel_item_visible`. `tests/no_tileset.gd` covers it.

The demo project has `Demos/17_Slopes.tscn` with an original tileset,
`Demos/Tilesets/slopes_platformer.png`, drawn by `Tools/slopes_tileset/make_slope_tiles.py`
from the shape of ground around each tile, and set up by `build_slopes_demo.gd`
with the same `assign` and `add_rules` the Slopes window uses.

### AC. Drawing on from what is there: Autofill, Freehand, the _hidden group

`SlopeTerrain.gd` (`_continue`, `_half_end`, `_ceiling_at`, `_bury`, `free_moves`,
`free_trail`, `_flattened`, `free_plan`, `hide_pieces`, `tidy`), `editor/Dock.gd`
(`_slope_autofill`, `_slope_freehand`, `_slope_smooth`, `picker_modifier_down`).

**A drag pressed on a slope goes on beside it.** Pressed on a floor slope or the
Ground under it, `_continue` climbs to the column's top piece and starts the drag in
the next column, at the height where that piece's surface meets its edge
(`FLOOR_EDGES`); pressed on a ceiling slope or the Ground over it, the same from its
underside (`CEILING_EDGES`), and the drag is a ceiling. On a gentle half it first
moves to the other half (`_half_end`), which it would otherwise overwrite. The drag
still ends by the mouse. Pressed inside plain Ground it carves where pressed, as
before. A straight line started in the air is a ceiling when the cell before its
start or after its end is a ceiling slope or the underside of ground (`_ceiling_at`).
Slope pieces left right under new ground become Ground (`_bury`): a stroke one row
above an older one left its slope buried.

**Autofill**, in the tool options, fills straight lines down to the ground (up, for
a ceiling), as slopes always were. With no ground within 64 cells the line stays a
one-row bar, so floating platforms need no toggling.

**Freehand** keeps the mouse's trail in cell units and turns it into moves between
cell corners (`free_moves`): climbing or dropping without leaving the column is a
wall (its column reaches the lower floor); otherwise the rise over the next column
picks flat (under 0.25), gentle (under 0.75) or steep. Deciding from the trail, not
from where the mouse is now, is what makes walls: the latest position alone rounded
every corner into a slope. Going back pops trail points ahead of the mouse
(`free_trail`), which rubs out; Shift pins new points to the stroke's height. The
whole stroke is one undo step on release. **Smooth** (default 2) turns bumps and
dips one row high and at most that many columns wide into flat ground
(`_flattened`): averaging the trail did not work, since jitter inflates its length.
Freehand flats and walls go around slope pieces already there. A stroke that goes on
from a ceiling at either end (a ceiling slope, or the last cell of a flat ceiling's
bottom row) draws the underside: BL/BR pieces, flats above the stroke, no wall cells,
and Ground growing up; pressed on the top of that last row, it starts from its bottom.
The line tool treats the end of a flat ceiling the same way, as a ceiling piece whose
underside is its bottom: before, a slope rising away from it had nothing over its high
end and came out as a floor.

**The `_hidden` group.** The 12 slope terrains and `SlopeSolid` exist so that each
cell remembers its shape; they are never painted by hand, so the set-up puts them in
a `_hidden` group the list leaves out unless Options → "Show the _hidden group" is
on. Opening the Slopes window tidies older set-ups (`tidy`): the "Solid" category
they made is kept when only Ground and slopes are in it, else a new one is made, so
a category Ground shared with other terrains is never widened with slopes.

**The picker modifier.** Alt+click is often a window-manager shortcut on Linux, and
the Alt release can be swallowed, leaving `Input.is_key_pressed(KEY_ALT)` true and
the pick cursor on until the next key. Mouse events carry the real modifiers, so a
mouse event without it marks the key state stale until a key event arrives.

### AD. The slope set-up, rebuilt: piece cards, and a simple mode that flips

`editor/SlopeEditor.gd`, `SlopeTerrain.gd` (`mode`, `set_mode`, `turn`, `remove_turned`, `TURNS`).

The first window set pieces by clicking a sample landscape. It did two jobs badly: a
cell could be a piece, many cells were the same piece (every plain one was Ground),
and what they showed was the matching's pick, so it looked as if the window mixed
tiles up. It also opened a window of its own, and with the GPU memory nearly full
(another program held most of it) creating one failed with an X `BadAlloc` and took
Godot down. Now the set-up covers the dock instead of opening a window: cards on the
left, one per piece, each showing its shape and the tile picked; the atlas in the
middle, with each tile in use labelled with its pieces; a preview on the right that
only shows. A click in the atlas sets the selected card and moves to the next card
without a tile. A tile another piece had is swapped with it, so a pick is never
refused. Ground shows its solid block, not the first Ground tile found.

**Simple mode** asks for Ground, the steep and both gentle halves rising right, the
ground under each, and optionally the thin diagonal rising right (top and
underside). `turn` makes the rest as alternative tiles of those: rising left is
`flip_h`, ceilings `flip_v`, ceilings rising left both, copying the tile's other
properties (collision, occlusion, custom data) so Godot flips them too. Each flipped
piece keeps a fixed alternative id (`TURN_ID_BASE` + its index in `TURNS`) and is
reused while its original stays, because recreating them would give new ids and
break every map painted with them. Undo restores the metadata and calls `turn` again.
The mode is stored in the TileSet when the set-up opens: deciding it from whether the
set is complete turned it advanced as soon as the pieces were filled in. Existing,
complete set-ups open advanced. Going to advanced keeps the flipped pieces until they
are replaced; going back to simple flips over them.
