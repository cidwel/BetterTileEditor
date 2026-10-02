@tool
extends ConfirmationDialog
## Splits a block of atlas tiles into equal blocks, one per frame, and animates the first one.

signal animation_accepted(frame_cells: Vector2i, frames: int, speed: float, mode: int)

const DEFAULT_SPEED := 5.0
const SHEET_HEIGHT := 72.0

var _src: TileSetAtlasSource
var _origin: Vector2i
var _tile_size: Vector2i
## Selection size, in tiles of _tile_size.
var _grid := Vector2i.ONE
var _blocks_pick: OptionButton
## How the blocks sit in the selection: across × down.
var _split := Vector2i.ONE
var _speed_spin: SpinBox
var _mode_pick: OptionButton
var _preview: Control
var _sheet: Control
var _note: Label
var _time := 0.0


func setup(src: TileSetAtlasSource, origin: Vector2i, tile_size: Vector2i, grid: Vector2i, problem: Callable) -> void:
	_src = src
	_origin = origin
	_tile_size = tile_size
	_grid = grid
	# Only the counts that cut the selection evenly and leave whole tiles in each block.
	_blocks_pick.clear()
	for n in range(2, grid.x * grid.y + 1):
		var split := split_for(grid, n)
		if split == Vector2i.ZERO:
			continue
		@warning_ignore("integer_division")
		var block := Vector2i(grid.x / split.x, grid.y / split.y)
		if not str(problem.call(block * tile_size, n)).is_empty():
			continue
		_blocks_pick.add_item("%d  (%d×%d tiles each)" % [n, block.x, block.y], n)
	if _blocks_pick.item_count > 0:
		_blocks_pick.select(_blocks_pick.item_count - 1)
	_sync()


func blocks() -> int:
	return _blocks_pick.get_selected_id() if _blocks_pick.selected >= 0 else 0


func frame_cells() -> Vector2i:
	@warning_ignore("integer_division")
	var tiles := Vector2i(_grid.x / _split.x, _grid.y / _split.y)
	return tiles * _tile_size


## How n equal blocks fit the selection, across × down, or (0, 0) when they don't.
## A row of blocks is preferred, then a column, then the squarest grid.
static func split_for(grid: Vector2i, n: int) -> Vector2i:
	var best := Vector2i.ZERO
	for across in range(1, n + 1):
		if n % across != 0:
			continue
		@warning_ignore("integer_division")
		var down := n / across
		if grid.x % across != 0 or grid.y % down != 0:
			continue
		var candidate := Vector2i(across, down)
		if best == Vector2i.ZERO or _split_rank(candidate, n) < _split_rank(best, n):
			best = candidate
	return best


static func _split_rank(split: Vector2i, n: int) -> int:
	if split.y == 1:
		return 0
	if split.x == 1:
		return 1
	return 2 + absi(split.x - split.y) * n


func _init() -> void:
	title = "Quick animation"
	ok_button_text = "Create animation"
	min_size = Vector2i(380, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	_preview = Control.new()
	_preview.custom_minimum_size = Vector2(128, 128)
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.draw.connect(_draw_preview)
	box.add_child(_preview)

	_sheet = Control.new()
	_sheet.custom_minimum_size = Vector2(0, SHEET_HEIGHT)
	_sheet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sheet.draw.connect(_draw_sheet)
	box.add_child(_sheet)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)

	_blocks_pick = OptionButton.new()
	_blocks_pick.tooltip_text = ("How many blocks, one per frame, the selection holds. It is cut into that many equal\n"
		+ "blocks, and every tile of the first one steps through the same spot of the next ones.\nOnly the counts that fit the selection are listed.")
	_blocks_pick.item_selected.connect(func(_i): _sync())
	_add_row(grid, "Blocks", _blocks_pick)

	_speed_spin = SpinBox.new()
	_speed_spin.min_value = 0.1
	_speed_spin.max_value = 120.0
	_speed_spin.step = 0.1
	_speed_spin.value = DEFAULT_SPEED
	_speed_spin.suffix = "fps"
	_speed_spin.tooltip_text = "Frames per second. Every frame lasts the same."
	_add_row(grid, "Speed", _speed_spin)

	_mode_pick = OptionButton.new()
	_mode_pick.add_item("In sync", TileSetAtlasSource.TILE_ANIMATION_MODE_DEFAULT)
	_mode_pick.add_item("Random start times", TileSetAtlasSource.TILE_ANIMATION_MODE_RANDOM_START_TIMES)
	_mode_pick.tooltip_text = "In sync: every cell shows the same frame.\nRandom start times: each cell starts at a random frame, e.g. for water or grass."
	_add_row(grid, "Mode", _mode_pick)

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 340
	box.add_child(_note)

	confirmed.connect(func():
		animation_accepted.emit(frame_cells(), blocks(), _speed_spin.value, _mode_pick.get_selected_id())
	)
	visibility_changed.connect(func():
		if not visible:
			queue_free()
	)


func _add_row(grid: GridContainer, text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _sync() -> void:
	if _src == null:
		return
	var count := blocks()
	get_ok_button().disabled = count == 0
	if count == 0:
		_split = Vector2i.ONE
		_note.text = "This selection can't be cut into equal blocks of whole tiles."
		_note.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		return
	_split = split_for(_grid, count)
	_note.text = ("The first block plays the animation; the other %d stop being tiles of their own, "
		+ "so map cells that use them will turn empty.") % (count - 1)
	_note.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))


func _process(delta: float) -> void:
	_time += delta
	_preview.queue_redraw()
	_sheet.queue_redraw()


func _current_frame() -> int:
	return int(_time * _speed_spin.value) % maxi(1, blocks())


func _cells_region(from: Vector2i, cells: Vector2i) -> Rect2:
	var region := _src.texture_region_size
	var step := region + _src.separation
	return Rect2(Vector2(_src.margins + from * step), Vector2(region * cells + _src.separation * (cells - Vector2i.ONE)))


## Same layout Godot uses: frame i sits at (i % columns, i / columns) frames from the origin.
func _frame_origin(index: int) -> Vector2i:
	var across := _split.x
	@warning_ignore("integer_division")
	return _origin + Vector2i(index % across, index / across) * frame_cells()


func _fit(area: Vector2, content: Vector2) -> Rect2:
	var zoom := minf(area.x / content.x, area.y / content.y)
	var shown := content * zoom
	return Rect2((area - shown) * 0.5, shown)


func _draw_preview() -> void:
	if _src == null or _src.texture == null or get_ok_button().disabled:
		return
	var region := _cells_region(_frame_origin(_current_frame()), frame_cells())
	var at := _fit(_preview.size, region.size)
	_preview.draw_rect(at, Color(0.15, 0.15, 0.15))
	_preview.draw_texture_rect_region(_src.texture, at, region)


## The whole selection, cut into frames, with the one playing outlined.
func _draw_sheet() -> void:
	if _src == null or _src.texture == null:
		return
	var whole := _cells_region(_origin, _grid * _tile_size)
	var at := _fit(_sheet.size, whole.size)
	_sheet.draw_rect(at, Color(0.15, 0.15, 0.15))
	_sheet.draw_texture_rect_region(_src.texture, at, whole)
	if get_ok_button().disabled:
		return
	var across := _split.x
	var down := _split.y
	var frame_size := at.size / Vector2(across, down)
	for i in across * down:
		@warning_ignore("integer_division")
		var box := Rect2(at.position + frame_size * Vector2(i % across, i / across), frame_size)
		_sheet.draw_rect(box, Color(1, 1, 1, 0.5), false, 1.0)
	@warning_ignore("integer_division")
	var playing := Rect2(at.position + frame_size * Vector2(_current_frame() % across, _current_frame() / across), frame_size)
	_sheet.draw_rect(playing, Color(1.0, 0.75, 0.2), false, 2.0)
