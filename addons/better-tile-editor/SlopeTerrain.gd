@tool
extends RefCounted

## Slope tool: a drag becomes a staircase of slope terrains, with Ground filled under it.

const META = &"_better_terrain_slopes"
# tile state from before the set-up took it, restored when released
const TAKEN_META = &"_better_terrain_slopes_taken"
const TYPE_MATCH_TILES := 0  # BetterTerrain.TerrainType.MATCH_TILES
const TYPE_CATEGORY := 2  # BetterTerrain.TerrainType.CATEGORY
const TYPE_FREE := -2  # BetterTerrain.TileCategory.NON_TERRAIN, a tile with no terrain
const MAX_FILL := 64
# group the terrain list hides
const HIDDEN_GROUP := "_hidden"
# category shared by slopes and Ground, owned by the set-up
const SOLID_META = &"_better_terrain_slopes_solid"

# gentle slopes climb one row per two cells: g1 is the low half, g2 the high half
const ROLES := ["ground",
	"steep_tl", "steep_tr", "steep_bl", "steep_br",
	"g1_tl", "g2_tl", "g1_tr", "g2_tr",
	"g1_bl", "g2_bl", "g1_br", "g2_br"]

const ROLE_LABELS := {
	"ground": "Ground",
	"steep_tl": "Steep, floor rising right", "steep_tr": "Steep, floor rising left",
	"steep_bl": "Steep, ceiling falling right", "steep_br": "Steep, ceiling falling left",
	"g1_tl": "Gentle low half, floor rising right", "g2_tl": "Gentle high half, floor rising right",
	"g1_tr": "Gentle low half, floor rising left", "g2_tr": "Gentle high half, floor rising left",
	"g1_bl": "Gentle low half, ceiling falling right", "g2_bl": "Gentle high half, ceiling falling right",
	"g1_br": "Gentle low half, ceiling falling left", "g2_br": "Gentle high half, ceiling falling left",
}


const ROLE_NAMES := {
	"steep_tl": "SteepSlopeTL", "steep_tr": "SteepSlopeTR", "steep_bl": "SteepSlopeBL", "steep_br": "SteepSlopeBR",
	"g1_tl": "GentleSlope1TL", "g2_tl": "GentleSlope2TL", "g1_tr": "GentleSlope1TR", "g2_tr": "GentleSlope2TR",
	"g1_bl": "GentleSlope1BL", "g2_bl": "GentleSlope2BL", "g1_br": "GentleSlope1BR", "g2_br": "GentleSlope2BR",
}

# [partner role, peering side the partner is on]
const THIN := {
	"g1_tl": ["g2_br", 4], "g2_tl": ["g1_br", 4], "g2_br": ["g1_tl", 12], "g1_br": ["g2_tl", 12],
	"g1_tr": ["g2_bl", 4], "g2_tr": ["g1_bl", 4], "g2_bl": ["g1_tr", 12], "g1_bl": ["g2_tr", 12],
	"steep_tl": ["steep_br", 0], "steep_br": ["steep_tl", 8], "steep_tr": ["steep_bl", 8], "steep_bl": ["steep_tr", 0],
}
# thin steep halves touch their partner both beside and above/below
const THIN_SIDES := {"steep_tl": [0, 4], "steep_br": [8, 12], "steep_tr": [8, 4], "steep_bl": [0, 12]}
const SIDES := [0, 3, 4, 7, 8, 11, 12, 15]

# simple mode: only rising-right pieces are picked, the rest are flips of them
const MODE_META = &"_better_terrain_slopes_mode"
const TURNED_META = &"_better_terrain_slope_turned"
const TURN_ID_BASE := 700
const GROUND_PICK_META = &"_better_terrain_slopes_ground_pick"
const BASIC_SLOTS := ["ground", "steep_tl", "g1_tl", "g2_tl", "arrow:steep_tl", "arrow:g1_tl", "arrow:g2_tl",
	"thin:steep_tl", "thin:g1_tl", "thin:g2_tl", "thin:steep_br", "thin:g1_br", "thin:g2_br"]
# [source piece, flip_h, flip_v]
const TURNS := {
	"steep_tr": ["steep_tl", true, false], "steep_bl": ["steep_tl", false, true], "steep_br": ["steep_tl", true, true],
	"g1_tr": ["g1_tl", true, false], "g1_bl": ["g1_tl", false, true], "g1_br": ["g1_tl", true, true],
	"g2_tr": ["g2_tl", true, false], "g2_bl": ["g2_tl", false, true], "g2_br": ["g2_tl", true, true],
	"arrow:steep_tr": ["arrow:steep_tl", true, false], "arrow:steep_bl": ["arrow:steep_tl", false, true],
	"arrow:steep_br": ["arrow:steep_tl", true, true],
	"arrow:g1_tr": ["arrow:g1_tl", true, false], "arrow:g1_bl": ["arrow:g1_tl", false, true], "arrow:g1_br": ["arrow:g1_tl", true, true],
	"arrow:g2_tr": ["arrow:g2_tl", true, false], "arrow:g2_bl": ["arrow:g2_tl", false, true], "arrow:g2_br": ["arrow:g2_tl", true, true],
	"thin:steep_tr": ["thin:steep_tl", true, false], "thin:steep_bl": ["thin:steep_br", true, false],
	"thin:g1_tr": ["thin:g1_tl", true, false], "thin:g1_bl": ["thin:g1_br", true, false],
	"thin:g2_tr": ["thin:g2_tl", true, false], "thin:g2_bl": ["thin:g2_br", true, false],
	"ground:tr": ["ground:tl", true, false], "ground:r": ["ground:l", true, false], "ground:br": ["ground:bl", true, false],
	"ground:itr": ["ground:itl", true, false], "ground:ibr": ["ground:ibl", true, false],
}
# peering sides where ground continues, per edge/corner
const EDGE_SIDES := {
	"tl": [0, 3, 4], "t": [0, 3, 4, 7, 8], "tr": [4, 7, 8], "l": [12, 15, 0, 3, 4], "r": [4, 7, 8, 11, 12],
	"bl": [12, 15, 0], "b": [8, 11, 12, 15, 0], "br": [8, 11, 12],
	"itl": [0, 3, 4, 7, 8, 12, 15], "itr": [0, 3, 4, 7, 8, 11, 12], "ibl": [0, 3, 4, 8, 11, 12, 15], "ibr": [0, 4, 7, 8, 11, 12, 15],
}
const EDGE_LABELS := {
	"tl": "top-left corner", "t": "top edge", "tr": "top-right corner", "l": "left edge", "r": "right edge",
	"bl": "bottom-left corner", "b": "bottom edge", "br": "bottom-right corner",
	"itl": "inner corner, open at the top left", "itr": "inner corner, open at the top right",
	"ibl": "inner corner, open at the bottom left", "ibr": "inner corner, open at the bottom right",
}
# never copied onto a flipped tile
const TURN_SKIP := ["flip_h", "flip_v", "transpose"]


static func _terrains(ts: TileSet) -> Array:
	if ts == null or not ts.has_meta(&"_better_terrain"):
		return []
	return ts.get_meta(&"_better_terrain").get("terrains", [])


# guesses roles from names like GentleSlope1TL or steep_slope_br
static func detect(ts: TileSet) -> Dictionary:
	var found := {}
	var terrains := _terrains(ts)
	for i in terrains.size():
		if int(terrains[i][2]) != TYPE_MATCH_TILES:
			continue
		var name := String(terrains[i][0]).to_lower()
		var flat := ""
		for ch in name:
			if ch.is_valid_identifier() or ch.is_valid_int():
				flat += ch
		flat = flat.replace("_", "")
		var corner := flat.right(2)
		if corner in ["tl", "tr", "bl", "br"]:
			if flat.contains("steep"):
				found["steep_" + corner] = i
				continue
			if flat.contains("gentle"):
				var half := flat.left(flat.length() - 2).right(1)
				if half in ["1", "2"]:
					found["g%s_%s" % [half, corner]] = i
					continue
		if flat == "ground":
			found["ground"] = i
	return found


## Role to terrain index; saved choices override what the names suggest.
static func roles(ts: TileSet) -> Dictionary:
	var result := detect(ts)
	var terrains := _terrains(ts)
	var saved: Dictionary = ts.get_meta(META, {}) if ts != null else {}
	for role in saved:
		# older set-ups saved unset roles as empty names
		if String(saved[role]).is_empty():
			continue
		result.erase(role)
		for i in terrains.size():
			if String(terrains[i][0]) == String(saved[role]):
				result[role] = i
	return result


## Only set roles are saved; the rest fall back to name detection.
static func save_roles(ts: TileSet, by_index: Dictionary) -> void:
	var terrains := _terrains(ts)
	var names := {}
	for role in ROLES:
		var i := int(by_index.get(role, -1))
		if i >= 0 and i < terrains.size():
			names[role] = String(terrains[i][0])
	ts.set_meta(META, names)
	ts.emit_changed()


static func is_complete(found: Dictionary) -> bool:
	return ROLES.all(func(role): return found.has(role))


static func uses_terrain(ts: TileSet, index: int) -> bool:
	var found := roles(ts)
	return is_complete(found) and index in found.values()


## Returns [code]{cells = {coord: type}, erase = [coords], label}[/code].
static func plan(ts: TileSet, solid: Callable, a: Vector2i, offset: Vector2, erasing := false, thin := false, autofill := false, terrain_at := Callable()) -> Dictionary:
	return shape(roles(ts), solid, a, offset, erasing, thin, autofill, terrain_at)


const ANGLES := {"line": 0.0, "gentle": 26.565, "steep": 45.0, "column": 90.0}


static func snap(offset: Vector2) -> Dictionary:
	if offset.length() < 0.5:
		return {}
	var angle := rad_to_deg(atan2(absf(offset.y), absf(offset.x)))
	var kind := "line"
	for k in ANGLES:
		if absf(angle - ANGLES[k]) < absf(angle - ANGLES[kind]):
			kind = k
	return {"kind": kind, "steps": _steps(kind, offset), "h": int(signf(offset.x)), "v": int(signf(offset.y))}


static func _steps(kind: String, offset: Vector2) -> int:
	match kind:
		"line": return maxi(roundi(absf(offset.x)) + 1, 1)
		"column": return roundi(absf(offset.y)) + 1
		"steep": return maxi(roundi(absf(offset.x) + 0.5), 1)
	return maxi(roundi((absf(offset.x) + 0.5) / 2.0), 1)


static func thin_ready(bt, ts: TileSet) -> bool:
	return THIN.keys().all(func(role): return not slot_tile(bt, ts, "thin:" + role).is_empty())


## [method plan] with roles already resolved.
static func shape(found: Dictionary, solid: Callable, a: Vector2i, offset: Vector2, erasing := false, thin := false, autofill := false, terrain_at := Callable()) -> Dictionary:
	var out := {"cells": {}, "erase": [], "label": ""}
	var s := snap(offset)
	if not is_complete(found) or s.is_empty():
		return out
	var ceiling := false
	if not thin and not erasing and s.kind != "column":
		var cont := _continue(found, solid, terrain_at, a, s)
		var from: Vector2i = cont.a
		ceiling = cont.ceiling
		if from.x != a.x:
			var left := offset.x - (from.x - a.x)
			s.steps = _steps(s.kind, Vector2(left, 0)) if signf(left) == s.h else 1
		a = from
	if s.kind in ["line", "column"]:
		var step := Vector2i(s.h, 0) if s.kind == "line" else Vector2i(0, s.v)
		if s.kind == "line" and not ceiling and terrain_at.is_valid():
			ceiling = _ceiling_at(found, solid, terrain_at, a - step) \
				or _ceiling_at(found, solid, terrain_at, a + step * s.steps)
		for i in s.steps:
			if erasing:
				out.erase.append(a + step * i)
			else:
				out.cells[a + step * i] = found["ground"]
				if autofill and s.kind == "line":
					for f in _fill_down(solid, a + step * i, -1 if ceiling else 1):
						out.cells[f] = found["ground"]
		out.label = "Straight line · %d tiles" % s.steps
		return out
	var steep: bool = s.kind == "steep"
	var steps: int = s.steps
	if not thin and not erasing and not ceiling:
		a = _surface(solid, a, s)
		ceiling = not solid.call(a) and solid.call(a + Vector2i.UP) and not solid.call(a + Vector2i.DOWN)
	if not thin and not erasing and not ceiling:
		if s.v < 0 or not solid.call(a + Vector2i.UP):
			for k in [0, 1, -1, 2, -2]:
				if steps + k >= 1 and _joins(solid, a, s, steps + k, steep):
					steps += k
					break
	var width: int = steps if steep else 2 * steps
	var last: Vector2i = a + Vector2i(s.h * (width - 1), s.v * (steps - 1))
	# dragging down starts from the high end, so the low end is the far one
	var low: Vector2i = a if s.v < 0 else last
	return build(found, solid, low, s.h if s.v < 0 else -s.h, steps, steep, erasing, thin, terrain_at, ceiling)


# empty cells from c down to ground (up with dir -1); none if no ground within reach
static func _fill_down(solid: Callable, c: Vector2i, dir := 1) -> Array:
	var fill := []
	var y := c.y + dir
	while not solid.call(Vector2i(c.x, y)):
		if fill.size() >= MAX_FILL:
			return []
		fill.append(Vector2i(c.x, y))
		y += dir
	return fill


# where a floor surface meets the left/right edge: 0 = cell top, 1 = bottom
const FLOOR_EDGES := {"steep_tl": [1.0, 0.0], "steep_tr": [0.0, 1.0], "g1_tl": [1.0, 0.5], "g2_tl": [0.5, 0.0],
	"g1_tr": [0.5, 1.0], "g2_tr": [0.0, 0.5]}


# same for a ceiling's underside
const CEILING_EDGES := {"steep_bl": [0.0, 1.0], "steep_br": [1.0, 0.0], "g1_bl": [0.0, 0.5], "g2_bl": [0.5, 1.0],
	"g1_br": [0.5, 0.0], "g2_br": [1.0, 0.5]}


# returns {a, ceiling}: where a drag pressed on a slope or its ground really starts
static func _continue(found: Dictionary, solid: Callable, terrain_at: Callable, a: Vector2i, s: Dictionary) -> Dictionary:
	if not solid.call(a) or not terrain_at.is_valid():
		return {"a": a, "ceiling": false}
	var top := a
	while solid.call(top + Vector2i.UP) and a.y - top.y < MAX_FILL:
		top += Vector2i.UP
	var role := str(found.find_key(terrain_at.call(top)))
	if FLOOR_EDGES.has(role):
		top = _half_end(found, terrain_at, FLOOR_EDGES, top, s.h)
		role = str(found.find_key(terrain_at.call(top)))
		var beside := top + Vector2i(s.h, 0)
		var edge: float = FLOOR_EDGES[role][1 if s.h > 0 else 0]
		if s.kind == "line":
			return {"a": beside + (Vector2i.DOWN if edge == 1.0 else Vector2i.ZERO), "ceiling": false}
		if s.v < 0:
			return {"a": beside + (Vector2i.UP if edge == 0.0 else Vector2i.ZERO), "ceiling": false}
		return {"a": beside + (Vector2i.DOWN if edge > 0.0 else Vector2i.ZERO), "ceiling": false}
	var bottom := a
	while solid.call(bottom + Vector2i.DOWN) and bottom.y - a.y < MAX_FILL:
		bottom += Vector2i.DOWN
	role = str(found.find_key(terrain_at.call(bottom)))
	var flat_end: bool = role == "ground" and not solid.call(bottom + Vector2i(s.h, 0)) \
		and _ceiling_at(found, solid, terrain_at, bottom)
	if CEILING_EDGES.has(role) or flat_end:
		if not flat_end:
			bottom = _half_end(found, terrain_at, CEILING_EDGES, bottom, s.h)
			role = str(found.find_key(terrain_at.call(bottom)))
		var beside := bottom + Vector2i(s.h, 0)
		var edge: float = 1.0 if flat_end else CEILING_EDGES[role][1 if s.h > 0 else 0]
		if s.kind == "line" or s.v < 0:
			return {"a": beside + (Vector2i.UP if edge == 0.0 else Vector2i.ZERO), "ceiling": true}
		return {"a": beside + (Vector2i.DOWN if edge == 1.0 else Vector2i.ZERO), "ceiling": true}
	return {"a": a, "ceiling": false}


static func _ceiling_at(found: Dictionary, solid: Callable, terrain_at: Callable, c: Vector2i) -> bool:
	if CEILING_EDGES.has(str(found.find_key(terrain_at.call(c)))):
		return true
	return solid.call(c) and solid.call(c + Vector2i.UP) and not solid.call(c + Vector2i.DOWN) \
		and terrain_at.call(c) == found.ground


# gentle halves pair up, so the drag starts past the whole step
static func _half_end(found: Dictionary, terrain_at: Callable, edges: Dictionary, c: Vector2i, h: int) -> Vector2i:
	for i in 2:
		var role := str(found.find_key(terrain_at.call(c)))
		var next := str(found.find_key(terrain_at.call(c + Vector2i(h, 0))))
		if edges[role][1 if h > 0 else 0] != 0.5 or not edges.has(next):
			break
		c += Vector2i(h, 0)
	return c


# top row: up starts above, down beside the edge; under a ceiling, just below; deeper, carve in place
static func _surface(solid: Callable, a: Vector2i, s: Dictionary) -> Vector2i:
	if not solid.call(a):
		return a
	if not solid.call(a + Vector2i.UP):
		if s.v < 0:
			return a + Vector2i.UP
		var beside := a + Vector2i(s.h, 0)
		return beside if not solid.call(beside) else a
	if not solid.call(a + Vector2i.DOWN):
		return a + Vector2i.DOWN
	return a


static func _joins(solid: Callable, a: Vector2i, s: Dictionary, steps: int, steep: bool) -> bool:
	var width := steps if steep else 2 * steps
	var last: Vector2i = a + Vector2i(s.h * (width - 1), s.v * (steps - 1))
	var beyond: Vector2i = last + Vector2i(s.h, 0)
	if s.v < 0:
		return solid.call(beyond) and not solid.call(beyond + Vector2i.UP)
	return solid.call(beyond + Vector2i.DOWN) and not solid.call(beyond)


static func build(found: Dictionary, solid: Callable, low: Vector2i, h_up: int, steps: int, steep: bool, erasing := false, thin := false, terrain_at := Callable(), ceiling := false) -> Dictionary:
	var out := {"cells": {}, "erase": [], "label": ""}
	var width := steps if steep else 2 * steps
	var high := low + Vector2i(h_up * (width - 1), -(steps - 1))
	# ceilings hang from above the high end; thin slopes always keep their floor face
	var on_floor: bool = not ceiling and (thin or solid.call(low + Vector2i.DOWN) or not solid.call(high + Vector2i.UP))
	var start := low if on_floor else high
	var h := h_up if on_floor else -h_up
	var v := -1 if on_floor else 1
	var corner := ("tl" if h > 0 else "tr") if on_floor else ("bl" if h > 0 else "br")

	var under := "br" if corner == "tl" else "bl"
	var slope := {}
	for k in steps:
		if steep:
			slope[start + Vector2i(h * k, v * k)] = found["steep_" + corner]
			if thin:
				slope[start + Vector2i(h * (k + 1), v * k)] = found["steep_" + under]
		else:
			slope[start + Vector2i(h * 2 * k, v * k)] = found["g1_" + corner]
			slope[start + Vector2i(h * (2 * k + 1), v * k)] = found["g2_" + corner]
			if thin:
				slope[start + Vector2i(h * 2 * k, v * k + 1)] = found["g2_" + under]
				slope[start + Vector2i(h * (2 * k + 1), v * k + 1)] = found["g1_" + under]
	out.label = "%s %s · %d step%s" % ["Steep" if steep else "Gentle",
		"thin diagonal" if thin else ("slope" if on_floor else "ceiling slope"), steps, "" if steps == 1 else "s"]
	if thin:
		if not erasing:
			out.cells = slope
		else:
			out.erase = slope.keys()
		return out

	var last_row := start.y + v * (steps - 1)
	for c: Vector2i in slope:
		if erasing:
			out.erase.append(c)
			continue
		out.cells[c] = slope[c]
		var fill := []
		var y := c.y - v
		while not solid.call(Vector2i(c.x, y)) and fill.size() < MAX_FILL:
			fill.append(Vector2i(c.x, y))
			y -= v
		if not solid.call(Vector2i(c.x, y)):
			fill = fill.slice(0, absi(start.y - c.y))
		for f in fill:
			out.cells[f] = found["ground"]
		_bury(found, terrain_at, Vector2i(c.x, y), -v, out.cells)
		# only carve what touches the slope, ground across a gap is someone else's
		y = c.y + v
		while ((y >= last_row) if on_floor else (y <= last_row)) and solid.call(Vector2i(c.x, y)):
			out.erase.append(Vector2i(c.x, y))
			y += v
	return out


## Moves between cell corners: flat (h, 0), steep (h, ±1), gentle (2h, ±1) or wall (0, ±1).
static func free_moves(start: Vector2i, trail: Array, smooth := 0) -> Array:
	var moves := []
	var h := _trail_dir(start, trail)
	if h == 0:
		return moves
	var p := start
	var i := 0
	for guard in 1024:
		var j := i
		while j + 1 < trail.size() and (trail[j + 1].x - p.x) * h < 0.5:
			j += 1
		var dy := roundi(trail[j].y - p.y) if (trail[j].x - p.x) * h < 0.5 else 0
		if dy != 0:
			moves.append(Vector2i(0, signi(dy)))
			p.y += signi(dy)
			continue
		var k := j
		while k < trail.size() and (trail[k].x - p.x) * h < 1.0:
			k += 1
		var q: Vector2 = trail[mini(k, trail.size() - 1)]
		var ax: float = (q.x - p.x) * h
		if ax < 0.5:
			break
		var rise: float = (q.y - p.y) / ax
		var sy := signi(roundi(signf(rise)))
		var m := Vector2i(h, 0)
		if absf(rise) >= 0.75:
			m = Vector2i(h, sy)
		elif absf(rise) >= 0.25:
			m = Vector2i(2 * h, sy)
		moves.append(m)
		p += m
		while i < trail.size() and (trail[i].x - p.x) * h <= -0.5:
			i += 1
		if i >= trail.size():
			break
	return _flattened(moves, smooth) if smooth > 0 else moves


# one-row bumps and dips up to [param width] columns wide
static func _flattened(moves: Array, width: int) -> Array:
	var out := moves.duplicate()
	var h := _free_dir(out)
	var i := 0
	while i < out.size():
		var y := 0
		var cols := 0
		var done := -1
		for j in range(i, out.size()):
			y += out[j].y
			cols += absi(out[j].x)
			if absi(y) > 1 or cols > width or (j == i and y == 0):
				break
			if y == 0:
				done = j
				break
		if done < 0:
			i += 1
			continue
		var flat := []
		for k in cols:
			flat.append(Vector2i(h, 0))
		out = out.slice(0, i) + flat + out.slice(done + 1)
		i = maxi(i - 1, 0)
	return out


## Going back rubs out the trail ahead; [param straight] holds the height reached.
static func free_trail(start: Vector2i, trail: Array, point: Vector2, straight := false, smooth := 0) -> Array:
	var out := trail.duplicate()
	var h := _trail_dir(start, out)
	while h != 0 and not out.is_empty() and (out.back().x - point.x) * h > 0.0:
		out.pop_back()
	if straight:
		var y := start.y
		for m: Vector2i in free_moves(start, out, smooth):
			y += m.y
		point.y = y
	out.append(point)
	return out


static func _trail_dir(start: Vector2i, trail: Array) -> int:
	for q: Vector2 in trail:
		if absf(q.x - start.x) >= 0.5:
			return int(signf(q.x - start.x))
	return 0


static func _free_dir(moves: Array) -> int:
	for m: Vector2i in moves:
		if m.x != 0:
			return signi(m.x)
	return 0


# slope pieces buried under new ground become Ground
static func _bury(found: Dictionary, terrain_at: Callable, c: Vector2i, dir: int, cells: Dictionary) -> void:
	if not terrain_at.is_valid():
		return
	for i in MAX_FILL:
		var t = terrain_at.call(c)
		if cells.has(c) or t == found.ground or not t in found.values():
			return
		cells[c] = found.ground
		c.y += dir


## Same result shape as [method plan].
static func free_plan(found: Dictionary, solid: Callable, start: Vector2i, moves: Array, erasing := false, autofill := false, terrain_at := Callable()) -> Dictionary:
	var out := {"cells": {}, "erase": [], "label": ""}
	if not is_complete(found) or moves.is_empty():
		return out
	var h := _free_dir(moves)
	# continuing a ceiling draws its underside, so ground fills upwards
	var ceiling := false
	if terrain_at.is_valid():
		var end := start
		for m: Vector2i in moves:
			end += m
		for at: Vector2i in [start, end]:
			var side := -h if at == start else h
			var cell := Vector2i(at.x if side > 0 else at.x - 1, at.y)
			if _ceiling_at(found, solid, terrain_at, cell + Vector2i.UP):
				ceiling = true
			elif _ceiling_at(found, solid, terrain_at, cell):
				ceiling = true
				if at == start:
					start += Vector2i.DOWN
	var surface := {}
	var slopes := {}
	var p := start
	for m: Vector2i in moves:
		var x0 := mini(p.x, p.x + m.x)
		var up := m.y < 0
		var row := p.y - 1 if up else p.y
		var rising := (m.x > 0) == up
		if ceiling:
			if m.x == 0:
				pass
			elif m.y == 0:
				surface[Vector2i(x0, p.y - 1)] = found.ground
			elif absi(m.x) == 1:
				slopes[Vector2i(x0, row)] = found["steep_br" if rising else "steep_bl"]
			elif rising:
				slopes[Vector2i(x0, row)] = found.g2_br
				slopes[Vector2i(x0 + 1, row)] = found.g1_br
			else:
				slopes[Vector2i(x0, row)] = found.g1_bl
				slopes[Vector2i(x0 + 1, row)] = found.g2_bl
		elif m.x == 0:
			var col := p.x if (h > 0) == up else p.x - 1
			surface[Vector2i(col, p.y)] = found.ground
			surface[Vector2i(col, p.y + m.y)] = found.ground
		elif m.y == 0:
			surface[Vector2i(x0, p.y)] = found.ground
		elif absi(m.x) == 1:
			slopes[Vector2i(x0, row)] = found["steep_tl" if rising else "steep_tr"]
		elif rising:
			slopes[Vector2i(x0, row)] = found.g1_tl
			slopes[Vector2i(x0 + 1, row)] = found.g2_tl
		else:
			slopes[Vector2i(x0, row)] = found.g2_tr
			slopes[Vector2i(x0 + 1, row)] = found.g1_tr
		p += m
	if terrain_at.is_valid():
		for c in surface.keys():
			var t = terrain_at.call(c)
			if t != found.ground and t in found.values():
				surface.erase(c)
	for c in slopes:
		surface[c] = slopes[c]
	out.label = "Freehand · %d step%s" % [moves.size(), "" if moves.size() == 1 else "s"]
	if erasing:
		out.erase = surface.keys()
		return out
	out.cells = surface.duplicate()
	var rows: Array = surface.keys().map(func(c: Vector2i) -> int: return c.y)
	var top: int = rows.min()
	var bottom: int = rows.max()
	var d := -1 if ceiling else 1
	for c: Vector2i in surface:
		var y := c.y + d
		var fill := []
		while not surface.has(Vector2i(c.x, y)) and not solid.call(Vector2i(c.x, y)) and fill.size() < MAX_FILL:
			fill.append(Vector2i(c.x, y))
			y += d
		var grounded: bool = surface.has(Vector2i(c.x, y)) or solid.call(Vector2i(c.x, y))
		if not ceiling and (fill.is_empty() or slopes.has(c) or autofill):
			_bury(found, terrain_at, Vector2i(c.x, y), 1, out.cells)
		if not slopes.has(c):
			if not (autofill and grounded):
				continue
		elif not grounded:
			fill = fill.filter(func(f: Vector2i) -> bool: return f.y >= top if ceiling else f.y <= bottom)
		for f in fill:
			out.cells[f] = found.ground
		if slopes.has(c):
			var open := Vector2i(c.x, c.y - d)
			while open.y >= top and open.y <= bottom and not surface.has(open) and solid.call(open):
				out.erase.append(open)
				open.y -= d
	return out


const SAMPLE_BLOCK_AT := Vector2i(17, 0)
const EXAMPLE_BLOCK := ["######", "######", "##.###", "######", "######"]
const SIDE_OFFSETS := {0: Vector2i(1, 0), 3: Vector2i(1, 1), 4: Vector2i(0, 1), 7: Vector2i(-1, 1),
	8: Vector2i(-1, 0), 11: Vector2i(-1, -1), 12: Vector2i(0, -1), 15: Vector2i(1, -1)}


## Bakes the preview into a new atlas source and sets the slopes up on it. Returns the source id.
static func make_example(bt, ts: TileSet, ground := -1) -> int:
	var cells := sample()
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var block_at := SAMPLE_BLOCK_AT
	var size := ts.tile_size
	var span := hi - lo + Vector2i.ONE
	var image := Image.create_empty(span.x * size.x, span.y * size.y, false, Image.FORMAT_RGBA8)
	var solid := {}
	for c in cells:
		var outline := blueprint(cells[c])
		var at: Vector2i = (c - lo) * size
		for y in size.y:
			for x in size.x:
				if Geometry2D.is_point_in_polygon(Vector2((x + 0.5) / size.x, (y + 0.5) / size.y), outline):
					solid[at + Vector2i(x, y)] = true
	@warning_ignore("integer_division")
	var grass := maxi(2, size.y / 5)
	for p in solid:
		var sky := 0
		for k in range(1, grass + 1):
			if not solid.has(p + Vector2i(0, -k)):
				sky = k
				break
		var speck := int(abs(sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453)) % 7
		var colour := Color(0.62, 0.40, 0.22) if speck > 1 else Color(0.52, 0.33, 0.18)
		if sky == 1:
			colour = Color(0.55, 0.85, 0.3)
		elif sky > 1:
			colour = Color(0.33, 0.66, 0.2)
		elif not solid.has(p + Vector2i(0, 1)) or not solid.has(p + Vector2i(1, 0)) or not solid.has(p + Vector2i(-1, 0)):
			colour = Color(0.34, 0.2, 0.1)
		image.set_pixelv(p, colour)
	var src := TileSetAtlasSource.new()
	src.resource_name = "Example slopes (%dx%d)" % [size.x, size.y]
	src.texture = ImageTexture.create_from_image(image)
	src.texture.resource_name = src.resource_name
	src.texture_region_size = size
	for c in cells:
		src.create_tile(c - lo)
	var id := ts.add_source(src)

	if ground < 0:
		bt.add_terrain(ts, _free_name(ts, "Ground"), Color(0.55, 0.4, 0.25), TYPE_MATCH_TILES)
		ground = bt.terrain_count(ts) - 1
	else:
		for s_i in ts.get_source_count():
			var other := ts.get_source(ts.get_source_id(s_i)) as TileSetAtlasSource
			if other == null or ts.get_source_id(s_i) == id:
				continue
			for t_i in other.get_tiles_count():
				var c := other.get_tile_id(t_i)
				for a in other.get_alternative_tiles_count(c):
					var td := other.get_tile_data(c, other.get_alternative_tile_id(c, a))
					if bt.get_tile_terrain_type(td) == ground:
						bt.set_tile_terrain_type(ts, td, -2)
	var found := roles(ts)
	found.ground = ground
	save_roles(ts, found)
	ts.set_meta(MODE_META, "advanced")
	remove_turned(bt, ts)
	var first := {}
	for pass_slots in [func(slot): return slot != "ground" and not slot.contains(":"),
			func(slot): return slot.begins_with("arrow:"), func(slot): return slot.begins_with("thin:")]:
		for c in cells:
			var slot: String = cells[c]
			if not pass_slots.call(slot):
				continue
			if not first.has(slot):
				first[slot] = c - lo
				assign(bt, ts, slot, id, c - lo)
	# ground tiles come from the clean block; ones next to a slope carry grass and would mix in
	var block_cells := {}
	for c in cells:
		if c.x >= block_at.x:
			block_cells[c] = true
	var done := {}
	for y in EXAMPLE_BLOCK.size():
		for x in EXAMPLE_BLOCK[y].length():
			var c := block_at + Vector2i(x, y)
			if not block_cells.has(c):
				continue
			var slot := edge_of(block_cells, c)
			if not done.has(slot):
				done[slot] = true
				assign(bt, ts, slot, id, c - lo)
	add_rules(bt, ts)
	bt._purge_cache(ts)
	ts.emit_changed()
	return id


## Cell to slot; slots are a role, "arrow:role" or "thin:role".
static func sample() -> Dictionary:
	var found := {}
	for role in ROLES:
		found[role] = role
	var grid := {}
	var solid := func(c: Vector2i) -> bool: return grid.has(c)
	for r in [Rect2i(0, 1, 8, 3), Rect2i(3, 0, 2, 1), Rect2i(3, 4, 2, 1), Rect2i(10, 1, 5, 3), Rect2i(12, 0, 1, 1), Rect2i(12, 4, 1, 1)]:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				grid[Vector2i(x, y)] = "ground"
	for drag in [[Vector2i(1, 0), Vector2(1.5, -0.5)], [Vector2i(6, 0), Vector2(-1.5, -0.5)],
			[Vector2i(1, 4), Vector2(1.5, 0.5)], [Vector2i(6, 4), Vector2(-1.5, 0.5)],
			[Vector2i(11, 0), Vector2(0.5, -0.5)], [Vector2i(13, 0), Vector2(-0.5, -0.5)],
			[Vector2i(11, 4), Vector2(0.5, 0.5)], [Vector2i(13, 4), Vector2(-0.5, 0.5)]]:
		var out := shape(found, solid, drag[0], drag[1])
		for c in out.erase:
			grid.erase(c)
		for c in out.cells:
			grid[c] = out.cells[c]
	for c in grid.keys():
		var role: String = grid[c]
		if role == "ground" or role.begins_with("arrow"):
			continue
		var below: Vector2i = c + (Vector2i.DOWN if role.ends_with("tl") or role.ends_with("tr") else Vector2i.UP)
		if grid.get(below, "") == "ground":
			grid[below] = "arrow:" + role
	for drag in [[Vector2i(0, 9), 1, 2, false], [Vector2i(7, 9), -1, 2, false], [Vector2i(10, 9), 1, 2, true], [Vector2i(15, 9), -1, 2, true]]:
		var out := build(found, func(_c): return false, drag[0], drag[1], drag[2], drag[3], false, true)
		for c in out.cells:
			grid[c] = "thin:" + out.cells[c]
	for y in EXAMPLE_BLOCK.size():
		for x in EXAMPLE_BLOCK[y].length():
			if EXAMPLE_BLOCK[y][x] == "#":
				grid[SAMPLE_BLOCK_AT + Vector2i(x, y)] = "ground"
	return grid


## [code]{source, coord}[/code] of the slot's tile, empty when unset.
static func slot_tile(bt, ts: TileSet, slot: String) -> Dictionary:
	var found := roles(ts)
	var role := "ground" if slot.begins_with("ground:") else slot.get_slice(":", slot.get_slice_count(":") - 1)
	if not found.has(role):
		return {}
	var terrain: int = found[role]
	# ground shows its solid block, not whichever Ground tile comes first
	if slot == "ground":
		var pick: Array = ts.get_meta(GROUND_PICK_META, [])
		if pick.size() == 2:
			var picked := _tile_data(ts, pick[0], pick[1])
			if picked != null and bt.get_tile_terrain_type(picked) == terrain:
				return {"source": pick[0], "coord": pick[1], "alt": 0}
		var any := {}
		for s in ts.get_source_count():
			var src := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
			if src == null:
				continue
			for i in src.get_tiles_count():
				var coord := src.get_tile_id(i)
				var td := src.get_tile_data(coord, 0)
				if bt.get_tile_terrain_type(td) != terrain:
					continue
				if _is_block(bt, found, td):
					return {"source": ts.get_source_id(s), "coord": coord, "alt": 0}
				if any.is_empty():
					any = {"source": ts.get_source_id(s), "coord": coord, "alt": 0}
		return any
	for s in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
		if src == null:
			continue
		for i in src.get_tiles_count():
			var coord := src.get_tile_id(i)
			for a in src.get_alternative_tiles_count(coord):
				var alt := src.get_alternative_tile_id(coord, a)
				if _fits(bt, ts, found, slot, src.get_tile_data(coord, alt)):
					return {"source": ts.get_source_id(s), "coord": coord, "alt": alt}
	return {}


static func _fits(bt, ts: TileSet, found: Dictionary, slot: String, td: TileData) -> bool:
	var type: int = bt.get_tile_terrain_type(td)
	if slot == "ground":
		return type == found.ground
	if slot.begins_with("ground:"):
		if type != found.get("ground", -100) or _is_arrow(bt, found, td):
			return false
		var sides := SIDES.filter(func(side): return not bt.tile_peering_types(td, side).is_empty())
		sides.sort()
		var want: Array = EDGE_SIDES[slot.get_slice(":", 1)].duplicate()
		want.sort()
		return sides == want
	var role := slot.get_slice(":", slot.get_slice_count(":") - 1)
	if slot.begins_with("arrow:"):
		return type == found.get("ground", -2) and found[role] in bt.tile_peering_types(td, _arrow_side(role))
	if type != found[role]:
		return false
	# a thin half accepts its partner and doesn't ask for Ground on that side
	var partner: int = found.get(THIN[role][0], -2)
	var is_thin := false
	for side in THIN_SIDES.get(role, [THIN[role][1]]):
		var listed: Array = bt.tile_peering_types(td, side)
		if partner >= 0 and _accepts(bt, ts, listed, partner) and not found.get("ground", -2) in listed:
			is_thin = true
	return is_thin == slot.begins_with("thin:")


static func _arrow_side(role: String) -> int:
	return 12 if role.ends_with("tl") or role.ends_with("tr") else 4


static func _clear_peering(bt, ts: TileSet, td: TileData) -> void:
	for side in bt.tile_peering_keys(td):
		for t in bt.tile_peering_types(td, side):
			bt.remove_tile_peering_type(ts, td, side, t)
		for t in bt.tile_not_peering_types(td, side):
			bt.remove_tile_not_peering_type(ts, td, side, t)


static func assign(bt, ts: TileSet, slot: String, source_id: int, coord: Vector2i, alt := 0) -> String:
	var td := _tile_data(ts, source_id, coord, alt)
	if td == null:
		return "There is no tile there."
	var found := roles(ts)
	if slot == "ground":
		var type: int = bt.get_tile_terrain_type(td)
		# not -2: that's also a free tile
		var ground: int = found.get("ground", -100)
		if type == -1:
			return "That tile is marked as decoration. Pick a free tile or one of your ground terrain."
		var slope_piece: bool = type >= 0 and type in found.values() and type != ground
		if type >= 0 and not slope_piece and type != ground:
			var terrain: Array = _terrains(ts)[type]
			if found.has("ground") or int(terrain[2]) != TYPE_MATCH_TILES:
				return "That tile belongs to %s. Pick a free tile, or one of Ground's or the slopes'." % terrain[0]
			found.ground = type
			ground = type
		if type == ground and type >= 0:
			if _is_arrow(bt, found, td):
				return "That tile is the ground under a slope, a piece of its own. Ground here is the solid block inside the land: pick that tile, or a free one."
			if SIDES.any(func(side): return bt.tile_peering_types(td, side).is_empty()):
				return "That tile is one of Ground's edges or corners, so it stays as it is. Ground here is the solid block inside the land: pick that tile, or a free one."
		if not found.has("ground"):
			bt.add_terrain(ts, _free_name(ts, "Ground"), Color(0.45, 0.75, 0.3), TYPE_MATCH_TILES)
			found.ground = bt.terrain_count(ts) - 1
			ground = found.ground
		for s_i in ts.get_source_count():
			var src := ts.get_source(ts.get_source_id(s_i)) as TileSetAtlasSource
			if src == null:
				continue
			for t_i in src.get_tiles_count():
				var c := src.get_tile_id(t_i)
				var other := src.get_tile_data(c, 0)
				if (ts.get_source_id(s_i) == source_id and c == coord) or bt.get_tile_terrain_type(other) != ground \
						or not _is_block(bt, found, other):
					continue
				if not _give_back(ts, ts.get_source_id(s_i), c, other) or _is_block(bt, found, other):
					_remember(ts, ts.get_source_id(s_i), c, other)
					bt.set_tile_terrain_type(ts, other, -2)
		_remember(ts, source_id, coord, td, alt)
		save_roles(ts, found)
		var land := _solid_category(bt, ts, roles(ts))
		bt.set_tile_terrain_type(ts, td, ground)
		_clear_peering(bt, ts, td)
		for side in SIDES:
			bt.add_tile_peering_type(ts, td, side, land)
		ts.set_meta(GROUND_PICK_META, [source_id, coord])
		return ""
	if not found.has("ground"):
		return "Pick the Ground piece first."
	if slot.begins_with("ground:"):
		var old_edge := slot_tile(bt, ts, slot)
		if not old_edge.is_empty() and not (old_edge.source == source_id and old_edge.coord == coord and old_edge.alt == alt):
			var old_td := _tile_data(ts, old_edge.source, old_edge.coord, old_edge.alt)
			if not _give_back(ts, old_edge.source, old_edge.coord, old_td, old_edge.alt) or _fits(bt, ts, found, slot, old_td):
				bt.set_tile_terrain_type(ts, old_td, -2)
		_remember(ts, source_id, coord, td, alt)
		var land := _solid_category(bt, ts, found)
		bt.set_tile_terrain_type(ts, td, found.ground)
		_clear_peering(bt, ts, td)
		for side in EDGE_SIDES[slot.get_slice(":", 1)]:
			bt.add_tile_peering_type(ts, td, side, land)
		return ""
	var role := slot.get_slice(":", slot.get_slice_count(":") - 1)
	var solid := _solid_category(bt, ts, found)
	for needed in [role, THIN[role][0]]:
		if not found.has(needed):
			bt.add_terrain(ts, ROLE_NAMES[needed], Color.from_hsv(ROLES.find(needed) / 13.0, 0.55, 0.85),
				TYPE_MATCH_TILES, [solid], {}, HIDDEN_GROUP)
			found[needed] = bt.terrain_count(ts) - 1
	save_roles(ts, found)
	var old := slot_tile(bt, ts, slot)
	if not old.is_empty() and not (old.source == source_id and old.coord == coord and old.alt == alt):
		var old_td := _tile_data(ts, old.source, old.coord, old.alt)
		if not _give_back(ts, old.source, old.coord, old_td, old.alt) or _fits(bt, ts, found, slot, old_td):
			# freed, not left as Ground: a slope-less arrow would mix in with the real edge tiles
			bt.set_tile_terrain_type(ts, old_td, -2)
	_remember(ts, source_id, coord, td, alt)
	if slot.begins_with("arrow:"):
		bt.set_tile_terrain_type(ts, td, found.ground)
		_clear_peering(bt, ts, td)
		var floor_arrow := _arrow_side(role) == 12
		for side in SIDES:
			if side == _arrow_side(role):
				bt.add_tile_peering_type(ts, td, side, found[role])
			elif not side in ([11, 15] if floor_arrow else [3, 7]):
				bt.add_tile_peering_type(ts, td, side, solid)
	else:
		bt.set_tile_terrain_type(ts, td, found[role])
		_clear_peering(bt, ts, td)
		if slot.begins_with("thin:"):
			bt.add_tile_peering_type(ts, td, THIN[role][1], found[THIN[role][0]])
	return ""


## Solid part of the piece in cell units; the whole cell for non-slopes.
static func blueprint(slot: String) -> PackedVector2Array:
	var role := slot.get_slice(":", slot.get_slice_count(":") - 1)
	if slot == "ground" or slot.begins_with("arrow:") or slot.begins_with("ground:"):
		return PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var shapes := {
		"steep_tl": [Vector2(0, 1), Vector2(1, 0), Vector2(1, 1)],
		"steep_tr": [Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)],
		"steep_bl": [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
		"steep_br": [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)],
		"g1_tl": [Vector2(0, 1), Vector2(1, 0.5), Vector2(1, 1)],
		"g2_tl": [Vector2(0, 0.5), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
		"g1_tr": [Vector2(0, 0.5), Vector2(1, 1), Vector2(0, 1)],
		"g2_tr": [Vector2(0, 0), Vector2(1, 0.5), Vector2(1, 1), Vector2(0, 1)],
		"g1_bl": [Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.5)],
		"g2_bl": [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0.5)],
		"g1_br": [Vector2(0, 0), Vector2(1, 0), Vector2(0, 0.5)],
		"g2_br": [Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.5), Vector2(0, 1)],
	}
	return PackedVector2Array(shapes[role])


static func clear(bt, ts: TileSet) -> void:
	# restore taken tiles before terrain indices shift
	var taken: Dictionary = ts.get_meta(TAKEN_META, {})
	for key in taken.keys():
		var at := _parse_key(key)
		var td := _tile_data(ts, at[0], at[1], at[2])
		if td != null:
			_give_back(ts, at[0], at[1], td, at[2])
	ts.remove_meta(TAKEN_META)
	remove_turned(bt, ts)
	bt._purge_cache(ts)
	var found := roles(ts)
	var terrains := []
	for role in found:
		if role != "ground":
			terrains.append(found[role])
	for s in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
		if src == null:
			continue
		for i in src.get_tiles_count():
			var coord := src.get_tile_id(i)
			for a in src.get_alternative_tiles_count(coord):
				var td := src.get_tile_data(coord, src.get_alternative_tile_id(coord, a))
				var arrow := false
				for side in bt.tile_peering_keys(td):
					arrow = arrow or bt.tile_peering_types(td, side).any(func(t): return t in terrains)
				# arrows are Ground only to sit under a slope, so they go with it
				if arrow and bt.get_tile_terrain_type(td) == found.get("ground", -2):
					bt.set_tile_terrain_type(ts, td, -2)
	terrains.sort()
	terrains.reverse()
	for t in terrains:
		bt.remove_terrain(ts, t)
	var kept := {}
	if found.has("ground"):
		kept.ground = found.ground - terrains.filter(func(t): return t < found.ground).size()
	save_roles(ts, kept)


const SET_METAS := [META, TAKEN_META, MODE_META, GROUND_PICK_META, SOLID_META]


## Undo snapshot, tiles keyed by position.
static func snapshot(ts: TileSet) -> Array:
	var tiles := {}
	for s in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
		if src == null:
			continue
		for i in src.get_tiles_count():
			var coord := src.get_tile_id(i)
			for a in src.get_alternative_tiles_count(coord):
				var alt := src.get_alternative_tile_id(coord, a)
				var td := src.get_tile_data(coord, alt)
				tiles[[ts.get_source_id(s), coord, alt]] = td.get_meta(&"_better_terrain").duplicate(true) \
					if td.has_meta(&"_better_terrain") else null
	var metas := []
	for key in [&"_better_terrain"] + SET_METAS:
		var value = ts.get_meta(key) if ts.has_meta(key) else null
		metas.append(value.duplicate(true) if value is Dictionary or value is Array else value)
	return [tiles, metas]


static func restore(bt, ts: TileSet, saved: Array) -> void:
	var keys := [&"_better_terrain"] + SET_METAS
	for i in keys.size():
		var value = saved[1][i]
		if value == null:
			ts.remove_meta(keys[i])
		else:
			ts.set_meta(keys[i], value.duplicate(true) if value is Dictionary or value is Array else value)
	for key in saved[0]:
		var td := _tile_data(ts, key[0], key[1], key[2])
		if td == null:
			continue
		if saved[0][key] == null:
			td.remove_meta(&"_better_terrain")
		else:
			td.set_meta(&"_better_terrain", saved[0][key].duplicate(true))
	# flips are alternative tiles, rebuilt from their originals
	if ts.get_meta(MODE_META, "") == "simple":
		turn(bt, ts)
	bt._purge_cache(ts)
	ts.emit_changed()


## True if some Ground tile asks for nothing above it (a top edge).
static func has_edges(bt, ts: TileSet, ground: int) -> bool:
	for s in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
		if src == null:
			continue
		for i in src.get_tiles_count():
			var td := src.get_tile_data(src.get_tile_id(i), 0)
			if bt.get_tile_terrain_type(td) == ground and bt.tile_peering_types(td, 12).is_empty() \
					and not bt.tile_peering_types(td, 4).is_empty():
				return true
	return false


## "ground:t" and so on from which neighbours have land, "ground" when surrounded.
static func edge_of(cells: Dictionary, c: Vector2i) -> String:
	var has := func(offset: Vector2i) -> bool: return cells.has(c + offset)
	var up: bool = has.call(Vector2i.UP)
	var down: bool = has.call(Vector2i.DOWN)
	var left: bool = has.call(Vector2i.LEFT)
	var right: bool = has.call(Vector2i.RIGHT)
	if not up:
		return "ground:tl" if not left else ("ground:tr" if not right else "ground:t")
	if not down:
		return "ground:bl" if not left else ("ground:br" if not right else "ground:b")
	if not left:
		return "ground:l"
	if not right:
		return "ground:r"
	for corner in [["ground:itl", Vector2i(-1, -1)], ["ground:itr", Vector2i(1, -1)], ["ground:ibl", Vector2i(-1, 1)], ["ground:ibr", Vector2i(1, 1)]]:
		if not has.call(corner[1]):
			return corner[0]
	return "ground"


## Match Tiles terrains that aren't slope pieces.
static func ground_choices(bt, ts: TileSet) -> Array:
	var found := roles(ts)
	var out := []
	for i in bt.terrain_count(ts):
		var t: Dictionary = bt.get_terrain(ts, i)
		if t.type == TYPE_MATCH_TILES and (i == found.get("ground", -100) or not i in found.values()):
			out.append(i)
	return out


## Moves the tiles the set-up made Ground to [param index]; the old terrain keeps its own.
static func set_ground(bt, ts: TileSet, index: int) -> void:
	var found := roles(ts)
	var old: int = found.get("ground", -100)
	if old == index:
		return
	found.ground = index
	save_roles(ts, found)
	if old >= 0:
		var taken: Dictionary = ts.get_meta(TAKEN_META, {})
		for key in taken:
			var at := _parse_key(key)
			var td := _tile_data(ts, at[0], at[1], at[2])
			if td == null or bt.get_tile_terrain_type(td) != old:
				continue
			var sides := {}
			for side in bt.tile_peering_keys(td):
				sides[side] = bt.tile_peering_types(td, side).map(func(t): return index if t == old else t)
			bt.set_tile_terrain_type(ts, td, index)
			_clear_peering(bt, ts, td)
			for side in sides:
				for t in sides[side]:
					bt.add_tile_peering_type(ts, td, side, t)
	if found.size() > 1:
		_solid_category(bt, ts, found)
	bt._purge_cache(ts)


static func is_set_ground(ts: TileSet, index: int) -> bool:
	var found := roles(ts)
	return found.get("ground", -100) == index and found.size() > 1


## Removes Ground plus the slope terrains, flips, shared category and settings.
static func remove_set(bt, ts: TileSet) -> void:
	var ground_name := String(bt.get_terrain(ts, roles(ts).ground).name)
	var solid_name := String(ts.get_meta(SOLID_META, ""))
	clear(bt, ts)
	for i in range(bt.terrain_count(ts) - 1, -1, -1):
		var t: Dictionary = bt.get_terrain(ts, i)
		if String(t.name) == ground_name or (not solid_name.is_empty() and String(t.name) == solid_name and t.type == TYPE_CATEGORY):
			bt.remove_terrain(ts, i)
	for key in SET_METAS:
		ts.remove_meta(key)
	var groups: Array = bt.get_terrain_groups(ts)
	for i in groups.size():
		if groups[i].name == HIDDEN_GROUP and bt.get_terrains_in_group(ts, HIDDEN_GROUP).is_empty():
			bt.remove_terrain_group(ts, i)
			break
	bt._purge_cache(ts)
	ts.emit_changed()


static func _taken_key(source_id: int, coord: Vector2i, alt := 0) -> String:
	return "%d:%d,%d" % [source_id, coord.x, coord.y] + (":%d" % alt if alt != 0 else "")


# [source_id, coord, alt]
static func _parse_key(key: String) -> Array:
	var at := key.get_slice(":", 1)
	var alt := int(key.get_slice(":", 2)) if key.get_slice_count(":") > 2 else 0
	return [int(key.get_slice(":", 0)), Vector2i(int(at.get_slice(",", 0)), int(at.get_slice(",", 1))), alt]


static func _tile_data(ts: TileSet, source_id: int, coord: Vector2i, alt := 0) -> TileData:
	var src := ts.get_source(source_id) as TileSetAtlasSource if ts.has_source(source_id) else null
	if src == null or not src.has_tile(coord) or not src.has_alternative_tile(coord, alt):
		return null
	return src.get_tile_data(coord, alt)


static func _remember(ts: TileSet, source_id: int, coord: Vector2i, td: TileData, alt := 0) -> void:
	var taken: Dictionary = ts.get_meta(TAKEN_META, {}).duplicate(true)
	var key := _taken_key(source_id, coord, alt)
	if not taken.has(key):
		taken[key] = td.get_meta(&"_better_terrain").duplicate(true) if td.has_meta(&"_better_terrain") else null
		ts.set_meta(TAKEN_META, taken)


static func _give_back(ts: TileSet, source_id: int, coord: Vector2i, td: TileData, alt := 0) -> bool:
	var taken: Dictionary = ts.get_meta(TAKEN_META, {}).duplicate(true)
	var key := _taken_key(source_id, coord, alt)
	if not taken.has(key):
		return false
	if taken[key] == null:
		td.remove_meta(&"_better_terrain")
	else:
		td.set_meta(&"_better_terrain", taken[key].duplicate(true))
	taken.erase(key)
	ts.set_meta(TAKEN_META, taken)
	return true


## "simple" or "advanced"; set-ups older than simple mode stay advanced.
static func mode(ts: TileSet) -> String:
	if ts.has_meta(MODE_META):
		return String(ts.get_meta(MODE_META))
	return "advanced" if is_complete(roles(ts)) else "simple"


## Pieces with their own tiles that simple mode would replace with flips.
static func hand_made(bt, ts: TileSet) -> Array:
	var out := []
	for slot in TURNS:
		var t := slot_tile(bt, ts, slot)
		if not t.is_empty() and int(t.get("alt", 0)) == 0:
			out.append(slot)
	return out


static func set_mode(bt, ts: TileSet, value: String) -> void:
	ts.set_meta(MODE_META, value)
	if value == "simple":
		turn(bt, ts)


## Alternative tiles get fixed ids so painted maps keep them. Returns how many were made.
static func turn(bt, ts: TileSet) -> int:
	var made := 0
	var wanted := {}
	for i in TURNS.size():
		var slot: String = TURNS.keys()[i]
		var from := slot_tile(bt, ts, TURNS[slot][0])
		if not from.is_empty() and int(from.get("alt", 0)) == 0:
			wanted[slot] = [from, TURN_ID_BASE + i]
	var kept := {}
	for at in _turned(ts):
		var slot: String = at[3]
		if not wanted.has(slot) or wanted[slot][0].source != at[0] or wanted[slot][0].coord != at[1] or kept.has(slot):
			_remove_turned_at(bt, ts, at)
		else:
			kept[slot] = at[2]
	for slot in wanted:
		var from: Dictionary = wanted[slot][0]
		var src := ts.get_source(from.source) as TileSetAtlasSource
		var alt: int = kept.get(slot, wanted[slot][1])
		if not kept.has(slot) and src.has_alternative_tile(from.coord, alt):
			alt = src.get_next_alternative_tile_id(from.coord)
		if not src.has_alternative_tile(from.coord, alt):
			src.create_alternative_tile(from.coord, alt)
		var base := src.get_tile_data(from.coord, 0)
		var td := src.get_tile_data(from.coord, alt)
		for p in base.get_property_list():
			if p.usage & PROPERTY_USAGE_STORAGE and not String(p.name) in TURN_SKIP and not String(p.name).begins_with("metadata/"):
				td.set(p.name, base.get(p.name))
		td.flip_h = TURNS[slot][1]
		td.flip_v = TURNS[slot][2]
		td.set_meta(TURNED_META, slot)
		assign(bt, ts, slot, from.source, from.coord, alt)
		made += 1
	return made


static func remove_turned(bt, ts: TileSet) -> void:
	for at in _turned(ts):
		_remove_turned_at(bt, ts, at)


# [source_id, coord, alt, slot] per flipped piece
static func _turned(ts: TileSet) -> Array:
	var out := []
	for s in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
		if src == null:
			continue
		for i in src.get_tiles_count():
			var coord := src.get_tile_id(i)
			for a in src.get_alternative_tiles_count(coord):
				var alt := src.get_alternative_tile_id(coord, a)
				var slot := String(src.get_tile_data(coord, alt).get_meta(TURNED_META, ""))
				if alt != 0 and not slot.is_empty():
					out.append([ts.get_source_id(s), coord, alt, slot])
	return out


static func _remove_turned_at(bt, ts: TileSet, at: Array) -> void:
	# purge the terrain cache first, it still holds the tile
	bt._purge_cache(ts)
	var taken: Dictionary = ts.get_meta(TAKEN_META, {}).duplicate(true)
	taken.erase(_taken_key(at[0], at[1], at[2]))
	ts.set_meta(TAKEN_META, taken)
	(ts.get_source(at[0]) as TileSetAtlasSource).remove_alternative_tile(at[1], at[2])


## Terrain name the tile already belongs to, or empty.
static func owner_of(bt, ts: TileSet, source_id: int, coord: Vector2i, alt := 0) -> String:
	var td := _tile_data(ts, source_id, coord, alt)
	if td == null:
		return ""
	var type: int = bt.get_tile_terrain_type(td)
	return String(bt.get_terrain(ts, type).name) if type >= 0 else ""


static func _solid_category(bt, ts: TileSet, found: Dictionary) -> int:
	bt.add_terrain_group(ts, HIDDEN_GROUP)
	var terrains := _terrains(ts)
	var index := -1
	for i in terrains.size():
		if int(terrains[i][2]) == TYPE_CATEGORY and String(terrains[i][0]) == String(ts.get_meta(SOLID_META, "")):
			index = i
	if index < 0:
		index = _own_old_solid(ts, found)
	if index < 0:
		bt.add_terrain(ts, "SlopeSolid", Color(0.5, 0.5, 0.5), TYPE_CATEGORY, [], {}, "")
		index = bt.terrain_count(ts) - 1
	ts.set_meta(SOLID_META, String(bt.get_terrain(ts, index).name))
	for role in found:
		var t: Dictionary = bt.get_terrain(ts, found[role])
		if not index in t.categories:
			bt.set_terrain(ts, found[role], t.name, t.color, t.type, t.categories + [index], t.icon)
	hide_pieces(bt, ts)
	return index


# taken tiles made plain Ground on every side are free tiles picked as Ground
static func _release_solid_grounds(bt, ts: TileSet, ground: int) -> void:
	for key in ts.get_meta(TAKEN_META, {}).keys():
		var at := _parse_key(key)
		var td := _tile_data(ts, at[0], at[1], at[2])
		if td != null and bt.get_tile_terrain_type(td) == ground and _is_block(bt, roles(ts), td):
			_give_back(ts, at[0], at[1], td, at[2])


static func _is_block(bt, found: Dictionary, td: TileData) -> bool:
	return SIDES.all(func(side): return not bt.tile_peering_types(td, side).is_empty()) and not _is_arrow(bt, found, td)


static func _is_arrow(bt, found: Dictionary, td: TileData) -> bool:
	for side in SIDES:
		for t in bt.tile_peering_types(td, side):
			if t != found.get("ground", -100) and t in found.values():
				return true
	return false


static func _free_name(ts: TileSet, name: String) -> String:
	var taken := _terrains(ts).map(func(t): return String(t[0]))
	var out := name
	var n := 2
	while out in taken:
		out = "%s %d" % [name, n]
		n += 1
	return out


# legacy "Solid" category; ours only if it holds nothing but Ground and slopes
static func _own_old_solid(ts: TileSet, found: Dictionary) -> int:
	var terrains := _terrains(ts)
	for i in terrains.size():
		if int(terrains[i][2]) != TYPE_CATEGORY or String(terrains[i][0]) != "Solid":
			continue
		var mine := true
		for t in terrains.size():
			if i in terrains[t][3] and not t in found.values():
				mine = false
		if mine:
			return i
	return -1


## Moves an older set to its own category and hides its pieces.
static func tidy(bt, ts: TileSet) -> void:
	var found := roles(ts)
	if found.has("ground") and found.size() > 1:
		var land := _solid_category(bt, ts, found)
		# older blocks/edges asked for Ground exactly, so a slope in a corner broke them
		for key in ts.get_meta(TAKEN_META, {}).keys():
			var at := _parse_key(key)
			var td := _tile_data(ts, at[0], at[1], at[2])
			if td == null or bt.get_tile_terrain_type(td) != found.ground or _is_arrow(bt, found, td):
				continue
			for side in SIDES:
				if found.ground in bt.tile_peering_types(td, side):
					bt.remove_tile_peering_type(ts, td, side, found.ground)
					bt.add_tile_peering_type(ts, td, side, land)


static func hide_pieces(bt, ts: TileSet) -> void:
	var found := roles(ts)
	var hide := []
	for role in found:
		if role != "ground":
			hide.append(found[role])
	var terrains := _terrains(ts)
	for i in terrains.size():
		if int(terrains[i][2]) == TYPE_CATEGORY and String(terrains[i][0]) == String(ts.get_meta(SOLID_META, "")):
			hide.append(i)
	if hide.is_empty():
		return
	bt.add_terrain_group(ts, HIDDEN_GROUP)
	for i in hide:
		if bt.get_terrain(ts, i).group != HIDDEN_GROUP:
			bt.set_terrain_group(ts, i, HIDDEN_GROUP)


static func _accepts(bt, ts: TileSet, listed: Array, type: int) -> bool:
	if type in listed:
		return true
	var categories: Array = bt.get_terrain(ts, type).get("categories", [])
	return listed.any(func(c): return c in categories)


## Returns how many rules were added; see DESIGN.md, section AA.
static func add_rules(bt, ts: TileSet) -> int:
	var found := roles(ts)
	if not is_complete(found):
		return 0
	var ground: int = found.ground
	var slopes := []
	for role in ROLES:
		if role != "ground":
			slopes.append(found[role])
	var all_types := slopes + [ground]
	var widen := -1
	for i in _terrains(ts).size():
		if int(_terrains(ts)[i][2]) == TYPE_CATEGORY and all_types.all(func(t): return i in bt.get_terrain(ts, t).categories):
			widen = i
	var steep_mate := {found.steep_tl: [0, found.steep_tr], found.steep_tr: [8, found.steep_tl],
		found.steep_bl: [0, found.steep_br], found.steep_br: [8, found.steep_bl]}
	var arrow_mate := {found.steep_tl: [12, 15, found.steep_tr], found.steep_tr: [12, 11, found.steep_tl],
		found.steep_bl: [4, 3, found.steep_br], found.steep_br: [4, 7, found.steep_bl]}
	var added := 0
	for s in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
		if src == null:
			continue
		for i in src.get_tiles_count():
			var coord := src.get_tile_id(i)
			for a in src.get_alternative_tiles_count(coord):
				var td := src.get_tile_data(coord, src.get_alternative_tile_id(coord, a))
				var type: int = bt.get_tile_terrain_type(td)
				if steep_mate.has(type):
					var side: int = steep_mate[type][0]
					var listed: Array = bt.tile_peering_types(td, side)
					if not listed.is_empty() and not _accepts(bt, ts, listed, steep_mate[type][1]):
						added += int(bt.add_tile_peering_type(ts, td, side, steep_mate[type][1]))
					continue
				if type != ground:
					continue
				var named := []
				for side in bt.tile_peering_keys(td):
					named.append_array(bt.tile_peering_types(td, side).filter(func(t): return t in slopes))
				# an arrow names its slope; it only needs to accept a peak's other half
				for t in named:
					if arrow_mate.has(t) and t in bt.tile_peering_types(td, arrow_mate[t][0]):
						var listed: Array = bt.tile_peering_types(td, arrow_mate[t][1])
						if not listed.is_empty() and not _accepts(bt, ts, listed, arrow_mate[t][2]):
							added += int(bt.add_tile_peering_type(ts, td, arrow_mate[t][1], arrow_mate[t][2]))
				if not named.is_empty():
					continue
				var has := func(side: int) -> bool: return not bt.tile_peering_types(td, side).is_empty()
				var inner: bool = has.call(0) and has.call(8)
				for side in [4, 12]:
					var listed: Array = bt.tile_peering_types(td, side)
					if inner and slopes.any(func(t): return _accepts(bt, ts, listed, t)):
						for t in slopes:
							added += int(bt.add_tile_not_peering_type(ts, td, side, t))
				for side in [0, 8]:
					var listed: Array = bt.tile_peering_types(td, side)
					if _accepts(bt, ts, listed, ground) and not slopes.all(func(t): return _accepts(bt, ts, listed, t)):
						if widen >= 0:
							added += int(bt.add_tile_peering_type(ts, td, side, widen))
						else:
							for t in slopes:
								added += int(bt.add_tile_peering_type(ts, td, side, t))
	return added
