@tool
extends Control

signal base_changed(base: Rect2i)

var base := Rect2i(0, 0, 1, 1)
var drawing_size := Vector2i.ONE
var _source: TileSetAtlasSource
var _origin := Vector2i.ZERO
var _drag := ""
var _start_cell := Vector2i.ZERO
var _start_base := Rect2i()
## Corner being dragged, as (0|1, 0|1) for left/right and top/bottom.
var _corner := Vector2i.ONE

const CORNERS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]

func _init() -> void:
	custom_minimum_size = Vector2(280, 230)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	tooltip_text = "Drag the selected tiles to move the base. Drag any corner to resize. Shift-drag to select a new rectangle. Escape cancels a drag."

func setup(ts: TileSet, source_id: int, origin: Vector2i, dimensions: Vector2i, selection: Rect2i) -> void:
	_source = ts.get_source(source_id) as TileSetAtlasSource if ts != null and ts.has_source(source_id) else null
	_origin = origin
	drawing_size = dimensions
	base = selection
	queue_redraw()

func _cell_size() -> float:
	return maxf(1.0, floorf(minf((size.x - 32) / drawing_size.x, (size.y - 54) / drawing_size.y)))

func _art_rect() -> Rect2:
	var extent := Vector2(drawing_size) * _cell_size()
	return Rect2(Vector2((size.x - extent.x) / 2, 12), extent)

func _selection_rect() -> Rect2:
	return Rect2(_art_rect().position + Vector2(base.position) * _cell_size(), Vector2(base.size) * _cell_size())

func _handle_rect(corner: Vector2i) -> Rect2:
	var selected := _selection_rect()
	return Rect2(selected.position + selected.size * Vector2(corner) - Vector2(6, 6), Vector2(12, 12))

func _corner_at(point: Vector2) -> Vector2i:
	for corner in CORNERS:
		if _handle_rect(corner).has_point(point):
			return corner
	return Vector2i(-1, -1)

func _grid_line_at(point: Vector2) -> Vector2i:
	var local := (point - _art_rect().position) / _cell_size()
	return Vector2i(roundi(local.x), roundi(local.y))

func _corner_cell(rect: Rect2i, corner: Vector2i) -> Vector2i:
	return rect.position + (rect.size - Vector2i.ONE) * corner

func _cell_at(point: Vector2) -> Vector2i:
	var local := (point - _art_rect().position) / _cell_size()
	return Vector2i(clampi(floori(local.x), 0, drawing_size.x - 1), clampi(floori(local.y), 0, drawing_size.y - 1))

func _set_base(value: Rect2i) -> void:
	if value == base:
		return
	base = value
	queue_redraw()
	base_changed.emit(base)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not _drag.is_empty():
		_drag = ""
		_set_base(_start_base)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if not _drag.is_empty():
				_drag = ""
				accept_event()
			return
		var corner := _corner_at(event.position)
		if not _art_rect().has_point(event.position) and corner.x < 0:
			return
		grab_focus()
		_start_cell = _cell_at(event.position)
		_start_base = base
		if event.shift_pressed:
			_drag = "select"
		elif corner.x >= 0:
			_drag = "resize"
			_corner = corner
		elif base.has_point(_start_cell):
			_drag = "move"
		else:
			_drag = "select"
		if _drag == "select":
			_set_base(Rect2i(_start_cell, Vector2i.ONE))
		accept_event()
	elif event is InputEventMouseMotion:
		# A release outside the window never arrives; do not keep dragging without a button.
		if not _drag.is_empty() and not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_drag = ""
		var cell := _cell_at(event.position)
		match _drag:
			"move":
				var at := _start_base.position + cell - _start_cell
				at = at.clamp(Vector2i.ZERO, drawing_size - _start_base.size)
				_set_base(Rect2i(at, _start_base.size))
			"resize":
				# The opposite corner stays put; dragging past it flips the rectangle.
				var fixed := _corner_cell(_start_base, Vector2i.ONE - _corner)
				var moving := (_grid_line_at(event.position) - _corner).clamp(Vector2i.ZERO, drawing_size - Vector2i.ONE)
				_set_base(Rect2i(fixed.min(moving), (fixed - moving).abs() + Vector2i.ONE))
			"select":
				_set_base(Rect2i(_start_cell.min(cell), (_start_cell - cell).abs() + Vector2i.ONE))
		if not _drag.is_empty():
			accept_event()
		var hovered := _corner if _drag == "resize" else _corner_at(event.position)
		if hovered.x >= 0:
			mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE if hovered.x == hovered.y else Control.CURSOR_BDIAGSIZE
		else:
			mouse_default_cursor_shape = Control.CURSOR_MOVE if _selection_rect().has_point(event.position) else Control.CURSOR_CROSS

func _draw() -> void:
	var art := _art_rect()
	var px := _cell_size()
	for y in drawing_size.y:
		for x in drawing_size.x:
			var cell := Vector2i(x, y)
			var rect := Rect2(art.position + Vector2(cell) * px, Vector2(px, px))
			draw_rect(rect, Color(0.19, 0.20, 0.22) if (x + y) % 2 else Color(0.24, 0.25, 0.27))
			if _source != null and _source.has_tile(_origin + cell):
				draw_texture_rect_region(_source.texture, rect, _source.get_tile_texture_region(_origin + cell))
			draw_rect(rect, Color(0.8, 0.85, 0.9, 0.3), false)
	var selected := _selection_rect()
	draw_rect(selected, Color(1.0, 0.75, 0.2, 0.22))
	draw_rect(selected, Color(1.0, 0.75, 0.2), false, 2)
	for corner in CORNERS:
		draw_rect(_handle_rect(corner), Color(1.0, 0.75, 0.2))
	var font := get_theme_default_font()
	draw_string(font, Vector2(8, size.y - 23), "Drag base to move · Corners to resize", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(8, size.y - 5), "Shift-drag to select tiles · Esc to cancel", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.73, 0.77))
