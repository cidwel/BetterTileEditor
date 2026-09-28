@tool
extends RefCounted

const META := &"_better_terrain_exemplar"

const OFFSETS := [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]
const SIDES := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## IN_ roles belong to the terrain; OUT_ roles belong to its generated ring.
const ROLES := [
	"IN_NW", "IN_N", "IN_NE",
	"IN_W", "IN_C", "IN_E",
	"IN_SW", "IN_S", "IN_SE",
	"OUT_NW", "OUT_N", "OUT_NE",
	"OUT_W", "OUT_E",
	"OUT_SW", "OUT_S", "OUT_SE",
]

const CORNERS := ["CORNER_NW", "CORNER_NE", "CORNER_SW", "CORNER_SE"]

const VERTICAL := ["IN_W", "IN_E", "OUT_W", "OUT_E"]

const LABELS := {
	"IN_NW": "water, bank above and left", "IN_N": "water, bank above",
	"IN_NE": "water, bank above and right", "IN_W": "water, bank left",
	"IN_C": "open water", "IN_E": "water, bank right",
	"IN_SW": "water, bank below and left", "IN_S": "water, bank below",
	"IN_SE": "water, bank below and right",
	"OUT_NW": "bank, top left corner", "OUT_N": "bank above the water",
	"OUT_NE": "bank, top right corner", "OUT_W": "bank left of the water",
	"OUT_E": "bank right of the water", "OUT_SW": "bank, bottom left corner",
	"OUT_S": "bank below the water", "OUT_SE": "bank, bottom right corner",
	"CORNER_NW": "outer corner, top left (if drawn)", "CORNER_NE": "outer corner, top right (if drawn)",
	"CORNER_SW": "outer corner, bottom left (if drawn)", "CORNER_SE": "outer corner, bottom right (if drawn)",
}


static func role_label(role: String) -> String:
	return LABELS.get(role, role)


#region Stored sheet

static func all_tables(ts: TileSet) -> Dictionary:
	return ts.get_meta(META, {}) if ts else {}


static func table_of(ts: TileSet, terrain_name: String) -> Dictionary:
	var t: Dictionary = all_tables(ts).get(terrain_name, {})
	return {
		"source": t.get("source", -1),
		"roles": t.get("roles", {}),    # role -> [x, y], what to draw
		"lines": t.get("lines", {}),    # role -> [[x, y], ...], the run to stretch
		"slots": t.get("slots", {}),    # role -> where those cells sit in the drawing
		"block": t.get("block", []),    # [x, y, w, h] of the drawing that was read
		"water": t.get("water", []),    # [x, y, w, h] of what it wraps
		"tiles": t.get("tiles", 0),
		"corners_read": bool(t.get("corners_read", false)),
	}


static func marked_shape(ts: TileSet, terrain_index: int) -> Dictionary:
	var best := {}
	if ts == null:
		return best
	for i in ts.get_source_count():
		var sid := ts.get_source_id(i)
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src == null:
			continue
		var n := 0
		var lo := Vector2i(1 << 30, 1 << 30)
		var hi := Vector2i(-(1 << 30), -(1 << 30))
		for t in src.get_tiles_count():
			var coord := src.get_tile_id(t)
			var td := src.get_tile_data(coord, 0)
			if td == null or not td.has_meta(&"_better_terrain"):
				continue
			var meta = td.get_meta(&"_better_terrain")
			if typeof(meta) == TYPE_DICTIONARY and int(meta.get("type", -99)) == terrain_index:
				n += 1
				lo = Vector2i(mini(lo.x, coord.x), mini(lo.y, coord.y))
				hi = Vector2i(maxi(hi.x, coord.x), maxi(hi.y, coord.y))
		if n > int(best.get("tiles", 0)):
			best = {"source": sid, "block": [lo.x, lo.y, hi.x - lo.x + 1, hi.y - lo.y + 1], "tiles": n}
	return best


static func stale(ts: TileSet, terrain_index: int, table: Dictionary) -> bool:
	if table.roles.is_empty() or not bool(table.get("corners_read", false)):
		return true
	var pinned := drawing_of(ts, terrain_index)
	var marked := marked_rect(ts, terrain_index)
	# Only complete rectangles replace the pinned drawing; a missing tile may have been reassigned.
	if not marked.is_empty() and bool(marked.complete):
		if pinned.is_empty() or int(marked.source) != int(pinned.source) or marked.rect != pinned.rect:
			record_drawing(ts, terrain_index, int(marked.source), marked.rect)
			return true
	if pinned.is_empty():
		return false
	var r: Rect2i = pinned.rect
	return int(table.source) != int(pinned.source) \
			or table.block != [r.position.x, r.position.y, r.size.x, r.size.y]


## Pin the source and rectangle so reassigning a tile cannot change the exemplar drawing.
static func drawing_of(ts: TileSet, terrain_index: int) -> Dictionary:
	if ts == null or terrain_index < 0 or not ts.has_meta(&"_better_terrain"):
		return {}
	var meta = ts.get_meta(&"_better_terrain")
	if typeof(meta) != TYPE_DICTIONARY:
		return {}
	var terrains: Array = meta.get("terrains", [])
	if terrain_index >= terrains.size():
		return {}
	var t: Array = terrains[terrain_index]
	if t.size() < 7 or not (t[6] is Dictionary):
		return {}
	var d = t[6].get("exemplar", {})
	if not (d is Dictionary) or not d.has("rect"):
		return {}
	var r: Array = d["rect"]
	if r.size() != 4:
		return {}
	return {"source": int(d.get("source", -1)), "rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))}


static func record_drawing(ts: TileSet, terrain_index: int, source_id: int, rect: Rect2i) -> void:
	if ts == null or terrain_index < 0 or not ts.has_meta(&"_better_terrain"):
		return
	var meta = ts.get_meta(&"_better_terrain")
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var terrains: Array = meta.get("terrains", [])
	if terrain_index >= terrains.size():
		return
	var t: Array = terrains[terrain_index]
	while t.size() < 7:
		t.push_back("" if t.size() == 5 else {})
	var cfg: Dictionary = t[6].duplicate() if t[6] is Dictionary else {}
	cfg["exemplar"] = {"source": source_id, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]}
	t[6] = cfg
	ts.set_meta(&"_better_terrain", meta)
	ts.emit_changed()


static func marked_rect(ts: TileSet, terrain_index: int) -> Dictionary:
	var shape := marked_shape(ts, terrain_index)
	if shape.is_empty():
		return {}
	var b: Array = shape.block
	var rect := Rect2i(int(b[0]), int(b[1]), int(b[2]), int(b[3]))
	var complete: bool = int(shape.tiles) == rect.size.x * rect.size.y
	return {"source": int(shape.source), "rect": rect, "complete": complete, "tiles": int(shape.tiles)}


static func strays(ts: TileSet, terrain_index: int) -> Array:
	var out := []
	var d := drawing_of(ts, terrain_index)
	if d.is_empty():
		return out
	var src := ts.get_source(int(d.source)) as TileSetAtlasSource
	if src == null:
		return out
	var rect: Rect2i = d.rect
	for y in rect.size.y:
		for x in rect.size.x:
			var coord := rect.position + Vector2i(x, y)
			if not src.has_tile(coord):
				continue
			var td := src.get_tile_data(coord, 0)
			if td == null or not td.has_meta(&"_better_terrain"):
				continue
			var meta = td.get_meta(&"_better_terrain")
			if typeof(meta) == TYPE_DICTIONARY:
				var owner := int(meta.get("type", -99))
				if owner >= 0 and owner != terrain_index:
					out.append(coord)
	return out


static func store_table(ts: TileSet, terrain_name: String, table: Dictionary) -> void:
	if not ts: return
	var all := all_tables(ts).duplicate(true)
	all[terrain_name] = table
	ts.set_meta(META, all)
	ts.emit_changed()


static func has_tables(ts: TileSet) -> bool:
	return ts != null and not all_tables(ts).is_empty()

#endregion


#region The rule

static func role_for(region: Dictionary, c: Vector2i) -> String:
	var inside := region.has(c)
	var n := region.has(c + Vector2i(0, -1))
	var e := region.has(c + Vector2i(1, 0))
	var s := region.has(c + Vector2i(0, 1))
	var w := region.has(c + Vector2i(-1, 0))

	if not inside:
		if s:
			if not w and not region.has(c + Vector2i(-1, 1)): return "OUT_NW"
			if not e and not region.has(c + Vector2i(1, 1)): return "OUT_NE"
			return "OUT_N"
		if n:
			if not w and not region.has(c + Vector2i(-1, -1)): return "OUT_SW"
			if not e and not region.has(c + Vector2i(1, -1)): return "OUT_SE"
			return "OUT_S"
		if e: return "OUT_W"
		if w: return "OUT_E"
		if region.has(c + Vector2i(1, 1)): return "CORNER_NW"
		if region.has(c + Vector2i(-1, 1)): return "CORNER_NE"
		if region.has(c + Vector2i(1, -1)): return "CORNER_SW"
		if region.has(c + Vector2i(-1, -1)): return "CORNER_SE"
		return ""

	var v := "N" if not n else ("S" if not s else "")
	var h := "W" if not w else ("E" if not e else "")
	if v != "" or h != "":
		return "IN_" + v + h
	# Only upper diagonal gaps expose notches; the near bank hides lower gaps.
	if not region.has(c + Vector2i(1, -1)): return "IN_E"
	if not region.has(c + Vector2i(-1, -1)): return "IN_W"
	return "IN_C"


static func _run_extent(region: Dictionary, c: Vector2i, role: String, limit: int) -> Vector2i:
	var before := 0
	var p := c + Vector2i(0, -1)
	while before < limit and role_for(region, p) == role:
		before += 1
		p += Vector2i(0, -1)
	var after := 0
	p = c + Vector2i(0, 1)
	while after < limit and role_for(region, p) == role:
		after += 1
		p += Vector2i(0, 1)
	return Vector2i(before, after)


static func tile_for(table: Dictionary, region: Dictionary, c: Vector2i) -> Dictionary:
	var role := role_for(region, c)
	if role == "":
		return {}
	var roles: Dictionary = table.roles
	if not roles.has(role):
		return {}
	var at: Array = roles[role]
	if role in VERTICAL:
		var line: Array = table.lines.get(role, [])
		if line.size() > 1:
			var n := line.size()
			# Beyond half the drawing, distance no longer changes the chosen tile.
			var ext := _run_extent(region, c, role, ceili(n / 2.0))
			if ext.x < n / 2 and ext.x <= ext.y:
				at = line[ext.x]
			elif ext.y < n / 2:
				at = line[n - 1 - ext.y]
	return {"source": int(table.source), "coord": Vector2i(int(at[0]), int(at[1]))}

#endregion


#region Reading the drawing

## Use atlas regions to include margins and separation when reading pixels.
static func _pixels(img: Image, region: Rect2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(maxi(region.size.x * region.size.y, 0))
	var inside := region.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	for y in inside.size.y:
		for x in inside.size.x:
			var at := inside.position + Vector2i(x, y)
			var o := (at.y - region.position.y) * region.size.x + (at.x - region.position.x)
			out[o] = int(img.get_pixel(at.x, at.y).to_rgba32())
	return out


## Straight banks minimize variation along their repeating axis.
static func _spread(p: PackedInt32Array, size: Vector2i, vertical: bool) -> int:
	if size.x <= 0 or size.y <= 0 or p.size() != size.x * size.y:
		return 1 << 30
	var lines := []
	if vertical:
		for y in size.y:
			lines.append(p.slice(y * size.x, (y + 1) * size.x))
	else:
		for x in size.x:
			var col := PackedInt32Array()
			for y in size.y:
				col.append(p[y * size.x + x])
			lines.append(col)
	var total := 0
	for a in lines:
		for b in lines:
			for i in a.size():
				if a[i] != b[i]:
					total += 1
	return total


static func _representative(role: String, candidates: Array, pix: Dictionary, psize: Dictionary) -> Array:
	if candidates.size() == 1:
		return candidates[0]
	if role in VERTICAL:
		var best: Array = candidates[0]
		var best_cost := 1 << 30
		for c in candidates:
			var cost: int = _spread(pix[c], psize[c], true)
			if cost < best_cost:
				best_cost = cost
				best = c
		return best
	# Choose the most typical tile to exclude decorations frcm irregular runs.
	var pick: Array = candidates[0]
	var pick_cost := 1 << 30
	for c in candidates:
		var cost := 0
		for o in candidates:
			if o == c: continue
			var a: PackedInt32Array = pix[c]
			var b: PackedInt32Array = pix[o]
			if a.size() != b.size():
				cost += maxi(a.size(), b.size())
				continue
			for i in a.size():
				if a[i] != b[i]:
					cost += 1
		if cost < pick_cost:
			pick_cost = cost
			pick = c
	return pick


static func learn_from_block(ts: TileSet, terrain_index: int, source_id: int) -> Dictionary:
	var src := ts.get_source(source_id) as TileSetAtlasSource
	if src == null or src.texture == null:
		return {}
	var owned := []
	var pinned := drawing_of(ts, terrain_index)
	if not pinned.is_empty() and int(pinned.source) == source_id:
		var rect: Rect2i = pinned.rect
		for y in rect.size.y:
			for x in rect.size.x:
				var coord := rect.position + Vector2i(x, y)
				if src.has_tile(coord):
					owned.append(coord)
	else:
		for i in src.get_tiles_count():
			var coord := src.get_tile_id(i)
			var td := src.get_tile_data(coord, 0)
			if td == null or not td.has_meta(&"_better_terrain"):
				continue
			var meta = td.get_meta(&"_better_terrain")
			if typeof(meta) == TYPE_DICTIONARY and int(meta.get("type", -99)) == terrain_index:
				owned.append(coord)
	if owned.is_empty():
		return {}

	var block := {}
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for c in owned:
		block[c] = true
		lo.x = mini(lo.x, c.x); lo.y = mini(lo.y, c.y)
		hi.x = maxi(hi.x, c.x); hi.y = maxi(hi.y, c.y)

	var water := {}
	var wlo := Vector2i(1 << 30, 1 << 30)
	var whi := Vector2i(-(1 << 30), -(1 << 30))
	for c in block:
		var solid := true
		for d in SIDES:
			if not block.has(c + d):
				solid = false
				break
		if solid:
			water[c] = true
			wlo.x = mini(wlo.x, c.x); wlo.y = mini(wlo.y, c.y)
			whi.x = maxi(whi.x, c.x); whi.y = maxi(whi.y, c.y)
	if water.is_empty():
		return {}
	if pinned.is_empty() or int(pinned.source) != source_id:
		record_drawing(ts, terrain_index, source_id, Rect2i(lo, hi - lo + Vector2i.ONE))

	var groups := {}
	for c in block:
		var role := _role_by_position(c, water, wlo, whi)
		if role == "":
			continue
		if not groups.has(role):
			groups[role] = []
		groups[role].append([c.x, c.y])

	var img := src.texture.get_image()
	if img == null:
		return {}
	if img.is_compressed():
		img.decompress()
	var pix := {}
	var psize := {}
	for role in groups:
		for at in groups[role]:
			var region := Rect2i(src.get_tile_texture_region(Vector2i(at[0], at[1]), 0))
			pix[at] = _pixels(img, region)
			psize[at] = region.size

	# Transparent corners have no role; to_rgba32 stores alpha in the low byte.
	for role in CORNERS:
		if not groups.has(role):
			continue
		var inked := []
		for at in groups[role]:
			var p: PackedInt32Array = pix[at]
			for v in p:
				if (v & 0xFF) > 8:
					inked.append(at)
					break
		if inked.is_empty():
			groups.erase(role)
		else:
			groups[role] = inked

	var roles := {}
	var lines := {}
	var slots := {}
	for role in groups:
		var run: Array = groups[role]
		run.sort_custom(func(a, b):
			if role in VERTICAL: return a[1] < b[1] if a[1] != b[1] else a[0] < b[0]
			return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
		roles[role] = _representative(role, run, pix, psize)
		lines[role] = run.duplicate(true)
		slots[role] = run
	return {
		"source": source_id,
		"roles": roles,
		"lines": lines,
		"slots": slots,
		"block": [lo.x, lo.y, hi.x - lo.x + 1, hi.y - lo.y + 1],
		"water": [wlo.x, wlo.y, whi.x - wlo.x + 1, whi.y - wlo.y + 1],
		"tiles": owned.size(),
		"corners_read": true,
	}


static func _role_by_position(c: Vector2i, water: Dictionary, wlo: Vector2i, whi: Vector2i) -> String:
	if water.has(c):
		var v := "N" if c.y == wlo.y else ("S" if c.y == whi.y else "")
		var h := "W" if c.x == wlo.x else ("E" if c.x == whi.x else "")
		return "IN_" + (v + h if v + h != "" else "C")
	if c.y < wlo.y or c.y > whi.y:
		var v2 := "N" if c.y < wlo.y else "S"
		if c.x == wlo.x: return "OUT_" + v2 + "W"
		if c.x == whi.x: return "OUT_" + v2 + "E"
		if c.x > wlo.x and c.x < whi.x: return "OUT_" + v2
		if c.x < wlo.x: return "CORNER_" + v2 + "W"
		return "CORNER_" + v2 + "E"
	if c.x < wlo.x: return "OUT_W"
	if c.x > whi.x: return "OUT_E"
	return ""

#endregion
