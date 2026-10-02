@tool
extends VBoxContainer
## The cliff editor's "Autoassign from tilemap" page: drag a block of wall art in the atlas,
## starting on the one under the terrain's tiles.

const CliffData := preload("res://addons/better-tile-editor/CliffData.gd")
const PreviewMap := preload("res://addons/better-tile-editor/editor/PreviewMap.gd")
const QuarterPieces := preload("res://addons/better-tile-editor/editor/QuarterPieces.gd")
const SURFACE := Color(0.45, 0.85, 0.55)
const BLOCK := Color(1.0, 0.82, 0.3)

signal chosen(source_id: int, block: Rect2i)
signal canceled
## The block as it is dragged, or an empty one when it can't be used yet.
signal block_changed(source_id: int, block: Rect2i)

var tile_set: TileSet
var _source_id := -1
var _surface := Rect2i()
## The atlas the surface is in.
var _surface_id := -1
## Each atlas's box around the terrain's tiles in it.
var _surfaces := {}
var _block := Rect2i()
var _drag_from := Vector2i(-1, -1)
## Zoom in on the block once the view has its size; the page opens before it is laid out.
var _want_focus := false
var _sources: OptionButton
var _map: PreviewMap
var _summary: Label
var _assign: Button


func _init() -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	add_child(head)
	var title := Label.new()
	title.text = "Drag over the wall art in the tileset"
	title.theme_type_variation = &"HeaderSmall"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_sources = OptionButton.new()
	_sources.item_selected.connect(func(i: int) -> void: _pick_source(_sources.get_item_id(i)))
	head.add_child(_sources)
	var fit := Button.new()
	fit.icon = EditorInterface.get_editor_theme().get_icon(&"ZoomReset", &"EditorIcons")
	fit.flat = true
	fit.tooltip_text = "Show the whole atlas (or double-click it)"
	head.add_child(fit)
	_map = PreviewMap.new()
	_map.pan_with_left = false
	_map.tooltip_text = "Drag to pick the block. Wheel to zoom, right or middle drag to move."
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_map_input)
	fit.pressed.connect(_map.fit)
	add_child(_map)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	add_child(foot)
	_summary = Label.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(_summary)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void: canceled.emit())
	foot.add_child(cancel)
	_assign = Button.new()
	_assign.text = "Assign"
	_assign.tooltip_text = "Fill every slot of the face from this block. Undo with Ctrl+Z."
	_assign.pressed.connect(func() -> void: chosen.emit(_source_id, _block))
	foot.add_child(_assign)


## Opens on the atlas holding most of the terrain's tiles, with the block under them picked.
func open(ts: TileSet, bt: Object, terrain_index: int) -> void:
	tile_set = ts
	var counts := {}
	var boxes := {}
	for entry: Dictionary in bt.get_tile_sources_in_terrain(ts, terrain_index):
		var id := _id_of(entry.source)
		var box := Rect2i(entry.coord, Vector2i.ONE)
		boxes[id] = box if not boxes.has(id) else (boxes[id] as Rect2i).merge(box)
		counts[id] = int(counts.get(id, 0)) + 1
	_sources.clear()
	var best := -1
	for i in ts.get_source_count():
		var id := ts.get_source_id(i)
		if not (ts.get_source(id) is TileSetAtlasSource):
			continue
		var src := ts.get_source(id) as TileSetAtlasSource
		var label := src.texture.resource_path.get_file() if src.texture != null and src.texture.resource_path != "" else "Atlas %d" % id
		if src.has_meta(QuarterPieces.GENERATED_META):
			label += " (generated)"
		_sources.add_item(label, id)
		if _better_start(id, best, counts):
			best = id
	_sources.visible = _sources.item_count > 1
	_surfaces = boxes
	_pick_source(best)


# The sheet the terrain was drawn on, not the pieces Complete terrain generated from it:
# the wall art lies under the drawn tiles, and generated atlases have none.
func _better_start(id: int, best: int, counts: Dictionary) -> bool:
	if best == -1:
		return true
	var made := tile_set.get_source(id).has_meta(QuarterPieces.GENERATED_META)
	var best_made := tile_set.get_source(best).has_meta(QuarterPieces.GENERATED_META)
	if made != best_made:
		return best_made
	return int(counts.get(id, 0)) > int(counts.get(best, 0))


## The block a terrain's tiles suggest: as wide as they are, two rows, right below them.
static func default_block(src: TileSetAtlasSource, surface: Rect2i) -> Rect2i:
	if surface.size == Vector2i.ZERO:
		return Rect2i()
	var grid := src.get_atlas_grid_size()
	var block := Rect2i(surface.position.x, surface.end.y, surface.size.x, 2)
	block = block.intersection(Rect2i(Vector2i.ZERO, grid))
	return block if block.size.x > 0 and block.size.y > 0 else Rect2i()


func _pick_source(id: int) -> void:
	_source_id = id
	if id >= 0:
		_sources.select(_sources.get_item_index(id))
	var src := _source()
	if src == null:
		_block = Rect2i()
		_sync()
		return
	_map.grid = src.get_atlas_grid_size()
	_surface = _surfaces.get(id, Rect2i())
	_surface_id = id
	_block = default_block(src, _surface) if id == _surface_id else Rect2i()
	_sync()
	_want_focus = true
	_map.queue_redraw()


func _source() -> TileSetAtlasSource:
	return tile_set.get_source(_source_id) as TileSetAtlasSource if tile_set != null and tile_set.has_source(_source_id) else null


func _id_of(src: TileSetSource) -> int:
	for i in tile_set.get_source_count():
		if tile_set.get_source(tile_set.get_source_id(i)) == src:
			return tile_set.get_source_id(i)
	return -1


# Zoomed in on the surface and the block under it, or the whole atlas when there is none.
func _focus() -> void:
	var area := _surface if _source_id == _surface_id else Rect2i()
	if _block.size != Vector2i.ZERO:
		area = _block if area.size == Vector2i.ZERO else area.merge(_block)
	if area.size == Vector2i.ZERO or _map.size.x <= 0:
		_map.fit()
		return
	area = area.grow(2)
	var cell := floorf(minf(_map.size.x / area.size.x, _map.size.y / area.size.y))
	cell = clampf(cell, 2.0, 96.0)
	var centre := (Vector2(area.position) + Vector2(area.size) * 0.5) * cell
	_map.view = {cell = cell, origin = (_map.size * 0.5 - centre).round()}
	_map.queue_redraw()


func _cell_at(pos: Vector2) -> Vector2i:
	var view := _map.current()
	return Vector2i(((pos - view.origin) / view.cell).floor())


func _on_map_input(event: InputEvent) -> void:
	var src := _source()
	if src == null:
		return
	var grid := src.get_atlas_grid_size()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.double_click:
		var c := _cell_at(event.position).clamp(Vector2i.ZERO, grid - Vector2i.ONE)
		if event.pressed:
			_drag_from = c
			_block = Rect2i(c, Vector2i.ONE)
		else:
			_drag_from = Vector2i(-1, -1)
		_sync()
	elif event is InputEventMouseMotion and _drag_from.x >= 0:
		var c := _cell_at(event.position).clamp(Vector2i.ZERO, grid - Vector2i.ONE)
		var lo := Vector2i(mini(c.x, _drag_from.x), mini(c.y, _drag_from.y))
		var hi := Vector2i(maxi(c.x, _drag_from.x), maxi(c.y, _drag_from.y))
		_block = Rect2i(lo, hi - lo + Vector2i.ONE)
		_sync()


func _sync() -> void:
	_map.queue_redraw()
	var src := _source()
	var holes := 0
	if src != null and _block.size != Vector2i.ZERO:
		for y in range(_block.position.y, _block.end.y):
			for x in range(_block.position.x, _block.end.x):
				if not src.has_tile(Vector2i(x, y)):
					holes += 1
	_assign.disabled = _block.size == Vector2i.ZERO or holes > 0
	block_changed.emit(_source_id, Rect2i() if _assign.disabled else _block)
	if _block.size == Vector2i.ZERO:
		_summary.text = "Drag over the block of wall tiles."
	elif holes > 0:
		_summary.text = "%d cell%s of the block %s no tile." % [holes, "" if holes == 1 else "s", "has" if holes == 1 else "have"]
	else:
		_summary.text = "%d×%d: %s · %s" % [_block.size.x, _block.size.y, _columns_text(), _rows_text()]


func _columns_text() -> String:
	match _block.size.x:
		1: return "one column for every wall"
		2: return "left end, right end, both repeat between"
	var loop := _block.size.x - 2
	return "left end, %s repeating, right end" % ("1 column" if loop == 1 else "%d columns" % loop)


func _rows_text() -> String:
	match _block.size.y:
		1: return "one row for every height"
		2: return "the top repeats down, base on the ground"
	var loop := _block.size.y - 2
	return "top, %s repeating, base on the ground" % ("1 row" if loop == 1 else "%d rows" % loop)


## What each column and row of the block does, as [first, count, label] spans.
func _column_spans() -> Array:
	var w := _block.size.x
	if w == 1:
		return [[0, 1, "all"]]
	if w == 2:
		return [[0, 1, "left"], [1, 1, "right"]]
	return [[0, 1, "left"], [1, w - 2, "repeats ↔"], [w - 1, 1, "right"]]


func _row_spans() -> Array:
	var h := _block.size.y
	if h == 1:
		return [[0, 1, "all"]]
	if h == 2:
		return [[0, 1, "top ↕"], [1, 1, "base"]]
	return [[0, 1, "top"], [1, h - 2, "repeats ↕"], [h - 1, 1, "base"]]


func _draw_map() -> void:
	if _want_focus and _map.size.x > 100 and _map.size.y > 100:
		_want_focus = false
		_focus()
	_map.draw_rect(Rect2(Vector2.ZERO, _map.size), Color(0, 0, 0, 0.25))
	var src := _source()
	if src == null or src.texture == null:
		return
	var view := _map.current()
	var cell: float = view.cell
	var origin: Vector2 = view.origin
	for i in src.get_tiles_count():
		var c := src.get_tile_id(i)
		var r := Rect2(origin + Vector2(c) * cell, Vector2(src.get_tile_size_in_atlas(c)) * cell)
		_map.draw_texture_rect_region(src.texture, r, Rect2(src.get_tile_texture_region(c)))
	var font := get_theme_default_font()
	var fsize := 12
	if _source_id == _surface_id and _surface.size != Vector2i.ZERO:
		var sr := Rect2(origin + Vector2(_surface.position) * cell, Vector2(_surface.size) * cell)
		_map.draw_rect(sr, SURFACE, false, 2.0)
		_map.draw_string(font, sr.position + Vector2(0, -4), "surface", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, SURFACE)
	if _block.size == Vector2i.ZERO:
		return
	var br := Rect2(origin + Vector2(_block.position) * cell, Vector2(_block.size) * cell)
	_map.draw_rect(br, Color(BLOCK, 0.12))
	for span: Array in _column_spans():
		var x0: float = br.position.x + span[0] * cell
		if span[0] > 0:
			_map.draw_line(Vector2(x0, br.position.y), Vector2(x0, br.end.y), Color(BLOCK, 0.7), 1.0)
		var text: String = span[2]
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > span[1] * cell:
			text = {"left": "L", "right": "R", "repeats ↔": "↔"}.get(text, text)
		_map.draw_string(font, Vector2(x0, br.end.y + fsize + 2), text, HORIZONTAL_ALIGNMENT_CENTER,
			span[1] * cell, fsize, BLOCK)
	for span: Array in _row_spans():
		var y0: float = br.position.y + span[0] * cell
		if span[0] > 0:
			_map.draw_line(Vector2(br.position.x, y0), Vector2(br.end.x, y0), Color(BLOCK, 0.7), 1.0)
		_map.draw_string(font, Vector2(br.end.x + 6, y0 + span[1] * cell * 0.5 + fsize * 0.35), span[2],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, BLOCK)
	_map.draw_rect(br, BLOCK, false, 2.0)
