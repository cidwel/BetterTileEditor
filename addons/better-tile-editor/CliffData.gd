@tool
extends RefCounted

const ROWS := ["only", "top", "middle", "base"]

const CASES := [
	"single",
	"l_end",
	"r_end",
	"mid",
	"l_plat",
	"r_plat",
	"l_step_hi",
	"l_step_lo",
	"r_step_hi",
	"r_step_lo",
	"notch",
	"l_plat_end",
	"r_plat_end",
	"plat_step_hi",
	"plat_step_lo",
	"step_hi_plat",
	"step_lo_plat",
	"step_hi_step_hi",
	"step_hi_step_lo",
	"step_lo_step_hi",
	"step_lo_step_lo",
	"step_hi_open",
	"step_lo_open",
	"open_step_hi",
	"open_step_lo",
]

const _CASE_OF := {
	"open,open": "single", "open,face": "l_end", "face,open": "r_end",
	"face,face": "mid", "plat,face": "l_plat", "face,plat": "r_plat",
	"plat,plat": "notch", "plat,open": "l_plat_end", "open,plat": "r_plat_end",
	"step_hi,face": "l_step_hi", "step_lo,face": "l_step_lo",
	"face,step_hi": "r_step_hi", "face,step_lo": "r_step_lo",
	"plat,step_hi": "plat_step_hi", "plat,step_lo": "plat_step_lo",
	"step_hi,plat": "step_hi_plat", "step_lo,plat": "step_lo_plat",
	"step_hi,step_hi": "step_hi_step_hi", "step_hi,step_lo": "step_hi_step_lo",
	"step_lo,step_hi": "step_lo_step_hi", "step_lo,step_lo": "step_lo_step_lo",
	"step_hi,open": "step_hi_open", "step_lo,open": "step_lo_open",
	"open,step_hi": "open_step_hi", "open,step_lo": "open_step_lo",
}


static var _fallback_cache := {}


static var _sides_cache := {}

static func case_sides(case_name: String) -> PackedStringArray:
	if _sides_cache.has(case_name):
		return _sides_cache[case_name]
	var out := PackedStringArray()
	for k in _CASE_OF:
		if _CASE_OF[k] == case_name:
			out = k.split(",")
			break
	_sides_cache[case_name] = out
	return out


## Equal-height walls cannot produce base/step_hi or top/step_lo slots.
static func slot_reachable(row: String, case_name: String, height: int) -> bool:
	var rows := rows_for_height(height)
	if rows.is_empty():
		return false
	var sides := case_sides(case_name)
	if sides.size() != 2:
		return true
	var first_row: String = rows[0]
	var last_row: String = rows[rows.size() - 1]
	for side in sides:
		if side == "step_hi" and row == last_row:
			return false
		if side == "step_lo" and row == first_row:
			return false
	return true


const SIMPLE_SIDES := ["E", "W", "G"]
const SIMPLE_ROWS := ["wall", "ground"]

static func side_class(side: String) -> String:
	match side:
		"open", "step_hi": return "E"
		"plat": return "G"
		_: return "W"

static func simple_group(row: String, case_name: String) -> String:
	var sides := case_sides(case_name)
	if sides.size() != 2:
		return ""
	var ground: bool = row == "base" or row == "only"
	return "%s|%s%s" % ["ground" if ground else "wall", side_class(sides[0]), side_class(sides[1])]


static func simple_members(group: String) -> Array:
	var out := []
	for row in ROWS:
		var h: int = 1 if row == "only" else (3 if row == "middle" else 2)
		for c in CASES:
			if not slot_reachable(row, c, h):
				continue
			if simple_group(row, c) == group:
				out.append(slot_key(row, c))
	return out


static func fallback_case(case_name: String) -> String:
	if _fallback_cache.has(case_name):
		return _fallback_cache[case_name]
	var found := _derive_fallback(case_name)
	_fallback_cache[case_name] = found
	return found


static func _derive_fallback(case_name: String) -> String:
	for key in _CASE_OF:
		if _CASE_OF[key] != case_name:
			continue
		var sides: PackedStringArray = key.split(",")
		var l := _step_fallback(sides[0])
		var r := _step_fallback(sides[1])
		if l == sides[0] and r == sides[1]:
			return ""
		return _CASE_OF.get("%s,%s" % [l, r], "")
	return ""


static func resolve_tile(cfg: Dictionary, row: String, case_name: String) -> Dictionary:
	var tile := slot_tile(cfg, row, case_name)
	if not tile.is_empty():
		return tile
	# Bottom-up matrices have no separate top; an empty top slot uses the body.
	if row == "top" and bool(cfg.get("from_bottom", false)):
		var body := slot_tile(cfg, "middle", case_name)
		if not body.is_empty():
			return body
	var back := fallback_case(case_name)
	var coarser := slot_tile(cfg, row, back) if back != "" else {}
	if coarser.is_empty() and back != "" and row == "top" and bool(cfg.get("from_bottom", false)):
		coarser = slot_tile(cfg, "middle", back)
	return coarser

static func slot_key(row: String, case_name: String) -> String:
	return "%s/%s" % [row, case_name]

static func rows_for_height(height: int) -> Array:
	if height <= 0: return []
	if height == 1: return ["only"]
	var out := ["top"]
	for _i in range(height - 2): out.append("middle")
	out.append("base")
	return out

## Face cells continue for the full height, even where the painted region resumes below.
static func face_map(cells: Array, height: int) -> Dictionary:
	var plateau := {}
	for c in cells: plateau[c] = true
	var rows := rows_for_height(height)
	var bands := []
	for d in rows.size():
		bands.append(bands[d - 1] + 1 if d > 0 and rows[d] == rows[d - 1] else 0)
	var out := {}
	for e in south_edges(cells):
		for d in rows.size():
			out[e + Vector2i(0, 1 + d)] = {
				"row": rows[d], "edge": e.y, "band": bands[d],
				"rise": rows.size() - 1 - d,
			}
	return out


static func block_size(tile: Dictionary) -> Vector2i:
	var v = tile.get("size", null)
	if v == null:
		return Vector2i.ONE
	var size := Vector2i(v)
	return Vector2i(maxi(1, size.x), maxi(1, size.y))


static func matrix_foot(tile: Dictionary, row: String) -> int:
	if tile.has("foot"):
		return int(tile.foot)
	return 0 if row == "base" or row == "only" else 1


static func block_coord(tile: Dictionary, phase: int, vphase: int, from_bottom := false) -> Vector2i:
	var base: Vector2i = tile.get("coord", Vector2i.ZERO)
	var size := block_size(tile)
	if size.x <= 1 and size.y <= 1:
		return base
	var row: int = posmod(vphase, size.y)
	if from_bottom:
		row = size.y - 1 - row
	return base + Vector2i(posmod(phase, size.x), row)


static func face_rows(faces: Dictionary) -> Array:
	var lines := {}
	for f in faces:
		var key := Vector2i(f.y, int(faces[f].edge))
		if not lines.has(key):
			lines[key] = []
		lines[key].append(f)
	var rows := lines.values()
	for row in rows:
		row.sort_custom(func(a, b): return a.x < b.x)
	return rows


static func slot_runs(plateau: Dictionary, faces: Dictionary) -> Dictionary:
	var out := {}
	for row in face_rows(faces):
		var phase := 0
		var prev_x := -9999
		var prev_slot := ""
		for f in row:
			var case_name := case_at(plateau, faces, f)
			var slot := slot_key(faces[f].row, case_name)
			if f.x == prev_x + 1 and slot == prev_slot:
				phase += 1
			else:
				phase = 0
			out[f] = {"case": case_name, "phase": phase}
			prev_x = f.x
			prev_slot = slot
	return out

static func _side(plateau: Dictionary, faces: Dictionary, coord: Vector2i, dx: int) -> String:
	var n := coord + Vector2i(dx, 0)
	if faces.has(n) and faces[n].edge == faces[coord].edge:
		return "face"
	if faces.has(n):
		return "step_hi" if faces[n].edge < faces[coord].edge else "step_lo"
	if plateau.has(n):
		return "plat"
	return "open"

static func case_at(plateau: Dictionary, faces: Dictionary, coord: Vector2i) -> String:
	var l := _side(plateau, faces, coord, -1)
	var r := _side(plateau, faces, coord, 1)
	var key := "%s,%s" % [l, r]
	if _CASE_OF.has(key):
		return _CASE_OF[key]
	l = _step_fallback(l)
	r = _step_fallback(r)
	return _CASE_OF["%s,%s" % [l, r]]


static func _step_fallback(side: String) -> String:
	if side == "step_hi": return "face"
	if side == "step_lo": return "plat"
	return side

static func south_edges(cells: Array) -> Array:
	var set := {}
	for c in cells: set[c] = true
	var out := []
	for c in cells:
		if not set.has(c + Vector2i(0, 1)): out.append(c)
	out.sort()
	return out

const FIXTURES := [
	{
		"name": "Compact",
		"mask": [
			"..........................",
			"..XXX..XX.XXX.XX..XXX.....",
			"..XXXXXXX.XXXXXXXXXXXXXX..",
			"...X.XXX....X....XXX..XX..",
			"...X...XXXXXXX.XXXX...X...",
			"...X...XXX.XXXXX......X...",
			"...X........XXXX......X...",
			".XXX..................X...",
			".XXX..................XXX.",
			"..........................",
		],
	},
	{
		"name": "Cave plateau",
		"mask": [
			"........................................",
			".............XXXXXXXXXXXXXXXXXXXXXX.....",
			"...........XXXXXXXXXXXXXXXXXXXXXXXXXX...",
			"...........XXXXXXXXXXXXXXXXXXXXXXXXXX...",
			".....XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX..",
			".....XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX..",
			".XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX..",
			".XXXXXXX.XXXXXXXXXXXXXXXXXXXXXXXXXXXXX..",
			".XXX.XXX.XXXXXXXXXXXXXXXXX.XXXXX.XXXXX..",
			".....XXX.XXXXXXXXX..XXXXXX.XXXXX.XXX....",
			"..........XXXXXXXX..XXXXX.....XX.XXX....",
			"..............................XXXXXX....",
			"........................................",
		],
	},
	{
		"name": "Stepped mound",
		"mask": [
			"..........................",
			"..........XXXXXX..........",
			"........XXXXXXXXXX........",
			"......XXXXXXXXXXXXXX......",
			"....XXXXXXXXXXXXXXXXXX....",
			"..XXXXXXXXXXXXXXXXXXXXXX..",
			"..XXXXXXXXXXXXXXXXXXXXXX..",
			"...XXXXXXXXXXXXXXXXXXXX...",
			"....XXXXXXXXXXXXXXXXXX....",
			".....XXXXXXXXXXXXXXXX.....",
			".......XXXXXXXXXXXX.......",
			"........XXXX.XXXXX........",
			"..........................",
		],
	},
]


const SHAPES_SETTING := "better_terrain/cliff/shapes_scene"
const SHAPES_LEGACY := "res://Maps/Tilesets/cliff_preview_shapes.tscn"
const SHAPES_DEFAULT := "res://cliff_preview_shapes.tscn"

static func shapes_scene() -> String:
	var set_to := String(ProjectSettings.get_setting(SHAPES_SETTING, ""))
	if set_to != "":
		return set_to
	if ResourceLoader.exists(SHAPES_LEGACY):
		return SHAPES_LEGACY
	return SHAPES_DEFAULT


static func ensure_shapes_dir() -> String:
	var path := shapes_scene()
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return path


static var _captured: Array = []


static func set_captured(cells: Array) -> void:
	_captured = mask_from_cells(cells)


static func has_captured() -> bool:
	return not _captured.is_empty()


static func shapes() -> Array:
	var out := []
	if not _captured.is_empty():
		out.append({"name": "From the map", "mask": _captured.duplicate()})
	# Project shapes first, then the built-in ones it doesnt redraw.
	var painted := _painted_shapes()
	out.append_array(painted)
	var drawn := {}
	for shape in painted:
		drawn[shape.name] = true
	for shape in FIXTURES:
		if not drawn.has(shape.name):
			out.append(shape.duplicate(true))
	return out


static func _painted_shapes() -> Array:
	if not ResourceLoader.exists(shapes_scene()):
		return []
	var packed = load(shapes_scene())
	if packed == null:
		return []
	var root = packed.instantiate()
	var out := []
	for child in root.get_children():
		if not (child is TileMapLayer):
			continue
		var mask := _mask_from_layer(child)
		if not mask.is_empty():
			out.append({"name": str(child.name), "mask": mask})
	root.free()
	return out


static func _mask_from_layer(layer: TileMapLayer) -> Array:
	return mask_from_cells(layer.get_used_cells())


static func mask_from_cells(cells: Array) -> Array:
	if cells.is_empty():
		return []
	var r := Rect2i(cells[0], Vector2i.ONE)
	for c in cells:
		r = r.expand(c)
		r = r.expand(c + Vector2i.ONE)
	var filled := {}
	for c in cells:
		filled[c] = true
	var out := []
	for y in range(r.position.y - 1, r.end.y + 1):
		var row := ""
		for x in range(r.position.x - 1, r.end.x + 1):
			row += "X" if filled.has(Vector2i(x, y)) else "."
		out.append(row)
	return out


## The narrow-case column must span the wall height to exercise both plat_end cases.
static func narrow_block(width: int) -> Array:
	var rows := []
	var blank := ""
	for _x in width:
		blank += "."
	rows.append(blank)
	rows.append(_row(width, [1, 2, width - 3, width - 2]))
	for _i in 5:
		rows.append(_row(width, [1, width - 2]))
	rows.append(blank)
	rows.append(_row(width, [4, width - 5]))
	rows.append(blank)
	return rows


static func _row(width: int, xs: Array) -> String:
	var out := ""
	for x in width:
		out += "X" if xs.has(x) else "."
	return out


static func fixture(index: int, with_narrow: bool) -> Array:
	var all := shapes()
	var entry: Dictionary = all[clampi(index, 0, all.size() - 1)]
	var mask: Array = entry.mask.duplicate()
	if with_narrow:
		mask.append_array(narrow_block(mask[0].length()))
	return mask


static func mask_cells(mask: Array) -> Array:
	var out := []
	for y in mask.size():
		for x in mask[y].length():
			if mask[y][x] == "X": out.append(Vector2i(x, y))
	return out

static func coverage(mask: Array, height: int) -> Dictionary:
	var cells := mask_cells(mask)
	var plateau := {}
	for c in cells: plateau[c] = true
	var faces := face_map(cells, height)
	var out := {}
	for f in faces.keys():
		var k = case_at(plateau, faces, f)
		out[k] = out.get(k, 0) + 1
	return out


const CLIFF_META := &"_better_terrain_cliffs"

static func all_configs(ts: TileSet) -> Dictionary:
	return ts.get_meta(CLIFF_META, {}) if ts else {}

## The entry exacaly as stored, without following `inherits`.
static func raw_config(ts: TileSet, terrain_name: String) -> Dictionary:
	return all_configs(ts).get(terrain_name, {})


static func inherits_from(ts: TileSet, terrain_name: String) -> String:
	return str(raw_config(ts, terrain_name).get("inherits", ""))


## Follow inheritance until the ownzr, last valid link or cycle is reached.
static func inherit_source(ts: TileSet, terrain_name: String) -> String:
	var seen := {terrain_name: true}
	var current := terrain_name
	while true:
		var next := inherits_from(ts, current)
		if next == "" or seen.has(next) or not all_configs(ts).has(next):
			return current
		seen[next] = true
		current = next
	return current


static func would_cycle(ts: TileSet, terrain_name: String, candidate: String) -> bool:
	if candidate == terrain_name:
		return true
	var seen := {candidate: true}
	var current := candidate
	while true:
		var next := inherits_from(ts, current)
		if next == "":
			return false
		if next == terrain_name:
			return true
		if seen.has(next):
			return false
		seen[next] = true
		current = next
	return false


static func inheritable_sources(ts: TileSet, terrain_name: String) -> Array:
	var out := []
	for name in all_configs(ts).keys():
		if name == terrain_name or would_cycle(ts, terrain_name, name):
			continue
		var cfg: Dictionary = all_configs(ts)[name]
		if not cfg.get("slots", {}).is_empty():
			out.append(name)
	out.sort()
	return out


static func set_inherit(ts: TileSet, terrain_name: String, source: String) -> void:
	var cfg := raw_config(ts, terrain_name).duplicate(true)
	if source == "":
		cfg.erase("inherits")
	else:
		cfg["inherits"] = source
	store_config(ts, terrain_name, cfg)


static func make_local(ts: TileSet, terrain_name: String) -> void:
	var resolved := config_of(ts, terrain_name).duplicate(true)
	resolved.erase("inherits")
	store_config(ts, terrain_name, resolved)


static func config_of(ts: TileSet, terrain_name: String) -> Dictionary:
	var cfg: Dictionary = all_configs(ts).get(inherit_source(ts, terrain_name), {})
	var out: Dictionary = cfg.duplicate(true)
	out.erase("inherits")
	out.merge({
		"height": cfg.get("height", 2),
		"slots": cfg.get("slots", {}),
		# Default to top-down repetition for sheets saved before from_bottom existed.
		"from_bottom": bool(cfg.get("from_bottom", false)),
	}, true)
	return out

static func store_config(ts: TileSet, terrain_name: String, cfg: Dictionary) -> void:
	if not ts: return
	var all := all_configs(ts).duplicate(true)
	all[terrain_name] = cfg
	ts.set_meta(CLIFF_META, all)
	ts.emit_changed()

## An empty slot forbids that shape unless a fallback supplies its tile.
static func slot_tile(cfg: Dictionary, row: String, case_name: String) -> Dictionary:
	return cfg.get("slots", {}).get(slot_key(row, case_name), {})

static func set_slot_tile(cfg: Dictionary, row: String, case_name: String, tile: Dictionary) -> void:
	if not cfg.has("slots"): cfg["slots"] = {}
	if tile.is_empty(): cfg["slots"].erase(slot_key(row, case_name))
	else: cfg["slots"][slot_key(row, case_name)] = tile

static func missing_slots(cfg: Dictionary, height: int) -> Array:
	var out := []
	for row in rows_for_height(height):
		for c in CASES:
			var k := slot_key(row, c)
			if out.has(k):
				continue
			if not slot_reachable(row, c, height):
				continue
			if resolve_tile(cfg, row, c).is_empty():
				out.append(k)
	return out


static func terrain_names(ts: TileSet) -> Array:
	if ts == null or not ts.has_meta(&"_better_terrain"): return []
	var out := []
	for t in ts.get_meta(&"_better_terrain").get(&"terrains", []):
		out.append(str(t[0]))
	return out
