@tool
extends RefCounted

const SupportLayers := preload("res://addons/better-tile-editor/SupportLayers.gd")


const TERRAIN_META = &"_better_terrain"

static var _objects_cache := {}


static func invalidate(ts: TileSet) -> void:
	_objects_cache.erase(ts)


const TYPE_OBJECT := 4  # BetterTerrain.TerrainType.OBJECT


#region Blocks worked out from the marked tiles

static func tiles_of_terrain(ts: TileSet, terrain_id: int) -> Dictionary:
	var out := {}
	if ts == null:
		return out
	for s in ts.get_source_count():
		var sid := ts.get_source_id(s)
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src == null:
			continue
		var coords := {}
		for c in src.get_tiles_count():
			var coord := src.get_tile_id(c)
			var td := src.get_tile_data(coord, 0)
			if td == null or not td.has_meta(TERRAIN_META):
				continue
			var meta = td.get_meta(TERRAIN_META)
			if typeof(meta) == TYPE_DICTIONARY and meta.get("type", -2) == terrain_id:
				coords[coord] = true
		if not coords.is_empty():
			out[sid] = coords
	return out


static func detect_blocks(ts: TileSet, terrain_id: int, size: Vector2i = Vector2i.ZERO) -> Array:
	var out := []
	var by_source := tiles_of_terrain(ts, terrain_id)
	for sid in by_source:
		var pending: Dictionary = by_source[sid]
		while not pending.is_empty():
			var seed_cell = pending.keys()[0]
			var group := {}
			var queue := [seed_cell]
			while not queue.is_empty():
				var c: Vector2i = queue.pop_back()
				if not pending.has(c) or group.has(c):
					continue
				group[c] = true
				pending.erase(c)
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if pending.has(c + d):
						queue.push_back(c + d)

			var minx := 1 << 30; var miny := 1 << 30
			var maxx := -(1 << 30); var maxy := -(1 << 30)
			for c: Vector2i in group:
				minx = mini(minx, c.x); maxx = maxi(maxx, c.x)
				miny = mini(miny, c.y); maxy = maxi(maxy, c.y)
			var rect := Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)
			var filled: bool = group.size() == rect.size.x * rect.size.y

			if size.x > 0 and size.y > 0 and filled \
					and rect.size.x % size.x == 0 and rect.size.y % size.y == 0:
				for by in rect.size.y / size.y:
					for bx in rect.size.x / size.x:
						out.push_back({
							"source_id": sid,
							"rect": Rect2i(rect.position + Vector2i(bx, by) * size, size),
							"full": true,
						})
			else:
				out.push_back({"source_id": sid, "rect": rect, "full": filled})
	out.sort_custom(func(a, b):
		if a["rect"].position.y != b["rect"].position.y:
			return a["rect"].position.y < b["rect"].position.y
		return a["rect"].position.x < b["rect"].position.x)
	return out

#endregion


#region Objects defined in the TileSet

static func get_objects(ts: TileSet) -> Array:
	if _objects_cache.has(ts):
		return _objects_cache[ts]
	if ts == null or not ts.has_meta(TERRAIN_META):
		return []
	var meta = ts.get_meta(TERRAIN_META)
	if typeof(meta) != TYPE_DICTIONARY:
		return []
	var out := []
	var terrains: Array = meta.get("terrains", [])
	for id in terrains.size():
		var t: Array = terrains[id]
		if t.size() < 7 or t[2] != TYPE_OBJECT:
			continue
		var cfg: Dictionary = t[6]
		var sz: Array = cfg.get("size", [2, 2])
		var size := Vector2i(sz[0], sz[1])
		if bool(cfg.get("mass", false)):
			continue
		var blocks := detect_blocks(ts, id, size)
		# A single drawing doubles as its own joined block.
		if blocks.size() == 1:
			blocks = [blocks[0], blocks[0]]
		if blocks.size() != 2:
			continue

		var lone_cfg: Array = cfg.get("lone", [])
		var lone: Dictionary = blocks[1]
		if lone_cfg.size() == 2:
			for b in blocks:
				if b["rect"].position == Vector2i(lone_cfg[0], lone_cfg[1]):
					lone = b
		var fused: Dictionary = blocks[0] if blocks[1] == lone else blocks[1]

		out.push_back({
			"id": id,
			"name": t[0],
			"atlas": texture_name(ts, lone["source_id"]),
			"size": size,
			"fused": fused["rect"].position,
			"closed": lone["rect"].position,
		})
	_objects_cache[ts] = out
	return out


static func object_config(ts: TileSet, terrain_id: int) -> Dictionary:
	if ts == null or terrain_id < 0 or not ts.has_meta(TERRAIN_META):
		return {}
	var meta = ts.get_meta(TERRAIN_META)
	if typeof(meta) != TYPE_DICTIONARY:
		return {}
	var terrains: Array = meta.get("terrains", [])
	if terrain_id >= terrains.size():
		return {}
	var t: Array = terrains[terrain_id]
	if t.size() < 7 or t[2] != TYPE_OBJECT:
		return {}
	return t[6]


static func object_size(ts: TileSet, terrain_id: int) -> Vector2i:
	var cfg := object_config(ts, terrain_id)
	if cfg.is_empty():
		return Vector2i.ONE
	var sz: Array = cfg.get("size", [1, 1])
	return Vector2i(maxi(1, sz[0]), maxi(1, sz[1]))


static func has_objects(ts: TileSet) -> bool:
	var r := false
	if ts != null and ts.has_meta(TERRAIN_META):
		var meta = ts.get_meta(TERRAIN_META)
		if typeof(meta) == TYPE_DICTIONARY:
			for t in meta.get("terrains", []):
				if t.size() >= 3 and t[2] == TYPE_OBJECT:
					r = true
					break
	return r


static func make_config(size: Vector2i, lone: Vector2i, mass := false, base := Rect2i()) -> Dictionary:
	return {
		"size": [size.x, size.y],
		"lone": [lone.x, lone.y],
		"mass": mass,
		"base": [base.position.x, base.position.y, base.size.x, base.size.y] if base.has_area() \
				else [0, 0, size.x, size.y],
	}


## Base coordinates are relative to the drawing top-left, in tiles.
static func base_rect(size: Vector2i, cfg: Dictionary) -> Rect2i:
	var values: Array = cfg.get("base", [0, 0, size.x, size.y])
	var x := clampi(int(values[0]), 0, size.x - 1)
	var y := clampi(int(values[1]), 0, size.y - 1)
	return Rect2i(x, y, clampi(int(values[2]), 1, size.x - x), clampi(int(values[3]), 1, size.y - y))


static func base_fits(painted: Dictionary, origin: Vector2i, base: Rect2i) -> bool:
	for y in range(base.position.y, base.end.y):
		for x in range(base.position.x, base.end.x):
			if not painted.has(origin + Vector2i(x, y)):
				return false
	return true


#endregion


static func cells_of(size: Vector2i) -> Array:
	var out := []
	for j in size.y:
		for i in size.x:
			var sides := []
			if i == 0: sides.push_back("w")
			if i == size.x - 1: sides.push_back("e")
			if j == 0: sides.push_back("n")
			if j == size.y - 1: sides.push_back("s")
			var diag := ""
			if sides.has("n") and sides.has("w"): diag = "nw"
			elif sides.has("n") and sides.has("e"): diag = "ne"
			elif sides.has("s") and sides.has("w"): diag = "sw"
			elif sides.has("s") and sides.has("e"): diag = "se"
			if diag != "": sides.push_back(diag)
			out.push_back({"off": Vector2i(i, j), "sides": sides})
	return out


static func steps_for(size: Vector2i) -> Dictionary:
	return {
		"n": Vector2i(0, -size.y), "s": Vector2i(0, size.y),
		"w": Vector2i(-size.x, 0), "e": Vector2i(size.x, 0),
		"nw": Vector2i(-size.x, -size.y), "ne": Vector2i(size.x, -size.y),
		"sw": Vector2i(-size.x, size.y), "se": Vector2i(size.x, size.y),
	}


static func anchor_of(cell: Vector2i, size: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(size.x)) * size.x, floori(cell.y / float(size.y)) * size.y)


static func mass_anchor(cell: Vector2i, base_size: Vector2i) -> Vector2i:
	var row := floori(float(cell.y) / base_size.y)
	var shift := Vector2i(base_size.x / 2 if posmod(row, 2) == 1 else 0, 0)
	return anchor_of(cell - shift, base_size) + shift


static func texture_name(ts: TileSet, source_id: int) -> String:
	var src := ts.get_source(source_id) as TileSetAtlasSource
	if src == null or src.texture == null:
		return ""
	return src.texture.resource_path.get_file()


static func object_of_cell(tm: TileMapLayer, cell: Vector2i, objects: Array) -> Dictionary:
	var atlas := tm.get_cell_atlas_coords(cell)
	if atlas.x < 0:
		return {}
	var texture := texture_name(tm.tile_set, tm.get_cell_source_id(cell))
	for o in objects:
		if o["atlas"] != "" and o["atlas"] != texture:
			continue
		for origin: Vector2i in [o["fused"], o["closed"]]:
			var d: Vector2i = atlas - origin
			if d.x >= 0 and d.x < o["size"].x and d.y >= 0 and d.y < o["size"].y:
				return o
	return {}


static func object_at(tm: TileMapLayer, anchor: Vector2i, o: Dictionary, objects: Array) -> Dictionary:
	for c in cells_of(o["size"]):
		var found := object_of_cell(tm, anchor + c["off"], objects)
		if not found.is_empty() and found["id"] == o["id"]:
			return found
	return {}


static func _rebuild(tm: TileMapLayer, anchor: Vector2i, o: Dictionary, objects: Array) -> void:
	var block_cells := cells_of(o["size"])
	var source := -1
	for c in block_cells:
		if not object_of_cell(tm, anchor + c["off"], objects).is_empty():
			source = tm.get_cell_source_id(anchor + c["off"])
			break
	if source < 0:
		return

	var steps := steps_for(o["size"])
	var has := {}
	for side in steps:
		has[side] = not object_at(tm, anchor + steps[side], o, objects).is_empty()

	for c in block_cells:
		var fused := true
		for side in c["sides"]:
			if not has[side]:
				fused = false
				break
		tm.set_cell(anchor + c["off"], source, (o["fused"] if fused else o["closed"]) + c["off"], 0)


## Include neighbouring objects in the undo snapshot; they may change without being painted.
static func stroke_affects_objects(tm: TileMapLayer, cells: Array, paint_type: int = -1) -> bool:
	var ts := tm.tile_set
	var terrains: Array = ts.get_meta(TERRAIN_META, {}).get("terrains", [])
	if paint_type >= 0 and paint_type < terrains.size() and terrains[paint_type][2] == TYPE_OBJECT:
		return true
	for state in tm.get_meta(MASS_PLACEMENTS, {}).values():
		var size: Vector2i = state.signature[0]
		for origin in state.origins:
			var footprint := Rect2i(Vector2i(origin), size)
			for cell in cells:
				if footprint.has_point(cell):
					return true
	for cell in expand_cells(tm, cells):
		var source_id := tm.get_cell_source_id(cell)
		if source_id < 0:
			continue
		var source := ts.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		var tile := source.get_tile_data(tm.get_cell_atlas_coords(cell), tm.get_cell_alternative_tile(cell))
		if tile == null:
			continue
		if tile.get_meta(MASS_MARKER, false):
			return true
		var type: int = tile.get_meta(TERRAIN_META, {}).get("type", -1)
		if type >= 0 and type < terrains.size() and terrains[type][2] == TYPE_OBJECT:
			return true
	return false


static func expand_cells(tm: TileMapLayer, cells: Array) -> Array:
	var objects := get_objects(tm.tile_set) if tm and tm.tile_set else []
	if objects.is_empty():
		return cells
	var out := {}
	for c in cells:
		out[c] = true
		for o in objects:
			var anchor := anchor_of(c, o["size"])
			var steps := steps_for(o["size"])
			for step in [Vector2i.ZERO] + steps.values():
				for q in cells_of(o["size"]):
					out[anchor + step + q["off"]] = true
	return out.keys()


static func fix_cells(tm: TileMapLayer, cells: Array, erasing: bool = false, paint_type: int = -1) -> void:
	if tm == null or tm.tile_set == null:
		return
	if erasing and can_erase_mass_locally(tm, cells):
		erase_mass_locally(tm, cells)
		return
	fix_mass(tm, not erasing, cells, paint_type)
	var objects := get_objects(tm.tile_set)
	if objects.is_empty():
		return

	var anchors := {}   # anchor -> object
	for c in cells:
		var o := object_of_cell(tm, c, objects)
		if o.is_empty():
			for cand in objects:
				var a := anchor_of(c, cand["size"])
				if not object_at(tm, a, cand, objects).is_empty():
					anchors[a] = cand
			continue
		var a := anchor_of(c, o["size"])
		anchors[a] = o
		for step in steps_for(o["size"]).values():
			anchors[a + step] = o

	# Recover anchors from coordinates because the caller has already erased the painted cells.
	if erasing:
		for c in cells:
			for cand in objects:
				var a := anchor_of(c, cand["size"])
				if object_at(tm, a, cand, objects).is_empty():
					continue
				for q in cells_of(cand["size"]):
					tm.erase_cell(a + q["off"])
				var sz: Vector2i = cand["size"]
				for dy in [-sz.y, 0, sz.y]:
					for dx in [-sz.x, 0, sz.x]:
						if dx == 0 and dy == 0:
							continue
						var n: Vector2i = a + Vector2i(dx, dy)
						var near := object_at(tm, n, cand, objects)
						if not near.is_empty():
							anchors[n] = near

	for anchor in anchors:
		var o: Dictionary = anchors[anchor]
		if not object_at(tm, anchor, o, objects).is_empty():
			_rebuild(tm, anchor, o, objects)


static func fix_layer(tm: TileMapLayer) -> int:
	if tm == null or tm.tile_set == null:
		return 0
	var mass := fix_mass(tm)
	var objects := get_objects(tm.tile_set)
	if objects.is_empty():
		return mass
	var anchors := {}
	for cell in tm.get_used_cells():
		var o := object_of_cell(tm, cell, objects)
		if not o.is_empty():
			anchors[anchor_of(cell, o["size"])] = o
	for anchor in anchors:
		_rebuild(tm, anchor, anchors[anchor], objects)
	return anchors.size() + mass


#region Mass

## The whole base must fit the painted region; generated crowns may overhang it.
const MASS_LAYER := "_Mass"
const MASS_PLACEMENTS := &"_better_terrain_mass_placements"
const MASS_MARKER := &"_better_terrain_mass_marker"
const MASS_MAX_LAYERS := 6


static func is_mass(ts: TileSet, terrain_id: int) -> bool:
	var cfg := object_config(ts, terrain_id)
	if not bool(cfg.get("mass", false)):
		return false
	var size := object_size(ts, terrain_id)
	# The tree alone is enough, baking a filler is optional.
	return size != Vector2i.ONE and detect_blocks(ts, terrain_id, size).size() >= 1


static func has_mass(ts: TileSet) -> bool:
	if ts == null or not ts.has_meta(TERRAIN_META):
		return false
	var meta = ts.get_meta(TERRAIN_META)
	if typeof(meta) != TYPE_DICTIONARY:
		return false
	for t in meta.get("terrains", []):
		if t.size() >= 7 and t[2] == TYPE_OBJECT and t[6] is Dictionary and bool(t[6].get("mass", false)):
			return true
	return false


## Defer regeneration until undo has finished restoring the painted cells.
static func fix_mass_deferred(tm: TileMapLayer) -> void:
	if is_instance_valid(tm):
		(func(): fix_mass(tm)).call_deferred()


static func fix_mass(tm: TileMapLayer, allow_new := true, stroke: Array = [], paint_type: int = -1) -> int:
	var ts := tm.tile_set if tm else null
	if ts == null or not ts.has_meta(TERRAIN_META):
		return 0
	var meta = ts.get_meta(TERRAIN_META)
	if typeof(meta) != TYPE_DICTIONARY:
		return 0

	var previous: Dictionary = tm.get_meta(MASS_PLACEMENTS, {})
	var saved := {}
	var placements := []   # [[source, tree block, at, size], ...] over every mass
	var painted := {}
	var any_mass := false
	var terrains: Array = meta.get("terrains", [])
	for id in terrains.size():
		var t: Array = terrains[id]
		if t.size() < 3 or t[2] != TYPE_OBJECT or not is_mass(ts, id):
			continue
		any_mass = true
		var size := object_size(ts, id)
		var cfg := object_config(ts, id)
		var base := base_rect(size, cfg)
		var blocks := detect_blocks(ts, id, size)

		var lone_at: Array = cfg.get("lone", [])
		var lone := Vector2i(lone_at[0], lone_at[1]) if lone_at.size() == 2 else Vector2i(-1, -1)
		var fill: Dictionary = {}
		var tree: Dictionary = {}
		for b in blocks:
			if b["rect"].position == lone:
				tree = b
			elif fill.is_empty():
				fill = b
		if tree.is_empty():
			continue
		# No filler: the tree tile marks the region, the marker keep it invisible.
		if fill.is_empty():
			fill = tree
		var owner := {}
		for b in [fill, tree]:
			for dy in size.y:
				for dx in size.x:
					owner[[b["source_id"], b["rect"].position + Vector2i(dx, dy)]] = true
		var mine := {}
		for c in tm.get_used_cells():
			if owner.has([tm.get_cell_source_id(c), tm.get_cell_atlas_coords(c)]):
				mine[c] = true
		if mine.is_empty():
			continue

		var signature := [size, base, tree["source_id"], tree["rect"]]
		var old: Dictionary = previous.get(id, {})
		var keep: Array = []
		if old.get("signature", []) == signature:
			for origin in old.get("origins", PackedVector2Array()):
				keep.append(Vector2i(origin))
		elif not previous.has(id):
			keep = _existing_mass_origins(tm, tree["source_id"], tree["rect"], mine, base)

		var added := mine.duplicate()
		if old.get("signature", []) == signature:
			for c in old.get("cells", PackedVector2Array()):
				added.erase(Vector2i(c))
			if not old.has("cells"):
				added.clear()
		if not allow_new:
			added.clear()
		var explicit: bool = old.get("explicit", false) or id == paint_type
		var origins: Array
		if explicit:
			origins = keep.filter(func(origin): return base_fits(mine, origin, base))
			var covered := {}
			var occupied := {}
			for origin in origins:
				_record_mass_coverage(origin, size, base, covered, occupied)
			if allow_new and id == paint_type:
				for c in stroke:
					var origin := mass_anchor(c, base.size) - base.position
					if base_fits(mine, origin, base) and not _base_occupied(origin, base, occupied):
						origins.append(origin)
						_record_mass_coverage(origin, size, base, covered, occupied)
			for c in mine.keys():
				if not occupied.has(c):
					tm.erase_cell(c)
					mine.erase(c)
		else:
			origins = mass_origins(mine, size, base, keep, added)
		origins.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
		var fill_at: Vector2i = fill["rect"].position
		var source := ts.get_source(fill["source_id"]) as TileSetAtlasSource
		var marker := _mass_marker(source, fill_at)
		for c in mine:
			painted[c] = true
			tm.set_cell(c, fill["source_id"], fill_at, marker)


		var packed := PackedVector2Array()
		for origin in origins:
			packed.append(Vector2(origin))
		var region := mine.keys()
		region.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
		var packed_region := PackedVector2Array()
		for c in region:
			packed_region.append(Vector2(c))
		saved[id] = {signature = signature, origins = packed, cells = packed_region, explicit = explicit,
			marker = [fill["source_id"], fill_at, marker]}
		for origin in origins:
			placements.append([tree["source_id"], tree["rect"].position, origin, size])

	if not any_mass:
		return 0
	if saved != previous:
		if saved.is_empty():
			tm.remove_meta(MASS_PLACEMENTS)
		else:
			tm.set_meta(MASS_PLACEMENTS, saved)
	_stack(tm, ts, placements, painted)
	return placements.size()


## Adopt visible trees frop scenes saved before placements were recorded.
static func _existing_mass_origins(tm: TileMapLayer, source: int, drawing: Rect2i,
		painted: Dictionary, base: Rect2i) -> Array:
	var evidence := {}
	var layers := [tm]
	for child in tm.get_children():
		if child is TileMapLayer and str(child.name).trim_prefix("_").begins_with("Mass"):
			layers.append(child)
	for layer in layers:
		for cell in layer.get_used_cells():
			var atlas: Vector2i = layer.get_cell_atlas_coords(cell)
			if layer.get_cell_source_id(cell) != source or not drawing.has_point(atlas):
				continue
			var origin: Vector2i = cell - (atlas - drawing.position)
			evidence[origin] = int(evidence.get(origin, 0)) + 1
	var out := []
	for origin in evidence:
		if evidence[origin] >= 2 and base_fits(painted, origin, base):
			out.append(origin)
	return out


static func mass_origins(painted: Dictionary, size: Vector2i, base: Rect2i, previous: Array = [], added: Variant = null) -> Array:
	if painted.is_empty():
		return []
	var lo := Vector2i(999999, 999999)
	var hi := Vector2i(-999999, -999999)
	for c in painted:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var step_y := maxi(1, size.y / 2)
	var out := []
	var covered := {}
	var occupied := {}
	for origin: Vector2i in previous:
		if base_fits(painted, origin, base):
			out.append(origin)
			_record_mass_coverage(origin, size, base, covered, occupied)
	var ay := floori(float(lo.y - size.y) / float(step_y)) * step_y
	while ay <= hi.y:
		var off: int = size.x / 2 if posmod(ay / step_y, 2) == 1 else 0
		var ax := floori(float(lo.x - size.x - off) / float(size.x)) * size.x + off
		while ax <= hi.x + size.x:
			var origin := Vector2i(ax, ay)
			if base_fits(painted, origin, base) and not _base_occupied(origin, base, occupied) \
					and _base_was_painted(origin, base, added):
				out.append(origin)
				_record_mass_coverage(origin, size, base, covered, occupied)
			ax += size.x
		ay += step_y

	var cells := painted.keys()
	cells.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	for c: Vector2i in cells:
		var origin := c - base.position
		if not base_fits(painted, origin, base):
			continue
		var uncovered := false
		var overlaps := false
		for y in base.size.y:
			for x in base.size.x:
				var cell := c + Vector2i(x, y)
				uncovered = uncovered or not covered.has(cell)
				overlaps = overlaps or occupied.has(cell)
		if uncovered and not overlaps and _base_was_painted(origin, base, added):
			out.append(origin)
			_record_mass_coverage(origin, size, base, covered, occupied)
	out.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	return out


static func _base_was_painted(origin: Vector2i, base: Rect2i, added: Variant) -> bool:
	if added == null:
		return true
	for y in range(base.position.y, base.end.y):
		for x in range(base.position.x, base.end.x):
			if added.has(origin + Vector2i(x, y)):
				return true
	return false


static func mass_erase_cells(tm: TileMapLayer, cells: Array) -> Array:
	var placements: Dictionary = tm.get_meta(MASS_PLACEMENTS, {})
	var layers := [tm]
	for child in tm.get_children():
		if child is TileMapLayer and str(child.name).trim_prefix("_").begins_with("Mass"):
			layers.append(child)
	layers.reverse()
	var out := {}
	for c in cells:
		var found := false
		for layer in layers:
			for id in placements:
				var signature: Array = placements[id].signature
				var drawing: Rect2i = signature[3]
				var atlas: Vector2i = layer.get_cell_atlas_coords(c)
				if layer.get_cell_source_id(c) != signature[2] or not drawing.has_point(atlas):
					continue
				var origin: Vector2i = c - (atlas - drawing.position)
				if Vector2(origin) not in placements[id].origins:
					continue
				var base: Rect2i = signature[1]
				for y in range(base.position.y, base.end.y):
					for x in range(base.position.x, base.end.x):
						out[origin + Vector2i(x, y)] = true
				found = true
				break
			if found:
				break
		if not found:
			out[c] = true
	return out.keys()


## Older scenes need a full rebuild to acquire marker metadata.
static func can_erase_mass_locally(tm: TileMapLayer, cells: Array) -> bool:
	var states: Dictionary = tm.get_meta(MASS_PLACEMENTS, {})
	if cells.is_empty() or states.is_empty():
		return false
	for state in states.values():
		if not state.get("explicit", false) or not state.has("marker"):
			return false
	for c in cells:
		var found := false
		for state in states.values():
			if Vector2(c) in state.cells:
				found = true
				break
		if not found:
			return false
	return true


static func mass_erase_region(tm: TileMapLayer, cells: Array) -> Dictionary:
	var dirty := {}
	for state in tm.get_meta(MASS_PLACEMENTS, {}).values():
		var size: Vector2i = state.signature[0]
		var base: Rect2i = state.signature[1]
		for at in state.origins:
			var origin := Vector2i(at)
			var footprint := Rect2i(origin + base.position, base.size)
			for c in cells:
				if footprint.has_point(c):
					for y in size.y:
						for x in size.x:
							dirty[origin + Vector2i(x, y)] = true
					break
	return dirty


static func erase_mass_locally(tm: TileMapLayer, cells: Array) -> void:
	var dirty := mass_erase_region(tm, cells)
	var states: Dictionary = tm.get_meta(MASS_PLACEMENTS).duplicate(true)
	var removed := {}
	for id in states.keys():
		var state: Dictionary = states[id]
		var base: Rect2i = state.signature[1]
		var origins := PackedVector2Array()
		for at in state.origins:
			var footprint := Rect2i(Vector2i(at) + base.position, base.size)
			if cells.any(func(c): return footprint.has_point(c)):
				for y in range(footprint.position.y, footprint.end.y):
					for x in range(footprint.position.x, footprint.end.x):
						removed[Vector2i(x, y)] = true
			else:
				origins.append(at)
		state.origins = origins
		var region := PackedVector2Array()
		for c in state.cells:
			if not removed.has(Vector2i(c)):
				region.append(c)
		state.cells = region
		if origins.is_empty():
			states.erase(id)
	for c in removed:
		tm.erase_cell(c)
	var painted := {}
	var placements := []
	var bounds := Rect2i(cells[0], Vector2i.ONE)
	for c in dirty:
		bounds = bounds.merge(Rect2i(c, Vector2i.ONE))
	for state in states.values():
		for c in dirty:
			if Vector2(c) in state.cells:
				painted[c] = true
				tm.set_cell(c, state.marker[0], state.marker[1], state.marker[2])
		var size: Vector2i = state.signature[0]
		var drawing: Rect2i = state.signature[3]
		for at in state.origins:
			if Rect2i(Vector2i(at), size).intersects(bounds):
				placements.append([state.signature[2], drawing.position, Vector2i(at), size])
	if states.is_empty():
		tm.remove_meta(MASS_PLACEMENTS)
	else:
		tm.set_meta(MASS_PLACEMENTS, states)
	_stack(tm, tm.tile_set, placements, painted, dirty)


static func _base_occupied(origin: Vector2i, base: Rect2i, occupied: Dictionary) -> bool:
	for y in range(base.position.y, base.end.y):
		for x in range(base.position.x, base.end.x):
			if occupied.has(origin + Vector2i(x, y)):
				return true
	return false


static func _record_mass_coverage(origin: Vector2i, size: Vector2i, base: Rect2i,
		covered: Dictionary, occupied: Dictionary) -> void:
	for y in size.y:
		for x in size.x:
			covered[origin + Vector2i(x, y)] = true
	for y in range(base.position.y, base.end.y):
		for x in range(base.position.x, base.end.x):
			occupied[origin + Vector2i(x, y)] = true


static func _mass_marker(source: TileSetAtlasSource, coord: Vector2i) -> int:
	for i in source.get_alternative_tiles_count(coord):
		var alternative := source.get_alternative_tile_id(coord, i)
		if source.get_tile_data(coord, alternative).get_meta(MASS_MARKER, false):
			return alternative
	var alternative := source.create_alternative_tile(coord)
	var tile := source.get_tile_data(coord, alternative)
	tile.modulate = Color(1, 1, 1, 0)
	tile.set_meta(TERRAIN_META, source.get_tile_data(coord, 0).get_meta(TERRAIN_META).duplicate(true))
	tile.set_meta(MASS_MARKER, true)
	return alternative


## Transparent overlaps need child layers. Keep overhang off the parent to preserve region membership.
static func _stack(tm: TileMapLayer, ts: TileSet, placements: Array, painted: Dictionary, dirty: Variant = null) -> void:
	var layers := [tm]
	for c in tm.get_children():
		if c is TileMapLayer and str(c.name).trim_prefix("_").begins_with("Mass"):
			SupportLayers.prepare(c)
			layers.append(c)
			if SupportLayers.is_frozen(c):
				continue
			c.tile_set = ts
			if dirty == null:
				c.clear()
			else:
				for cell in dirty:
					c.erase_cell(cell)
	placements.sort_custom(func(a, b):
		var fa: int = a[2].y + a[3].y
		var fb: int = b[2].y + b[3].y
		return fa < fb if fa != fb else a[2].x < b[2].x)
	var top := {}   # cell -> highest level holding a tree celj there
	for p in placements:
		var src := ts.get_source(p[0]) as TileSetAtlasSource
		if src == null:
			continue
		var block: Vector2i = p[1]
		var at: Vector2i = p[2]
		var size: Vector2i = p[3]
		for dy in size.y:
			for dx in size.x:
				var cell := at + Vector2i(dx, dy)
				if dirty != null and not dirty.has(cell):
					continue
				var coord := block + Vector2i(dx, dy)
				if not src.has_tile(coord) or not _has_ink(src, coord):
					continue
				var level: int
				if top.has(cell):
					level = int(top[cell]) + (0 if _is_opaque(src, coord) else 1)
				else:
					level = 0 if painted.has(cell) else 1
				if level > MASS_MAX_LAYERS:
					level = MASS_MAX_LAYERS
				while layers.size() <= level:
					var l := TileMapLayer.new()
					l.name = "%s%d" % [MASS_LAYER, layers.size()]
					SupportLayers.prepare(l)
					l.tile_set = ts
					l.texture_filter = tm.texture_filter
					tm.add_child(l)
					if tm.owner != null:
						l.owner = tm.owner
					elif tm.is_inside_tree() and tm.get_tree().edited_scene_root != null:
						l.owner = tm.get_tree().edited_scene_root
					layers.append(l)
				if not SupportLayers.is_frozen(layers[level]):
					layers[level].set_cell(cell, p[0], coord, 0)
				top[cell] = level
	if dirty != null:
		return
	for c in tm.get_children():
		if c is TileMapLayer and str(c.name).trim_prefix("_").begins_with("Mass") and c.get_used_cells().is_empty():
			tm.remove_child(c)
			c.queue_free()


static var _opaque_cache := {}

static func _is_opaque(src: TileSetAtlasSource, coord: Vector2i) -> bool:
	var key := [src.texture.resource_path if src.texture else "", coord]
	if _opaque_cache.has(key):
		return _opaque_cache[key]
	var img := src.texture.get_image()
	if img.is_compressed():
		img.decompress()
	var r: Rect2i = src.get_tile_texture_region(coord, 0)
	var solid := true
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x >= img.get_width() or y >= img.get_height() or img.get_pixel(x, y).a < 0.97:
				solid = false
				break
		if not solid:
			break
	_opaque_cache[key] = solid
	return solid


static var _ink_cache := {}

static func _has_ink(src: TileSetAtlasSource, coord: Vector2i) -> bool:
	var key := [src.texture.resource_path if src.texture else "", coord]
	if _ink_cache.has(key):
		return _ink_cache[key]
	var img := src.texture.get_image()
	if img.is_compressed():
		img.decompress()
	var r: Rect2i = src.get_tile_texture_region(coord, 0)
	var found := false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.03:
				found = true
				break
		if found:
			break
	_ink_cache[key] = found
	return found

#endregion
