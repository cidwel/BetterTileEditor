@tool
extends Control

signal mode_picked(mass: bool)

const CARD_GAP := 12
const PAD := 8
const CAPTION_H := 84

var _ts: TileSet = null
var _blocks: Array = []
var _lone := Vector2i(-1, -1)
var _size := Vector2i(2, 2)
var _base_config := {}
var mass := false:
	set(v):
		mass = v
		queue_redraw()
var _hover := -1

const ObjectTerrain := preload("res://addons/better-tile-editor/ObjectTerrain.gd")


func _ready() -> void:
	custom_minimum_size = Vector2(400, 250)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): _hover = -1; queue_redraw())


func setup(ts: TileSet, blocks: Array, lone: Vector2i, object_size: Vector2i, base_config := {}) -> void:
	_ts = ts
	_base_config = base_config
	_blocks = blocks
	_lone = lone
	_size = Vector2i(maxi(1, object_size.x), maxi(1, object_size.y))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _card_at(event.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var h := _card_at(event.position)
		if h >= 0:
			mass = h == 1
			mode_picked.emit(mass)
			accept_event()


func _card_at(p: Vector2) -> int:
	for i in 2:
		if _card_rect(i).has_point(p):
			return i
	return -1


func _card_rect(i: int) -> Rect2:
	var w := (size.x - CARD_GAP) / 2.0
	return Rect2(i * (w + CARD_GAP), 0, w, size.y)


func _draw() -> void:
	var font := get_theme_default_font()
	var fsize := get_theme_default_font_size()
	var fg := get_theme_color("font_color", "Label")
	var accent := get_theme_color("accent_color", "Editor") if has_theme_color("accent_color", "Editor") else Color(0.4, 0.7, 1.0)
	var dim := Color(fg, 0.55)
	for i in 2:
		var r := _card_rect(i)
		var active := (i == 1) == mass
		var bg := Color(fg, 0.05 if not active else 0.09)
		draw_rect(r, bg, true)
		var border := accent if active else Color(fg, 0.25 if _hover != i else 0.5)
		draw_rect(r, border, false, 2.0 if active else 1.0)
		var title := "Objects" if i == 0 else "Area"
		draw_string(font, r.position + Vector2(PAD, PAD + fsize), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, accent if active else fg)
		var caption := "One by one on a grid, neighbours fusing.\nFor art that fits it: a 2x2 tree, a rock." if i == 0 \
				else "The whole base fits inside the shape.\nThe crown may extend outside."
		draw_multiline_string(font, Vector2(r.position.x + PAD, r.end.y - CAPTION_H + fsize - 3), caption,
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - PAD * 2, fsize - 2, 4, dim)
		var stage := Rect2(r.position + Vector2(PAD, PAD * 2 + fsize), Vector2(r.size.x - PAD * 2, r.size.y - CAPTION_H - PAD * 3 - fsize))
		if i == 0:
			_draw_objects(stage)
		else:
			_draw_area(stage)


func _has_art() -> bool:
	return _ts != null and _blocks.size() == 2 and _lone.x >= 0


func _lone_block() -> Dictionary:
	for b in _blocks:
		if b["rect"].position == _lone:
			return b
	return _blocks[0] if not _blocks.is_empty() else {}


func _joined_block() -> Dictionary:
	for b in _blocks:
		if b["rect"].position != _lone:
			return b
	return _blocks[0] if not _blocks.is_empty() else {}


func _cell_px(stage: Rect2, cells: Vector2) -> float:
	var tile: Vector2 = Vector2(_ts.tile_size) if _ts != null else Vector2(16, 16)
	var s: float = minf(stage.size.x / (cells.x * tile.x), stage.size.y / (cells.y * tile.y))
	return tile.x * minf(1.0, s)


func _draw_block(block: Dictionary, at: Vector2, px: float, only_cells: Array = []) -> void:
	var src := _ts.get_source(block["source_id"]) as TileSetAtlasSource
	if src == null or src.texture == null:
		return
	var origin: Vector2i = block["rect"].position
	for dy in _size.y:
		for dx in _size.x:
			var off := Vector2i(dx, dy)
			if not only_cells.is_empty() and not only_cells.has(off):
				continue
			var coord := origin + off
			if not src.has_tile(coord):
				continue
			var region: Rect2i = src.get_tile_texture_region(coord, 0)
			draw_texture_rect_region(src.texture, Rect2(at + Vector2(off) * px, Vector2(px, px)), region)


func _draw_objects(stage: Rect2) -> void:
	var cells := Vector2(_size.x * 3 + 1, _size.y * 2)
	var px := _cell_px(stage, cells)
	var base := stage.position + (stage.size - cells * px) / 2.0
	if not _has_art():
		_draw_shape_tree(Rect2(base, Vector2(_size) * px), true)
		_draw_base(base, px)
		for gy in 2:
			for gx in 2:
				_draw_shape_tree(Rect2(base + Vector2((_size.x + 1 + gx * _size.x) * px, gy * _size.y * px), Vector2(_size) * px), false)
		return
	_draw_block(_lone_block(), base + Vector2(0, _size.y * px * 0.5), px)
	_draw_base(base + Vector2(0, _size.y * px * 0.5), px)
	var joined := _joined_block()
	for gy in 2:
		for gx in 2:
			_draw_block(joined, base + Vector2((_size.x + 1 + gx * _size.x) * px, gy * _size.y * px), px)


func _draw_base(at: Vector2, px: float) -> void:
	if not mass:
		return
	var base := ObjectTerrain.base_rect(_size, _base_config)
	var rect := Rect2(at + Vector2(base.position) * px, Vector2(base.size) * px)
	draw_rect(rect, Color(1.0, 0.75, 0.2, 0.25))
	draw_rect(rect, Color(1.0, 0.75, 0.2), false, 2.0)


func _draw_area(stage: Rect2) -> void:
	var w: int = _size.x * 3
	var h: int = _size.y + 2
	var painted := {}
	for y in h:
		for x in w:
			if (x == 0 or x == w - 1) and (y == 0 or y == h - 1):
				continue
			painted[Vector2i(x, y)] = true
	var cells := Vector2(w + 2, h + _size.y)
	var px := _cell_px(stage, cells)
	var base := stage.position + (stage.size - cells * px) / 2.0 + Vector2(1, _size.y) * px
	var places := _placements(painted)
	if not _has_art():
		for c in painted:
			draw_rect(Rect2(base + Vector2(c) * px, Vector2(px, px)), Color(0.35, 0.6, 0.3, 0.6), true)
		for p in places:
			_draw_shape_tree(Rect2(base + Vector2(p) * px, Vector2(_size) * px), true)
		return
	var lone := _lone_block()
	for p in places:
		_draw_block(lone, base + Vector2(p) * px, px)


func _placements(painted: Dictionary) -> Array:
	return ObjectTerrain.mass_origins(painted, _size, ObjectTerrain.base_rect(_size, _base_config))


func _draw_shape_tree(r: Rect2, lone: bool) -> void:
	var fg := get_theme_color("font_color", "Label")
	var green := Color(0.35, 0.65, 0.3, 0.9)
	var trunk := Color(0.5, 0.35, 0.2, 0.9)
	var canopy := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.75))
	var stem := Rect2(r.position + Vector2(r.size.x * 0.4, r.size.y * 0.7), Vector2(r.size.x * 0.2, r.size.y * 0.3))
	draw_rect(stem, trunk, true)
	if lone:
		var pts := PackedVector2Array([
			canopy.position + Vector2(canopy.size.x / 2.0, 0),
			canopy.position + Vector2(canopy.size.x, canopy.size.y),
			canopy.position + Vector2(0, canopy.size.y)])
		draw_colored_polygon(pts, green)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(fg, 0.5), 1.0)
	else:
		draw_rect(canopy, green, true)
