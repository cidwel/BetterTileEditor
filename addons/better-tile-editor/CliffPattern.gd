@tool
extends RefCounted

const CliffData := preload("res://addons/better-tile-editor/CliffData.gd")

const MODE := "pattern"

const PIECES := [
	{"key": "top_left", "label": "corner", "shape": "1x1", "row": "top", "col": "left"},
	{"key": "top", "label": "TOP", "shape": "?x1", "row": "top", "col": "mid"},
	{"key": "top_right", "label": "corner", "shape": "1x1", "row": "top", "col": "right"},
	{"key": "left", "label": "LEFT", "shape": "1x?", "row": "mid", "col": "left"},
	{"key": "body", "label": "BODY", "shape": "?x?", "row": "mid", "col": "mid"},
	{"key": "right", "label": "RIGHT", "shape": "1x?", "row": "mid", "col": "right"},
	{"key": "bottom_left", "label": "corner", "shape": "1x1", "row": "bottom", "col": "left"},
	{"key": "bottom", "label": "BOTTOM", "shape": "?x1", "row": "bottom", "col": "mid"},
	{"key": "bottom_right", "label": "corner", "shape": "1x1", "row": "bottom", "col": "right"},
	{"key": "alone_top", "label": "top", "shape": "?x1", "row": "top", "col": "alone"},
	{"key": "alone", "label": "TOWER", "shape": "?x?", "row": "mid", "col": "alone"},
	{"key": "alone_bottom", "label": "foot", "shape": "?x1", "row": "bottom", "col": "alone"},
]

const FALLBACK := {
	"top_left": ["top", "left", "body"],
	"top_right": ["top", "right", "body"],
	"bottom_left": ["bottom", "left", "body"],
	"bottom_right": ["bottom", "right", "body"],
	"top": ["body"], "bottom": ["body"], "left": ["body"], "right": ["body"],
	"alone_top": ["alone", "top", "body"],
	"alone": ["left", "right", "body"],
	"alone_bottom": ["alone", "bottom", "body"],
	"body": [],
}

## Legacy piece names retained for saved sheets.
const RENAMED := {"top": "cap", "bottom": "base", "left": "first", "right": "last"}


static func default_config() -> Dictionary:
	var out := {
		"mode": MODE,
		"source_id": -1,
		"body": {"use": true, "rect": Rect2i(0, 0, 0, 0), "col_offset": 0, "row_offset": 0},
		"rows_up": false,
	}
	for spec in PIECES:
		if spec.key != "body":
			out[spec.key] = {"use": false, "rect": Rect2i(0, 0, 0, 0)}
	return out


static func is_pattern(cfg: Dictionary) -> bool:
	return String(cfg.get("mode", "")) == MODE


static func piece(cfg: Dictionary, name: String) -> Dictionary:
	var p = cfg.get(name)
	if not (p is Dictionary) and RENAMED.has(name):
		p = cfg.get(RENAMED[name])
	if not (p is Dictionary):
		p = {}
	var rect: Rect2i = p.get("rect", Rect2i())
	var on: bool = bool(p.get("use", name == "body")) and rect.size.x > 0 and rect.size.y > 0
	return {"use": on, "rect": rect}


static func effective(cfg: Dictionary, name: String) -> Dictionary:
	var p := piece(cfg, name)
	if p.use:
		return p
	for alt in FALLBACK.get(name, []):
		var q := piece(cfg, alt)
		if q.use:
			return q
	return {"use": false, "rect": Rect2i()}


static func body_offset(cfg: Dictionary) -> Vector2i:
	var b = cfg.get("body")
	if not (b is Dictionary):
		return Vector2i.ZERO
	return Vector2i(int(b.get("col_offset", 0)), int(b.get("row_offset", 0)))


static func key_at(rband: String, cband: String) -> String:
	for spec in PIECES:
		if spec.row == rband and spec.col == cband:
			return spec.key
	return "body"


static func runs_of(plateau: Dictionary, faces: Dictionary) -> Dictionary:
	var out := {}
	for row in CliffData.face_rows(faces):
		var start := 0
		while start < row.size():
			var stop := start
			while stop + 1 < row.size() and row[stop + 1].x == row[stop].x + 1:
				stop += 1
			var l_open := _open(plateau, faces, row[start] + Vector2i(-1, 0))
			var r_open := _open(plateau, faces, row[stop] + Vector2i(1, 0))
			# Read continuation at the plateau row so the edge role stays constant down the wall.
			var edge: int = int(faces[row[start]].edge)
			var l_ground: bool = plateau.has(Vector2i(row[start].x - 1, edge))
			var r_ground: bool = plateau.has(Vector2i(row[stop].x + 1, edge))
			for i in range(start, stop + 1):
				out[row[i]] = {
					"col": i - start, "width": stop - start + 1,
					"open_left": l_open, "open_right": r_open,
					"ground_left": l_ground, "ground_right": r_ground,
				}
			start = stop + 1

	# Align every row to the top run to prevent seams where the wall width changes.
	var top := {}
	for f in out:
		if f.y == int(faces[f].edge) + 1:
			top[Vector2i(f.x, int(faces[f].edge))] = out[f]
	for f in out:
		var anchor = top.get(Vector2i(f.x, int(faces[f].edge)))
		if anchor == null:
			continue
		var here: Dictionary = out[f]
		here.col = int(anchor.col)
		here.width = int(anchor.width)
		here.open_left = anchor.open_left
		here.open_right = anchor.open_right
		here.ground_left = anchor.ground_left
		here.ground_right = anchor.ground_right
	return out


static func _open(plateau: Dictionary, faces: Dictionary, c: Vector2i) -> bool:
	return not plateau.has(c) and not faces.has(c)


static func bands_at(cfg: Dictionary, place: Dictionary, depth: int, rise: int, rows: int) -> Dictionary:
	var col: int = int(place.get("col", 0))
	var ncols: int = int(place.get("width", 1))
	var open_left: bool = bool(place.get("open_left", true))
	var open_right: bool = bool(place.get("open_right", true))
	var ground_left: bool = bool(place.get("ground_left", false))
	var ground_right: bool = bool(place.get("ground_right", false))
	# Bands don't need the body, so filled pieces draw before it exists.
	var left := piece(cfg, "left")
	var right := piece(cfg, "right")
	var alone_w := 1
	for k in ["alone", "alone_top", "alone_bottom"]:
		var ap := piece(cfg, k)
		if ap.use:
			alone_w = maxi(alone_w, ap.rect.size.x)
	# A corner without its side still gets a one tile end column.
	var left_w: int = _end_width(cfg, left, "top_left", "bottom_left") if not ground_left else 0
	var right_w: int = _end_width(cfg, right, "top_right", "bottom_right") if not ground_right else 0
	if left_w + right_w > ncols:
		if open_right and not open_left:
			left_w = maxi(0, ncols - right_w)
		else:
			right_w = maxi(0, ncols - left_w)

	# Offsets shift the repeating bodg; end pieces stay pinned to the wall.
	var off := body_offset(cfg).x
	var cband := "mid"
	var cx := 0
	# Choose tower geometry even without tower artwork; fallbacks supply missing pieces.
	if open_left and open_right and ncols <= alone_w:
		cband = "alone"
		cx = col
	elif left_w > 0 and col < left_w:
		cband = "left"
		cx = col
	elif right_w > 0 and col >= ncols - right_w:
		cband = "right"
		cx = col - (ncols - right_w)
	else:
		cx = col - left_w + off

	var top := piece(cfg, "alone_top" if cband == "alone" else "top")
	var bottom := piece(cfg, "alone_bottom" if cband == "alone" else "bottom")
	if cband == "alone" and not top.use:
		top = piece(cfg, "top")
	if cband == "alone" and not bottom.use:
		bottom = piece(cfg, "bottom")
	# Same for a corner with no top or bottom row.
	var top_h: int = top.rect.size.y if top.use else (1 if _corner_used(cfg, "top", cband) else 0)
	var bot_h: int = bottom.rect.size.y if bottom.use else (1 if _corner_used(cfg, "bottom", cband) else 0)
	if top_h + bot_h > rows:
		top_h = maxi(0, rows - bot_h)

	var rband := "mid"
	var ry := 0
	if top_h > 0 and depth < top_h:
		rband = "top"
		ry = depth
	elif bot_h > 0 and rise < bot_h:
		rband = "bottom"
		ry = bot_h - 1 - rise
	elif bool(cfg.get("rows_up", false)):
		# Negative row offsets read the body upward from the base, independently of wals height.
		ry = -(rise - bot_h + body_offset(cfg).y) - 1
	else:
		ry = depth - top_h + body_offset(cfg).y

	# Wrap offsets only when drawing; nested modulo operations can change the phase.
	return {"row": rband, "col": cband, "x": cx, "y": ry}


static func _corner_used(cfg: Dictionary, row: String, cband: String) -> bool:
	if cband != "left" and cband != "right":
		return false
	return piece(cfg, "%s_%s" % [row, cband]).use


static func _end_width(cfg: Dictionary, side: Dictionary, top_corner: String, bottom_corner: String) -> int:
	if side.use:
		return side.rect.size.x
	return 1 if piece(cfg, top_corner).use or piece(cfg, bottom_corner).use else 0


static func key_for_cell(cfg: Dictionary, place: Dictionary, depth: int, rise: int, rows: int) -> String:
	var b := bands_at(cfg, place, depth, rise, rows)
	return key_at(b.row, b.col) if not b.is_empty() else ""


static func tile_for(cfg: Dictionary, place: Dictionary, depth: int, rise: int, rows: int) -> Dictionary:
	var source: int = int(cfg.get("source_id", -1))
	if source < 0:
		return {}
	var b := bands_at(cfg, place, depth, rise, rows)
	if b.is_empty():
		return {}
	var p := effective(cfg, key_at(b.row, b.col))
	if not p.use:
		return {}
	return {
		"source_id": source,
		"coord": p.rect.position + Vector2i(posmod(int(b.x), p.rect.size.x), posmod(int(b.y), p.rect.size.y)),
	}
