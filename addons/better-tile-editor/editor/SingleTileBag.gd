@tool
extends HBoxContainer

const DRAG_VISUALS := preload("res://addons/better-tile-editor/editor/DragVisuals.gd")

signal collapsed_changed
signal entry_selected(entry: Dictionary)
signal config_changed(entries: Array, groups: Array)

const META := &"_better_terrain_single_favorites"
const GROUPS_META := &"_better_terrain_single_favorite_groups"
const CELL_SIZES := [40, 56, 78, 104, 136]
const SIZE_SETTING := "editors/better_terrain/favorite_cell_size_step"
const FOLDED_SETTING := "editors/better_terrain/folded_favorite_groups"

var _content: VBoxContainer
var _rows: VBoxContainer
var _toggle: Button
var _collapsed := true
var _tileset: TileSet
var _selected := {}
var _entries: Array = []
var _groups: Array = []
var _folded := {}
var _move_menu: PopupMenu
var _move_entry_index := -1
var _destinations: Array = []
var _menu: PopupMenu
var _actions: Array[Callable] = []
var _entry_buttons: Array[Button] = []
var _group_manager: AcceptDialog
var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _name_error: Label
var _name_action: Callable
var _size_step := 2
var _handles: Array[TextureRect] = []
var _sections: Array[Control] = []
var _insertion := {}

func _init() -> void:
	_content = VBoxContainer.new()
	_content.custom_minimum_size.x = 180
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_content)
	var title_row := HBoxContainer.new()
	_content.add_child(title_row)
	var title := Label.new()
	title.text = "Favorites"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var add := Button.new()
	add.text = "+"
	add.flat = true
	add.tooltip_text = "Manage favourite groups"
	add.pressed.connect(_group_menu.bind(""))
	title_row.add_child(add)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wire_drop(_rows)
	_rows.draw.connect(_draw_insertion)
	_rows.mouse_exited.connect(func(): _set_insertion({}))
	scroll.add_child(_rows)
	# A tab with a frame, lit on hover and clickable as a whole: the bare caption and
	# arrow did not read as something to press.
	var tab := PanelContainer.new()
	tab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tab.mouse_filter = Control.MOUSE_FILTER_STOP
	tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var tab_style := _tab_style(false)
	var tab_hover := _tab_style(true)
	tab.add_theme_stylebox_override("panel", tab_style)
	tab.mouse_entered.connect(func(): tab.add_theme_stylebox_override("panel", tab_hover))
	tab.mouse_exited.connect(func(): tab.add_theme_stylebox_override("panel", tab_style))
	tab.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			set_collapsed(not _collapsed)
			tab.accept_event())
	add_child(tab)
	var toggle_column := VBoxContainer.new()
	toggle_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(toggle_column)
	var caption_slot := Control.new()
	caption_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle_column.add_child(caption_slot)
	var caption := Label.new()
	caption.text = "Favourites"
	caption.add_theme_font_size_override("font_size", 11)
	caption.rotation = PI / 2.0
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_slot.add_child(caption)
	var layout_caption := func():
		var text_size := caption.get_combined_minimum_size()
		caption.size = text_size
		caption_slot.custom_minimum_size = Vector2(text_size.y, text_size.x)
		caption.position = Vector2((caption_slot.size.x + text_size.y) / 2.0, 0)
	caption.minimum_size_changed.connect(layout_caption)
	caption_slot.resized.connect(layout_caption)
	layout_caption.call()
	_toggle = Button.new()
	_toggle.flat = true
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_toggle.pressed.connect(func(): set_collapsed(not _collapsed))
	toggle_column.add_child(_toggle)
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(func(id: int): _actions[id].call())
	add_child(_menu)
	_move_menu = PopupMenu.new()
	_menu.add_child(_move_menu)
	_move_menu.id_pressed.connect(func(id: int): _assign(_move_entry_index, _destinations[id]))
	_name_dialog = ConfirmationDialog.new()
	_name_dialog.dialog_hide_on_ok = false
	var fields := VBoxContainer.new()
	_name_dialog.add_child(fields)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size.x = 260
	fields.add_child(_name_edit)
	_name_error = Label.new()
	fields.add_child(_name_error)
	_name_dialog.confirmed.connect(_confirm_name)
	_name_edit.text_submitted.connect(func(_text): _confirm_name())
	add_child(_name_dialog)
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting(SIZE_SETTING):
		_size_step = clampi(int(settings.get_setting(SIZE_SETTING)), 0, CELL_SIZES.size())
	set_collapsed(true)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _collapsed or _menu.visible or _name_dialog.visible or (_group_manager != null and _group_manager.visible):
		return
	if event is InputEventMouseButton and event.pressed and event.ctrl_pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _content.get_global_rect().has_point(get_global_mouse_position()):
			get_viewport().set_input_as_handled()
			_set_size_step(_size_step + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1))

func _set_size_step(value: int) -> void:
	var step := clampi(value, 0, CELL_SIZES.size())
	if step == _size_step:
		return
	_size_step = step
	EditorInterface.get_editor_settings().set_setting(SIZE_SETTING, _size_step)
	_rebuild()

func set_collapsed(value: bool) -> void:
	_collapsed = value
	_content.visible = not value
	_toggle.text = "›" if value else "‹"
	_toggle.get_parent().get_parent().tooltip_text = "Show favorites" if value else "Hide favorites"
	collapsed_changed.emit()

static func same_tile(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() and a.source == b.source and a.origin == b.origin and a.size == b.size and a.alt == b.alt

func setup(ts: TileSet, selected: Dictionary) -> void:
	var changed_tileset := ts != _tileset
	if changed_tileset:
		_menu.hide()
		_name_dialog.hide()
		if _group_manager != null:
			_group_manager.hide()
	_tileset = ts
	_selected = selected
	_entries = ts.get_meta(META, []).duplicate(true) if ts else []
	_groups = ts.get_meta(GROUPS_META, []).duplicate(true) if ts else []
	var settings := EditorInterface.get_editor_settings()
	if ts != null and not ts.resource_path.is_empty():
		_folded = settings.get_setting(FOLDED_SETTING) if settings.has_setting(FOLDED_SETTING) else {}
	elif changed_tileset:
		_folded = {}
	_rebuild()

func select_entry(entry: Dictionary) -> void:
	_selected = entry
	for button in _entry_buttons:
		button.set_pressed_no_signal(same_tile(_entries[button.get_meta("favorite_index")], entry))

func _clear(control: Control) -> void:
	for child in control.get_children():
		control.remove_child(child)
		child.queue_free()

func _rebuild() -> void:
	_set_insertion({})
	_handles.clear()
	_sections.clear()
	_clear(_rows)
	_entry_buttons.clear()
	for group in [""] + _groups:
		var section := VBoxContainer.new()
		section.set_meta("favorite_group", group)
		_rows.add_child(section)
		_sections.append(section)
		_wire_drop(section)
		var header := HBoxContainer.new()
		section.add_child(header)
		var folded: bool = _folded.has(_fold_key(group))
		var arrow := Button.new()
		arrow.text = "▸" if folded else "▾"
		arrow.flat = true
		arrow.focus_mode = Control.FOCUS_NONE
		arrow.pressed.connect(func(): _toggle_group(group))
		header.add_child(arrow)
		var thumbnail := TextureRect.new()
		thumbnail.texture = _group_thumbnail(group)
		thumbnail.custom_minimum_size = Vector2(14, 14)
		thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumbnail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		thumbnail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(thumbnail)
		var label := Label.new()
		label.text = "General" if group.is_empty() else group
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", get_theme_color("font_disabled_color", "Editor"))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(label)
		var rule := HSeparator.new()
		rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(rule)
		header.gui_input.connect(func(event): _group_input(event, group))
		header.tooltip_text = "Hold Ctrl to show the drag handle. Right-click for group options."
		_wire_drop(header)
		if not group.is_empty():
			var handle := _add_handle(header)
			_wire_drop(handle, func(_at): return _group_drag(group, handle))
		var grid: Container
		if _size_step == CELL_SIZES.size():
			grid = VBoxContainer.new()
		else:
			grid = HFlowContainer.new()
		grid.custom_minimum_size.y = 32
		grid.visible = not folded
		section.add_child(grid)
		_wire_drop(grid)
		for index in _entries.size():
			if _group_of(_entries[index]) == group:
				_add_entry(grid, index)
	if _group_manager != null and _group_manager.visible:
		_group_manager.refresh()

func _group_thumbnail(group: String) -> Texture2D:
	for entry in _entries:
		if _group_of(entry) == group:
			return _thumbnail(_tileset, entry)
	return null

func _group_of(entry: Dictionary) -> String:
	var group: String = entry.get("group", "")
	return group if _groups.has(group) else ""

func _fold_key(group: String) -> String:
	return "%s::%s" % [_tileset.resource_path if not _tileset.resource_path.is_empty() else str(_tileset.get_instance_id()), group]

func _store_folded() -> void:
	if not _tileset.resource_path.is_empty():
		EditorInterface.get_editor_settings().set_setting(FOLDED_SETTING, _folded)

func _toggle_group(group: String) -> void:
	var key := _fold_key(group)
	if _folded.has(key):
		_folded.erase(key)
	else:
		_folded[key] = true
	_store_folded()
	_rebuild()

func _add_entry(grid: Container, index: int) -> void:
	var entry: Dictionary = _entries[index]
	var button := Button.new()
	var list_mode := _size_step == CELL_SIZES.size()
	var side: int = 78 if list_mode else CELL_SIZES[_size_step]
	button.custom_minimum_size = Vector2(0 if list_mode else side, side)
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		button.add_theme_color_override("icon_" + state + "_color", Color.WHITE)
	var selected_style := StyleBoxFlat.new()
	var normal := get_theme_stylebox("normal", "Button")
	var background: Color = normal.bg_color if normal is StyleBoxFlat else Color(0.15, 0.15, 0.15)
	selected_style.bg_color = background.lerp(get_theme_color("accent_color", "Editor"), 0.35)
	selected_style.set_corner_radius_all(4)
	selected_style.set_content_margin_all(8)
	button.add_theme_stylebox_override("pressed", selected_style)
	button.add_theme_stylebox_override("hover_pressed", selected_style)
	button.toggle_mode = true
	button.button_pressed = same_tile(entry, _selected)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.expand_icon = true
	button.icon = _thumbnail(_tileset, entry)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.text = entry.get("name", "")
	if list_mode:
		button.text = entry.get("name", "%d × %d tiles" % [entry.size.x, entry.size.y])
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	elif not button.text.is_empty():
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 11)
	button.add_theme_constant_override("icon_max_width", side - 16)
	button.tooltip_text = "%s\n%d × %d tiles — source %d, (%d, %d)\nClick to select. Drag to move. Right-click for options.\nCtrl + wheel: cell size. Wheel: scroll." % [entry.get("name", "Favorite"), entry.size.x, entry.size.y, entry.source, entry.origin.x, entry.origin.y]
	if button.icon == null:
		button.text = "?"
		button.tooltip_text += "\nThe source or tile is no longer available."
	button.pressed.connect(func():
		if _thumbnail(_tileset, entry) != null:
			entry_selected.emit(entry))
	button.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			button.accept_event()
			_entry_menu(index))
	button.set_meta("favorite_index", index)
	_wire_drop(button, func(_at): return _entry_drag(index, button))
	grid.add_child(button)
	_entry_buttons.append(button)

func _add_handle(parent: Control) -> TextureRect:
	var handle := TextureRect.new()
	handle.name = "DragHandle"
	handle.texture = EditorInterface.get_base_control().get_theme_icon("DragHandle", "EditorIcons")
	handle.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	handle.mouse_default_cursor_shape = Control.CURSOR_DRAG
	handle.tooltip_text = "Ctrl + drag to reorder."
	handle.visible = Input.is_key_pressed(KEY_CTRL)
	parent.add_child(handle)
	_handles.append(handle)
	return handle

func _process(_delta: float) -> void:
	var show_handles := Input.is_key_pressed(KEY_CTRL) and is_visible_in_tree() and not _collapsed
	for handle in _handles:
		handle.visible = show_handles

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_set_insertion({})

func _wire_drop(control: Control, drag := Callable()) -> void:
	control.draw.connect(func():
		if _insertion.get("highlight") == control:
			DRAG_VISUALS.highlight(control))
	control.set_drag_forwarding(drag,
		func(at, data):
			var target := _drop_target(control.global_position + at - _rows.global_position, data)
			_set_insertion(target)
			return not target.is_empty(),
		func(at, data):
			var target := _drop_target(control.global_position + at - _rows.global_position, data)
			_set_insertion({})
			if not target.is_empty():
				_drop(data, target.group, target.index, target.after))

func _drop_target(at: Vector2, data: Variant) -> Dictionary:
	if not _can_drop(at, data):
		return {}
	if data.has("group"):
		var sections := _sections.filter(func(candidate): return not String(candidate.get_meta("favorite_group")).is_empty())
		for i in sections.size():
			var favorite_section = sections[i]
			if at.y < favorite_section.position.y + favorite_section.size.y / 2.0:
				return _horizontal_target(favorite_section.get_meta("favorite_group"), -1, false, favorite_section.position.y - 2.0)
			if i == sections.size() - 1:
				return _horizontal_target(favorite_section.get_meta("favorite_group"), -1, true, favorite_section.position.y + favorite_section.size.y + 2.0)
		return {}
	var section: Control = _sections[0]
	for candidate in _sections:
		if at.y >= candidate.position.y:
			section = candidate
	var group: String = section.get_meta("favorite_group")
	var header: Control = section.get_child(0)
	if Rect2(header.global_position - _rows.global_position, header.size).has_point(at):
		return {group = group, index = -1, after = false, highlight = header}
	for button in _entry_buttons:
		if not button.is_visible_in_tree():
			continue
		var rect := Rect2(button.global_position - _rows.global_position, button.size)
		if rect.has_point(at):
			var index: int = button.get_meta("favorite_index")
			if same_tile(data.entry, _entries[index]):
				return {}
			var after: bool = at.y > rect.get_center().y if _size_step == CELL_SIZES.size() else at.x > rect.get_center().x
			return {group = _group_of(_entries[index]), index = index, after = after, highlight = button}
	return {group = group, index = -1, after = false, highlight = section}

func _horizontal_target(group: String, index: int, after: bool, y: float) -> Dictionary:
	y = clampf(y, 1.0, _rows.size.y - 1.0)
	return {group = group, index = index, after = after, start = Vector2(3, y), end = Vector2(_rows.size.x - 3, y)}

func _set_insertion(target: Dictionary) -> void:
	if _insertion == target:
		return
	var previous = _insertion.get("highlight")
	if is_instance_valid(previous):
		previous.queue_redraw()
	_insertion = target
	var highlighted = _insertion.get("highlight")
	if is_instance_valid(highlighted):
		highlighted.queue_redraw()
	_rows.queue_redraw()

func _draw_insertion() -> void:
	if _insertion.is_empty() or _insertion.has("highlight"):
		return
	var color := Color(0.35, 0.9, 1.0)
	_rows.draw_line(_insertion.start, _insertion.end, color, 2.0)
	_rows.draw_circle(_insertion.start, 3.0, color)
	_rows.draw_circle(_insertion.end, 3.0, color)

func _entry_drag(index: int, button: Control) -> Dictionary:
	var entry: Dictionary = _entries[index]
	button.set_drag_preview(DRAG_VISUALS.preview(entry.get("name", "%d × %d tiles" % [entry.size.x, entry.size.y])))
	return {favorite_source = _tileset.get_instance_id(), entry = entry.duplicate(true)}

func _group_drag(group: String, handle: Control) -> Variant:
	if group.is_empty() or not Input.is_key_pressed(KEY_CTRL):
		return null
	var preview := Label.new()
	preview.text = group
	handle.set_drag_preview(preview)
	return {favorite_source = _tileset.get_instance_id(), group = group}

func _can_drop(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("favorite_source", -1) == _tileset.get_instance_id() and (data.has("entry") or data.has("group"))

func _drop(data: Dictionary, group: String, index: int, after := false) -> void:
	if data.has("group"):
		var from := _groups.find(data.group)
		var to := _groups.find(group)
		if from < 0 or to < 0:
			return
		to += int(after)
		if from < to:
			to -= 1
		if from == to:
			return
		_groups.remove_at(from)
		_groups.insert(to, data.group)
	else:
		var from := _entries.find(data.entry)
		if from < 0:
			return
		var entry: Dictionary = _entries[from]
		var to := _entries.size() if index < 0 else index + int(after)
		_entries.remove_at(from)
		if from < to:
			to -= 1
		entry["group"] = group
		_entries.insert(to, entry)
	_commit()

func _start_menu() -> void:
	_menu.clear()
	_actions.clear()

func _action(label: String, action: Callable) -> void:
	_menu.add_item(label, _actions.size())
	_actions.append(action)

func _popup_menu() -> void:
	_menu.position = Vector2i(get_screen_transform() * get_local_mouse_position())
	_menu.popup()

func _entry_menu(index: int) -> void:
	_start_menu()
	_action("Select", func():
		if _thumbnail(_tileset, _entries[index]) != null:
			entry_selected.emit(_entries[index]))
	_action("Rename…", func(): _ask_name("Rename favorite", _entries[index].get("name", ""), func(value):
		_entries[index]["name"] = value
		_commit()
		return true))
	_menu.add_separator()
	_move_menu.clear()
	_move_entry_index = index
	_destinations = [""] + _groups
	for id in _destinations.size():
		var group: String = _destinations[id]
		_move_menu.add_item("General" if group.is_empty() else group, id)
	_menu.add_submenu_node_item("Move to", _move_menu, _actions.size())
	_actions.append(_move_menu.popup)

	_action("New group…", func(): _ask_name("New favorite group", "", func(value): return _create_group(value, index)))
	_menu.add_separator()
	_action("Delete favorite", func():
		_entries.remove_at(index)
		_commit())
	_popup_menu()

func _assign(index: int, group: String) -> void:
	_entries[index]["group"] = group
	_commit()

func _group_input(event: InputEvent, group: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_group_menu(group)

func _group_menu(group: String) -> void:
	if _group_manager == null:
		_group_manager = load("res://addons/better-tile-editor/editor/FavoriteGroups.gd").new()
		_group_manager.bag = self
		add_child(_group_manager)
	_group_manager.refresh()
	_group_manager.select_group(group)
	_group_manager.popup_centered()

func _valid_name(value: String, previous := "") -> bool:
	return not value.is_empty() and value.nocasecmp_to("General") != 0 and (_groups.all(func(group): return group == previous or String(group).nocasecmp_to(value) != 0))

func _create_group(value: String, entry_index := -1) -> bool:
	if not _valid_name(value):
		return false
	_groups.append(value)
	if entry_index >= 0:
		_entries[entry_index]["group"] = value
	_commit()
	return true

func _rename_group(group: String, value: String) -> bool:
	if not _valid_name(value, group):
		return false
	if _folded.has(_fold_key(group)):
		_folded.erase(_fold_key(group))
		_folded[_fold_key(value)] = true
		_store_folded()
	_groups[_groups.find(group)] = value
	for entry in _entries:
		if entry.get("group", "") == group:
			entry["group"] = value
	_commit()
	return true

func _delete_group(group: String) -> void:
	_groups.erase(group)
	for entry in _entries:
		if entry.get("group", "") == group:
			entry.erase("group")
	_commit()

func _ask_name(title: String, current: String, action: Callable) -> void:
	_name_dialog.title = title
	_name_edit.text = current
	_name_error.text = ""
	_name_action = action
	_name_dialog.popup_centered()
	_name_edit.grab_focus()
	_name_edit.select_all()

func _confirm_name() -> void:
	var value := _name_edit.text.strip_edges()
	if value.is_empty() or not _name_action.call(value):
		_name_error.text = "Use a unique, non-empty name. General is reserved."
		return
	_name_dialog.hide()

func selected_index() -> int:
	if _selected.is_empty():
		return -1
	for i in _entries.size():
		if same_tile(_entries[i], _selected):
			return i
	return -1

func delete_selected() -> void:
	var index := selected_index()
	if index >= 0:
		_entries.remove_at(index)
		_commit()

func _commit() -> void:
	config_changed.emit(_entries.duplicate(true), _groups.duplicate(true))

func _thumbnail(ts: TileSet, entry: Dictionary) -> Texture2D:
	if not ts.has_source(entry.source):
		return null
	var source := ts.get_source(entry.source) as TileSetAtlasSource
	if source == null or source.texture == null or not source.has_tile(entry.origin) or not source.has_alternative_tile(entry.origin, entry.alt):
		return null
	var texture := AtlasTexture.new()
	texture.atlas = source.texture
	var region := source.get_tile_texture_region(entry.origin, entry.alt)
	var extent: Vector2i = (source.texture_region_size + source.separation) * (entry.size - Vector2i.ONE)
	texture.region = Rect2(region.position, region.size + extent)
	return texture

static func _tab_style(hover: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var accent := EditorInterface.get_editor_theme().get_color("accent_color", "Editor")
	style.bg_color = Color(1, 1, 1, 0.12 if hover else 0.06)
	style.border_color = accent if hover else Color(1, 1, 1, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 8
	style.content_margin_bottom = 4
	return style

