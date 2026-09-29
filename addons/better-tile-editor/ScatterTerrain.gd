@tool
extends RefCounted

const SupportLayers := preload("res://addons/better-tile-editor/SupportLayers.gd")

## Store painted zones separately from generated art so empty rolls retain region membership.

const ObjectTerrain := preload("res://addons/better-tile-editor/ObjectTerrain.gd")

const TERRAIN_META = &"_better_terrain"
const ZONES_META = &"_better_terrain_scatter"

const TYPE_SCATTER := 6  # BetterTerrain.TerrainType.SCATTER

const LAYER_NAME := "_ScatterDecor"
const LAYER_SCRIPT := "res://addons/better-tile-editor/ScatterLayer.gd"

const FACES_LAYER_NAME := "_CliffFaces"


#region The bag

## empty_pct controls density; bag entry weights share the remaining probability.
static func config_of(ts: TileSet, id: int) -> Dictionary:
	var t := _terrain(ts, id)
	if t.is_empty():
		return {}
	var cfg: Dictionary = t[6] if t.size() > 6 and typeof(t[6]) == TYPE_DICTIONARY else {}
	var out := {
		bag = cfg.get("bag", []),
		empty_pct = _empty_pct_of(cfg),
		seed = int(cfg.get("seed", 0)),
		live = bool(cfg.get("live", false)),
		edge = maxi(0, int(cfg.get("edge", 0))),
	}
	return out


## Convert legacy empty weights to percentages without changing density.
static func _empty_pct_of(cfg: Dictionary) -> float:
	if cfg.has("empty_pct"):
		return clampf(float(cfg["empty_pct"]), 0.0, 100.0)
	var was := maxf(0.0, float(cfg.get("empty", 0.0)))
	if was <= 0.0:
		return 0.0
	var total := was
	for e in cfg.get("bag", []):
		total += normalise_entry(e).get("weight", 0.0)
	return 0.0 if total <= 0.0 else clampf(was / total * 100.0, 0.0, 100.0)


## notify=false skips TileSet.changed, which makes every layer reprocess all its cells.
static func set_config(ts: TileSet, id: int, cfg: Dictionary, notify := true) -> void:
	if ts == null or not ts.has_meta(TERRAIN_META):
		return
	var meta: Dictionary = ts.get_meta(TERRAIN_META)
	var terrains: Array = meta.get("terrains", [])
	if id < 0 or id >= terrains.size():
		return
	var t: Array = terrains[id]
	while t.size() < 7:
		if t.size() == 5:
			t.push_back("")
		else:
			t.push_back({})
	t[6] = cfg
	ts.set_meta(TERRAIN_META, meta)
	if notify:
		ts.emit_changed()


static func is_scatter(ts: TileSet, id: int) -> bool:
	var t := _terrain(ts, id)
	return t.size() > 2 and int(t[2]) == TYPE_SCATTER


static func has_scatter(ts: TileSet) -> bool:
	if ts == null or not ts.has_meta(TERRAIN_META):
		return false
	var meta: Dictionary = ts.get_meta(TERRAIN_META)
	for t in meta.get("terrains", []):
		if t.size() > 2 and int(t[2]) == TYPE_SCATTER:
			return true
	return false


static func _terrain(ts: TileSet, id: int) -> Array:
	if ts == null or id < 0 or not ts.has_meta(TERRAIN_META):
		return []
	var meta: Dictionary = ts.get_meta(TERRAIN_META)
	var terrains: Array = meta.get("terrains", [])
	return terrains[id] if id < terrains.size() else []


static func entry_at(cfg: Dictionary, index: int) -> Dictionary:
	var bag: Array = cfg.get("bag", [])
	if index < 0 or index >= bag.size():
		return {}
	return normalise_entry(bag[index])


static func normalise_entry(e) -> Dictionary:
	if typeof(e) != TYPE_DICTIONARY:
		return {}
	var origin: Array = e.get("origin", [0, 0])
	var size: Array = e.get("size", [1, 1])
	var drawing_size := Vector2i(maxi(1, int(size[0])), maxi(1, int(size[1])))
	return {
		source = int(e.get("source", -1)),
		origin = Vector2i(int(origin[0]), int(origin[1])),
		size = drawing_size,
		base = ObjectTerrain.base_rect(drawing_size, e),
		weight = maxf(0.0, float(e.get("weight", 1.0))),
	}


static func make_entry(source: int, origin: Vector2i, size: Vector2i, weight := 1.0) -> Dictionary:
	return {
		source = source,
		origin = [origin.x, origin.y],
		size = [maxi(1, size.x), maxi(1, size.y)],
		weight = weight,
	}


static func entry_covering(cfg: Dictionary, source: int, coord: Vector2i) -> int:
	var bag: Array = cfg.get("bag", [])
	for i in bag.size():
		var e := normalise_entry(bag[i])
		if e.is_empty() or e.source != source:
			continue
		var r := Rect2i(e.origin, e.size)
		if r.has_point(coord):
			return i
	return -1

#endregion


#region The zone

static func zones_of(tm: TileMapLayer) -> Dictionary:
	if tm == null or not tm.has_meta(ZONES_META):
		return {}
	var z = tm.get_meta(ZONES_META)
	return z if typeof(z) == TYPE_DICTIONARY else {}


static func zone_cells(tm: TileMapLayer, id: int) -> Array:
	var zones := zones_of(tm)
	var out := []
	for v in zones.get(id, PackedVector2Array()):
		out.push_back(Vector2i(v))
	return out


static func has_zone(tm: TileMapLayer) -> bool:
	for id in zones_of(tm):
		if not zones_of(tm)[id].is_empty():
			return true
	return false


static func set_zone(tm: TileMapLayer, id: int, cells: PackedVector2Array) -> void:
	if tm == null:
		return
	var zones := zones_of(tm).duplicate()
	if cells.is_empty():
		zones.erase(id)
	else:
		zones[id] = cells
	set_zones(tm, zones)


static func set_zones(tm: TileMapLayer, zones: Dictionary) -> void:
	if tm == null:
		return
	var keep := {}
	for id in zones:
		if not zones[id].is_empty():
			keep[int(id)] = zones[id]
	if keep.is_empty():
		if tm.has_meta(ZONES_META):
			tm.remove_meta(ZONES_META)
	else:
		tm.set_meta(ZONES_META, keep)
	rebuild(tm)


static func add_cells(tm: TileMapLayer, id: int, cells: Array) -> void:
	set_zone(tm, id, with_cells(tm, id, cells))


static func remove_cells(tm: TileMapLayer, id: int, cells: Array) -> void:
	set_zone(tm, id, without_cells(tm, id, cells))


static func remove_everywhere(tm: TileMapLayer, cells: Array) -> void:
	set_zones(tm, erased_everywhere(tm, cells))


## Only return newly painted cylls; undo must preserve cells from earlier strokes.
static func cells_not_in(tm: TileMapLayer, id: int, cells: Array) -> Array:
	var seen := {}
	for v in zones_of(tm).get(id, PackedVector2Array()):
		seen[Vector2i(v)] = true
	var out := []
	for c in cells:
		if not seen.has(Vector2i(c)):
			out.push_back(Vector2i(c))
	return out


## Returns erased cells by terrain ID: {id: [cells]}.
static func cells_in_any(tm: TileMapLayer, cells: Array) -> Dictionary:
	var out := {}
	for id in zones_of(tm):
		var seen := {}
		for v in zones_of(tm)[id]:
			seen[Vector2i(v)] = true
		var hit := []
		for c in cells:
			if seen.has(Vector2i(c)):
				hit.push_back(Vector2i(c))
		if not hit.is_empty():
			out[int(id)] = hit
	return out


## Returns the modified zone without writing it.
static func with_cells(tm: TileMapLayer, id: int, cells: Array) -> PackedVector2Array:
	var seen := {}
	for v in zones_of(tm).get(id, PackedVector2Array()):
		seen[Vector2i(v)] = true
	for c in cells:
		seen[Vector2i(c)] = true
	return _pack(seen.keys())


static func without_cells(tm: TileMapLayer, id: int, cells: Array) -> PackedVector2Array:
	var seen := {}
	for v in zones_of(tm).get(id, PackedVector2Array()):
		seen[Vector2i(v)] = true
	for c in cells:
		seen.erase(Vector2i(c))
	return _pack(seen.keys())


static func erased_everywhere(tm: TileMapLayer, cells: Array) -> Dictionary:
	var out := {}
	for id in zones_of(tm):
		out[id] = without_cells(tm, int(id), cells)
	return out


static func _pack(coords: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in coords:
		out.push_back(Vector2(c))
	return out

#endregion


#region The generated layer

static func find_layer(tm: TileMapLayer) -> TileMapLayer:
	if tm == null:
		return null
	return SupportLayers.find_layer(tm, LAYER_NAME)


static func scatter_layer(tm: TileMapLayer, create := false) -> TileMapLayer:
	if tm == null:
		return null
	var existing := find_layer(tm)
	if existing != null:
		SupportLayers.prepare(existing)
		if existing.get_script() == null:
			existing.set_script(load(LAYER_SCRIPT))
		_place_in_front(existing)
		return existing
	if not create:
		return null

	var l := TileMapLayer.new()
	l.set_script(load(LAYER_SCRIPT))
	l.name = LAYER_NAME
	SupportLayers.prepare(l)
	l.tile_set = tm.tile_set
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tm.add_child(l)
	if tm.owner != null:
		l.owner = tm.owner
	_place_in_front(l)
	return l


static func _place_in_front(l: TileMapLayer) -> void:
	l.z_index = 1
	l.show_behind_parent = false
	l.y_sort_enabled = l.get_parent().y_sort_enabled if l.get_parent() is TileMapLayer else false

#endregion


#region Rolling the bag

static func face_cells(tm: TileMapLayer) -> Dictionary:
	var out := {}
	if tm == null:
		return out
	var family := [tm]
	if tm.get_parent() != null:
		family = tm.get_parent().get_children()
	var layers: Array[TileMapLayer] = []
	for l in family:
		if not (l is TileMapLayer) or not l.visible:
			continue
		var faces := SupportLayers.find_layer(l, FACES_LAYER_NAME)
		if faces != null and faces.visible and faces.show_behind_parent:
			layers.append(faces)
		layers.append(l)
		if faces != null and faces.visible and not faces.show_behind_parent:
			layers.append(faces)

	var top := {}
	var to_local := tm.global_transform.affine_inverse()
	for layer in layers:
		var z := _layer_z(layer)
		var is_face := str(layer.name).trim_prefix("_") == FACES_LAYER_NAME.trim_prefix("_")
		for cell in layer.get_used_cells():
			var coord := tm.local_to_map(to_local * layer.global_transform * layer.map_to_local(cell))
			if not top.has(coord) or z >= top[coord]:
				top[coord] = z
				if is_face:
					out[coord] = true
				else:
					out.erase(coord)
	return out


static func _layer_z(layer: CanvasItem) -> int:
	var z := 0
	var node: Node = layer
	while node != null:
		if node is CanvasItem:
			z += node.z_index
			if not node.z_as_relative:
				break
		node = node.get_parent()
	return z


static func rebuild(tm: TileMapLayer) -> Dictionary:
	var report := {written = 0, cleared = 0}
	if tm == null or tm.tile_set == null:
		return report

	var zones := zones_of(tm)
	var layer := find_layer(tm)
	if SupportLayers.is_frozen(layer):
		report["frozen"] = true
		return report
	if zones.is_empty():
		if layer != null:
			report.cleared = layer.get_used_cells().size()
			layer.get_parent().remove_child(layer)
			layer.queue_free()
		return report

	if layer == null:
		layer = scatter_layer(tm, true)
	if layer.tile_set != tm.tile_set:
		layer.tile_set = tm.tile_set
	report.cleared = layer.get_used_cells().size()
	layer.clear()

	# Stable terrain order determines which overlapping zone wins.
	var ids := []
	for id in zones:
		ids.push_back(int(id))
	ids.sort()

	var taken := face_cells(tm)
	for id in ids:
		report.written += _scatter_one(tm, layer, id, zone_cells(tm, id), taken)
	return report


static func _scatter_one(tm: TileMapLayer, layer: TileMapLayer, id: int, cells: Array, taken: Dictionary) -> int:
	var cfg := config_of(tm.tile_set, id)
	var bag: Array = cfg.get("bag", [])
	if bag.is_empty():
		return 0

	var entries := []
	var total := 0.0
	for e in bag:
		var n := normalise_entry(e)
		if n.is_empty() or n.weight <= 0.0:
			continue
		entries.push_back(n)
		total += n.weight
	if entries.is_empty() or total <= 0.0:
		return 0
	var empty_pct: float = clampf(float(cfg.get("empty_pct", 0.0)), 0.0, 100.0)

	var allowed := {}
	for c in inside_of(cells, int(cfg.get("edge", 0))):
		allowed[c] = true

	# Rows then columns, packed as ints: the native sort is much faster then sort_custom.
	var keys := PackedInt64Array()
	keys.resize(allowed.size())
	var k := 0
	for c: Vector2i in allowed:
		keys[k] = (int(c.y) << 32) + int(c.x) + 0x7fffffff
		k += 1
	keys.sort()

	var seed_of: int = int(cfg.get("seed", 0))
	var rng := RandomNumberGenerator.new()
	var written := 0
	for key in keys:
		var row := key >> 32
		var coord := Vector2i(key - (row << 32) - 0x7fffffff, row)
		if taken.has(coord):
			continue
		rng.seed = hash(Vector3i(coord.x, coord.y, seed_of))
		# Roll density first, then entry weight, to keep the two independent.
		if rng.randf() * 100.0 < empty_pct:
			continue
		var pick: float = rng.randf() * total
		var chosen := {}
		for e in entries:
			if pick < e.weight:
				chosen = e
				break
			pick -= e.weight
		if chosen.is_empty():
			continue  # Rounding can place the draw beyond the final weight.

		var src := tm.tile_set.get_source(chosen.source) as TileSetAtlasSource
		if src == null:
			continue
		var base: Rect2i = chosen.base
		# One-tile pieces skip the block bookkeeping.
		if chosen.size == Vector2i.ONE and base.size == Vector2i.ONE and base.position == Vector2i.ZERO:
			taken[coord] = true
			if src.get_tile_at_coords(chosen.origin) == chosen.origin:
				layer.set_cell(coord, chosen.source, chosen.origin, 0)
				written += 1
			continue
		var origin: Vector2i = coord - base.position
		var footprint := _block_cells(coord, base.size)
		if not _fits(footprint, allowed, taken):
			continue
		var block := _block_cells(origin, chosen.size)
		for c in footprint:
			taken[c] = true
		for i in block.size():
			var offset: Vector2i = block[i] - origin
			var atlas: Vector2i = chosen.origin + offset
			if src.get_tile_at_coords(atlas) != atlas:
				continue
			layer.set_cell(block[i], chosen.source, atlas, 0)
			written += 1
	return written


static func _block_cells(origin: Vector2i, size: Vector2i) -> Array:
	var out := []
	for dy in size.y:
		for dx in size.x:
			out.push_back(origin + Vector2i(dx, dy))
	return out


static func inside_of(cells: Array, rim: int) -> Array:
	if rim <= 0:
		return cells
	var zone := {}
	for c in cells:
		zone[c] = true
	var out := []
	for c: Vector2i in cells:
		var clear := true
		for dy in range(-rim, rim + 1):
			for dx in range(-rim, rim + 1):
				if not zone.has(c + Vector2i(dx, dy)):
					clear = false
					break
			if not clear:
				break
		if clear:
			out.push_back(c)
	return out


static func _fits(block: Array, allowed: Dictionary, taken: Dictionary) -> bool:
	for c in block:
		if not allowed.has(c) or taken.has(c):
			return false
	return true

#endregion
