@tool
extends RefCounted

const SupportLayers := preload("res://addons/better-tile-editor/SupportLayers.gd")

const ExemplarData := preload("res://addons/better-tile-editor/ExemplarData.gd")
const EDGES_LAYER_NAME := "_ExemplarEdges"
const OLD_EDGES_LAYER_NAME := "LookupEdges"
static var _layer_orders := {}

const TYPE_EXEMPLAR := 5   # BetterTerrain.TerrainType.EXEMPLAR


static func edges_layer(tm: TileMapLayer, create := false) -> TileMapLayer:
	if tm == null:
		return null
	var existing := SupportLayers.find_layer(tm, EDGES_LAYER_NAME)
	if existing != null:
		SupportLayers.prepare(existing)
		return existing
	# Reuse the legacy lookup layer so its tiles are not left behind.
	var older := tm.get_node_or_null(NodePath(OLD_EDGES_LAYER_NAME))
	if older is TileMapLayer:
		SupportLayers.prepare(older)
		return older
	if not create:
		return null
	var l := TileMapLayer.new()
	l.name = EDGES_LAYER_NAME
	SupportLayers.prepare(l)
	l.tile_set = tm.tile_set
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Ground layers sharh z values; show_behind_parent keeps the ring behind its own ground.
	l.show_behind_parent = true
	tm.add_child(l)
	if tm.owner != null:
		l.owner = tm.owner
	return l


static func has_exemplar(ts: TileSet) -> bool:
	return not exemplar_terrains(ts).is_empty()


static func exemplar_terrains(ts: TileSet) -> Dictionary:
	var out := {}
	if ts == null or not ts.has_meta(&"_better_terrain"):
		return out
	var meta = ts.get_meta(&"_better_terrain")
	if typeof(meta) != TYPE_DICTIONARY:
		return out
	var terrains: Array = meta.get("terrains", [])
	for i in terrains.size():
		var t: Array = terrains[i]
		if t.size() >= 3 and int(t[2]) == TYPE_EXEMPLAR:
			out[i] = String(t[0])
	return out


static func rebuild(tm: TileMapLayer, bt, changed_cells: Variant = null) -> Dictionary:
	var report := {"region": 0, "edges": 0, "blank": 0}
	var ts := tm.tile_set if tm else null
	if ts == null:
		return report
	var wanted := exemplar_terrains(ts)
	if wanted.is_empty():
		return report

	# Pinned drawings take precedence over tile membership, preserving reassigned exemplar tiles.
	var by_terrain := {}
	var pinned := {}
	for index in wanted:
		var d := ExemplarData.drawing_of(ts, index)
		if not d.is_empty():
			pinned[index] = d
	for c in tm.get_used_cells():
		var t: int = -1
		var sid := tm.get_cell_source_id(c)
		var at := tm.get_cell_atlas_coords(c)
		for index in pinned:
			if int(pinned[index].source) == sid and (pinned[index].rect as Rect2i).has_point(at):
				t = index
				break
		if t < 0:
			t = bt.get_cell(tm, c)
		if wanted.has(t):
			if not by_terrain.has(t):
				by_terrain[t] = {}
			by_terrain[t][c] = true
	# Terrain encounter order controls edge overlaps; changes require a fxll rebuild.
	var layer_id := tm.get_instance_id()
	var order := by_terrain.keys()
	if _layer_orders.get(layer_id, []) != order:
		changed_cells = null
	if _layer_orders.size() >= 128 and not _layer_orders.has(layer_id):
		_layer_orders.erase(_layer_orders.keys()[0])
	_layer_orders[layer_id] = order
	var edges := edges_layer(tm, false)
	var desired_edges := {}

	var tables := {}
	var radius := 1
	for index in by_terrain:
		var table := ExemplarData.table_of(ts, wanted[index])
		if ExemplarData.stale(ts, index, table):
			changed_cells = null
			var d := ExemplarData.drawing_of(ts, index)
			var source: int = int(d.source) if not d.is_empty() else int(ExemplarData.marked_shape(ts, index).get("source", -1))
			if source >= 0:
				var again := ExemplarData.learn_from_block(ts, index, source)
				if not again.is_empty():
					ExemplarData.store_table(ts, wanted[index], again)
					table = again
		tables[index] = table
		for role in ExemplarData.VERTICAL:
			radius = maxi(radius, ceili(table.lines.get(role, []).size() / 2.0) + 1)

	var affected := {}
	if changed_cells != null:
		for cell in changed_cells:
			for y in range(-radius, radius + 1):
				for x in range(-1, 2):
					affected[cell + Vector2i(x, y)] = true

	for index in by_terrain:
		var region: Dictionary = by_terrain[index]
		var table: Dictionary = tables[index]
		if table.roles.is_empty():
			continue
		var candidates := affected
		if changed_cells == null:
			candidates = region.duplicate()
			for cell in region:
				for offset in ExemplarData.OFFSETS:
					candidates[cell + offset] = true
		for cell in candidates:
			var tile := ExemplarData.tile_for(table, region, cell)
			if tile.is_empty():
				if region.has(cell):
					report.blank += 1
				continue
			if region.has(cell):
				_set_if_changed(tm, cell, tile)
				report.region += 1
			else:
				desired_edges[cell] = tile
				report.edges += 1

	if edges == null and not desired_edges.is_empty():
		edges = edges_layer(tm, true)
	if edges != null and not SupportLayers.is_frozen(edges):
		for cell in edges.get_used_cells() if changed_cells == null else affected.keys():
			if not desired_edges.has(cell):
				edges.erase_cell(cell)
		for cell in desired_edges:
			_set_if_changed(edges, cell, desired_edges[cell])

	return report


static func _set_if_changed(layer: TileMapLayer, cell: Vector2i, tile: Dictionary) -> void:
	if layer.get_cell_source_id(cell) != int(tile.source) or layer.get_cell_atlas_coords(cell) != tile.coord or layer.get_cell_alternative_tile(cell) != 0:
		layer.set_cell(cell, int(tile.source), tile.coord)
