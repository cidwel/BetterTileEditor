@tool
extends Window
## Collision shape of one tile or a group: detected from the sprite, then edited by hand.

signal apply_requested(source_id: int, layer: int, per_tile: Dictionary)
signal physics_layer_changed(index: int)
signal physics_layer_add_requested
signal clipboard_changed

const Shapes := preload("res://addons/better-tile-editor/editor/CollisionShapes.gd")
const Collisions := preload("res://addons/better-tile-editor/editor/Collisions.gd")
const HINT_COLOR := Color(0.7, 0.75, 0.85)
const ONE_WAY_COLOR := Color(1.0, 0.75, 0.2)
const SETTINGS_KEY := "editors/better_terrain/collision_shape_settings"

var tile_set: TileSet
var source_id := -1
var origin := Vector2i.ZERO
var cells := Vector2i.ONE
var physics_layer := 0

var _src: TileSetAtlasSource
var _lay := {}
var _image: Image
var _polygons: Array = []
## One flag per shape in _polygons: one-way shapes only stop bodies coming from above.
var _one_way: Array = []
var _margin := 1.0
## Shapes on the tile set's other physics layers, drawn faint for reference: [[layer, polygons]].
var _others: Array = []
var _history: Array = []
var _future: Array = []
var _dirty := false
## The last auto mode, re-run when a setting moves until the shape is edited by hand.
var _last_auto := -1
var _settings := Shapes.DEFAULTS.duplicate()
## Live symmetry: only the left and/or top part is edited, the rest is its mirror image.
var _sym_h := false
var _sym_v := false

var _canvas: ShapeCanvas
var _per_tile: CheckBox
var _base_row: Control
var _nav: HBoxContainer
var _info: Label
var _info_base := ""
var _sliders := {}
## Each slider's value label, to update when a value is set without a signal.
var _slider_text := {}
var _layer_pick: OptionButton
var _show_others: CheckBox
var _one_way_check: CheckBox
var _margin_slider: HSlider
var _margin_label: Label


## The block drawn big, with its polygons; points dragged, added and removed by hand.
class ShapeCanvas extends Control:
	signal edited
	signal about_to_edit

	var editor
	var zoom := 1.0
	var offset := Vector2.ZERO
	var snap := true
	var selected := -1:
		set(value):
			selected = value
			if editor != null:
				editor._sync_selection()
	var _draft := PackedVector2Array()
	var _drag := {}
	var _hover := {}
	var _mouse := Vector2.ZERO
	var _panning := false
	## Zoomed or panned by hand: a resize then leaves the view alone.
	var _moved := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		clip_contents = true
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tooltip_text = "Wheel to zoom, middle drag to move, middle double-click to fit"
		resized.connect(func() -> void:
			if not _moved:
				fit())

	func fit() -> void:
		_moved = false
		if editor == null or editor._lay.is_empty():
			return
		var px: Vector2 = editor._lay.size
		var room := size - Vector2(32, 32)
		zoom = maxf(0.25, minf(room.x / px.x, room.y / px.y))
		if zoom >= 1.0:
			zoom = floorf(zoom)
		offset = ((size - px * zoom) * 0.5).round()
		queue_redraw()

	func to_block(at: Vector2) -> Vector2:
		var p := (at - offset) / zoom
		return editor._clamp(p.round() if snap else p, 8.0 / zoom)

	func to_screen(p: Vector2) -> Vector2:
		return offset + p * zoom

	func _draw() -> void:
		if editor == null or editor._lay.is_empty():
			return
		var px: Vector2 = editor._lay.size
		draw_rect(Rect2(offset, px * zoom), Color(0.12, 0.12, 0.14))
		var src: TileSetAtlasSource = editor._src
		for t: Dictionary in editor._lay.tiles:
			var rect := Rect2(to_screen(t.rect.position), t.rect.size * zoom)
			if src.texture != null:
				draw_texture_rect_region(src.texture, rect, src.get_tile_texture_region(t.coords))
			draw_rect(rect, Color(1, 1, 1, 0.25), false, 1.0)
		var tint := Collisions.overlay_color()
		var mirrored: bool = editor._sym_h or editor._sym_v
		if editor._show_others.button_pressed:
			for other: Array in editor._others:
				var hue: Color = Collisions.layer_color(other[0])
				for polygon: PackedVector2Array in other[1]:
					var faint := _screen(polygon)
					if Geometry2D.triangulate_polygon(faint).size() > 0:
						draw_colored_polygon(faint, Color(hue, 0.18))
					_outline(faint, Color(hue, 0.7), 1.0, true)
		# Under live symmetry the whole shape is drawn joined, as it will be applied.
		var shapes: Array = []
		var flags: Array = []
		if mirrored:
			var groups: Array = editor._result_groups()
			shapes = groups[0] + groups[1]
			for i in shapes.size():
				flags.append(i >= groups[0].size())
		else:
			shapes = editor._polygons
			flags = editor._one_way
		for i in shapes.size():
			var shown := _screen(shapes[i])
			var picked := not mirrored and i == selected
			var fill: Color = Color(ONE_WAY_COLOR, tint.a) if flags[i] else tint
			if Geometry2D.triangulate_polygon(shown).size() > 0:
				draw_colored_polygon(shown, Color(fill, fill.a * (1.3 if picked else 1.0)))
			var edge := ONE_WAY_COLOR if flags[i] else Color(1, 0.55, 0.5)
			_outline(shown, Color.WHITE if picked else edge, 2.0 if picked else 1.5, flags[i])
		if mirrored:
			var area := Rect2(offset, px * zoom)
			var editable_area: Rect2 = editor._editable()
			var free_screen := Rect2(to_screen(editable_area.position), editable_area.size * zoom)
			if editor._sym_h:
				draw_rect(Rect2(free_screen.end.x, area.position.y, area.end.x - free_screen.end.x, area.size.y), Color(0, 0, 0, 0.55))
			if editor._sym_v:
				draw_rect(Rect2(area.position.x, free_screen.end.y, free_screen.size.x, area.end.y - free_screen.end.y), Color(0, 0, 0, 0.55))
			# Dashed and faint, so it does not read as a cut through the shape.
			var axis := Color(EditorInterface.get_editor_theme().get_color("accent_color", "Editor"), 0.7)
			if editor._sym_h:
				draw_dashed_line(Vector2(free_screen.end.x, area.position.y), Vector2(free_screen.end.x, area.end.y), axis, 1.0, 5.0)
			if editor._sym_v:
				draw_dashed_line(Vector2(area.position.x, free_screen.end.y), Vector2(area.end.x, free_screen.end.y), axis, 1.0, 5.0)
		var accent := EditorInterface.get_editor_theme().get_color("accent_color", "Editor")
		for i in editor._polygons.size():
			var shown := _screen(editor._polygons[i])
			for j in shown.size():
				var hot: bool = _hover.get("polygon", -1) == i and _hover.get("point", -1) == j
				var box := Rect2(shown[j] - Vector2(4, 4), Vector2(8, 8))
				draw_rect(box, Color(1, 0.9, 0.3) if hot else (accent if mirrored and i == selected else Color.WHITE))
				draw_rect(box, Color.BLACK, false, 1.0)
		if _hover.has("edge") and not drafting():
			var e: Dictionary = _hover.edge
			draw_circle(to_screen(e.at), 4.0, Color(0.5, 1, 0.6))
		if drafting():
			var points := _draft.duplicate()
			points.append(to_block(_mouse))
			var copies := [points]
			if editor._sym_h:
				copies.append_array(editor.Shapes.reflect(copies, editor._lay.size, true))
			if editor._sym_v:
				copies.append_array(editor.Shapes.reflect(copies, editor._lay.size, false))
			for i in copies.size():
				var line := PackedVector2Array()
				for p in copies[i]:
					line.append(to_screen(p))
				draw_polyline(line, Color(0.5, 1, 0.6, 1.0 if i == 0 else 0.4), 2.0)
			for p in _draft:
				draw_rect(Rect2(to_screen(p) - Vector2(3, 3), Vector2(6, 6)), Color(0.5, 1, 0.6))
			if _draft.size() >= 3:
				draw_arc(to_screen(_draft[0]), 8.0, 0.0, TAU, 16, Color(0.5, 1, 0.6), 1.5)

	func _screen(polygon: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in polygon:
			out.append(to_screen(p))
		return out

	func _outline(shown: PackedVector2Array, color: Color, width: float, dashed := false) -> void:
		if shown.is_empty():
			return
		if dashed:
			for i in shown.size():
				draw_dashed_line(shown[i], shown[(i + 1) % shown.size()], color, width, 4.0)
			return
		var loop := shown.duplicate()
		loop.append(shown[0])
		draw_polyline(loop, color, width)

	func _find(at: Vector2) -> Dictionary:
		var polygons: Array = editor._polygons
		for i in range(polygons.size() - 1, -1, -1):
			var polygon: PackedVector2Array = polygons[i]
			for j in polygon.size():
				if to_screen(polygon[j]).distance_to(at) <= 7.0:
					return {polygon = i, point = j}
		for i in range(polygons.size() - 1, -1, -1):
			var polygon: PackedVector2Array = polygons[i]
			for j in polygon.size():
				var a := to_screen(polygon[j])
				var b := to_screen(polygon[(j + 1) % polygon.size()])
				var near := Geometry2D.get_closest_point_to_segment(at, a, b)
				if near.distance_to(at) <= 6.0:
					var p := (near - offset) / zoom
					return {edge = {polygon = i, after = j, at = p.round() if snap else p}}
		var p := (at - offset) / zoom
		for i in range(polygons.size() - 1, -1, -1):
			if Geometry2D.is_point_in_polygon(p, polygons[i]):
				return {inside = i}
		return {}

	# Whole steps from 1x up keep pixel art sharp; below that, quarter steps.
	func _zoom_at(at: Vector2, zoom_in: bool) -> void:
		var next := zoom
		if zoom_in:
			next = zoom + 1.0 if zoom >= 1.0 else minf(1.0, zoom + 0.25)
		else:
			next = zoom - 1.0 if zoom > 1.0 else maxf(0.25, zoom - 0.25)
		next = minf(next, 64.0)
		offset = (at - (at - offset) * (next / zoom)).round()
		zoom = next
		_moved = true
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_at(event.position, event.button_index == MOUSE_BUTTON_WHEEL_UP)
			accept_event()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed and event.double_click:
				fit()
			_panning = event.pressed
			mouse_default_cursor_shape = Control.CURSOR_DRAG if _panning else Control.CURSOR_ARROW
			accept_event()
			return
		if event is InputEventMouseMotion and _panning:
			offset += event.relative
			_moved = true
			queue_redraw()
			accept_event()
			return
		if event is InputEventMouseMotion:
			_mouse = event.position
			if not _drag.is_empty():
				_drag_to(event.position)
				accept_event()
			else:
				_hover = _find(event.position)
			queue_redraw()
			return
		if not (event is InputEventMouseButton) or not event.pressed:
			if event is InputEventMouseButton and not event.pressed and not _drag.is_empty():
				_drag = {}
				edited.emit()
			return
		grab_focus()
		var hit := _find(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if drafting():
				_add_draft_point(event.position, event.double_click)
			elif hit.has("point"):
				about_to_edit.emit()
				selected = hit.polygon
				_drag = {polygon = hit.polygon, point = hit.point}
			elif hit.has("edge"):
				about_to_edit.emit()
				var e: Dictionary = hit.edge
				var polygon: PackedVector2Array = editor._polygons[e.polygon]
				polygon.insert(e.after + 1, e.at)
				editor._polygons[e.polygon] = polygon
				selected = e.polygon
				_drag = {polygon = e.polygon, point = e.after + 1}
			elif hit.has("inside"):
				about_to_edit.emit()
				selected = hit.inside
				_drag = {polygon = hit.inside, move_from = to_block(event.position),
					original = (editor._polygons[hit.inside] as PackedVector2Array).duplicate()}
			else:
				selected = -1
				_add_draft_point(event.position, false)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if drafting():
				_draft.remove_at(_draft.size() - 1)
			elif hit.has("point"):
				about_to_edit.emit()
				var polygon: PackedVector2Array = editor._polygons[hit.polygon]
				polygon.remove_at(hit.point)
				if polygon.size() < 3:
					editor._remove_shape(hit.polygon)
					selected = -1
				else:
					editor._polygons[hit.polygon] = polygon
				edited.emit()
			accept_event()
		_hover = _find(event.position)
		queue_redraw()

	func _drag_to(at: Vector2) -> void:
		var p := to_block(at)
		var polygon: PackedVector2Array = editor._polygons[_drag.polygon]
		if _drag.has("point"):
			polygon[_drag.point] = p
		else:
			var delta: Vector2 = p - _drag.move_from
			var original: PackedVector2Array = _drag.original
			for i in polygon.size():
				polygon[i] = editor._clamp(original[i] + delta)
		editor._polygons[_drag.polygon] = polygon

	func _add_draft_point(at: Vector2, closing: bool) -> void:
		var p := to_block(at)
		if _draft.size() >= 3 and (closing or to_screen(_draft[0]).distance_to(at) <= 8.0):
			finish_draft()
			return
		_draft.append(p)

	func finish_draft() -> void:
		if _draft.size() >= 3:
			about_to_edit.emit()
			editor._add_shape(_draft.duplicate(), false)
			selected = editor._polygons.size() - 1
			edited.emit()
		_draft.clear()
		queue_redraw()

	func drafting() -> bool:
		return not _draft.is_empty()

	func cancel_draft() -> void:
		_draft.clear()
		queue_redraw()


func _editable() -> Rect2:
	return Shapes.editable_rect(_lay.size, _sym_h, _sym_v)


## Keeps points inside the part being edited under live symmetry. Points near an axis
## land on it, so the shape and its mirror image touch and join into one.
func _clamp(p: Vector2, stick := 0.0) -> Vector2:
	if not (_sym_h or _sym_v):
		return p
	var editable_area := _editable()
	p = p.clamp(editable_area.position, editable_area.end)
	if _sym_h and editable_area.end.x - p.x <= stick:
		p.x = editable_area.end.x
	if _sym_v and editable_area.end.y - p.y <= stick:
		p.y = editable_area.end.y
	return p


## The shapes with the given one-way flag.
func _group(one_way: bool) -> Array:
	var out := []
	for i in _polygons.size():
		if _one_way[i] == one_way:
			out.append(_polygons[i])
	return out


func _set_groups(normal: Array, one_way: Array) -> void:
	_polygons = normal + one_way
	_one_way = []
	for i in _polygons.size():
		_one_way.append(i >= normal.size())


func _add_shape(polygon: PackedVector2Array, one_way: bool) -> void:
	_polygons.append(polygon)
	_one_way.append(one_way)


func _remove_shape(index: int) -> void:
	_polygons.remove_at(index)
	_one_way.remove_at(index)


## The whole shape, what is edited plus its mirror images: [normal, one-way]. The two
## kinds are joined separately, as a one-way shape can't merge with a solid one.
func _result_groups() -> Array:
	return [Shapes.symmetric(_group(false), _lay.size, _sym_h, _sym_v),
		Shapes.symmetric(_group(true), _lay.size, _sym_h, _sym_v)]


func _result() -> Array:
	var groups := _result_groups()
	return groups[0] + groups[1]


## A whole shape as the part to edit: the editable part of it under live symmetry.
func _editable_part(full: Array) -> Array:
	return Shapes.clip(full, _editable()) if _sym_h or _sym_v else full


func _set_symmetry(horizontal: bool, vertical: bool) -> void:
	_remember()
	var full := _result_groups()
	_sym_h = horizontal
	_sym_v = vertical
	_set_groups(_editable_part(full[0]), _editable_part(full[1]))
	_canvas.selected = -1
	_canvas.cancel_draft()
	_changed()


func setup(ts: TileSet, source: int, from: Vector2i, size_cells: Vector2i, layer: int) -> void:
	tile_set = ts
	physics_layer = layer
	var saved = EditorInterface.get_editor_settings().get_setting(SETTINGS_KEY) \
		if EditorInterface.get_editor_settings().has_setting(SETTINGS_KEY) else {}
	if saved is Dictionary:
		for key in saved:
			# Each tile on its own is a choice per block, not remembered.
			if _settings.has(key) and key != "per_tile":
				_settings[key] = saved[key]
	_build()
	load_block(source, from, size_cells)


func load_block(source: int, from: Vector2i, size_cells: Vector2i) -> void:
	source_id = source
	origin = from
	cells = size_cells
	_src = tile_set.get_source(source) as TileSetAtlasSource
	_lay = Shapes.layout(_src, origin, cells)
	_image = Shapes.block_image(_src, _lay)
	var found := Shapes.gather(_src, tile_set, _lay, physics_layer)
	_set_groups(_editable_part(found.normal), _editable_part(found.one_way))
	_margin = found.margin
	_show_margin()
	_others.clear()
	for i in tile_set.get_physics_layers_count():
		if i != physics_layer:
			var other := Shapes.gather(_src, tile_set, _lay, i)
			_others.append([i, other.normal + other.one_way])
	_refresh_layer_pick()
	_history.clear()
	_future.clear()
	_last_auto = -1
	_set_dirty(false)
	_settings.per_tile = false
	_per_tile.set_pressed_no_signal(false)
	_per_tile.visible = _lay.tiles.size() > 1
	_nav.visible = _lay.tiles.size() == 1
	var names := "tile %s" % str(origin) if _lay.tiles.size() == 1 \
		else "%d tiles from %s" % [_lay.tiles.size(), str(origin)]
	_info_base = "%s · %d×%d px" % [names, int(_lay.size.x), int(_lay.size.y)]
	_update_info()
	(_sliders.base as Range).max_value = maxf(1.0, _lay.size.y)
	if bool(_settings.get("rim_auto", true)):
		_settings.rim = maxf(1.0, floorf(_lay.region.x / 16.0))
		(_sliders.rim as Range).set_value_no_signal(_settings.rim)
		_slider_text.rim.call(_settings.rim)
	_canvas.selected = -1
	_canvas.fit()


func _build() -> void:
	title = "Collision shape"
	size = Vector2i(980, 640)
	min_size = Vector2i(720, 460)
	wrap_controls = false
	close_requested.connect(_on_cancel)
	window_input.connect(_on_window_input)
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	var info_row := HBoxContainer.new()
	left.add_child(info_row)
	_info = Label.new()
	_info.add_theme_color_override("font_color", HINT_COLOR)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(_info)
	var fit := Button.new()
	fit.icon = EditorInterface.get_editor_theme().get_icon("ZoomReset", "EditorIcons")
	fit.flat = true
	fit.tooltip_text = "Fit the tiles in view (or middle double-click)"
	info_row.add_child(fit)
	_canvas = ShapeCanvas.new()
	fit.pressed.connect(_canvas.fit)
	_canvas.editor = self
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.about_to_edit.connect(_remember)
	_canvas.edited.connect(func():
		_last_auto = -1
		_changed())
	left.add_child(_canvas)
	var hint := Label.new()
	hint.text = "Click empty space to draw a shape, then click its first point, double click or Enter to close it · drag points or shapes · click an edge to add a point · right click removes one"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", HINT_COLOR)
	left.add_child(hint)

	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 270
	root.add_child(column)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 6)
	scroll.add_child(side)

	side.add_child(_heading("Physics layer"))
	var layer_row := HBoxContainer.new()
	side.add_child(layer_row)
	_layer_pick = OptionButton.new()
	_layer_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layer_pick.tooltip_text = "The TileSet physics layer these shapes are on. Each layer has its own\nshapes per tile, and its own collision layer and mask."
	_layer_pick.item_selected.connect(func(i: int): show_physics_layer(_layer_pick.get_item_id(i)))
	layer_row.add_child(_layer_pick)
	var add_layer := Button.new()
	add_layer.icon = EditorInterface.get_editor_theme().get_icon("Add", "EditorIcons")
	add_layer.tooltip_text = "Add a physics layer to the tile set."
	add_layer.pressed.connect(func(): physics_layer_add_requested.emit())
	layer_row.add_child(add_layer)
	_show_others = CheckBox.new()
	_show_others.text = "Show the other layers"
	_show_others.tooltip_text = "Draw the shapes the tiles have on the other physics layers, faint, in their colours."
	_show_others.button_pressed = true
	_show_others.toggled.connect(func(_on: bool): _canvas.queue_redraw())
	side.add_child(_show_others)

	side.add_child(HSeparator.new())
	side.add_child(_heading("Detect from the sprite"))
	var auto_row := HBoxContainer.new()
	side.add_child(auto_row)
	for entry in [[Shapes.Auto.CONTOUR, "ShapeContour", "Contour\nFollows the painted pixels."],
			[Shapes.Auto.CONVEX, "ShapeConvex", "Convex\nOne shape with no dents around everything painted."],
			[Shapes.Auto.BOX, "ShapeBox", "Box\nThe rectangle around the painted pixels."],
			[Shapes.Auto.BASE_BOX, "ShapeBaseBox", "Basic base\nA rectangle at the bottom of the drawing, as wide as what is painted there:\nfor things you walk behind."],
			[Shapes.Auto.BASE, "ShapeBase", "Precise base\nThe bottom of the drawing, following its outline."],
			[Shapes.Auto.RIM, "ShapeRim", "Border\nA band along the inside of the outline, as wide as Border width in Advanced:\nfor shapes you walk inside of."]]:
		auto_row.add_child(_icon_button(entry[1], entry[2], _auto.bind(entry[0])))
	_per_tile = CheckBox.new()
	_per_tile.text = "Each tile on its own"
	_per_tile.tooltip_text = "Detect every tile of the group separately instead of the whole drawing."
	_per_tile.button_pressed = bool(_settings.per_tile)
	_per_tile.toggled.connect(func(on: bool): _set_setting("per_tile", on))
	side.add_child(_per_tile)
	var advanced_toggle := Button.new()
	advanced_toggle.text = "Advanced"
	advanced_toggle.flat = true
	advanced_toggle.toggle_mode = true
	advanced_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	advanced_toggle.icon = EditorInterface.get_editor_theme().get_icon("GuiTreeArrowRight", "EditorIcons")
	side.add_child(advanced_toggle)
	var advanced := VBoxContainer.new()
	advanced.add_theme_constant_override("separation", 6)
	advanced.hide()
	side.add_child(advanced)
	advanced_toggle.toggled.connect(func(on: bool):
		advanced.visible = on
		advanced_toggle.icon = EditorInterface.get_editor_theme().get_icon("GuiTreeArrowDown" if on else "GuiTreeArrowRight", "EditorIcons"))
	_add_slider(advanced, "smoothness", "Smoothness", 0.0, 8.0, 0.25, "px", "Higher follows the outline more loosely, with fewer points.")
	_add_slider(advanced, "alpha", "Alpha threshold", 0.01, 1.0, 0.01, "", "A pixel counts as painted above this opacity.")
	_add_slider(advanced, "specks", "Ignore specks under", 0.0, 64.0, 1.0, "px²", "Painted bits smaller than this are left out.")
	_add_slider(advanced, "grow", "Grow", -8.0, 8.0, 0.5, "px", "Push the outline out, or pull it in with a negative value.")
	_base_row = _add_slider(advanced, "base", "Base height", 1.0, 64.0, 1.0, "px", "How tall the base is, from the bottom of the drawing.")
	_add_slider(advanced, "rim", "Border width", 1.0, 32.0, 1.0, "px", "How deep the Border band goes in from the outline.")

	side.add_child(HSeparator.new())
	side.add_child(_heading("Symmetry"))
	var live := HBoxContainer.new()
	side.add_child(live)
	var sym_h := CheckBox.new()
	sym_h.text = "Left ↔ right"
	sym_h.tooltip_text = "Edit the left half only; the right half mirrors it as you go."
	live.add_child(sym_h)
	var sym_v := CheckBox.new()
	sym_v.text = "Top ↔ bottom"
	sym_v.tooltip_text = "Edit the top half only; the bottom half mirrors it as you go."
	live.add_child(sym_v)
	sym_h.toggled.connect(func(on: bool): _set_symmetry(on, _sym_v))
	sym_v.toggled.connect(func(on: bool): _set_symmetry(_sym_h, on))
	var once := Label.new()
	once.text = "Copy one half over the other:"
	once.add_theme_color_override("font_color", HINT_COLOR)
	side.add_child(once)
	var mirror_row := HBoxContainer.new()
	side.add_child(mirror_row)
	for entry in [[Shapes.Mirror.LEFT_TO_RIGHT, "MirrorLeftRight", "Left → right"],
			[Shapes.Mirror.RIGHT_TO_LEFT, "MirrorRightLeft", "Right → left"],
			[Shapes.Mirror.TOP_TO_BOTTOM, "MirrorTopBottom", "Top → bottom"],
			[Shapes.Mirror.BOTTOM_TO_TOP, "MirrorBottomTop", "Bottom → top"]]:
		mirror_row.add_child(_icon_button(entry[1], "%s\nCopy this half of the shape over the other, mirrored." % entry[2], _mirror.bind(entry[0])))

	side.add_child(HSeparator.new())
	side.add_child(_heading("Edit"))
	var edit_row := HBoxContainer.new()
	side.add_child(edit_row)
	var remove := Button.new()
	remove.text = "Delete shape"
	remove.tooltip_text = "Delete the selected shape (Delete key)."
	remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove.pressed.connect(_delete_selected)
	edit_row.add_child(remove)
	var clear := Button.new()
	clear.text = "Clear all"
	clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear.pressed.connect(func():
		_remember()
		_set_groups([], [])
		_canvas.selected = -1
		_last_auto = -1
		_changed())
	edit_row.add_child(clear)
	_one_way_check = CheckBox.new()
	_one_way_check.text = "One-way (selected shape)"
	_one_way_check.tooltip_text = "Bodies pass through it from below and land on top of it, like a platform.\nDrawn dashed, in amber."
	_one_way_check.disabled = true
	_one_way_check.toggled.connect(_set_selected_one_way)
	side.add_child(_one_way_check)
	var margin_box := VBoxContainer.new()
	margin_box.add_theme_constant_override("separation", 0)
	var margin_row := HBoxContainer.new()
	var margin_label := Label.new()
	margin_label.text = "One-way margin"
	margin_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_row.add_child(margin_label)
	_margin_label = Label.new()
	margin_row.add_child(_margin_label)
	margin_box.add_child(margin_row)
	_margin_slider = HSlider.new()
	_margin_slider.min_value = 0.0
	_margin_slider.max_value = 16.0
	_margin_slider.step = 0.5
	_margin_slider.value = _margin
	_margin_slider.tooltip_text = "How deep a body may sink into a one-way shape and still land on it."
	_show_margin()
	_margin_slider.value_changed.connect(func(v: float):
		_margin_label.text = "%s px" % str(v)
		if not is_equal_approx(v, _margin):
			_remember()
			_margin = v
			_changed())
	margin_box.add_child(_margin_slider)
	side.add_child(margin_box)
	var alt_row := HBoxContainer.new()
	var alt_label := Label.new()
	alt_label.text = "Apply to"
	alt_row.add_child(alt_label)
	var alt_pick := OptionButton.new()
	alt_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in Collisions.ALT_SCOPE_NAMES.size():
		alt_pick.add_item(Collisions.ALT_SCOPE_NAMES[i], i)
	alt_pick.select(Collisions.alt_scope())
	alt_pick.tooltip_text = Collisions.ALT_SCOPE_HINT
	alt_pick.item_selected.connect(func(i: int): Collisions.set_alt_scope(i))
	alt_row.add_child(alt_pick)
	side.add_child(alt_row)
	var clip_row := HBoxContainer.new()
	side.add_child(clip_row)
	var copy := Button.new()
	copy.text = "Copy shape"
	copy.icon = EditorInterface.get_editor_theme().get_icon("ActionCopy", "EditorIcons")
	copy.tooltip_text = "Copy the whole shape, to paste on other tiles: here, with Ctrl+V over a tile\nin the atlas, or with the Stamp mode."
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.pressed.connect(_copy)
	clip_row.add_child(copy)
	var paste := Button.new()
	paste.text = "Paste shape"
	paste.icon = EditorInterface.get_editor_theme().get_icon("ActionPaste", "EditorIcons")
	paste.tooltip_text = "Replace the shape with the copied one, fitted to these tiles."
	paste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paste.pressed.connect(_paste)
	clip_row.add_child(paste)
	var snap := CheckBox.new()
	snap.text = "Snap to pixels"
	snap.button_pressed = true
	snap.toggled.connect(func(on: bool): _canvas.snap = on)
	side.add_child(snap)

	column.add_child(HSeparator.new())
	_nav = HBoxContainer.new()
	var prev := Button.new()
	prev.text = "◀ Previous"
	prev.tooltip_text = "Apply and edit the previous tile of the atlas."
	prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev.pressed.connect(_step.bind(-1))
	_nav.add_child(prev)
	var next := Button.new()
	next.text = "Next ▶"
	next.tooltip_text = "Apply and edit the next tile of the atlas."
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next.pressed.connect(_step.bind(1))
	_nav.add_child(next)
	column.add_child(_nav)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	for pair in [["Apply", _apply], ["OK", _on_ok], ["Cancel", _on_cancel]]:
		var b := Button.new()
		b.text = pair[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(pair[1])
		buttons.add_child(b)


func _icon_button(icon_name: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.icon = load("res://addons/better-tile-editor/icons/%s.svg" % icon_name)
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(36, 30)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(action)
	return b


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", EditorInterface.get_editor_theme().get_color("accent_color", "Editor"))
	return label


func _add_slider(parent: Control, key: String, text: String, lo: float, hi: float, step: float, suffix: String, hint: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.tooltip_text = hint
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := Label.new()
	row.add_child(value)
	box.add_child(row)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = float(_settings[key])
	slider.tooltip_text = hint
	var display := func(v: float): value.text = ("%s %s" % [str(snappedf(v, step)), suffix]).strip_edges()
	display.call(slider.value)
	_slider_text[key] = display
	slider.value_changed.connect(func(v: float):
		display.call(v)
		_set_setting(key, v))
	box.add_child(slider)
	parent.add_child(box)
	_sliders[key] = slider
	return box


func _set_setting(key: String, value) -> void:
	_settings[key] = value
	if key == "rim":
		_settings.rim_auto = false
	EditorInterface.get_editor_settings().set_setting(SETTINGS_KEY, _settings.duplicate())
	if _last_auto >= 0:
		_set_groups(_editable_part(Shapes.detect(_image, _lay, _last_auto, _settings)), [])
		_changed()


func _auto(mode: int) -> void:
	_remember()
	_last_auto = mode
	_set_groups(_editable_part(Shapes.detect(_image, _lay, mode, _settings)), [])
	_canvas.selected = -1
	_changed()


func _mirror(how: int) -> void:
	_remember()
	_last_auto = -1
	var full := _result_groups()
	_set_groups(_editable_part(Shapes.mirror(full[0], _lay.size, how)), _editable_part(Shapes.mirror(full[1], _lay.size, how)))
	_canvas.selected = -1
	_changed()


func _delete_selected() -> void:
	if _canvas.selected < 0 or _canvas.selected >= _polygons.size():
		return
	_remember()
	_remove_shape(_canvas.selected)
	_canvas.selected = -1
	_last_auto = -1
	_changed()


func _changed() -> void:
	_set_dirty(true)
	_update_info()
	_canvas.queue_redraw()


## How many separate shapes the whole result has, so a joined one reads as "1 shape".
func _update_info() -> void:
	var count := _result().size()
	_info.text = "%s · %s" % [_info_base, "no shape" if count == 0 else "%d shape%s" % [count, "" if count == 1 else "s"]]


func _set_dirty(on: bool) -> void:
	_dirty = on
	title = "Collision shape" + (" (*)" if on else "")


func _remember() -> void:
	_history.append(_snapshot())
	_future.clear()


func _snapshot() -> Array:
	return [_polygons.map(func(p: PackedVector2Array): return p.duplicate()), _one_way.duplicate(), _margin]


func _restore(snapshot: Array) -> void:
	_polygons = snapshot[0]
	_one_way = snapshot[1]
	_margin = snapshot[2]
	_show_margin()
	_canvas.selected = -1
	_changed()


func _undo() -> void:
	if _history.is_empty():
		return
	_future.append(_snapshot())
	_restore(_history.pop_back())


func _redo() -> void:
	if _future.is_empty():
		return
	_history.append(_snapshot())
	_restore(_future.pop_back())


func _on_window_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var ctrl: bool = event.is_command_or_control_pressed()
	match event.keycode:
		KEY_Z when ctrl and event.shift_pressed:
			_redo()
		KEY_Z when ctrl:
			_undo()
		KEY_Y when ctrl:
			_redo()
		KEY_DELETE, KEY_BACKSPACE:
			_delete_selected()
		KEY_ENTER, KEY_KP_ENTER:
			_canvas.finish_draft()
		KEY_ESCAPE:
			_canvas.cancel_draft()
		_:
			return
	set_input_as_handled()


func _apply() -> void:
	var groups := _result_groups()
	var normal := Shapes.split(groups[0], _src, tile_set, _lay)
	var one_way := Shapes.split(groups[1], _src, tile_set, _lay)
	var per_tile := {}
	for coords in normal:
		per_tile[coords] = normal[coords].map(func(p): return [p, false, 1.0]) \
			+ one_way[coords].map(func(p): return [p, true, _margin])
	apply_requested.emit(source_id, physics_layer, per_tile)
	_set_dirty(false)


func _show_margin() -> void:
	_margin_slider.set_value_no_signal(_margin)
	_margin_label.text = "%s px" % str(_margin)


func _copy() -> void:
	var groups := _result_groups()
	Shapes.clipboard = Shapes.make_clip(groups[0], groups[1], _margin, _lay, cells)
	clipboard_changed.emit()


func _paste() -> void:
	if Shapes.clipboard.is_empty():
		return
	_remember()
	var groups := Shapes.fit_clip(Shapes.clipboard, _lay)
	_set_groups(_editable_part(groups[0]), _editable_part(groups[1]))
	_margin = float(Shapes.clipboard.margin)
	_show_margin()
	_last_auto = -1
	_canvas.selected = -1
	_changed()


## Keeps the one-way box in step with the selected shape.
func _sync_selection() -> void:
	if _one_way_check == null:
		return
	var index: int = _canvas.selected if _canvas != null else -1
	var has := index >= 0 and index < _polygons.size()
	_one_way_check.disabled = not has
	_one_way_check.set_pressed_no_signal(has and _one_way[index])


func _set_selected_one_way(on: bool) -> void:
	var index: int = _canvas.selected
	if index < 0 or index >= _polygons.size() or _one_way[index] == on:
		return
	_remember()
	_one_way[index] = on
	_last_auto = -1
	_changed()


func _refresh_layer_pick() -> void:
	_layer_pick.clear()
	var count := tile_set.get_physics_layers_count()
	for i in maxi(1, count):
		var label := "Layer %d" % i
		if i < count:
			label += " · on %s" % Collisions.bits_text(tile_set, i)
		else:
			label += " (new)"
		_layer_pick.add_item(label, i)
	_layer_pick.select(clampi(physics_layer, 0, _layer_pick.item_count - 1))


## Shows the shapes of another physics layer; changes made on the current one are applied first.
func show_physics_layer(index: int) -> void:
	if index == physics_layer and not _lay.is_empty():
		_refresh_layer_pick()
		return
	if _dirty:
		_apply()
	physics_layer = index
	physics_layer_changed.emit(index)
	load_block(source_id, origin, cells)


func _on_ok() -> void:
	if _dirty:
		_apply()
	queue_free()


func _on_cancel() -> void:
	queue_free()


## Applies, then opens the neighbouring tile of the atlas.
func _step(direction: int) -> void:
	if _dirty:
		_apply()
	var count := _src.get_tiles_count()
	var at := -1
	for i in count:
		if _src.get_tile_id(i) == origin:
			at = i
	if at < 0 or count < 2:
		return
	var next := _src.get_tile_id(posmod(at + direction, count))
	load_block(source_id, next, _src.get_tile_size_in_atlas(next))
