@tool
extends Window


class Preview extends Control:
	var image: Image = null
	var frame := Rect2i()          ## the piece that gets cut, in image pixels
	var zoom := 1.0
	var at := Vector2.ZERO         ## top-left of the image, in control pixels
	var _texture: ImageTexture = null
	var _dragging := false
	var _moved := false

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func show_image(img: Image, piece: Rect2i) -> void:
		var same_size: bool = image != null and img != null and image.get_size() == img.get_size()
		image = img
		frame = piece
		_texture = ImageTexture.create_from_image(img) if img != null else null
		if not same_size:
			_moved = false
		queue_redraw()

	func fit() -> void:
		if image == null or size.x < 4.0 or size.y < 4.0:
			return
		var by := minf(size.x / float(image.get_width()), size.y / float(image.get_height()))
		zoom = maxf(1.0, floorf(by))
		at = (size - Vector2(image.get_size()) * zoom) * 0.5
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and not _moved:
			fit()

	func _draw() -> void:
		if _texture == null:
			return
		if not _moved:
			fit()
		var whole := Rect2(at, Vector2(image.get_size()) * zoom)
		draw_texture_rect(_texture, whole, false)
		if frame.size.x > 0:
			var box := Rect2(at + Vector2(frame.position) * zoom, Vector2(frame.size) * zoom)
			draw_rect(box, Color(1, 0.2, 0.2), false, maxf(1.0, zoom * 0.15))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_zoom_at(event.position, 1.0)
				accept_event()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_zoom_at(event.position, -1.0)
				accept_event()
			elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_LEFT]:
				_dragging = event.pressed
				accept_event()
		elif event is InputEventMouseMotion and _dragging:
			at += event.relative
			_moved = true
			queue_redraw()
			accept_event()

	func _zoom_at(where: Vector2, step: float) -> void:
		if image == null:
			return
		var was := zoom
		zoom = clampf(zoom + step, 1.0, 16.0)
		if zoom == was:
			return
		at = where - (where - at) * (zoom / was)
		_moved = true
		queue_redraw()


const ObjectBake := preload("res://addons/better-tile-editor/ObjectBake.gd")
const ObjectTerrain := preload("res://addons/better-tile-editor/ObjectTerrain.gd")
const Chrome := preload("res://addons/better-tile-editor/editor/Chrome.gd")

signal bake_requested(sheet: Image, unit_cells: Vector2i, from: Dictionary)

var _tileset: TileSet
var _terrain_id := -1
var _from := {}          ## source, origin, size of the lone drawing
var _mass := false
var _art: Image = null

var _off_x: SpinBox
var _off_y: SpinBox
var _across: SpinBox
var _down: SpinBox
var _stagger: CheckBox
var _keep: SpinBox
var _status: Label
var _view: Preview
var _bake: Button
var _syncing := false


func _init() -> void:
	title = "Bake the second block"
	size = Vector2i(760, 520)
	close_requested.connect(hide)

	var root := HSplitContainer.new()
	root.anchors_preset = Control.PRESET_FULL_RECT
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	add_child(root)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size.x = 250
	root.add_child(left)

	var how := Label.new()
	how.text = "Stack the drawing against itself and cut out the piece that repeats."
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	left.add_child(how)

	left.add_child(_heading("What gets stacked"))
	_keep = _px_row(left, "Top of the drawing", "A tree is two things in one picture: the canopy, which is what a wood is made of, and the trunk, which stands on the ground. Stack only the canopy and the trunks stop running through the middle of the mass. Zero means the whole drawing.")
	_keep.tooltip_text = _keep.tooltip_text

	left.add_child(_heading("Where the piece is cut"))
	_off_x = _px_row(left, "Across", "Slide the cut sideways. Half the drawing puts its left and right edges together in the middle of the piece, which is where you can see whether they meet.")
	_off_y = _px_row(left, "Down", "Slide the cut down. Half the drawing brings its top and bottom edges into the middle.")
	var half := Button.new()
	half.text = "Half and half"
	half.tooltip_text = "The usual answer: both edges into the middle."
	half.pressed.connect(func():
		var unit := _unit_px()
		_syncing = true
		_off_x.value = unit.x / 2
		_off_y.value = unit.y / 2
		_syncing = false
		_refresh())
	left.add_child(half)

	left.add_child(_heading("How many fit in the piece"))
	_across = _count_row(left, "Across", "One means the copies touch and never meet. Two means each one covers half of its neighbour.")
	_down = _count_row(left, "Down", "Two is what packed art usually wants: the rows half a drawing apart.")
	_stagger = CheckBox.new()
	_stagger.text = "Shift odd rows"
	_stagger.tooltip_text = "Every other row moved half a drawing sideways, which is the brickwork look."
	_stagger.button_pressed = true
	_stagger.toggled.connect(func(_on): _refresh())
	left.add_child(_stagger)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	left.add_child(_status)

	left.add_child(Chrome.rule())
	_bake = Button.new()
	_bake.text = "Bake"
	_bake.tooltip_text = "Write the pair into the tileset as a source of its own, and take the terrain off the drawing it came from."
	_bake.pressed.connect(_on_bake)
	left.add_child(_bake)
	var export_png := Button.new()
	export_png.text = "Export PNG"
	export_png.tooltip_text = "Save the sheet next to the tileset, to touch it up by hand."
	export_png.pressed.connect(_on_export)
	left.add_child(export_png)

	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	_view = Preview.new()
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.tooltip_text = "Wheel to zoom, drag to move."
	right.add_child(_view)

	Chrome.dress_split(root)
	Chrome.open_at(root, 0.34)


func _heading(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	return l


func _px_row(into: Control, text: String, tip: String) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.tooltip_text = tip
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var sp := SpinBox.new()
	sp.min_value = 0
	sp.max_value = 512
	sp.step = 1
	sp.suffix = "px"
	sp.custom_minimum_size.x = 92
	sp.tooltip_text = tip
	sp.value_changed.connect(func(_v): _refresh())
	row.add_child(sp)
	into.add_child(row)
	return sp


func _count_row(into: Control, text: String, tip: String) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.tooltip_text = tip
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var sp := SpinBox.new()
	sp.min_value = 1
	sp.max_value = 8
	sp.step = 1
	sp.custom_minimum_size.x = 92
	sp.tooltip_text = tip
	sp.value_changed.connect(func(_v): _refresh())
	row.add_child(sp)
	into.add_child(row)
	return sp


func setup(ts: TileSet, terrain_id: int, terrain_name: String) -> String:
	_tileset = ts
	_terrain_id = terrain_id
	title = "Bake the second block: %s" % terrain_name
	_from = {}
	_art = null

	var cfg := ObjectTerrain.object_config(ts, terrain_id)
	_mass = bool(cfg.get("mass", false))
	if cfg.is_empty():
		return "This terrain has no object configuration yet."
	var size_a: Array = cfg.get("size", [2, 2])
	var size := Vector2i(int(size_a[0]), int(size_a[1]))
	var lone_a: Array = cfg.get("lone", [])
	if lone_a.size() != 2:
		return "Mark the lone drawing first: pick the terrain, press Lone in the toolbar and click its top-left tile in the atlas."
	var lone := Vector2i(lone_a[0], lone_a[1])

	var source_id := -1
	for i in ts.get_source_count():
		var sid := ts.get_source_id(i)
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src == null or sid == ObjectBake.source_of(ts, terrain_id):
			continue
		if src.get_tile_at_coords(lone) == lone:
			var td := src.get_tile_data(lone, 0)
			if td != null and td.has_meta(&"_better_terrain") \
					and int(td.get_meta(&"_better_terrain").get("type", -2)) == terrain_id:
				source_id = sid
				break
	if source_id < 0:
		return "The lone drawing is not marked in any atlas. Mark it with the Lone button first."

	var src := ts.get_source(source_id) as TileSetAtlasSource
	_from = {source = source_id, origin = lone, size = size, tile = src.texture_region_size}
	_art = ObjectBake.art_of(src, lone, size)
	if _art == null:
		return "That source has no readable texture."

	var unit_px := size * Vector2i(src.texture_region_size)
	_syncing = true
	_off_x.value = 0
	_off_y.value = 0
	_across.value = 1
	_down.value = 2
	_stagger.button_pressed = true
	_keep.max_value = unit_px.y
	_keep.value = ObjectBake.default_crop(_art, unit_px, Vector2i(unit_px.x, unit_px.y / 2), unit_px.x / 2)
	_syncing = false
	_refresh()
	return ""


func _unit_cells() -> Vector2i:
	return _from.get("size", Vector2i.ONE)


func _unit_px() -> Vector2i:
	var tile: Vector2i = _from.get("tile", Vector2i(16, 16))
	return _unit_cells() * tile


## The pitch must divide the unit so the pattern repeats exactly.
func _pitch() -> Vector2i:
	var unit := _unit_px()
	return Vector2i(maxi(1, unit.x / _count(_across, unit.x)),
		maxi(1, unit.y / _count(_down, unit.y)))


func _count(box: SpinBox, span: int) -> int:
	var want: int = maxi(1, int(box.value))
	if span % want == 0:
		return want
	var best := 1
	for n in range(1, int(box.max_value) + 1):
		if span % n == 0 and absi(n - want) < absi(best - want):
			best = n
	box.set_value_no_signal(best)
	return best


func _mass_art() -> Image:
	return ObjectBake.crown(_art, int(_keep.value))


func _offset() -> Vector2i:
	var unit := _unit_px()
	return Vector2i(posmod(int(_off_x.value), maxi(1, unit.x)), posmod(int(_off_y.value), maxi(1, unit.y)))


func _stagger_px() -> int:
	return _unit_px().x / 2 if _stagger.button_pressed else 0


func _refresh() -> void:
	if _syncing or _art == null:
		return
	var unit_px := _unit_px()
	var unit: Image = ObjectBake.bake_piece(_mass_art(), unit_px, _pitch(), _stagger_px(), _offset())
	var grid: Image = ObjectBake.mass_preview(_art, unit, unit_px, _pitch(), _stagger_px()) \
		if _mass else ObjectBake.tiled(unit, Vector2i(3, 3))
	_view.show_image(grid, Rect2i(unit_px, unit_px))
	var cells := _unit_cells()
	var pitch := _pitch()
	var n: int = (unit_px.x / maxi(1, pitch.x)) * (unit_px.y / maxi(1, pitch.y))
	var off := _offset()
	var gaps: int = ObjectBake.holes(unit)
	if _mass:
		_status.text = "Painted as an area: what you see is the drawings stacked, and the piece fills in behind them."
		return
	_status.text = "%d drawing%s on a piece of %dx%d cells, cut at %d, %d. It repeats itself." % [
		n, "" if n == 1 else "s", cells.x, cells.y, off.x, off.y]
	if gaps > 0:
		_status.text += "\n%d pixels of it are see-through: stack more of the drawing, or let the copies overlap." % gaps


func _on_bake() -> void:
	if _art == null:
		return
	var unit_px := _unit_px()
	var sheet: Image = ObjectBake.sheet(_art, unit_px, _pitch(), _stagger_px(), _offset(), _mass_art())
	bake_requested.emit(sheet, _unit_cells(), _from)


func _on_export() -> void:
	if _art == null or _tileset == null:
		return
	var sheet: Image = ObjectBake.sheet(_art, _unit_px(), _pitch(), _stagger_px(), _offset(), _mass_art())
	var base := _tileset.resource_path
	var to := "res://baked.png" if base.is_empty() else base.get_basename() + "_baked.png"
	var err := sheet.save_png(to)
	if err == OK:
		print("[BetterTerrain] baked sheet written to %s" % to)
	else:
		push_warning("Could not write %s (error %d)" % [to, err])
