@tool
extends ConfirmationDialog
## Create quick terrain's preview: the joins read from the drawing (click to toggle one) and a
## map painted with them.

const Coverage := preload("res://addons/better-tile-editor/editor/TerrainCoverage.gd")
const CoverageWindow := preload("res://addons/better-tile-editor/editor/CoverageWindow.gd")
const PreviewMap := preload("res://addons/better-tile-editor/editor/PreviewMap.gd")
const FOLLOW_SETTING := "editors/better_terrain/quick_match_follow"
## Each peering bit's place in a tile's 3x3 sketch.
const PLACES := {
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE: Vector2i(2, 1), TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: Vector2i(1, 2),
	TileSet.CELL_NEIGHBOR_LEFT_SIDE: Vector2i(0, 1), TileSet.CELL_NEIGHBOR_TOP_SIDE: Vector2i(1, 0),
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: Vector2i(2, 2), TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: Vector2i(0, 2),
	TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: Vector2i(0, 0), TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: Vector2i(2, 0),
}

## The joins as adjusted ({coords: [bits]}), the colour, and whether to go on to Complete terrain.
signal chosen(bits: Dictionary, color: Color, follow: bool)

var _src: TileSetAtlasSource
var _bits := {}
var _box := Rect2i()
var _tiles_view: Control
var _sample: PreviewMap
var _summary: Label
var _colour: ColorPickerButton
var _follow: CheckBox


func _init() -> void:
	title = "Create quick terrain"
	ok_button_text = "Create terrain"
	min_size = Vector2i(760, 460)
	wrap_controls = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_summary = Label.new()
	_summary.theme_type_variation = &"HeaderMedium"
	column.add_child(_summary)
	var views := HBoxContainer.new()
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views.add_theme_constant_override("separation", 12)
	column.add_child(views)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	views.add_child(left)
	var hint := Label.new()
	hint.text = "Joins read from the drawing. Click a side or corner to change one."
	hint.modulate = Color(1, 1, 1, 0.6)
	left.add_child(hint)
	_tiles_view = Control.new()
	_tiles_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tiles_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tiles_view.draw.connect(_draw_tiles)
	_tiles_view.gui_input.connect(_on_tiles_input)
	_tiles_view.resized.connect(_tiles_view.queue_redraw)
	left.add_child(_tiles_view)
	views.add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 300
	views.add_child(right)
	var head := HBoxContainer.new()
	right.add_child(head)
	var preview := Label.new()
	preview.text = "Preview"
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(preview)
	var fit := Button.new()
	fit.icon = EditorInterface.get_editor_theme().get_icon(&"ZoomReset", &"EditorIcons")
	fit.flat = true
	fit.tooltip_text = "Fit the map (or double-click it)"
	head.add_child(fit)
	_sample = PreviewMap.new()
	_sample.grid = Vector2i(CoverageWindow.SAMPLE[0].length(), CoverageWindow.SAMPLE.size())
	_sample.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sample.draw.connect(_draw_sample)
	fit.pressed.connect(_sample.fit)
	right.add_child(_sample)
	var legend := Label.new()
	legend.text = "Red = no piece yet"
	legend.modulate = Color(1, 1, 1, 0.6)
	right.add_child(legend)
	var form := HBoxContainer.new()
	form.add_theme_constant_override("separation", 8)
	column.add_child(form)
	var colour_label := Label.new()
	colour_label.text = "Colour"
	form.add_child(colour_label)
	_colour = ColorPickerButton.new()
	_colour.custom_minimum_size = Vector2(40, 0)
	_colour.color_changed.connect(func(_c): _tiles_view.queue_redraw())
	form.add_child(_colour)
	_follow = CheckBox.new()
	_follow.text = "Generate missing pieces and/or collisions"
	_follow.tooltip_text = "Open Complete terrain on the new terrain once it is made."
	_follow.toggled.connect(func(on):
		EditorInterface.get_editor_settings().set_setting(FOLLOW_SETTING, on)
		_sync_ok())
	column.add_child(_follow)
	confirmed.connect(func(): chosen.emit(_bits.duplicate(true), _colour.color, _follow.button_pressed))


func setup(src: TileSetAtlasSource, bits: Dictionary, color: Color) -> void:
	_src = src
	_bits = bits.duplicate(true)
	_box = Rect2i()
	for c: Vector2i in _bits:
		_box = Rect2i(c, Vector2i.ONE) if _box.size == Vector2i.ZERO else _box.merge(Rect2i(c, Vector2i.ONE))
	_colour.color = color
	var settings := EditorInterface.get_editor_settings()
	_follow.button_pressed = not settings.has_setting(FOLLOW_SETTING) or bool(settings.get_setting(FOLLOW_SETTING))
	_sync_ok()
	_sync()


# With the tick on, the button leads on to the next window, and says so.
func _sync_ok() -> void:
	ok_button_text = "Create and configure pieces…" if _follow.button_pressed else "Create terrain"


func _sync() -> void:
	var with_corners := _with_corners()
	var drawn := {}
	for c: Vector2i in _bits:
		drawn[Coverage.normalize(_mask(c), _match(), with_corners)] = true
	var need := Coverage.required(_match(), with_corners)
	_summary.text = "%d tiles · %d / %d pieces (%s)" % [_bits.size(), need.filter(func(m): return drawn.has(m)).size(),
		need.size(), "blob" if with_corners else "sides only"]
	_tiles_view.queue_redraw()
	_sample.queue_redraw()


static func _match() -> int:
	return BetterTerrain.TerrainType.MATCH_TILES


func _with_corners() -> bool:
	for c: Vector2i in _bits:
		for corner in Coverage.CORNERS:
			if corner in _bits[c]:
				return true
	return false


func _mask(c: Vector2i) -> int:
	var out := 0
	for bit: int in _bits[c]:
		out |= 1 << bit
	return out


## The selection laid out as in the atlas, each tile at a whole zoom that fits the view.
func _tile_cell() -> float:
	var region := Vector2(_src.texture_region_size)
	var fit := minf(_tiles_view.size.x / (_box.size.x * region.x), _tiles_view.size.y / (_box.size.y * region.y))
	return maxf(1.0, floorf(fit)) * region.x


func _tile_rect(c: Vector2i, cell: float) -> Rect2:
	return Rect2(Vector2(c - _box.position) * cell, Vector2(cell, cell))


func _draw_tiles() -> void:
	if _src == null:
		return
	var cell := _tile_cell()
	var third := cell / 3.0
	for c: Vector2i in _bits:
		var r := _tile_rect(c, cell)
		_tiles_view.draw_texture_rect_region(_src.texture, r, Rect2(_src.get_tile_texture_region(c)))
		_tiles_view.draw_rect(Rect2(r.position + Vector2(third, third), Vector2(third, third)).grow(-1), Color(_colour.color, 0.55))
		for bit: int in _bits[c]:
			if PLACES.has(bit):
				_tiles_view.draw_rect(Rect2(r.position + Vector2(PLACES[bit]) * third, Vector2(third, third)).grow(-1), Color(_colour.color, 0.55))
		_tiles_view.draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)


func _on_tiles_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var cell := _tile_cell()
	var c := _box.position + Vector2i((event.position / cell).floor())
	if not _bits.has(c):
		return
	var place := Vector2i(((event.position - _tile_rect(c, cell).position) / (cell / 3.0)).floor())
	for bit: int in PLACES:
		if PLACES[bit] == place:
			if bit in _bits[c]:
				_bits[c].erase(bit)
			else:
				_bits[c].append(bit)
			_sync()
			return


func _draw_sample() -> void:
	_sample.draw_rect(Rect2(Vector2.ZERO, _sample.size), Color(0, 0, 0, 0.25))
	if _src == null:
		return
	var with_corners := _with_corners()
	var lookup := {}
	for c: Vector2i in _bits:
		var m := Coverage.normalize(_mask(c), _match(), with_corners)
		if not lookup.has(m):
			lookup[m] = []
		lookup[m].append(c)
	var sample: Array = CoverageWindow.SAMPLE
	var rows := sample.size()
	var cols: int = sample[0].length()
	var view := _sample.current()
	var cell: float = view.cell
	var origin: Vector2 = view.origin
	for y in rows:
		for x in cols:
			if not CoverageWindow._painted(x, y):
				continue
			var m := 0
			for bit: int in PLACES:
				var step: Vector2i = PLACES[bit] - Vector2i.ONE
				if CoverageWindow._painted(x + step.x, y + step.y):
					m |= 1 << bit
			m = Coverage.normalize(m, _match(), with_corners)
			var r := Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell))
			if lookup.has(m):
				var tiles: Array = lookup[m]
				var c: Vector2i = tiles[absi(hash(Vector2i(x, y))) % tiles.size()]
				_sample.draw_texture_rect_region(_src.texture, r, Rect2(_src.get_tile_texture_region(c)))
			else:
				_sample.draw_rect(r.grow(-1), Color(0.9, 0.2, 0.2, 0.55))
