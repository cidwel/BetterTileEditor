@tool
extends PopupPanel
## Asks which layer a wand, bucket or picker click meant: rows of "layer › tile name" with the tile
## shown whole (a PopupMenu can't), the picker's with a layer's choices side by side ([method add_pick_row]).

signal id_pressed(id: int)

var _list: VBoxContainer
## id -> {row, check}
var _items := {}
var _focused := -1
## The layer name labels, widened to the longest when the menu opens.
var _layer_labels: Array[Label] = []
## The arrows after them, made as wide as each other so the tiles line up.
var _arrows: Array[Label] = []
## The picker's choice cards by column, made as wide as the widest in theirs.
var _columns: Array = []
## Smallest size a tile is shown at, before the editor scale; smaller tiles zoom by whole steps.
const TILE_MIN := 32
const TILE_MAX := 64
## Side of the pictures in the picker's cards, before the editor scale.
const CARD_TILE := 28
## Widest a card's name gets before it is cut short, before the editor scale.
const NAME_MAX := 130


func _init() -> void:
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	add_child(_list)
	popup_hide.connect(func(): _focused = -1)
	about_to_popup.connect(_line_up)


func clear() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_items.clear()
	_layer_labels.clear()
	_arrows.clear()
	_columns.clear()
	_focused = -1


func add_check_item(label: String, id: int, tip := "") -> void:
	var row := _row(id, tip)
	row.get_child(0).add_child(_label(label))


## [param tile] may be null and [param tile_name] empty when the cell has nothing to show.
func add_layer_item(layer: String, tile: Texture2D, tile_name: String, id: int) -> void:
	var line: HBoxContainer = _row(id).get_child(0)
	var name_label := _label(layer)
	_layer_labels.append(name_label)
	line.add_child(name_label)
	if tile == null and tile_name.is_empty():
		return
	var arrow := _label("›")
	arrow.modulate = Color(1, 1, 1, 0.5)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrows.append(arrow)
	line.add_child(arrow)
	if tile != null:
		var picture := TextureRect.new()
		picture.texture = tile
		picture.custom_minimum_size = _tile_size(tile.get_size())
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(picture)
	else:
		# Keeps the names in line with those of the rows that show a tile.
		var gap := Control.new()
		gap.custom_minimum_size.x = _tile_size(Vector2(TILE_MIN, TILE_MIN)).x
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(gap)
	if not tile_name.is_empty():
		line.add_child(_label(tile_name))


## A row under the one before it: [param name] with a swatch of [param color], the swatch in
## line with the tiles above.
func add_sub_item(color: Color, name: String, id: int) -> void:
	var line: HBoxContainer = _row(id).get_child(0)
	var indent := _label("")
	_layer_labels.append(indent)
	line.add_child(indent)
	var arrow := _label("↳")
	arrow.modulate = Color(1, 1, 1, 0.5)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrows.append(arrow)
	line.add_child(arrow)
	var swatch := ColorRect.new()
	swatch.color = color
	var side := _tile_size(Vector2(TILE_MIN, TILE_MIN)).x
	swatch.custom_minimum_size = Vector2(side, side * 0.6)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(swatch)
	line.add_child(_label(name))


## The picker's column headings, over the cards of [method add_pick_row].
func add_pick_header(headings: Array) -> void:
	var line := _pick_line()
	# Built like a row's layer column, with nothing shown, so the headings sit over the cards.
	var head := _layer_head("")
	head.modulate = Color(1, 1, 1, 0)
	line.add_child(head)
	for i in headings.size():
		var heading := _label(str(headings[i]))
		heading.add_theme_font_size_override("font_size", int(get_theme_font_size(&"font_size", &"Label") * 0.85))
		heading.modulate = Color(1, 1, 1, 0.45)
		# In line with the cards' pictures, past their border and margin.
		var box := MarginContainer.new()
		box.add_theme_constant_override("margin_left", int(4 * _scale()))
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(heading)
		line.add_child(box)
		while _columns.size() <= i:
			_columns.append([])
		_columns[i].append(box)


## One layer of the picker: its name, then a card per way to pick from it. Each choice is
## {id, icon, name} and may add color, a dot of the terrain's colour after the name.
func add_pick_row(layer: String, choices: Array) -> void:
	var line := _pick_line()
	line.add_child(_layer_head(layer))
	for i in choices.size():
		var card := _card(choices[i])
		line.add_child(card)
		while _columns.size() <= i:
			_columns.append([])
		_columns[i].append(card)


## The layer column of a picker row: the layer icon and [param layer], its width shared.
func _layer_head(layer: String) -> HBoxContainer:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = get_theme_icon(&"TileMapLayer", &"EditorIcons") if has_theme_icon(&"TileMapLayer", &"EditorIcons") else null
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.modulate = Color(1, 1, 1, 0.55)
	head.add_child(icon)
	var name_label := _label(layer)
	name_label.modulate = Color(1, 1, 1, 0.7)
	_layer_labels.append(name_label)
	head.add_child(name_label)
	return head


func _pick_line() -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", int(4 * _scale()))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(4 * _scale()))
	margin.add_theme_constant_override("margin_right", int(2 * _scale()))
	margin.add_theme_constant_override("margin_top", 1)
	margin.add_theme_constant_override("margin_bottom", 1)
	margin.add_child(line)
	_list.add_child(margin)
	return line


func _card(choice: Dictionary) -> PanelContainer:
	var id: int = choice.id
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var idle := _card_style(false)
	var lit := _card_style(true)
	card.add_theme_stylebox_override("panel", idle)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", int(5 * _scale()))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(line)
	line.add_child(_plate(choice.get("icon")))
	# What the card is (tile, terrain) is the column's heading; the card holds only the name.
	var title := _label(str(choice.name))
	var room := NAME_MAX * _scale()
	var natural := title.get_theme_font(&"font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		title.get_theme_font_size(&"font_size")).x
	if natural > room:
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.custom_minimum_size.x = room
		card.tooltip_text = str(choice.name)
	line.add_child(title)
	if choice.has("color"):
		var dot := ColorRect.new()
		dot.color = choice.color
		dot.custom_minimum_size = Vector2(6, 6) * _scale()
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(dot)
	card.mouse_entered.connect(func():
		_focused = id
		card.add_theme_stylebox_override("panel", lit))
	card.mouse_exited.connect(func():
		if _focused == id:
			_focused = -1
		card.add_theme_stylebox_override("panel", idle))
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			id_pressed.emit(id))
	_items[id] = {row = card, check = null}
	return card


## The picture on the editor's transparency checkerboard, so clear and dark pixels still read.
func _plate(picture: Texture2D) -> Control:
	var side := CARD_TILE * _scale()
	var size := Vector2(side, side)
	if picture != null:
		# Fitted to the card's side; a whole zoom would jump a 16 px tile to 32.
		var longest := maxf(1.0, maxf(picture.get_width(), picture.get_height()))
		size = picture.get_size() * (side / longest)
	var plate := TextureRect.new()
	plate.texture = _checker()
	plate.stretch_mode = TextureRect.STRETCH_TILE
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.custom_minimum_size = size
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if picture != null:
		var image := TextureRect.new()
		image.texture = picture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		plate.add_child(image)
	return plate


func _card_style(lit: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var accent := get_theme_color(&"accent_color", &"Editor") if has_theme_color(&"accent_color", &"Editor") \
		else Color(0.44, 0.73, 0.98)
	style.bg_color = Color(accent, 0.22) if lit else Color(1, 1, 1, 0.04)
	style.border_color = Color(accent, 0.8) if lit else Color(1, 1, 1, 0.08)
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(4 * _scale()))
	style.set_content_margin_all(3 * _scale())
	style.content_margin_right = 6 * _scale()
	return style


static var _checker_texture: Texture2D


## Two greys in 4 px squares, the usual backdrop for transparency.
static func _checker() -> Texture2D:
	if _checker_texture == null:
		var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
		for y in 8:
			for x in 8:
				image.set_pixel(x, y, Color(0.36, 0.36, 0.38) if ((x >> 2) + (y >> 2)) % 2 == 0 else Color(0.28, 0.28, 0.30))
		_checker_texture = ImageTexture.create_from_image(image)
	return _checker_texture


func _scale() -> float:
	return EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0


func add_separator() -> void:
	var line := HSeparator.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(line)


## A line of help that can't be picked.
func add_hint(text: String) -> void:
	var hint := _label(text)
	hint.modulate = Color(1, 1, 1, 0.45)
	var box := MarginContainer.new()
	box.add_theme_constant_override("margin_left", 6)
	box.add_theme_constant_override("margin_right", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hint)
	_list.add_child(box)


func set_checked(id: int, on: bool) -> void:
	if _items.has(id) and _items[id].check != null:
		_items[id].check.texture = _check_icon(on)


## The id of the row under the mouse, or -1.
func focused_id() -> int:
	return _focused


## The tile at a whole zoom that makes it at least [constant TILE_MIN] (scaled) on its long side;
## big pictures, as scene thumbnails, shrink to [constant TILE_MAX].
func _tile_size(size: Vector2) -> Vector2:
	var scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	var longest := maxf(1.0, maxf(size.x, size.y))
	if longest > TILE_MAX * scale:
		return size * (TILE_MAX * scale / longest)
	return size * maxf(1.0, ceilf(TILE_MIN * scale / longest))


func _line_up() -> void:
	var widest := 0.0
	for label in _layer_labels:
		label.custom_minimum_size.x = 0.0
		widest = maxf(widest, label.get_minimum_size().x)
	for label in _layer_labels:
		label.custom_minimum_size.x = widest
	widest = 0.0
	for arrow in _arrows:
		arrow.custom_minimum_size.x = 0.0
		widest = maxf(widest, arrow.get_minimum_size().x)
	for arrow in _arrows:
		arrow.custom_minimum_size.x = widest
	for column: Array in _columns:
		widest = 0.0
		for card: Control in column:
			card.custom_minimum_size.x = 0.0
			widest = maxf(widest, card.get_combined_minimum_size().x)
		for card: Control in column:
			card.custom_minimum_size.x = widest
	reset_size()


## The hover box with nothing drawn, so a row keeps its place when the mouse comes and goes.
func _idle_style() -> StyleBox:
	var hover := get_theme_stylebox(&"hover", &"PopupMenu")
	var idle := StyleBoxEmpty.new()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		idle.set_content_margin(side, hover.get_margin(side))
	return idle


func _row(id: int, tip := "") -> PanelContainer:
	var row := PanelContainer.new()
	row.tooltip_text = tip
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_stylebox_override("panel", _idle_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var check := TextureRect.new()
	check.texture = _check_icon(false)
	check.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(check)
	row.mouse_entered.connect(func():
		_focused = id
		row.add_theme_stylebox_override("panel", get_theme_stylebox(&"hover", &"PopupMenu")))
	row.mouse_exited.connect(func():
		if _focused == id:
			_focused = -1
		row.add_theme_stylebox_override("panel", _idle_style()))
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			id_pressed.emit(id))
	_list.add_child(row)
	_items[id] = {row = row, check = check}
	return row


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _check_icon(on: bool) -> Texture2D:
	return get_theme_icon(&"checked" if on else &"unchecked", &"PopupMenu")

