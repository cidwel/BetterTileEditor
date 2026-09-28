@tool
extends HBoxContainer

signal collapse_toggled(group_name: String, collapsed: bool)
signal terrain_dropped(terrain_id: int, group_name: String)
signal manage_requested(group_name: String)

var group_name := ""
var tileset_id := 0
## The Scenes header lists the tile set's scene tiles; terrains cannot be moved into it.
var accepts_terrains := true

var _handle: TextureRect
var _arrow: Button
var _drop_hint := false
var _pad: Control
var _visible_width := 0.0


func setup(name_of_group: String, collapsed: bool, thumbnail: Control, font_color: Color, title := "") -> void:
	group_name = name_of_group
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_constant_override("separation", 6)

	_arrow = Button.new()
	_arrow.toggle_mode = true
	_arrow.flat = true
	_arrow.focus_mode = Control.FOCUS_NONE
	_arrow.button_pressed = collapsed
	_arrow.tooltip_text = "Fold this group away. The terrains stay where they are."
	_arrow.custom_minimum_size = Vector2(18, 0)
	_arrow.toggled.connect(func(on: bool) -> void:
		_sync_arrow()
		collapse_toggled.emit(group_name, on))
	add_child(_arrow)
	_sync_arrow()

	thumbnail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(thumbnail)

	var label := Label.new()
	label.text = title if not title.is_empty() else name_of_group
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", font_color)
	add_child(label)

	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(rule)
	tooltip_text = "Hold Ctrl to show the drag handle. Right-click to manage groups."

	_pad = Control.new()
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE


## The row can be wider than the view; the excess is padding so the rule and handle stay visible.
func set_row_width(visible_width: float, row_width: float) -> void:
	_visible_width = visible_width
	custom_minimum_size.x = row_width
	_pad.custom_minimum_size.x = maxf(row_width - visible_width, 0.0)
	if _pad.get_parent() == null:
		add_child(_pad)
	move_child(_pad, -1)


func setup_reordering(source_id: int) -> void:
	tileset_id = source_id
	_handle = TextureRect.new()
	_handle.name = "DragHandle"
	_handle.texture = EditorInterface.get_base_control().get_theme_icon("DragHandle", "EditorIcons")
	_handle.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_handle.mouse_filter = Control.MOUSE_FILTER_PASS
	_handle.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_handle.tooltip_text = "Ctrl + drag to reorder this group."
	_handle.visible = Input.is_key_pressed(KEY_CTRL)
	add_child(_handle)
	if _pad.get_parent() == self:
		move_child(_pad, -1)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		manage_requested.emit(group_name)
		accept_event()


func _process(_delta: float) -> void:
	if _handle != null:
		_handle.visible = Input.is_key_pressed(KEY_CTRL) and is_visible_in_tree()


func _get_drag_data(at: Vector2) -> Variant:
	if _handle == null or not Input.is_key_pressed(KEY_CTRL) or not _handle.visible or not _handle.get_rect().has_point(at):
		return null
	var preview := Label.new()
	preview.text = group_name
	set_drag_preview(preview)
	return {"better_terrain_group_drag": group_name, "tileset_id": tileset_id}


func set_collapsed(collapsed: bool) -> void:
	if _arrow != null:
		_arrow.set_pressed_no_signal(collapsed)
		_sync_arrow()


func _sync_arrow() -> void:
	var folded: bool = _arrow.button_pressed
	var want := "GuiTreeArrowRight" if folded else "GuiTreeArrowDown"
	# setup() runs before the header is in the tree, where its own theme lookup fails
	var theme_owner := EditorInterface.get_base_control()
	if theme_owner.has_theme_icon(want, "EditorIcons"):
		_arrow.icon = theme_owner.get_theme_icon(want, "EditorIcons")
		_arrow.text = ""
	else:
		_arrow.icon = null
		_arrow.text = "▸" if folded else "▾"


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if data is Dictionary and (data.has("better_terrain_group_drag") or data.has("better_terrain_scene")):
		_set_hint(false)
		return get_parent()._can_drop_data(position + at, data)
	var ok: bool = accepts_terrains and data is Dictionary and data.has("better_terrain_entry")
	_set_hint(ok)
	return ok


func _drop_data(at: Vector2, data: Variant) -> void:
	_set_hint(false)
	if data.has("better_terrain_group_drag") or data.has("better_terrain_scene"):
		get_parent()._drop_data(position + at, data)
	else:
		terrain_dropped.emit(int(data["better_terrain_entry"]), group_name)


## _can_drop_data stops firing on exit; clear highlights through notifications.
func _notification(what: int) -> void:
	if what in [NOTIFICATION_DRAG_END, NOTIFICATION_MOUSE_EXIT]:
		_set_hint(false)


func _set_hint(on: bool) -> void:
	if _drop_hint == on:
		return
	_drop_hint = on
	queue_redraw()


func _draw() -> void:
	if not _drop_hint:
		return
	var r := Rect2(Vector2.ZERO, Vector2(minf(size.x, _visible_width) if _visible_width > 0.0 else size.x, size.y))
	draw_rect(r, Color(0.35, 0.9, 1.0, 0.18), true)
	draw_rect(r, Color(0.35, 0.9, 1.0, 0.95), false, 2.0)
