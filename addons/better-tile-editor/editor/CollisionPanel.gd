@tool
extends PanelContainer
## Side panel of the Collisions tool: which physics layer to paint and its layer and mask bits.

signal physics_layer_picked(index: int)
signal bits_changed(index: int, collision_layer: int, collision_mask: int)
signal all_layers_toggled(on: bool)

const HINT_COLOR := Color(0.7, 0.75, 0.85)
const Collisions := preload("res://addons/better-tile-editor/editor/Collisions.gd")

var _tileset: TileSet
var _index := 0
var _layer_row: HBoxContainer
var _layer_pick: OptionButton
var _no_layer: Label
var _bits_box: VBoxContainer
var _layer_bits: BitGrid
var _mask_bits: BitGrid
var _more_buttons := {}
var _alt_pick: OptionButton
var _all_layers: CheckBox
var _clipboard: Label
var _keys: GridContainer
var _clip_row: HBoxContainer
var _clip_preview: Control
var _clip := {}


## Layer bits drawn like Godot's inspector: blocks of 2×4 small cells, 1–16 shown, 17–32 on demand.
class BitGrid extends Control:
	signal changed(value: int)

	const CELL := Vector2(17, 14)
	const GAP := 1.0
	const BLOCK_GAP := 4.0
	const ROWS := 2
	const PER_ROW := 8

	var value := 0
	var expanded := false:
		set(on):
			expanded = on
			update_minimum_size()
			queue_redraw()
	var _hover := -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _get_minimum_size() -> Vector2:
		var width := PER_ROW * (CELL.x + GAP) + BLOCK_GAP
		var groups := 2 if expanded else 1
		return Vector2(width, groups * ROWS * (CELL.y + GAP) + (groups - 1) * BLOCK_GAP)

	@warning_ignore("integer_division")
	func _cell_rect(bit: int) -> Rect2:
		var group := bit / (ROWS * PER_ROW)
		var in_group := bit % (ROWS * PER_ROW)
		var row := in_group / PER_ROW
		var col := in_group % PER_ROW
		var x := col * (CELL.x + GAP) + (BLOCK_GAP if col * 2 >= PER_ROW else 0.0)
		var y := (group * ROWS + row) * (CELL.y + GAP) + group * BLOCK_GAP
		return Rect2(Vector2(x, y), CELL)

	func _bit_at(at: Vector2) -> int:
		for bit in (32 if expanded else 16):
			if _cell_rect(bit).has_point(at):
				return bit
		return -1

	func _draw() -> void:
		var font := get_theme_font("font", "Label")
		var on_color := get_theme_color("accent_color", "Editor")
		for bit in (32 if expanded else 16):
			var rect := _cell_rect(bit)
			var on := value & (1 << bit) != 0
			var fill := on_color if on else Color(1, 1, 1, 0.08)
			if bit == _hover:
				fill = fill.lightened(0.25) if on else Color(1, 1, 1, 0.18)
			draw_rect(rect, fill)
			var text := str(bit + 1)
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
			draw_string(font, rect.position + Vector2((rect.size.x - text_size.x) * 0.5, rect.size.y - 3.5), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 0, 0, 0.8) if on else Color(1, 1, 1, 0.55))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var bit := _bit_at(event.position)
			if bit != _hover:
				_hover = bit
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var bit := _bit_at(event.position)
			if bit >= 0:
				value ^= 1 << bit
				queue_redraw()
				changed.emit(value)
				accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
			_hover = -1
			queue_redraw()

	func _get_tooltip(at: Vector2) -> String:
		var bit := _bit_at(at)
		if bit < 0:
			return ""
		var layer_name := str(ProjectSettings.get_setting("layer_names/2d_physics/layer_%d" % (bit + 1), ""))
		return "Layer %d%s" % [bit + 1, "" if layer_name.is_empty() else ": " + layer_name]


func _init() -> void:
	name = "CollisionPanel"
	custom_minimum_size.x = 180
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	var title := Label.new()
	title.text = "Collisions"
	outer.add_child(title)

	_keys = GridContainer.new()
	_keys.columns = 2
	_keys.add_theme_constant_override("h_separation", 10)
	_keys.add_theme_constant_override("v_separation", 0)
	_keys.tooltip_text = "Works in the atlas and on the map. On the map it changes the tile you see there, everywhere it is used."
	outer.add_child(_keys)
	set_keys([["Left click", "solid"], ["Right click", "clear"]])

	_clip_row = HBoxContainer.new()
	_clip_preview = Control.new()
	_clip_preview.custom_minimum_size = Vector2(44, 44)
	_clip_preview.draw.connect(_draw_clip)
	_clip_row.add_child(_clip_preview)
	_clipboard = Label.new()
	_clipboard.text = "Nothing copied"
	_clipboard.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_clipboard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clipboard.tooltip_text = "A shape is copied with the Stamp mode's first click on a tile, Alt+click in Stamp,\nCtrl+C over a tile in the atlas, or Copy in the shape editor."
	_clipboard.mouse_filter = Control.MOUSE_FILTER_STOP
	_clipboard.add_theme_color_override("font_color", HINT_COLOR)
	_clip_row.add_child(_clipboard)
	outer.add_child(_clip_row)

	_layer_row = HBoxContainer.new()
	var layer_label := Label.new()
	layer_label.text = "Physics layer"
	layer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layer_row.add_child(layer_label)
	_layer_pick = OptionButton.new()
	_layer_pick.tooltip_text = "The TileSet physics layer the marks go to."
	_layer_pick.item_selected.connect(func(i: int):
		physics_layer_picked.emit(_layer_pick.get_item_id(i)))
	_layer_row.add_child(_layer_pick)
	outer.add_child(_layer_row)

	_all_layers = CheckBox.new()
	_all_layers.text = "Show every layer"
	_all_layers.tooltip_text = "Draw the shapes of every physics layer on the map, each in its colour,\nthe one being edited stronger. Rest the mouse on the map to list what is under it."
	_all_layers.toggled.connect(func(on: bool): all_layers_toggled.emit(on))
	outer.add_child(_all_layers)

	_no_layer = Label.new()
	_no_layer.text = "No physics layer yet; the first mark adds one."
	_no_layer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_layer.add_theme_color_override("font_color", HINT_COLOR)
	outer.add_child(_no_layer)

	var alt_row := HBoxContainer.new()
	var alt_label := Label.new()
	alt_label.text = "Apply to"
	alt_row.add_child(alt_label)
	var alt_pick := OptionButton.new()
	alt_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alt_pick.fit_to_longest_item = false
	for i in Collisions.ALT_SCOPE_NAMES.size():
		alt_pick.add_item(Collisions.ALT_SCOPE_NAMES[i], i)
	alt_pick.tooltip_text = Collisions.ALT_SCOPE_HINT
	alt_pick.item_selected.connect(func(i: int): Collisions.set_alt_scope(i))
	alt_row.add_child(alt_pick)
	outer.add_child(alt_row)
	_alt_pick = alt_pick

	_bits_box = VBoxContainer.new()
	_bits_box.add_theme_constant_override("separation", 4)
	outer.add_child(_bits_box)
	_layer_bits = _add_bits("Collision layer", "The layers these tiles are on: what finds them.")
	_mask_bits = _add_bits("Collision mask", "The layers these tiles look at.")


func setup(ts: TileSet, index: int) -> void:
	_tileset = ts
	_index = index
	_alt_pick.select(Collisions.alt_scope())
	_all_layers.set_pressed_no_signal(Collisions.show_all_layers())
	_all_layers.visible = ts != null and ts.get_physics_layers_count() > 1
	var count := ts.get_physics_layers_count() if ts != null else 0
	_layer_pick.clear()
	for i in count:
		_layer_pick.add_item("%d" % i, i)
		_layer_pick.set_item_icon(i, _swatch(Collisions.layer_color(i)))
	if count > 0:
		_layer_pick.select(clampi(index, 0, count - 1))
	_layer_row.visible = count > 1
	_no_layer.visible = count == 0
	_bits_box.visible = count > 0
	if count > 0:
		_layer_bits.value = ts.get_physics_layer_collision_layer(_index)
		_mask_bits.value = ts.get_physics_layer_collision_mask(_index)
		for grid: BitGrid in [_layer_bits, _mask_bits]:
			if grid.value >> 16 != 0:
				_more_buttons[grid].button_pressed = true
		_layer_bits.queue_redraw()
		_mask_bits.queue_redraw()


func _add_bits(heading: String, hint: String) -> BitGrid:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = heading
	label.tooltip_text = hint
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var more := Button.new()
	more.flat = true
	more.toggle_mode = true
	more.focus_mode = Control.FOCUS_NONE
	more.tooltip_text = "Show layers 17 to 32"
	more.icon = EditorInterface.get_base_control().get_theme_icon("GuiTreeArrowRight", "EditorIcons")
	row.add_child(more)
	_bits_box.add_child(row)
	var grid := BitGrid.new()
	grid.tooltip_text = hint
	grid.changed.connect(func(_v: int): _emit_bits())
	_bits_box.add_child(grid)
	_more_buttons[grid] = more
	more.toggled.connect(func(on: bool):
		grid.expanded = on
		more.icon = EditorInterface.get_base_control().get_theme_icon("GuiTreeArrowDown" if on else "GuiTreeArrowRight", "EditorIcons"))
	return grid


func _emit_bits() -> void:
	if _tileset == null:
		return
	bits_changed.emit(_index, _layer_bits.value, _mask_bits.value)


static func _swatch(color: Color) -> Texture2D:
	var img := Image.create_empty(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## What a click does in the current mode: [[gesture, action], ...].
func set_keys(pairs: Array) -> void:
	for child in _keys.get_children():
		_keys.remove_child(child)
		child.queue_free()
	for pair: Array in pairs:
		for i in 2:
			var cell := Label.new()
			cell.text = pair[i]
			cell.mouse_filter = Control.MOUSE_FILTER_PASS
			cell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if i == 1 else TextServer.AUTOWRAP_OFF
			if i == 1:
				cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_theme_color_override("font_color", HINT_COLOR if i == 0 else Color.WHITE)
			_keys.add_child(cell)


## The copied shape ({} for none) and its description; shown only where it matters.
func show_clipboard(text: String, copied := {}, visible_here := true) -> void:
	_clipboard.text = text
	_clip = copied
	_clip_row.visible = visible_here
	_clip_preview.visible = not copied.is_empty()
	_clip_preview.queue_redraw()


func _draw_clip() -> void:
	if _clip.is_empty():
		return
	var block := Vector2(_clip.cells) * Vector2(_clip.region)
	var box := _clip_preview.size
	var zoom := minf(box.x / block.x, box.y / block.y)
	var at := (box - block * zoom) * 0.5
	_clip_preview.draw_rect(Rect2(at, block * zoom), Color(0.12, 0.12, 0.14))
	_clip_preview.draw_rect(Rect2(at, block * zoom), Color(1, 1, 1, 0.3), false, 1.0)
	var tint := Collisions.overlay_color()
	for kind in ["normal", "one_way"]:
		for polygon: PackedVector2Array in _clip[kind]:
			var shown := PackedVector2Array()
			for p in polygon:
				shown.append(at + p * zoom)
			if Geometry2D.triangulate_polygon(shown).size() > 0:
				_clip_preview.draw_colored_polygon(shown, Color(1.0, 0.75, 0.2, 0.7) if kind == "one_way" else Color(tint, 0.8))
