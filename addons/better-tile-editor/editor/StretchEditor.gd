@tool
extends ConfirmationDialog
## Picks which row and column of a Stretch block repeat, next to a preview of the block grown.

const StretchTerrain := preload("res://addons/better-tile-editor/StretchTerrain.gd")

signal repeat_chosen(row: int, col: int)

const GROW := Vector2i(2, 3)

var _src: TileSetAtlasSource
var _block := {}
var _row := 0
var _col := 0
var _zoom := 3.0
var _picker: Control
var _preview: Control


func setup(ts: TileSet, terrain_index: int, terrain_name: String) -> bool:
	_block = StretchTerrain.sync_block(ts, terrain_index)
	if _block.is_empty() or not ts.has_source(int(_block.source)):
		return false
	_src = ts.get_source(int(_block.source)) as TileSetAtlasSource
	if _src == null or _src.texture == null:
		return false
	_row = int(_block.row)
	_col = int(_block.col)
	title = "Stretch: %s" % terrain_name
	ok_button_text = "Apply"
	var rect: Rect2i = _block.rect
	var tile := Vector2(_src.texture_region_size)
	_zoom = clampf(floorf(260.0 / maxf(tile.y * (rect.size.y + GROW.y), tile.x * (rect.size.x + GROW.x))), 1.0, 4.0)
	_build()
	return true


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var note := Label.new()
	note.text = "Click the tile that repeats. Its row fills the extra height,\nits column the extra width."
	box.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var rect: Rect2i = _block.rect
	var tile := Vector2(_src.texture_region_size) * _zoom
	_picker = _panel(row, "Block", tile * Vector2(rect.size))
	_picker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_picker.gui_input.connect(_on_picker_input)
	_picker.draw.connect(_draw_picker)
	_preview = _panel(row, "Painted %d×%d" % [rect.size.x + GROW.x, rect.size.y + GROW.y], tile * Vector2(rect.size + GROW))
	_preview.draw.connect(_draw_preview)


func _panel(parent: Control, caption: String, area: Vector2) -> Control:
	var col := VBoxContainer.new()
	parent.add_child(col)
	var label := Label.new()
	label.text = caption
	col.add_child(label)
	var canvas := Control.new()
	canvas.custom_minimum_size = area
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	col.add_child(canvas)
	return canvas


func _draw_tile(canvas: Control, at: Vector2i, coord: Vector2i) -> void:
	var tile := Vector2(_src.texture_region_size) * _zoom
	var where := Rect2(Vector2(at) * tile, tile)
	if _src.has_tile(coord):
		canvas.draw_texture_rect_region(_src.texture, where, _src.get_tile_texture_region(coord))


func _draw_picker() -> void:
	var rect: Rect2i = _block.rect
	var tile := Vector2(_src.texture_region_size) * _zoom
	for y in rect.size.y:
		for x in rect.size.x:
			_draw_tile(_picker, Vector2i(x, y), rect.position + Vector2i(x, y))
	var gold := Color(1.0, 0.85, 0.3)
	var band_row := Rect2(Vector2(0, _row) * tile, Vector2(rect.size.x, 1) * tile)
	var band_col := Rect2(Vector2(_col, 0) * tile, Vector2(1, rect.size.y) * tile)
	for band in [band_row, band_col]:
		_picker.draw_rect(band, Color(gold, 0.25))
		_picker.draw_rect(band, gold, false, 2.0)


func _draw_preview() -> void:
	var rect: Rect2i = _block.rect
	var region := {}
	for y in rect.size.y + GROW.y:
		for x in rect.size.x + GROW.x:
			region[Vector2i(x, y)] = true
	var block := {"rect": rect, "row": _row, "col": _col}
	for cell in region:
		_draw_tile(_preview, cell, StretchTerrain.tile_for(region, cell, block))


func _on_picker_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var tile := Vector2(_src.texture_region_size) * _zoom
	var at := Vector2i((event.position / tile).floor())
	var rect: Rect2i = _block.rect
	if at.x < 0 or at.y < 0 or at.x >= rect.size.x or at.y >= rect.size.y:
		return
	_row = at.y
	_col = at.x
	_picker.queue_redraw()
	_preview.queue_redraw()


func _ready() -> void:
	confirmed.connect(func(): repeat_chosen.emit(_row, _col))
