@tool
extends RefCounted

const SupportLayers := preload("res://addons/better-tile-editor/SupportLayers.gd")

const ExemplarTerrain := preload("res://addons/better-tile-editor/ExemplarTerrain.gd")
const CliffData := preload("res://addons/better-tile-editor/CliffData.gd")
const CliffPattern := preload("res://addons/better-tile-editor/CliffPattern.gd")

const FACES_LAYER_NAME := "_CliffFaces"
const FACES_LAYER_SCRIPT := "res://addons/better-tile-editor/CliffFacesLayer.gd"


## Returns the explicit wall heighs, or -1 when unset.
static func explicit_rows(tm: TileMapLayer) -> int:
	var faces := SupportLayers.find_layer(tm, FACES_LAYER_NAME) if tm != null else null
	if faces == null:
		return -1
	var v = faces.get("cliffRows")
	return v if typeof(v) == TYPE_INT and v >= 0 else -1


static func rows_for(tm: TileMapLayer) -> int:
	var rows := explicit_rows(tm)
	return rows if rows >= 0 else level_of(tm)


## A negative value clears the height override.
static func set_rows_override(tm: TileMapLayer, rows: int) -> void:
	var faces := find_faces(tm)
	if faces == null:
		faces = faces_layer(tm, true)
	if faces != null:
		faces.set("cliffRows", rows)

## Reserve two z slots per level: ground above its faces and above the previous level.
const LEVEL_Z_BASE := 0
const LEVEL_Z_STRIDE := 2


static func z_for_level(level: int) -> int:
	return LEVEL_Z_BASE + level * LEVEL_Z_STRIDE


static func _terrain_indices(bt, ts: TileSet, name: String) -> Array:
	var out := []
	for i in bt.terrain_count(ts):
		if bt.get_terrain(ts, i).get("name", "") == name:
			out.append(i)
	return out


static func is_level(n: Node) -> bool:
	if n == null or not (n is TileMapLayer):
		return false
	if SupportLayers.find_layer(n, FACES_LAYER_NAME) != null:
		return true
	return _paints_cliff_terrain(n)


static func _paints_cliff_terrain(tm: TileMapLayer) -> bool:
	var ts := tm.tile_set
	if ts == null:
		return false
	var names: Array = CliffData.all_configs(ts).keys()
	if names.is_empty():
		return false
	var meta: Dictionary = ts.get_meta(&"_better_terrain", {})
	var terrains: Array = meta.get("terrains", [])
	var wanted := {}
	for i in terrains.size():
		if str(terrains[i][0]) in names:
			wanted[i] = true
	if wanted.is_empty():
		return false
	for c in tm.get_used_cells():
		var td: TileData = tm.get_cell_tile_data(c)
		if td == null or not td.has_meta(&"_better_terrain"):
			continue
		var m = td.get_meta(&"_better_terrain")
		if m is Dictionary and wanted.has(int(m.get("type", -1))):
			return true
	return false


static func explicit_level(n: Node) -> int:
	var faces := SupportLayers.find_layer(n, FACES_LAYER_NAME)
	if faces == null:
		return -1
	var v = faces.get("cliffLevel")
	return v if typeof(v) == TYPE_INT and v >= 0 else -1


static func level_of(tm: Node) -> int:
	if not is_level(tm):
		return 0
	var parent := tm.get_parent()
	if parent == null:
		return max(0, explicit_level(tm))
	var level := -1
	for c in parent.get_children():
		if not is_level(c):
			continue
		var e := explicit_level(c)
		if e >= 0:
			level = e
		else:
			level += 1
		if c == tm:
			return level
	return 0


## Read-only lookup; faces_layer may create, migrate or reposition nodes.
static func find_faces(tm: TileMapLayer) -> TileMapLayer:
	if tm == null:
		return null
	return SupportLayers.find_layer(tm, FACES_LAYER_NAME)


## Mutates the scene tree; use find_faces during drawing or selection changes.
static func faces_layer(tm: TileMapLayer, create := false) -> TileMapLayer:
	if tm == null:
		return null

	var parent := tm.get_parent()
	if parent != null:
		var stray := parent.get_node_or_null(NodePath("%s%s" % [tm.name, FACES_LAYER_NAME]))
		if stray is TileMapLayer:
			parent.remove_child(stray)
			stray.queue_free()

	var existing := SupportLayers.find_layer(tm, FACES_LAYER_NAME)
	if existing != null:
		SupportLayers.prepare(existing)
		if existing.get_script() == null:
			existing.set_script(load(FACES_LAYER_SCRIPT))
		_place_behind(existing)
		return existing
	if not create:
		return null

	var l := TileMapLayer.new()
	l.set_script(load(FACES_LAYER_SCRIPT))
	l.name = FACES_LAYER_NAME
	SupportLayers.prepare(l)
	l.tile_set = tm.tile_set
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tm.add_child(l)
	if tm.owner != null:
		l.owner = tm.owner
	_place_behind(l)
	return l


static func _place_behind(l: TileMapLayer) -> void:
	l.z_as_relative = true
	l.z_index = -1
	l.show_behind_parent = false


static func _layers_above(tm: Node, level: int) -> Array:
	var out := []
	var parent := tm.get_parent()
	if parent == null:
		return out
	for c in parent.get_children():
		if c == tm or not is_level(c):
			continue
		if level_of(c) > level:
			out.append(c)
	return out


## Only higher levels suppress face cells; ground on this level may cover them visually.
static func _covering_layers(tm: Node, level: int) -> Array:
	return _layers_above(tm, level)


static func _covered_from_above(above: Array, coord: Vector2i) -> bool:
	for l in above:
		if l.get_cell_source_id(coord) != -1:
			return true
	return false


static func _drop_if_empty(tm: TileMapLayer, dry_run: bool) -> void:
	if dry_run:
		return
	var l := SupportLayers.find_layer(tm, FACES_LAYER_NAME)
	if l == null or not l.get_used_cells().is_empty():
		return
	# Keep empty nodes lith explicit settings, including a zero wall height.
	if int(l.get("cliffRows")) >= 0 or int(l.get("cliffLevel")) >= 0:
		return
	tm.remove_child(l)
	l.queue_free()


static func rebuild(tm: TileMapLayer, bt, dry_run := false) -> Dictionary:
	var report := {"written": 0, "cleared": 0, "conflicts": [], "missing": {}, "covered": 0}
	var ts := tm.tile_set if tm else null
	if ts == null:
		return report

	var faces := faces_layer(tm, false)
	var previous: int = faces.get_used_cells().size() if faces != null else 0

	var level := level_of(tm)
	var covering := _covering_layers(tm, level)
	var rows := rows_for(tm)

	if not dry_run and is_level(tm):
		var wanted := z_for_level(level)
		if wanted > 9:
			push_warning("[BetterTerrain] %s is level %d, which puts its ground at z=%d, outside the 0-9 band (it holds 5 levels). Wall height is the terrain's cliff height, not the level." % [tm.name, level, wanted])
		if tm.z_index != wanted or not tm.z_as_relative:
			tm.z_as_relative = true
			tm.z_index = wanted

	if SupportLayers.is_frozen(faces):
		report["frozen"] = true
		return report

	if level <= 0 and explicit_rows(tm) <= 0:
		if faces != null and not dry_run:
			faces.clear()
		report.cleared = previous
		_drop_if_empty(tm, dry_run)
		return report

	if faces != null and not dry_run:
		faces.clear()

	var wanted := {}
	for terrain_name in CliffData.all_configs(ts).keys():
		for index in _terrain_indices(bt, ts, terrain_name):
			wanted[index] = terrain_name
	if wanted.is_empty():
		_drop_if_empty(tm, dry_run)
		return report
	var by_terrain := {}
	# Exemplar rims extend the plateau, so their cells also start cliff faces.
	var sources: Array = [tm]
	var edges := SupportLayers.find_layer(tm, ExemplarTerrain.EDGES_LAYER_NAME)
	if edges != null:
		sources.append(edges)
	var seen := {}
	for layer in sources:
		for c in layer.get_used_cells():
			if seen.has(c):
				continue
			var t: int = bt.get_cell(layer, c)
			if wanted.has(t):
				seen[c] = true
				if not by_terrain.has(t):
					by_terrain[t] = []
				by_terrain[t].append(c)

	for index in by_terrain:
		var terrain_name: String = wanted[index]
		var cfg := CliffData.config_of(ts, terrain_name)
		var cells: Array = by_terrain[index]

		var plateau := {}
		for c in cells:
			plateau[c] = true
		var face_map := CliffData.face_map(cells, rows)
		if CliffPattern.is_pattern(cfg):
			_write_pattern(tm, ts, cfg, plateau, face_map, rows, covering, report, dry_run)
			continue
		var runs := CliffData.slot_runs(plateau, face_map)

		for f in face_map.keys():
			if _covered_from_above(covering, f):
				report.covered += 1
				continue
			var row: String = face_map[f].row
			var case_name: String = runs[f].case
			var tile := CliffData.resolve_tile(cfg, row, case_name)
			if tile.is_empty():
				var k := CliffData.slot_key(row, case_name)
				report.missing[k] = report.missing.get(k, 0) + 1
				continue

			if tm.get_cell_source_id(f) != -1:
				report.conflicts.append(f)

			var from_bottom: bool = bool(cfg.get("from_bottom", false))
			# Measure from the matrix bottom without clamping, or its last row repeats twice.
			var vphase: int = int(face_map[f].rise) - CliffData.matrix_foot(tile, row) if from_bottom else int(face_map[f].band)
			var coord := CliffData.block_coord(tile, int(runs[f].phase), vphase, from_bottom)
			var src := ts.get_source(int(tile.source_id)) as TileSetAtlasSource
			if src != null and not src.has_tile(coord):
				coord = tile.coord
			if not dry_run:
				if faces == null:
					faces = faces_layer(tm, true)
				faces.set_cell(f, int(tile.source_id), coord)
			report.written += 1

	report.cleared = maxi(0, previous - report.written)
	_drop_if_empty(tm, dry_run)
	return report


static func _write_pattern(tm: TileMapLayer, ts: TileSet, cfg: Dictionary, plateau: Dictionary, face_map: Dictionary, rows: int, covering: Array, report: Dictionary, dry_run: bool) -> void:
	var runs := CliffPattern.runs_of(plateau, face_map)
	var faces := faces_layer(tm, false)
	for f in face_map.keys():
		if _covered_from_above(covering, f):
			report.covered += 1
			continue
		var rise: int = int(face_map[f].rise)
		var tile := CliffPattern.tile_for(cfg, runs[f], rows - 1 - rise, rise, rows)
		if tile.is_empty():
			report.missing["pattern/body"] = report.missing.get("pattern/body", 0) + 1
			continue
		var src := ts.get_source(int(tile.source_id)) as TileSetAtlasSource
		if src != null and not src.has_tile(tile.coord):
			report.missing["pattern/outside the atlas"] = report.missing.get("pattern/outside the atlas", 0) + 1
			continue
		if tm.get_cell_source_id(f) != -1:
			report.conflicts.append(f)
		if not dry_run:
			if faces == null:
				faces = faces_layer(tm, true)
			faces.set_cell(f, int(tile.source_id), tile.coord)
		report.written += 1
