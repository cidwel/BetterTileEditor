@tool
extends RefCounted
## Stretch: one atlas block grows to fit the painted region. Each cell takes its block row from
## how far it is from the region's top and bottom, and its block column likewise; one row and one
## column repeat to fill the rest.

const ExemplarData := preload("res://addons/better-tile-editor/ExemplarData.gd")

const TYPE_STRETCH := 8   # BetterTileEditor.TerrainType.STRETCH


static func stretch_terrains(ts: TileSet) -> Array:
	var out := []
	if ts == null or not ts.has_meta(&"_better_terrain"):
		return out
	var meta = ts.get_meta(&"_better_terrain")
	if typeof(meta) != TYPE_DICTIONARY:
		return out
	var terrains: Array = meta.get("terrains", [])
	for i in terrains.size():
		var t: Array = terrains[i]
		if t.size() >= 3 and int(t[2]) == TYPE_STRETCH:
			out.append(i)
	return out


static func has_stretch(ts: TileSet) -> bool:
	return not stretch_terrains(ts).is_empty()


## {source, rect, row, col}: row and col are the repeating ones, counted inside the block.
static func block_of(ts: TileSet, terrain_index: int) -> Dictionary:
	var cfg := _config(ts, terrain_index)
	var d = cfg.get("stretch", {})
	if not (d is Dictionary) or not d.has("rect") or (d["rect"] as Array).size() != 4:
		return {}
	var r: Array = d["rect"]
	var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	@warning_ignore("integer_division")
	return {
		"source": int(d.get("source", -1)), "rect": rect,
		"row": clampi(int(d.get("row", rect.size.y / 2)), 0, rect.size.y - 1),
		"col": clampi(int(d.get("col", rect.size.x / 2)), 0, rect.size.x - 1),
	}


static func record_block(ts: TileSet, terrain_index: int, source_id: int, rect: Rect2i, row := -1, col := -1) -> void:
	if ts == null or terrain_index < 0 or not ts.has_meta(&"_better_terrain"):
		return
	var meta = ts.get_meta(&"_better_terrain")
	var terrains: Array = meta.get("terrains", [])
	if terrain_index >= terrains.size():
		return
	var t: Array = terrains[terrain_index]
	while t.size() < 7:
		t.push_back("" if t.size() == 5 else {})
	var cfg: Dictionary = t[6].duplicate() if t[6] is Dictionary else {}
	var entry := {"source": source_id, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]}
	if row >= 0:
		entry["row"] = row
	if col >= 0:
		entry["col"] = col
	cfg["stretch"] = entry
	t[6] = cfg
	ts.set_meta(&"_better_terrain", meta)
	ts.emit_changed()


## Pins the block the marked tiles span; a block that moved or grew drops its repeat choice.
## As with Patch, only a fully marked block replaces a pinned one.
static func sync_block(ts: TileSet, terrain_index: int) -> Dictionary:
	var marked := ExemplarData.marked_rect(ts, terrain_index)
	var pinned := block_of(ts, terrain_index)
	if marked.is_empty() or (not pinned.is_empty() and not bool(marked.complete)):
		return pinned
	if pinned.is_empty() or int(pinned.source) != int(marked.source) or pinned.rect != marked.rect:
		record_block(ts, terrain_index, int(marked.source), marked.rect)
		return block_of(ts, terrain_index)
	return pinned


## Makes [param atlas_coord] the repeating row and column; false when it is outside the block.
static func set_repeat(ts: TileSet, terrain_index: int, source_id: int, atlas_coord: Vector2i) -> bool:
	var b := sync_block(ts, terrain_index)
	if b.is_empty() or int(b.source) != source_id or not (b.rect as Rect2i).has_point(atlas_coord):
		return false
	var at: Vector2i = atlas_coord - (b.rect as Rect2i).position
	record_block(ts, terrain_index, source_id, b.rect, at.y, at.x)
	return true


## Block index for a cell [param before] cells from one end and [param after] from the other.
## Fixed rows are kept closest to their own end; middle rows go first when the region is short.
static func pick(before: int, after: int, size: int, repeat: int) -> int:
	var near_start := before < repeat
	var near_end := after < size - 1 - repeat
	if near_start and near_end:
		return before if before <= after else size - 1 - after
	if near_start:
		return before
	if near_end:
		return size - 1 - after
	return repeat


static func tile_for(region: Dictionary, cell: Vector2i, block: Dictionary) -> Vector2i:
	var rect: Rect2i = block.rect
	var row := pick(_run(region, cell, Vector2i.UP), _run(region, cell, Vector2i.DOWN), rect.size.y, int(block.row))
	var col := pick(_run(region, cell, Vector2i.LEFT), _run(region, cell, Vector2i.RIGHT), rect.size.x, int(block.col))
	return rect.position + Vector2i(col, row)


static func _run(region: Dictionary, cell: Vector2i, step: Vector2i) -> int:
	var n := 0
	var at := cell + step
	while region.has(at):
		n += 1
		at += step
	return n


## The cells whose tiles a change at [param cells] can move: the stretch runs through them.
static func affected(tm: TileMapLayer, bt, cells: Array) -> Array:
	var ts := tm.tile_set if tm else null
	if ts == null or not has_stretch(ts):
		return cells
	var out := {}
	for c in cells:
		out[c] = true
		for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var at: Vector2i = c + step
			var t := _member_of(tm, bt, at, ts)
			if t < 0:
				continue
			while _member_of(tm, bt, at, ts) == t:
				out[at] = true
				at += step
	return out.keys()


static func _member_of(tm: TileMapLayer, bt, cell: Vector2i, ts: TileSet) -> int:
	var sid := tm.get_cell_source_id(cell)
	if sid == -1:
		return -1
	var at := tm.get_cell_atlas_coords(cell)
	for index in stretch_terrains(ts):
		var b := block_of(ts, index)
		if not b.is_empty() and int(b.source) == sid and (b.rect as Rect2i).has_point(at):
			return index
	var t: int = bt.get_cell(tm, cell)
	return t if t in stretch_terrains(ts) else -1


static func rebuild(tm: TileMapLayer, bt, _changed_cells: Variant = null) -> Dictionary:
	var report := {"region": 0, "written": 0}
	var ts := tm.tile_set if tm else null
	if ts == null:
		return report
	var wanted := stretch_terrains(ts)
	if wanted.is_empty():
		return report
	var blocks := {}
	for index in wanted:
		var b := sync_block(ts, index)
		if not b.is_empty():
			blocks[index] = b
	if blocks.is_empty():
		return report

	var by_hand: Dictionary = bt.hand_placed(tm)
	var seams: Dictionary = bt.seams(tm)
	var regions := {}
	for c in tm.get_used_cells():
		if by_hand.has(c) or seams.has(c):
			continue
		var sid := tm.get_cell_source_id(c)
		var at := tm.get_cell_atlas_coords(c)
		var t := -1
		for index in blocks:
			if int(blocks[index].source) == sid and (blocks[index].rect as Rect2i).has_point(at):
				t = index
				break
		if t < 0:
			t = bt.get_cell(tm, c)
		if blocks.has(t):
			if not regions.has(t):
				regions[t] = {}
			regions[t][c] = true

	for index in regions:
		var region: Dictionary = regions[index]
		var b: Dictionary = blocks[index]
		var sid := int(b.source)
		for cell in region:
			var coord := tile_for(region, cell, b)
			report.region += 1
			if tm.get_cell_source_id(cell) != sid or tm.get_cell_atlas_coords(cell) != coord or tm.get_cell_alternative_tile(cell) != 0:
				tm.set_cell(cell, sid, coord)
				report.written += 1
	return report


static func _config(ts: TileSet, terrain_index: int) -> Dictionary:
	if ts == null or terrain_index < 0 or not ts.has_meta(&"_better_terrain"):
		return {}
	var meta = ts.get_meta(&"_better_terrain")
	if typeof(meta) != TYPE_DICTIONARY:
		return {}
	var terrains: Array = meta.get("terrains", [])
	if terrain_index >= terrains.size():
		return {}
	var t: Array = terrains[terrain_index]
	return t[6] if t.size() >= 7 and t[6] is Dictionary else {}
