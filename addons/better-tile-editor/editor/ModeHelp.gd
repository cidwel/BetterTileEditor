@tool
extends Window

const ExemplarData := preload("res://addons/better-tile-editor/ExemplarData.gd")
const ObjectTerrain := preload("res://addons/better-tile-editor/ObjectTerrain.gd")
const ExemplarTerrain := preload("res://addons/better-tile-editor/ExemplarTerrain.gd")

# Use numeric IDs so help can load without the editor autoload.
const MATCH_TILES := 0
const MATCH_VERTICES := 1
const CATEGORY := 2
const DECORATION := 3
const OBJECT := 4
const EXEMPLAR := 5
const SCATTER := 6
const SINGLE := 7

const ZOOM := 2
const SQUARE_STEPS := [
	["This square",
	 "The drawing is the whole setup, and this is one square of it. What matters is "
	 + "where it sits, not what it looks like.", "block"],
	["When it gets used",
	 "The nine squares are a map cell and its eight neighbours. Whenever a cell "
	 + "comes out looking like this, this is the tile that answers.", "nine"],
	["Where it lands",
	 "Paint a shape and every cell works out its own role. The marked ones are the "
	 + "cells this square answered.", "shape_marked"],
	["Done",
	 "No table, no scoring. Every cell here came from one drawing.", "shape"],
]

const MODE_STEPS := {
	MATCH_TILES: [
		["What may sit next to it",
		 "Pick a tile and tell it what is allowed to touch each of its sides and "
		 + "corners. You do that with \"paint terrain connecting types\" in the "
		 + "toolbar.\n\nHere is one tile being set, a click at a time.", "sides"],
		["What may not sit next to it",
		 "Click a side that is already set and it flips to must-not: that terrain may "
		 + "not be there. Click again to flip it back; right click clears it.\n\nUse it "
		 + "for tiles defined by what they lack, like a notch, a tip or the corner on "
		 + "top of a slope. Forbid a category to forbid all its terrains, or Decoration "
		 + "to forbid an empty cell.", "not_sides"],
		["Now do that to every tile",
		 "Same job, tile after tile, until the whole terrain is described. This is "
		 + "the sheet you see over in the atlas panel.\n\nThat is the cost of this "
		 + "mode. You need a tile for every shape the terrain can take, and each one "
		 + "has to be told what it accepts.", "all_tiles"],
		["Then painting takes care of itself",
		 "Paint a cell and the engine looks at its neighbours, tries every tile of "
		 + "the terrain, and keeps the one that fits best.\n\nThis is the ordinary "
		 + "autotile. If your art was not drawn that way, say a pond drawn once as a "
		 + "whole, there is nothing for it to choose from. Use Patch for that.", "real_sides"],
	],
	MATCH_VERTICES: [
		["What meets at each corner",
		 "Same idea, but you set the four corners instead of the eight sides. Each "
		 + "corner says which terrain meets there.\n\nFewer clicks per tile.", "corners"],
		["Now do that to every tile",
		 "Tile after tile, same as before. Half as much to set on each one, which is "
		 + "the reason to pick this mode.", "all_tiles"],
		["Then painting takes care of itself",
		 "Terrains meet right at the corner instead of two sides having to agree, so "
		 + "the joins come out clean. It suits art drawn in quarters.", "real_corners"],
	],
	CATEGORY: [
		["A name, not a terrain",
		 "You never paint a category and it never shows up on the map. It is a label "
		 + "you hang on other terrains.", "category"],
		["What you would use it for",
		 "Put grass, sand and dirt in one category called Ground. Now any tile that "
		 + "accepts Ground accepts all three.\n\nHandy when a border does not care "
		 + "which of them is on the other side.", "real_category"],
	],
	DECORATION: [
		["It goes on the empty cells",
		 "Decoration is not painted onto terrain. It drops into cells that are "
		 + "empty, going by what surrounds them.", "decoration"],
		["What you would use it for",
		 "Flowers on a meadow, cracks in a floor, tufts along a path. Things that "
		 + "should turn up on their own once the ground is there, instead of you "
		 + "placing them one by one.", "real_decoration"],
	],
	OBJECT: [
		["One object, several cells",
		 "A 2x2 tree, a bush, a statue: a block of cells placed in one go. Set its "
		 + "size here, then mark its blocks in the atlas.", "object"],
		["It needs two versions",
		 "Mark the lone block for when the object stands on its own, and the joined "
		 + "block, whose art runs off the edges, for when another one is beside "
		 + "it.", "object_joined"],
		["Then placing takes care of itself",
		 "Paint a patch and each block picks its own version, so a row of trees "
		 + "reads as one thicket instead of copies in a line.", "real_object"],
		["Or paint it as an area",
		 "Pick the Area card in the properties and the same two blocks stop being "
		 + "placed one by one. Paint a shape and the lone drawing is stamped across "
		 + "it on a shingled lattice, back to front, each one covering the one "
		 + "behind. A wood, a hedge, a crowd of anything tall.", "real_area"],
		["Where its edge comes from",
		 "Set Base offset and Base size in the terrain properties to define the "
		 + "rectangle that must stand inside the painted shape. Every tile of this "
		 + "base must fit; the crown may extend outside it. The yellow rectangle "
		 + "in the mode preview shows the base.",
		 "real_area_edge"],
	],
	EXEMPLAR: [
		["Draw it once, whole",
		 "Instead of wiring up pieces, you draw the terrain complete: a pond, water "
		 + "with its bank around it, laid out as it would look on the map.\n\nThat "
		 + "drawing is the whole setup: mark its tiles with the paint-type tool, "
		 + "bank and all. The atlas outlines what will be read as you mark, and the "
		 + "first stroke on the map reads it. There is nothing to fill in.", "block"],
		["Each square gets a role from where it sits",
		 "The block is peeled inwards. What is left in the middle is the terrain, "
		 + "the ring around it is the border. Each square then takes its role from "
		 + "its position: top bank, the corner where top and left meet, open "
		 + "water.\n\nSeventeen roles cover everything. The smallest drawing that "
		 + "has them all is 5x5 with the corners left empty, 21 tiles. Draw the four "
		 + "corners too, a bank that wraps the corner, and they are read as well: "
		 + "the cells that touch the water only corner to corner get them.", "block_all"],
		["Painting follows a rule",
		 "For each cell it looks at the neighbours it needs, works out which role "
		 + "that cell plays, and puts down that role's tile. Nothing is scored and "
		 + "no table is read.\n\nThe marked square is one cell and the eight "
		 + "around it.", "shape_nine"],
		["The result",
		 "Cells that only touch the terrain corner to corner get nothing at all. "
		 + "That is an answer, not a hole.\n\nTwo things the drawing teaches that "
		 + "are easy to miss: the diagonal pieces belong at the ends of the top and "
		 + "bottom runs, and the side banks are stretched over their run, so a bank "
		 + "tapers into a corner instead of repeating up to it.", "shape_claims"],
	],
	SCATTER: [
		["A bag, and a region",
		 "Nothing is matched against anything here. You put tiles in the bag, give "
		 + "each one a weight, and paint a region; every cell of it throws the bag "
		 + "once.\n\nTwo scales, and they do different jobs. Nothing is a "
		 + "percentage and sets the density: 90 leaves nine cells in ten bare. The "
		 + "entries are weights against each other and share out the rest, so 4 "
		 + "and 1 is four times as much grass as rocks however dense it is.", "scatter"],
		["Nothing is a result",
		 "A cell that comes up empty stays part of the region all the same, which "
		 + "is what lets you change the numbers afterwards and see the whole region "
		 + "answer.\n\nSo the region is not the art. It lives on the layer you "
		 + "paint; the art lives on a ScatterDecor layer underneath it, wiped and "
		 + "rewritten on every change.", "scatter"],
		["Pieces bigger than a cell",
		 "A bag entry can be a block: drag a box over the atlas and the whole "
		 + "box goes in as one piece. A block is placed only "
		 + "where all of it fits inside the region and nothing is there already, "
		 + "so a bush never comes out sawn in half at the edge.\n\nThe throw is "
		 + "seeded from the coordinate, so a saved map opens the same way it was "
		 + "left. Reroll is what moves it.", "scatter_block"],
	],
	SINGLE: [
		["One tile, and no rules",
		 "Pick the terrain, click a tile in the atlas, and that is the whole "
		 + "setup. Painting puts down that tile and nothing else looks at it: no "
		 + "neighbours, no scoring, no second drawing.\n\nIt is the plain tile "
		 + "brush, inside the terrain list, for the things that are not terrain: "
		 + "a signpost, a doorway, one rock you want exactly there.", "single"],
		["Nothing is marked",
		 "The tile is not marked as this terrain, because a tile can only belong "
		 + "to one and this mode would steal it from whatever already had it. The "
		 + "terrain remembers which tile it points at, and the atlas outlines "
		 + "it.\n\nWhich means the same tile can be a single-tile terrain here "
		 + "and part of a proper terrain elsewhere, and neither knows about the "
		 + "other. The bucket and the picker still recognise what you painted: "
		 + "they go by which tile is in the cell.", "single"],
	],
}

const MODE_TITLES := {
	MATCH_TILES: "Match tiles", MATCH_VERTICES: "Match vertices", CATEGORY: "Category",
	DECORATION: "Decoration", OBJECT: "Object (NxM)", EXEMPLAR: "Patch",
	SCATTER: "Scatter", SINGLE: "Single tile",
}

const DIR_NAMES := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

var tile_set: TileSet
var terrain_color := Color.WHITE

var _table := {}
var _role := ""
var _step := 0
var _canvas: Control
var _text: RichTextLabel
var _bar: HBoxContainer
var _region := {}
var _example := Vector2i.ZERO
var _has_example := false
var _overview := false
var _art := false
var _steps_data: Array = []
var _type := EXEMPLAR
var _counter: Label
var _prev: Button
var _next: Button
var _real := {}
var _real_done := false
var _lone := {}
var _lone_done := false
var _example_ts: TileSet
var _example_index := -1
var _example_from := ""
var _example_done := false
var _anim := 0.0         ## seconds into the current step's animation
var _animated := false


static func demo_region() -> Dictionary:
	var region := {}
	for y in range(1, 6):
		for x in range(1, 9):
			if (x == 1 or x == 8) and (y == 1 or y == 5):
				continue
			region[Vector2i(x, y)] = true
	return region


func setup_mode(ts: TileSet, table: Dictionary, type: int, color: Color) -> void:
	_type = type
	_overview = true
	_role = "OUT_W"
	_steps_data = MODE_STEPS.get(type, MODE_STEPS[MATCH_TILES])
	_prepare(ts, table, color)
	title = "Mode: %s" % MODE_TITLES.get(type, "terrain")


func setup_square(ts: TileSet, table: Dictionary, role: String, color: Color) -> void:
	_type = EXEMPLAR
	_overview = false
	_role = role
	_steps_data = SQUARE_STEPS
	_prepare(ts, table, color)
	title = "This square: %s" % ExemplarData.role_label(role)


func _prepare(ts: TileSet, table: Dictionary, color: Color) -> void:
	tile_set = ts
	_table = table
	terrain_color = color
	_region = demo_region()
	_art = _table.get("block", []).size() == 4 and not _table.get("lines", {}).is_empty() \
		and ts != null and ts.get_source(int(_table.get("source", -1))) is TileSetAtlasSource
	if not _art and _type == EXEMPLAR:
		_resolve_example()
		if _example_ts != null:
			var borrowed := ExemplarData.table_of(_example_ts, _terrain_name(_example_index))
			if borrowed.get("block", []).size() == 4:
				_table = borrowed
				_art = true
	_find_example()
	size = Vector2i(660, 360)
	_build()
	_show_step(0)


func _build() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var header := Label.new()
	header.text = "How does it work:"
	header.add_theme_font_size_override("font_size", 17)
	box.add_child(header)

	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 10)
	box.add_child(middle)

	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.draw.connect(_draw_canvas)
	middle.add_child(_canvas)

	# Let RichTextLabel scroll itself; fit_content inside ScrollContainer creates a layout loop.
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = true
	_text.custom_minimum_size = Vector2(250, 0)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(_text)

	_bar = HBoxContainer.new()
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar.add_theme_constant_override("separation", 10)
	box.add_child(_bar)
	_prev = Button.new()
	_prev.text = "< Previous"
	_prev.focus_mode = Control.FOCUS_NONE
	_prev.pressed.connect(func(): _show_step(maxi(_step - 1, 0)))
	_bar.add_child(_prev)
	_counter = Label.new()
	_counter.custom_minimum_size = Vector2(56, 0)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar.add_child(_counter)
	_next = Button.new()
	_next.text = "Next >"
	_next.focus_mode = Control.FOCUS_NONE
	_next.pressed.connect(func(): _show_step(mini(_step + 1, _steps().size() - 1)))
	_bar.add_child(_next)

	close_requested.connect(hide)


func _find_example() -> void:
	_has_example = false
	var seen := {}
	for c in _region:
		seen[c] = true
		for off in ExemplarData.OFFSETS:
			seen[c + off] = true
	for c in seen:
		if ExemplarData.role_for(_region, c) == _role:
			_example = c
			_has_example = true
			return


func _steps() -> Array:
	return _steps_data


func _process(delta: float) -> void:
	_anim += delta
	_canvas.queue_redraw()


func _show_step(i: int) -> void:
	_step = i
	var entry: Array = _steps()[i]
	var kind: String = entry[2] if entry.size() > 2 else ""
	_animated = kind == "sides" or kind == "corners"
	_anim = 0.0
	set_process(_animated)
	var body := "[b]%s[/b]\n\n%s" % [entry[0], entry[1]]
	var extra := _about_this_square() if not _overview else _about_the_example(entry)
	if extra != "":
		body += "\n\n[color=#9fd]%s[/color]" % extra
	_text.text = body
	_counter.text = "%d / %d" % [i + 1, _steps().size()]
	_prev.disabled = i == 0
	_next.disabled = i == _steps().size() - 1
	_canvas.queue_redraw()


func _about_the_example(entry: Array) -> String:
	var kind: String = entry[2] if entry.size() > 2 else ""
	if not kind.begins_with("real_") or _real_example().is_empty():
		return ""
	var who := _terrain_name(_example_index)
	if _example_from == "":
		return "Painted with \"%s\", one of this mode's terrains from the tileset you have open." % who
	return "This tileset has no terrain of this mode yet, so it is painted with \"%s\", borrowed from %s." % [who, _example_from]


func _about_this_square() -> String:
	var lines := PackedStringArray()
	lines.append("This square: %s." % ExemplarData.role_label(_role))
	var run: Array = _table.get("slots", {}).get(_role, [])
	if run.size() > 1:
		if _role in ExemplarData.VERTICAL:
			lines.append("The drawing has %d squares for it. They stretch down the run: first at the top, last at the bottom, the middle one filling in between. That is what tapers the bank into a corner." % run.size())
		else:
			lines.append("The drawing has %d squares for it. The most ordinary one is reused wherever the role comes up: this run is drawn uneven on purpose, so there is nothing to stretch." % run.size())
	if _has_example:
		var around := PackedStringArray()
		for i in ExemplarData.OFFSETS.size():
			if _region.has(_example + ExemplarData.OFFSETS[i]):
				around.append(DIR_NAMES[i])
		var where := "inside the terrain" if _region.has(_example) else "outside it"
		lines.append("Wanted by a cell %s, with terrain to the %s." % [
			where, ", ".join(around) if not around.is_empty() else "none of the eight"])
		var count := 0
		var seen := {}
		for c in _region:
			seen[c] = true
			for off in ExemplarData.OFFSETS:
				seen[c + off] = true
		for c in seen:
			if ExemplarData.role_for(_region, c) == _role:
				count += 1
		lines.append("On the shape below that happens %d times." % count)
	else:
		lines.append("This one never comes up on a plain pond. It is for shapes with a notch or a corner cut out of them.")
	return "\n".join(lines)


#region Drawing the steps

func _tile_rect(at: Array) -> Rect2:
	var src := tile_set.get_source(int(_table.source)) as TileSetAtlasSource
	if src == null:
		return Rect2()
	var coord := Vector2i(int(at[0]), int(at[1]))
	if not src.has_tile(coord):
		return Rect2()
	return src.get_tile_texture_region(coord)


func _blit(at: Array, where: Rect2) -> void:
	var src := tile_set.get_source(int(_table.source)) as TileSetAtlasSource
	var r := _tile_rect(at)
	if src == null or r.size.x <= 0.0:
		return
	_canvas.draw_texture_rect_region(src.texture, where, r)


func _schematic(role: String) -> Color:
	if role.begins_with("IN_"):
		return terrain_color
	return terrain_color.lerp(Color(0.32, 0.30, 0.28), 0.62)


func _cell_size() -> Vector2:
	return Vector2(tile_set.tile_size) * ZOOM


func _draw_canvas() -> void:
	var entry: Array = _steps()[_step]
	var kind: String = entry[2] if entry.size() > 2 else "shape"
	match kind:
		"block": _draw_drawing(false)
		"block_all": _draw_drawing(true)
		"nine": _draw_neighbourhood()
		"shape_marked": _draw_landing(true, false)
		"shape_nine": _draw_landing(true, true)
		"shape": _draw_landing(false, false)
		"shape_claims": _draw_claims()
		"sides": _draw_compass(true)
		"not_sides": _draw_not_sides()
		"corners": _draw_compass(false)
		"category": _draw_category()
		"decoration": _draw_decoration()
		"object": _draw_object(false)
		"object_joined": _draw_object(true)
		"all_tiles":
			if not _draw_all_tiles():
				_draw_compass(true)
		"real_sides": _draw_real("sides")
		"real_corners": _draw_real("corners")
		"real_category": _draw_real("category")
		"real_decoration": _draw_real("decoration")
		"real_object": _draw_real("object")
		"real_area": _draw_area_help(false)
		"real_area_edge": _draw_area_help(true)
		"single": _draw_single()
		"scatter": _draw_scatter(false)
		"scatter_block": _draw_scatter(true)


func _draw_claims() -> void:
	_draw_landing(false, false)
	var cs := _cell_size()
	var origin := Vector2(24, 20)
	var seen := {}
	for c in _region:
		seen[c] = true
		for off in ExemplarData.OFFSETS:
			seen[c + off] = true
	for c in seen:
		var role := ExemplarData.role_for(_region, c)
		var where := Rect2(origin + Vector2(c) * cs, cs)
		if role in ["OUT_NW", "OUT_NE", "OUT_SW", "OUT_SE"]:
			_canvas.draw_rect(where, Color(1.0, 0.85, 0.3, 0.30))
			_canvas.draw_rect(where, Color(1.0, 0.85, 0.3), false, 2.0)
		elif role == "OUT_W" or role == "OUT_E":
			_canvas.draw_rect(where, Color(0.45, 0.8, 1.0, 0.26))
			_canvas.draw_rect(where, Color(0.45, 0.8, 1.0), false, 2.0)
	var font := get_theme_default_font()
	var bottom := origin + Vector2(0, cs.y * 9.2)
	_canvas.draw_rect(Rect2(bottom, Vector2(14, 14)), Color(1.0, 0.85, 0.3))
	_canvas.draw_string(font, bottom + Vector2(22, 12), "the diagonals, at the ends of the runs",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.75))
	_canvas.draw_rect(Rect2(bottom + Vector2(0, 20), Vector2(14, 14)), Color(0.45, 0.8, 1.0))
	_canvas.draw_string(font, bottom + Vector2(22, 32), "the side banks, stretched over theirs",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.75))


#region A real example

## Editor autoloads may be unnamed; fall back to matching lheir script.
func _better_terrain() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root: Node = (loop as SceneTree).root
	var named := root.get_node_or_null(NodePath("BetterTerrain"))
	if named != null:
		return named
	for child in root.get_children():
		var script = child.get_script()
		if script != null and script.resource_path == "res://addons/better-tile-editor/BetterTerrain.gd":
			return child
	return null


func _terrain_score(ts: TileSet, index: int, bt) -> float:
	var tiles: Array = bt.get_tile_sources_in_terrain(ts, index)
	if tiles.size() < 8:
		return -99.0
	var meta = ts.get_meta(&"_better_terrain")
	var kind := int(meta.terrains[index][2])
	var sides: Array = bt.data.get_terrain_peering_cells(ts, kind)
	var images := {}
	var solid := 0
	var whole := 0
	var seen := {}
	for e in tiles:
		var src := e.get("source") as TileSetAtlasSource
		var td := e.get("td") as TileData
		if src == null or td == null or src.texture == null:
			continue
		if not images.has(src):
			var img := src.texture.get_image()
			if img != null and img.is_compressed():
				img.decompress()
			images[src] = img
		var image: Image = images[src]
		if image != null:
			var r := src.get_tile_texture_region(e.coord)
			var opaque := 0
			for gy in 4:
				for gx in 4:
					var at := r.position + Vector2i(int(r.size.x * (gx + 0.5) / 4.0),
													int(r.size.y * (gy + 0.5) / 4.0))
					if at.x < image.get_width() and at.y < image.get_height() \
							and image.get_pixel(at.x, at.y).a > 0.9:
						opaque += 1
			if opaque >= 15:
				solid += 1
		var key := ""
		var accepts := 0
		for side in sides:
			if index in bt.tile_peering_types(td, side):
				key += "1"
				accepts += 1
			else:
				key += "0"
		seen[key] = true
		if accepts == sides.size():
			whole += 1
	var n := float(tiles.size())
	return (float(solid) / n) * 2.0 \
		+ minf(float(seen.size()), 16.0) / 16.0 \
		+ (1.0 if whole > 0 else -2.0) \
		+ (0.0 if tiles.size() >= 12 else -1.0)


func _terrain_of_type_in(ts: TileSet) -> int:
	if ts == null or not ts.has_meta(&"_better_terrain"):
		return -1
	var meta = ts.get_meta(&"_better_terrain")
	var terrains: Array = meta.get("terrains", [])
	var bt := _better_terrain()
	var best := -1
	var best_score := -1.0e9
	for i in terrains.size():
		var t: Array = terrains[i]
		if t.size() < 3 or int(t[2]) != _type:
			continue
		if bt == null:
			return i
		var score := _terrain_score(ts, i, bt)
		if score > best_score:
			best_score = score
			best = i
	return best


func _resolve_example() -> void:
	if _example_done:
		return
	_example_done = true
	_example_index = _terrain_of_type_in(tile_set)
	if _example_index >= 0:
		_example_ts = tile_set
		return
	var bt := _better_terrain()
	var best_score := -1.0e9
	for path in _project_tilesets():
		var other = load(path)
		if not (other is TileSet):
			continue
		var idx := _terrain_of_type_in(other)
		if idx < 0:
			continue
		var score := _terrain_score(other, idx, bt) if bt != null else 0.0
		if score > best_score:
			best_score = score
			_example_ts = other
			_example_index = idx
			_example_from = path.get_file()


func _project_tilesets() -> Array:
	var found := []
	var pending := ["res://"]
	while not pending.is_empty() and found.size() < 64:
		var at: String = pending.pop_front()
		var dir := DirAccess.open(at)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var path := at.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with(".") and entry != "addons":
					pending.append(path)
			elif entry.ends_with(".tres"):
				var f := FileAccess.open(path, FileAccess.READ)
				if f != null:
					var head := f.get_buffer(120).get_string_from_utf8()
					f.close()
					if head.contains('type="TileSet"'):
						found.append(path)
			entry = dir.get_next()
		dir.list_dir_end()
	return found


func _terrain_name(index: int) -> String:
	var ts := _example_ts if _example_ts != null else tile_set
	if ts == null or not ts.has_meta(&"_better_terrain"):
		return ""
	var meta = ts.get_meta(&"_better_terrain")
	var terrains: Array = meta.get("terrains", [])
	return String(terrains[index][0]) if index >= 0 and index < terrains.size() else ""


func _real_example() -> Dictionary:
	if _real_done:
		return _real
	_real_done = true
	_resolve_example()
	var index := _example_index
	var bt := _better_terrain()
	if index < 0 or bt == null or _example_ts == null:
		return _real
	var layer := TileMapLayer.new()
	layer.tile_set = _example_ts
	add_child(layer)
	var cells := []
	if _type == OBJECT:
		for y in range(0, 4):
			for x in range(0, 6):
				cells.append(Vector2i(x, y))
	else:
		for c in _region:
			cells.append(c)
	bt.set_cells(layer, cells, index)
	bt.update_terrain_cells(layer, cells)
	if _type == OBJECT:
		ObjectTerrain.fix_layer(layer)
	elif _type == EXEMPLAR:
		ExemplarTerrain.rebuild(layer, bt)
	for c in layer.get_used_cells():
		_real[c] = {"source": layer.get_cell_source_id(c), "coord": layer.get_cell_atlas_coords(c)}
	var edges := ExemplarTerrain.edges_layer(layer, false)
	if edges != null:
		for c in edges.get_used_cells():
			_real[c] = {"source": edges.get_cell_source_id(c), "coord": edges.get_cell_atlas_coords(c)}
	remove_child(layer)
	layer.queue_free()
	return _real


func _real_middle() -> Vector2i:
	var cells := _real_example()
	for c in cells:
		var whole := true
		for off in ExemplarData.OFFSETS:
			if not cells.has(c + off):
				whole = false
				break
		if whole:
			return c
	return Vector2i(1 << 30, 1 << 30)


func _lone_example() -> Dictionary:
	if _lone_done:
		return _lone
	_lone_done = true
	_resolve_example()
	var index := _example_index
	var bt := _better_terrain()
	if index < 0 or bt == null or _example_ts == null:
		return _lone
	var object_size := ObjectTerrain.object_size(_example_ts, index)
	if object_size.x <= 0:
		object_size = Vector2i(2, 2)
	var layer := TileMapLayer.new()
	layer.tile_set = _example_ts
	add_child(layer)
	var cells := []
	for y in object_size.y:
		for x in object_size.x:
			cells.append(Vector2i(x, y))
	bt.set_cells(layer, cells, index)
	bt.update_terrain_cells(layer, cells)
	ObjectTerrain.fix_layer(layer)
	for c in layer.get_used_cells():
		_lone[c] = {"source": layer.get_cell_source_id(c), "coord": layer.get_cell_atlas_coords(c)}
	remove_child(layer)
	layer.queue_free()
	return _lone


var _area_done := false
var _area_layers: Array = []     # one {cell: {source, coord}} per layer, bottom first
var _area_painted := {}

## Resolve on a tileset copy so generated markers cannot change the user resource.
func _area_example() -> Array:
	if _area_done:
		return _area_layers
	_area_done = true
	_resolve_example()
	var bt := _better_terrain()
	if _example_index < 0 or bt == null or _example_ts == null:
		return _area_layers
	var ts: TileSet = _example_ts.duplicate(true)
	var t = bt.get_terrain(ts, _example_index)
	if not t.valid:
		return _area_layers
	var cfg: Dictionary = t.get("object", {}).duplicate()
	cfg["mass"] = true
	bt.set_terrain_object(ts, _example_index, cfg)
	var object_size := ObjectTerrain.object_size(ts, _example_index)
	if object_size.x <= 0:
		object_size = Vector2i(2, 2)
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	add_child(layer)
	var w: int = object_size.x * 3
	var h: int = object_size.y * 2
	var cells := []
	for y in h:
		for x in w:
			if (x == 0 or x == w - 1) and (y == 0 or y == h - 1):
				continue
			@warning_ignore("integer_division")
			if x >= w / 2 - 1 and x <= w / 2 and y >= h / 2 - 1 and y <= h / 2:
				continue
			cells.append(Vector2i(x, y))
	for c in cells:
		_area_painted[c] = true
	bt.set_cells(layer, cells, _example_index)
	bt.update_terrain_cells(layer, cells)
	ObjectTerrain.fix_mass(layer)
	var stack := [layer]
	for k in layer.get_children():
		if k is TileMapLayer:
			stack.append(k)
	for l in stack:
		var d := {}
		for c in l.get_used_cells():
			d[c] = {"source": l.get_cell_source_id(c), "coord": l.get_cell_atlas_coords(c)}
		_area_layers.append(d)
	remove_child(layer)
	layer.queue_free()
	return _area_layers


func _draw_area_help(outline: bool) -> void:
	var layers := _area_example()
	if layers.is_empty():
		_draw_object(true)
		return
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for l in layers:
		for c in l:
			lo.x = mini(lo.x, c.x); lo.y = mini(lo.y, c.y)
			hi.x = maxi(hi.x, c.x); hi.y = maxi(hi.y, c.y)
	var span := Vector2(hi - lo + Vector2i.ONE)
	var room := _canvas.size - Vector2(48, 48 + (22 if outline else 0))
	var fit: float = minf(room.x / span.x, room.y / span.y)
	var cs: Vector2 = _cell_size()
	if cs.x > fit:
		cs = Vector2(fit, fit)
	var origin := Vector2(24, 24) - Vector2(lo) * cs
	if outline:
		for c in _area_painted:
			_canvas.draw_rect(Rect2(origin + Vector2(c) * cs, cs), Color(1.0, 0.85, 0.3, 0.18))
	for l in layers:
		for c in l:
			_blit_from(int(l[c].source), l[c].coord, Rect2(origin + Vector2(c) * cs, cs))
	if outline:
		for c in _area_painted:
			var r := Rect2(origin + Vector2(c) * cs, cs)
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if _area_painted.has(c + d):
					continue
				var a := r.position
				var b := r.position
				match d:
					Vector2i.LEFT: b = r.position + Vector2(0, cs.y)
					Vector2i.RIGHT: a = r.position + Vector2(cs.x, 0); b = r.end
					Vector2i.UP: b = r.position + Vector2(cs.x, 0)
					Vector2i.DOWN: a = r.position + Vector2(0, cs.y); b = r.end
				_canvas.draw_line(a, b, Color(1.0, 0.85, 0.3), 2.0)
		var font := get_theme_default_font()
		_canvas.draw_string(font, Vector2(24, origin.y + (Vector2(hi - lo) + Vector2.ONE).y * cs.y + 18),
			"outlined: what was painted", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.85, 0.3, 0.85))


func _blit_from(source_id: int, coord: Vector2i, where: Rect2) -> void:
	var ts := _example_ts if _example_ts != null else tile_set
	if ts == null:
		return
	var src := ts.get_source(source_id) as TileSetAtlasSource
	if src == null or not src.has_tile(coord):
		return
	_canvas.draw_texture_rect_region(src.texture, where, src.get_tile_texture_region(coord))


func _draw_real(fallback: String) -> void:
	var cells := _real_example()
	if cells.is_empty():
		match fallback:
			"sides": _draw_compass(true)
			"corners": _draw_compass(false)
			"category": _draw_category_use()
			"decoration": _draw_decoration_use()
			_: _draw_object(true)
		return
	var cs := _cell_size()
	var lo := Vector2i(1 << 30, 1 << 30)
	for c in cells:
		lo.x = mini(lo.x, c.x); lo.y = mini(lo.y, c.y)
	var origin := Vector2(24, 24) - Vector2(lo) * cs
	for c in cells:
		_blit_from(int(cells[c].source), cells[c].coord, Rect2(origin + Vector2(c) * cs, cs))


#endregion


#region The other modes

func _swatch(where: Rect2, col: Color, label := "") -> void:
	_canvas.draw_rect(where, col)
	_canvas.draw_rect(where, Color(0, 0, 0, 0.4), false, 1.0)
	if label != "":
		_canvas.draw_string(get_theme_default_font(), where.position + Vector2(6, where.size.y * 0.5 + 5),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))


func _draw_pointer(at: Vector2, clicking: bool) -> void:
	var arrow := PackedVector2Array([
		Vector2(0, 0), Vector2(0, 17), Vector2(4.6, 12.8), Vector2(7.6, 19.4),
		Vector2(10.6, 18.0), Vector2(7.6, 11.8), Vector2(13.4, 11.4),
	])
	var moved := PackedVector2Array()
	for v in arrow:
		moved.append(v + at)
	if clicking:
		_canvas.draw_circle(at, 13.0, Color(1.0, 0.95, 0.6, 0.35))
		_canvas.draw_circle(at, 13.0, Color(1.0, 0.9, 0.4, 0.8), false, 2.0)
	_canvas.draw_colored_polygon(moved, Color(1, 1, 1, 0.95))
	var edge := moved.duplicate()
	edge.append(moved[0])
	_canvas.draw_polyline(edge, Color(0.05, 0.05, 0.07, 0.9), 1.5)


func _mark(poly: PackedVector2Array, fill: Color, edge: Color, width := 2.0) -> void:
	_canvas.draw_colored_polygon(poly, fill)
	var closed := poly.duplicate()
	closed.append(poly[0])
	_canvas.draw_polyline(closed, edge, width)


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for v in poly:
		sum += v
	return sum / maxf(float(poly.size()), 1.0)


func _draw_declaration() -> bool:
	_resolve_example()
	var bt := _better_terrain()
	if _example_index < 0 or _example_ts == null or bt == null:
		return false
	var terrain: Dictionary = bt.get_terrain(_example_ts, _example_index)
	if not terrain.get("valid", false):
		return false
	var cells := _real_example()

	var sides: Array = bt.data.get_terrain_peering_cells(_example_ts, terrain.type)
	var pick := Vector2i(1 << 30, 1 << 30)
	var pick_td: TileData = null
	var mid := 0.0
	for c in _region:
		mid += float(c.x)
	mid /= maxf(float(_region.size()), 1.0)
	var closest := 1.0e20
	for c in _region:
		if not cells.has(c):
			continue
		if _region.has(c + Vector2i(0, -1)):
			continue
		if not _region.has(c + Vector2i(-1, 0)) or not _region.has(c + Vector2i(1, 0)):
			continue
		if _region.has(c + Vector2i(-1, -1)) or _region.has(c + Vector2i(1, -1)):
			continue
		var away: float = absf(float(c.x) - mid)
		if away < closest:
			closest = away
			pick = c
	if cells.has(pick):
		var src := _example_ts.get_source(int(cells[pick].source)) as TileSetAtlasSource
		if src != null:
			pick_td = src.get_tile_data(cells[pick].coord, 0)

	if pick_td == null:
		for c in cells:
			var src2 := _example_ts.get_source(int(cells[c].source)) as TileSetAtlasSource
			if src2 == null:
				continue
			var td2 := src2.get_tile_data(cells[c].coord, 0)
			if td2 == null:
				continue
			var n := 0
			for side in sides:
				if _example_index in bt.tile_peering_types(td2, side):
					n += 1
			if n > 0 and n < sides.size():
				pick = c
				pick_td = td2
				break
	if pick_td == null:
		return false

	var accepted := []
	for side in sides:
		if _example_index in bt.tile_peering_types(pick_td, side):
			accepted.append(side)

	var side_px := clampf(_canvas.size.x * 0.52, 140.0, 190.0)
	var box := Rect2(Vector2(30, 34), Vector2(side_px, side_px))
	var square := side_px / 8.0
	for gy in 8:
		for gx in 8:
			if (gx + gy) % 2 == 0:
				continue
			_canvas.draw_rect(Rect2(box.position + Vector2(gx, gy) * square,
				Vector2(square, square)), Color(1, 1, 1, 0.06))
	_blit_from(int(cells[pick].source), cells[pick].coord, box)

	var at := Transform2D(0.0, box.size, 0.0, box.position)
	var col := Color(terrain.color, 0.38)
	var line := Color(terrain.color, 0.95)
	var beat := 0.75
	var beats: int = accepted.size() + 3
	var phase := fmod(_anim, beat * float(beats)) / beat
	var done: int = clampi(int(phase) - 1, 0, accepted.size())
	if int(phase) >= 1:
		_mark(at * bt.data.peering_polygon(_example_ts, terrain.type, -1),
			Color(terrain.color, 0.10), line)
	for i in done:
		_mark(at * bt.data.peering_polygon(_example_ts, terrain.type, accepted[i]), col, line)
	_canvas.draw_rect(box, Color(1, 1, 1, 0.25), false, 1.0)

	var font := get_theme_default_font()
	var step_in := int(phase)
	if step_in >= 1 and step_in <= accepted.size():
		var poly: PackedVector2Array = at * bt.data.peering_polygon(
			_example_ts, terrain.type, accepted[step_in - 1])
		var target := _centroid(poly)
		var fresh := fmod(phase, 1.0) < 0.35
		if fresh:
			_mark(poly, Color(terrain.color, 0.62), Color(1, 1, 1, 0.9))
		_draw_pointer(target, fresh)
	elif step_in == 0:
		_draw_pointer(box.position + box.size * Vector2(1.15, 1.1), false)

	var caption := box.position + Vector2(0, box.size.y + 26)
	_canvas.draw_string(font, caption,
		"clicking each side that accepts \"%s\"" % String(terrain.name),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))
	_canvas.draw_string(font, caption + Vector2(0, 22),
		"%d of its %d, marked exactly as the atlas panel marks them" % [accepted.size(), sides.size()],
		HORIZONTAL_ALIGNMENT_LEFT, int(maxf(_canvas.size.x - 50.0, 300.0)), 12, Color(1, 1, 1, 0.55))
	return true


func _draw_all_tiles() -> bool:
	_resolve_example()
	var bt := _better_terrain()
	if _example_index < 0 or _example_ts == null or bt == null:
		return false
	var terrain: Dictionary = bt.get_terrain(_example_ts, _example_index)
	if not terrain.get("valid", false):
		return false
	var all_tiles: Array = bt.get_tile_sources_in_terrain(_example_ts, _example_index)
	if all_tiles.is_empty():
		return false
	var sides: Array = bt.data.get_terrain_peering_cells(_example_ts, terrain.type)

	var owned := []
	var already := {}
	for e in all_tiles:
		var td := e.get("td") as TileData
		if td == null:
			continue
		var key := ""
		var accepts := 0
		for side in sides:
			if _example_index in bt.tile_peering_types(td, side):
				key += "1"
				accepts += 1
			else:
				key += "0"
		if already.has(key):
			continue
		already[key] = true
		owned.append({"entry": e, "accepts": accepts})
	owned.sort_custom(func(a, b): return a.accepts < b.accepts)

	var count: int = mini(owned.size(), 48)
	var cols: int = maxi(int(ceil(sqrt(float(count)))), 1)
	var rows: int = int(ceil(float(count) / float(cols)))
	var room := Vector2(maxf(_canvas.size.x - 60.0, 240.0), maxf(_canvas.size.y - 108.0, 160.0))
	var step := minf(room.x / float(cols), room.y / float(rows))
	var pad := step * 0.12
	var box := step - pad
	var origin := Vector2(30, 34)
	var col := Color(terrain.color, 0.30)
	var line := Color(terrain.color, 0.70)
	for i in count:
		var entry: Dictionary = owned[i].entry
		var src := entry.get("source") as TileSetAtlasSource
		var td := entry.get("td") as TileData
		if src == null or td == null or src.texture == null:
			continue
		var coord: Vector2i = entry.coord
		if not src.has_tile(coord):
			continue
		@warning_ignore("integer_division")
		var where := Rect2(origin + Vector2(i % cols, i / cols) * step, Vector2(box, box))
		_canvas.draw_texture_rect_region(src.texture, where, src.get_tile_texture_region(coord))
		var at := Transform2D(0.0, where.size, 0.0, where.position)
		for side in sides:
			var poly: PackedVector2Array = at * bt.data.peering_polygon(_example_ts, terrain.type, side)
			if _example_index in bt.tile_peering_types(td, side):
				_mark(poly, col, line, 1.0)
			elif _example_index in bt.tile_not_peering_types(td, side):
				_not_mark(poly, terrain.color, bt)
	var font := get_theme_default_font()
	var under := origin + Vector2(0, float(rows) * step + 18)
	_canvas.draw_string(font, under,
		"what \"%s\" declares, one tile of each" % String(terrain.name),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))
	_canvas.draw_string(font, under + Vector2(0, 20),
		"%d different declarations across its %d tiles: edges first, filled last" % [
			owned.size(), all_tiles.size()],
		HORIZONTAL_ALIGNMENT_LEFT, int(maxf(_canvas.size.x - 50.0, 300.0)), 12, Color(1, 1, 1, 0.55))
	return true


func _draw_compass(sides: bool) -> void:
	if _draw_declaration():
		return
	var cs := _cell_size() * 1.6
	var origin := Vector2(60, 60)
	var cells := _real_example()
	var middle_cell := _real_middle()
	var real := middle_cell.x < (1 << 29)
	for gy in 3:
		for gx in 3:
			var where := Rect2(origin + Vector2(gx, gy) * cs, cs)
			var middle := gx == 1 and gy == 1
			if real:
				var cell := middle_cell + Vector2i(gx - 1, gy - 1)
				_blit_from(int(cells[cell].source), cells[cell].coord, where)
			else:
				_canvas.draw_rect(where, terrain_color if middle else Color(0.18, 0.18, 0.2))
			_canvas.draw_rect(where, Color(0, 0, 0, 0.45), false, 1.0)
	if sides:
		for i in ExemplarData.OFFSETS.size():
			var off: Vector2i = ExemplarData.OFFSETS[i]
			var where := Rect2(origin + Vector2(off.x + 1, off.y + 1) * cs, cs)
			_canvas.draw_rect(where, Color(1.0, 0.85, 0.3, 0.32))
			_canvas.draw_string(get_theme_default_font(), where.position + Vector2(cs.x * 0.5 - 8, cs.y * 0.5 + 5),
				DIR_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.9, 0.5))
	else:
		var mine := Rect2(origin + Vector2(1, 1) * cs, cs)
		_canvas.draw_rect(mine, Color(1.0, 0.85, 0.3, 0.25))
		_canvas.draw_rect(mine, Color(1.0, 0.85, 0.3), false, 2.0)
		for c: Vector2 in [Vector2(1, 1), Vector2(2, 1), Vector2(1, 2), Vector2(2, 2)]:
			var at: Vector2 = origin + c * cs
			_canvas.draw_circle(at, 6.0, Color(1.0, 0.85, 0.3))
			_canvas.draw_circle(at, 6.0, Color(0.1, 0.1, 0.12), false, 1.5)
	_canvas.draw_string(get_theme_default_font(), origin + Vector2(0, cs.y * 3 + 26),
		"the cell, and the eight places it declares for" if sides else "one cell, and its four corners",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))


func _not_mark(poly: PackedVector2Array, color: Color, bt) -> void:
	for shape in bt.data.not_marker(poly):
		_canvas.draw_colored_polygon(shape[0], bt.data.NOT_RED if shape[1] else Color(color, 0.9))


func _draw_not_sides() -> void:
	var bt := _better_terrain()
	if bt == null:
		return
	var font := get_theme_default_font()
	var diagram_size := 110.0
	var captions := ["first click: must match", "second click: must not"]
	for i in 2:
		var box := Rect2(Vector2(40 + i * (diagram_size + 70), 50), Vector2(diagram_size, diagram_size))
		_canvas.draw_rect(box, terrain_color.darkened(0.55))
		_canvas.draw_rect(box, Color(1, 1, 1, 0.25), false, 1.0)
		var at := Transform2D(0.0, box.size, 0.0, box.position)
		var top: PackedVector2Array = at * bt.data._peering_polygon_square_tiles(TileSet.CELL_NEIGHBOR_TOP_SIDE)
		if i == 0:
			_mark(top, Color(terrain_color, 0.55), Color(terrain_color, 0.95))
		else:
			_not_mark(top, terrain_color, bt)
		_canvas.draw_string(font, box.position + Vector2(0, diagram_size + 22), captions[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))
	_canvas.draw_string(font, Vector2(40, 50 + diagram_size + 48), "right click clears either one",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55))


func _draw_category() -> void:
	var origin := Vector2(50, 50)
	var w := 96.0
	var names := ["Grass", "Sand", "Dirt"]
	var cols := [Color(0.35, 0.68, 0.32), Color(0.85, 0.78, 0.45), Color(0.55, 0.42, 0.30)]
	for i in 3:
		_swatch(Rect2(origin + Vector2(0, i * 44), Vector2(w, 34)), cols[i], names[i])
		_canvas.draw_string(get_theme_default_font(), origin + Vector2(w + 12, i * 44 + 23),
			"->", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.55))
	var box := Rect2(origin + Vector2(w + 44, 44), Vector2(w + 20, 34))
	_canvas.draw_rect(box, Color(0.25, 0.25, 0.3))
	_canvas.draw_rect(box, Color(1.0, 0.85, 0.3), false, 2.0)
	_canvas.draw_string(get_theme_default_font(), box.position + Vector2(10, 23),
		"Ground", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.9, 0.6))
	_canvas.draw_string(get_theme_default_font(), origin + Vector2(0, 160),
		"a category is never drawn, only answered to", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1, 1, 1, 0.6))


func _draw_category_use() -> void:
	var cs := _cell_size() * 1.5
	var origin := Vector2(46, 56)
	var cols := [Color(0.35, 0.68, 0.32), Color(0.85, 0.78, 0.45), Color(0.55, 0.42, 0.30)]
	var names := ["Grass", "Sand", "Dirt"]
	for i in 3:
		var where := Rect2(origin + Vector2(i * 2.2, 0) * cs, cs * Vector2(2.0, 1.0))
		_swatch(where, cols[i], names[i])
		var edge := Rect2(where.position + Vector2(0, cs.y), where.size * Vector2(1, 0.45))
		_canvas.draw_rect(edge, terrain_color)
		_canvas.draw_rect(edge, Color(1.0, 0.85, 0.3), false, 2.0)
	_canvas.draw_string(get_theme_default_font(), origin + Vector2(0, cs.y * 2.2),
		"one and the same border tile, because it accepts \"Ground\"",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))


func _draw_decoration_use() -> void:
	var cs := _cell_size() * 1.1
	var origin := Vector2(30, 60)
	for half in 2:
		var at := origin + Vector2(half * (cs.x * 4.0 + 44), 0)
		for y in 3:
			for x in 3:
				var where := Rect2(at + Vector2(x, y) * cs, cs)
				var empty := (x == 1 and y == 0) or (x == 0 and y == 2) or (x == 2 and y == 1)
				_canvas.draw_rect(where, Color(0.2, 0.2, 0.24) if empty else terrain_color)
				_canvas.draw_rect(where, Color(0, 0, 0, 0.35), false, 1.0)
				if empty and half == 1:
					_canvas.draw_circle(where.position + where.size * 0.5, cs.x * 0.22,
						Color(1.0, 0.85, 0.3))
		_canvas.draw_string(get_theme_default_font(), at + Vector2(0, cs.y * 3 + 22),
			"what you painted" if half == 0 else "what decoration adds",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
	_canvas.draw_string(get_theme_default_font(), origin + Vector2(cs.x * 3.2, cs.y * 1.6),
		"->", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.6))


func _draw_single() -> void:
	var cs := _cell_size() * 1.4
	var origin := Vector2(60, 60)
	for y in 4:
		for x in 6:
			var where := Rect2(origin + Vector2(x, y) * cs, cs)
			_canvas.draw_rect(where, Color(1, 1, 1, 0.05))
			_canvas.draw_rect(where, Color(1, 1, 1, 0.10), false, 1.0)
	for c in [Vector2i(1, 1), Vector2i(3, 0), Vector2i(4, 2), Vector2i(2, 3)]:
		var where := Rect2(origin + Vector2(c) * cs, cs)
		_canvas.draw_rect(where.grow(-2), terrain_color)
		_canvas.draw_rect(where.grow(-2), Color(0, 0, 0, 0.35), false, 1.0)
	_canvas.draw_string(get_theme_default_font(), origin + Vector2(0, cs.y * 4 + 26),
		"the tile you picked, wherever you put it", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1, 1, 1, 0.6))


func _draw_scatter(blocks: bool) -> void:
	var cs := _cell_size() * 1.15
	var origin := Vector2(40, 46)
	var cols := 7
	var rows := 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260921
	var taken := {}
	if blocks:
		for at in [Vector2i(1, 0), Vector2i(4, 2)]:
			for d in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
				taken[at + d] = at
	for y in rows:
		for x in cols:
			var c := Vector2i(x, y)
			var where := Rect2(origin + Vector2(c) * cs, cs)
			_canvas.draw_rect(where, Color(terrain_color, 0.16))
			_canvas.draw_rect(where, Color(1, 1, 1, 0.12), false, 1.0)
			if taken.has(c):
				continue
			if not blocks and rng.randf() < 0.28:
				_canvas.draw_circle(where.position + where.size * 0.5, cs.x * 0.2, terrain_color)
	if blocks:
		for at in taken.values():
			var block := Rect2(origin + Vector2(at) * cs, cs * 2.0)
			_canvas.draw_rect(block.grow(-2), terrain_color)
			_canvas.draw_rect(block.grow(-2), Color(0, 0, 0, 0.35), false, 1.0)
		var out := Rect2(origin + Vector2(cols - 1, rows - 1) * cs, cs * 2.0)
		_canvas.draw_rect(out.grow(-2), Color(1.0, 0.45, 0.35, 0.25))
		_canvas.draw_rect(out.grow(-2), Color(1.0, 0.45, 0.35), false, 1.5)
		_canvas.draw_string(get_theme_default_font(), out.position + Vector2(cs.x * 2.1, cs.y * 0.8),
			"does not fit: nothing is placed", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(1.0, 0.45, 0.35))
	_canvas.draw_string(get_theme_default_font(), origin + Vector2(0, cs.y * rows + 26),
		"the region you painted, and one throw of the bag per cell",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))


func _draw_decoration() -> void:
	var cs := _cell_size() * 1.3
	var origin := Vector2(50, 50)
	for y in 4:
		for x in 5:
			var where := Rect2(origin + Vector2(x, y) * cs, cs)
			var empty := (x == 1 and y == 1) or (x == 3 and y == 2)
			_canvas.draw_rect(where, Color(0.2, 0.2, 0.24) if empty else terrain_color)
			_canvas.draw_rect(where, Color(0, 0, 0, 0.35), false, 1.0)
			if empty:
				var mid := where.position + where.size * 0.5
				_canvas.draw_circle(mid, cs.x * 0.22, Color(1.0, 0.85, 0.3))
	_canvas.draw_string(get_theme_default_font(), origin + Vector2(0, cs.y * 4 + 26),
		"terrain, and the empty cells it fills", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1, 1, 1, 0.6))


func _draw_object(joined: bool) -> void:
	var lone := _lone_example()
	var patch := _real_example()
	var object_size := ObjectTerrain.object_size(_example_ts, _example_index) if _example_ts else Vector2i(2, 2)
	if object_size.x <= 0:
		object_size = Vector2i(2, 2)
	var font := get_theme_default_font()
	var cs := _cell_size() * 1.5
	var origin := Vector2(34, 44)

	if lone.is_empty():
		var blocks := 3 if joined else 1
		for bi in blocks:
			var at: Vector2 = origin + Vector2(bi * cs.x * float(object_size.x), 0)
			for y in object_size.y:
				for x in object_size.x:
					var where := Rect2(at + Vector2(x, y) * cs, cs)
					_canvas.draw_rect(where, terrain_color)
					_canvas.draw_rect(where, Color(0, 0, 0, 0.3), false, 1.0)
			_canvas.draw_rect(Rect2(at, cs * Vector2(object_size)), Color(1.0, 0.85, 0.3), false, 2.0)
		_canvas.draw_string(font, origin + Vector2(0, cs.y * float(object_size.y) + 26),
			"this tileset has no object terrain to show", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(1, 1, 1, 0.6))
		return

	var span := cs * Vector2(object_size)
	_draw_block(lone, Vector2i.ZERO, object_size, origin, cs)
	_canvas.draw_rect(Rect2(origin, span), Color(1.0, 0.85, 0.3), false, 2.0)
	_canvas.draw_string(font, origin + Vector2(0, span.y + 22), "LONE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.3))
	if not joined:
		_canvas.draw_string(font, origin + Vector2(0, span.y + 46),
			"one block, %dx%d cells, placed as a single piece" % [object_size.x, object_size.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55))
		return

	var second := origin + Vector2(span.x + 46, 0)
	_draw_block(patch, object_size, object_size, second, cs)
	_canvas.draw_rect(Rect2(second, span), Color(0.45, 0.8, 1.0), false, 2.0)
	_canvas.draw_string(font, second + Vector2(0, span.y + 22), "JOINED",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.8, 1.0))
	_canvas.draw_string(font, origin + Vector2(0, span.y + 46),
		"nothing of its kind beside it, and one with its kind on either side",
		HORIZONTAL_ALIGNMENT_LEFT, int(maxf(_canvas.size.x - 50.0, 300.0)), 12, Color(1, 1, 1, 0.6))
	_canvas.draw_string(font, origin + Vector2(0, span.y + 66),
		"the same object, marked twice in the atlas. Each gets used where it fits",
		HORIZONTAL_ALIGNMENT_LEFT, int(maxf(_canvas.size.x - 50.0, 300.0)), 12, Color(1, 1, 1, 0.5))


func _draw_block(cells: Dictionary, from: Vector2i, block_size: Vector2i, at: Vector2, cs: Vector2) -> void:
	for y in block_size.y:
		for x in block_size.x:
			var cell := from + Vector2i(x, y)
			if not cells.has(cell):
				continue
			_blit_from(int(cells[cell].source), cells[cell].coord,
				Rect2(at + Vector2(x, y) * cs, cs))

#endregion


func _draw_drawing(outline_all: bool) -> void:
	var cs := _cell_size()
	var origin := Vector2(30, 26)
	if not _art:
		for y in 5:
			for x in 5:
				var cell := Vector2i(x, y)
				var where := Rect2(origin + Vector2(x, y) * cs, cs)
				var role := ExemplarData.role_for(_canonical(), cell)
				if role == "":
					_canvas.draw_rect(where, Color(1, 1, 1, 0.05))
					continue
				_canvas.draw_rect(where, _schematic(role))
				_canvas.draw_rect(where, Color(0, 0, 0, 0.35), false, 1.0)
				if outline_all:
					_canvas.draw_rect(where, Color(1.0, 0.85, 0.3, 0.85), false, 2.0)
		return

	var block: Array = _table.block
	var mine := {}
	if not _overview:
		for at in _table.get("slots", {}).get(_role, []):
			mine[Vector2i(int(at[0]), int(at[1]))] = true
	var at_cell := {}
	for role in _table.slots:
		var run: Array = _table.slots[role]
		for i in run.size():
			at_cell[Vector2i(int(run[i][0]), int(run[i][1]))] = [role, i]
	for y in int(block[3]):
		for x in int(block[2]):
			var cell := Vector2i(int(block[0]) + x, int(block[1]) + y)
			var where := Rect2(origin + Vector2(x, y) * cs, cs)
			if not at_cell.has(cell):
				_canvas.draw_rect(where, Color(1, 1, 1, 0.05))
				continue
			var role: String = at_cell[cell][0]
			var index: int = at_cell[cell][1]
			var run: Array = _table.lines.get(role, [])
			if index < run.size():
				_blit(run[index], where)
			if not _overview and not mine.has(cell):
				_canvas.draw_rect(where, Color(0, 0, 0, 0.55))
			if outline_all:
				_canvas.draw_rect(where, Color(1.0, 0.85, 0.3, 0.85), false, 2.0)
	for cell in mine:
		var where := Rect2(origin + Vector2(cell - Vector2i(int(block[0]), int(block[1]))) * cs, cs)
		_canvas.draw_rect(where, Color(1.0, 0.85, 0.3), false, 3.0)


static func _canonical() -> Dictionary:
	var r := {}
	for y in range(1, 4):
		for x in range(1, 4):
			r[Vector2i(x, y)] = true
	return r


func _draw_neighbourhood() -> void:
	var cs := _cell_size()
	var origin := Vector2(30, 30)
	if not _has_example:
		_canvas.draw_string(get_theme_default_font(), origin + Vector2(0, 20),
			"This square never comes up on a plain pond.", HORIZONTAL_ALIGNMENT_LEFT,
			-1, 15, Color(1, 1, 1, 0.6))
		return
	for gy in 3:
		for gx in 3:
			var cell := _example + Vector2i(gx - 1, gy - 1)
			var where := Rect2(origin + Vector2(gx, gy) * cs, cs)
			var mine := _region.has(cell)
			_canvas.draw_rect(where, terrain_color if mine else Color(0.18, 0.18, 0.2))
			_canvas.draw_rect(where, Color(0, 0, 0, 0.5), false, 1.0)
	var middle := Rect2(origin + Vector2(1, 1) * cs, cs)
	_canvas.draw_rect(middle, Color(1.0, 0.85, 0.3), false, 3.0)
	var run: Array = _table.lines.get(_role, [])
	if not run.is_empty():
		var to := Rect2(origin + Vector2(3.6, 1) * cs, cs)
		_canvas.draw_string(get_theme_default_font(), origin + Vector2(3.1, 1.6) * cs,
			"→", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.8))
		_blit(run[0], to)
		_canvas.draw_rect(to, Color(1.0, 0.85, 0.3), false, 3.0)
	var legend := origin + Vector2(0, 3.5) * cs
	_canvas.draw_rect(Rect2(legend, Vector2(16, 16)), terrain_color)
	_canvas.draw_string(get_theme_default_font(), legend + Vector2(24, 13),
		"terrain", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	_canvas.draw_rect(Rect2(legend + Vector2(100, 0), Vector2(16, 16)), Color(0.18, 0.18, 0.2))
	_canvas.draw_string(get_theme_default_font(), legend + Vector2(124, 13),
		"not terrain", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))


func _draw_landing(mark: bool, as_nine: bool) -> void:
	var cs := _cell_size()
	var origin := Vector2(24, 20)
	var seen := {}
	for c in _region:
		seen[c] = true
		for off in ExemplarData.OFFSETS:
			seen[c + off] = true
	var mine := []
	for c in seen:
		var role := ExemplarData.role_for(_region, c)
		if role == "":
			continue
		var where := Rect2(origin + Vector2(c) * cs, cs)
		if _art:
			var tile := ExemplarData.tile_for(_table, _region, c)
			if tile.is_empty():
				continue
			_blit([tile.coord.x, tile.coord.y], where)
		else:
			_canvas.draw_rect(where, _schematic(role))
			_canvas.draw_rect(where, Color(0, 0, 0, 0.35), false, 1.0)
		if role == _role:
			mine.append(c)
	if not mark:
		return
	if as_nine:
		if not _has_example:
			return
		for gy in 3:
			for gx in 3:
				var cell := _example + Vector2i(gx - 1, gy - 1)
				var where := Rect2(origin + Vector2(cell) * cs, cs)
				_canvas.draw_rect(where, Color(1.0, 0.85, 0.3, 0.22))
				_canvas.draw_rect(where, Color(1.0, 0.85, 0.3, 0.7), false, 1.0)
		_canvas.draw_rect(Rect2(origin + Vector2(_example) * cs, cs), Color(1.0, 0.85, 0.3), false, 3.0)
		return
	for c in mine:
		_canvas.draw_rect(Rect2(origin + Vector2(c) * cs, cs), Color(1.0, 0.85, 0.3, 0.30))
		_canvas.draw_rect(Rect2(origin + Vector2(c) * cs, cs), Color(1.0, 0.85, 0.3), false, 2.0)


#endregion
