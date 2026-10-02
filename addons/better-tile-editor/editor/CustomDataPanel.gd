@tool
extends PanelContainer
## Side panel of the Custom data tool: Paint builds a brush from the fields, Inspect edits the
## selected tiles' values (see DESIGN.md AG).

signal brush_changed
signal view_changed
signal mode_changed
signal add_requested(field_name: String, type: int)
signal rename_requested(index: int, field_name: String)
signal retype_requested(index: int, type: int)
signal delete_requested(index: int)
## The field under the mouse, -1 when it leaves: the atlas and the map show that field meanwhile.
signal field_hovered(index: int)
## Inspect: a value set on every selected tile.
signal inspect_edited(field: int, value: Variant)
## The preset list to store in the tile set (the dock does it, with undo).
signal presets_changed(list: Array)

const CustomData := preload("res://addons/better-tile-editor/editor/CustomData.gd")
const Collisions := preload("res://addons/better-tile-editor/editor/Collisions.gd")
const HINT_COLOR := Color(0.7, 0.75, 0.85)

enum Mode { PAINT, INSPECT }
## What the atlas and the map show: the tiles holding the whole brush, nothing, or one field (>= 0).
enum View { MATCHES = -1, NONE = -2 }
## A value that differs between the selected tiles.
const MIXED := &"__mixed__"

const OVERVIEW_SETTING := "editors/better_terrain/custom_data_overview"
var mode := Mode.PAINT
## The next click takes a tile's fields as the brush, as the picker's key does.
var pick_armed := false

var _tileset: TileSet
## Per field name: {armed, value}. Kept by name so it survives the list being rebuilt.
var _brush := {}
var _view := View.MATCHES
var _filter := ""
var _only_used := false
var _used_button: Button
var _overview_button: Button
## The Used and Overview toggles, kept together wherever they sit.
var _toggles: HBoxContainer
var _filter_row: HBoxContainer
## Fields set on some tile of the tile set, for "Used" in Paint.
var _used := {}
var _match_count := -1
var _active_preset := ""
var _selection := {}
var _selection_count := 0
var _pick_key := "Alt"
var _accent := Color(0.44, 0.73, 0.98)

var _mode_buttons := {}
## Paint | Inspect and the picker, for the toolbar.
var mode_bar: HBoxContainer
var _pick_button: Button
var _hint: Label
var _presets_box: VBoxContainer
var _fields: VBoxContainer
var _add_row: HBoxContainer
var _name_edit: LineEdit
var _type_pick: OptionButton
var _alt_pick: OptionButton
var _view_pick: OptionButton
var _use_as_brush: Button


func _init() -> void:
	name = "CustomDataPanel"
	custom_minimum_size.x = 270
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 6)
	scroll.add_child(outer)
	var editor_theme := EditorInterface.get_editor_theme()
	_accent = editor_theme.get_color("accent_color", "Editor")

	# Paint | Inspect, and the picker: the dock puts them in the toolbar, where the
	# other tools keep their modes (Collisions' Solid / Shape / Stamp).
	var top := HBoxContainer.new()
	top.name = "CustomDataModes"
	mode_bar = top
	var group := ButtonGroup.new()
	for entry in [[Mode.PAINT, "Paint", "Build a brush from the fields and click tiles to apply it.", "Edit"],
			[Mode.INSPECT, "Inspect", "Select tiles to see their values and change them.", "Search"]]:
		var b := Button.new()
		b.set_meta(&"tool_name", entry[1])
		b.tooltip_text = "%s\n%s" % [entry[1], entry[2]]
		b.icon = editor_theme.get_icon(entry[3], "EditorIcons")
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = entry[0] == mode
		b.toggled.connect(func(on: bool):
			if on:
				set_mode(entry[0]))
		top.add_child(b)
		_mode_buttons[entry[0]] = b
	_pick_button = Button.new()
	_pick_button.icon = editor_theme.get_icon("ColorPick", "EditorIcons")
	_pick_button.toggle_mode = true
	_pick_button.flat = true
	_pick_button.focus_mode = Control.FOCUS_NONE
	_pick_button.tooltip_text = "Pick\nThe next click on a tile copies its fields to the brush."
	_pick_button.set_meta(&"tool_name", "Pick")
	_pick_button.toggled.connect(func(on: bool):
		pick_armed = on
		if on and mode != Mode.PAINT:
			_mode_buttons[Mode.PAINT].button_pressed = true
		_update_hint())
	top.add_child(_pick_button)

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", HINT_COLOR)
	outer.add_child(_hint)

	_presets_box = VBoxContainer.new()
	_presets_box.add_theme_constant_override("separation", 8)
	outer.add_child(_presets_box)

	var filter_row := HBoxContainer.new()
	_filter_row = filter_row
	outer.add_child(filter_row)
	var filter := LineEdit.new()
	filter.placeholder_text = "Filter fields"
	filter.right_icon = editor_theme.get_icon("Search", "EditorIcons")
	filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter.text_changed.connect(func(t: String):
		_filter = t.strip_edges().to_lower()
		_rebuild_fields())
	filter_row.add_child(filter)
	var used := Button.new()
	used.text = "Showing all"
	used.toggle_mode = true
	used.focus_mode = Control.FOCUS_NONE
	used.tooltip_text = "Show all fields, or only those in use: set on some tile in Paint, on the selection in Inspect."
	used.toggled.connect(func(on: bool):
		_only_used = on
		used.text = "Showing used" if on else "Showing all"
		_rebuild_fields())
	_toggles = HBoxContainer.new()
	_toggles.add_child(used)
	_used_button = used
	var overview := Button.new()
	overview.text = "All data"
	overview.toggle_mode = true
	overview.focus_mode = Control.FOCUS_NONE
	overview.tooltip_text = "With no field shown, darken every tile holding custom data and name what it holds."
	var settings := EditorInterface.get_editor_settings()
	overview.button_pressed = not settings.has_setting(OVERVIEW_SETTING) or bool(settings.get_setting(OVERVIEW_SETTING))
	overview.toggled.connect(func(on: bool) -> void:
		EditorInterface.get_editor_settings().set_setting(OVERVIEW_SETTING, on)
		view_changed.emit())
	_toggles.add_child(overview)
	_overview_button = overview
	filter_row.add_child(_toggles)
	var add := Button.new()
	add.icon = editor_theme.get_icon("Add", "EditorIcons")
	add.toggle_mode = true
	add.tooltip_text = "Add a custom data field to the tile set."
	add.toggled.connect(func(on: bool):
		_add_row.visible = on
		if on:
			_name_edit.grab_focus())
	filter_row.add_child(add)

	_add_row = HBoxContainer.new()
	_add_row.hide()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Field name"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t: String): _add())
	_add_row.add_child(_name_edit)
	_type_pick = OptionButton.new()
	for type: int in CustomData.TYPES:
		_type_pick.add_item(CustomData.type_name(type), type)
	_add_row.add_child(_type_pick)
	var confirm := Button.new()
	confirm.text = "Add"
	confirm.pressed.connect(_add)
	_add_row.add_child(confirm)
	outer.add_child(_add_row)

	_fields = VBoxContainer.new()
	_fields.add_theme_constant_override("separation", 2)
	_fields.theme = _compact_theme()
	outer.add_child(_fields)

	_use_as_brush = Button.new()
	_use_as_brush.text = "Use as brush"
	_use_as_brush.tooltip_text = "Take the selection's values (those they share) as the Paint brush."
	_use_as_brush.pressed.connect(_selection_to_brush)
	outer.add_child(_use_as_brush)

	outer.add_child(HSeparator.new())
	var options_toggle := Button.new()
	options_toggle.text = "Options"
	options_toggle.flat = true
	options_toggle.toggle_mode = true
	options_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	options_toggle.icon = editor_theme.get_icon("GuiTreeArrowRight", "EditorIcons")
	outer.add_child(options_toggle)
	var options := GridContainer.new()
	options.columns = 2
	options.hide()
	outer.add_child(options)
	options_toggle.toggled.connect(func(on: bool):
		options.visible = on
		options_toggle.icon = editor_theme.get_icon("GuiTreeArrowDown" if on else "GuiTreeArrowRight", "EditorIcons"))
	var show_label := Label.new()
	show_label.text = "Show"
	options.add_child(show_label)
	_view_pick = OptionButton.new()
	_view_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_pick.fit_to_longest_item = false
	_view_pick.tooltip_text = "What the atlas and the map show."
	_view_pick.item_selected.connect(func(i: int):
		_view = _view_pick.get_item_id(i)
		_update_hint()
		view_changed.emit())
	options.add_child(_view_pick)
	var alt_label := Label.new()
	alt_label.text = "Apply to"
	options.add_child(alt_label)
	_alt_pick = OptionButton.new()
	_alt_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_alt_pick.fit_to_longest_item = false
	for i in Collisions.ALT_SCOPE_NAMES.size():
		_alt_pick.add_item(Collisions.ALT_SCOPE_NAMES[i], i)
	_alt_pick.tooltip_text = "Which alternatives of a tile get the values written to it."
	_alt_pick.item_selected.connect(func(i: int): CustomData.set_alt_scope(i))
	options.add_child(_alt_pick)


func setup(ts: TileSet) -> void:
	_tileset = ts
	_alt_pick.select(CustomData.alt_scope())
	_rebuild_view_pick()
	_rebuild_presets()
	_rebuild_fields()


func set_mode(value: int) -> void:
	if mode == value:
		return
	mode = value
	# Without the signal the button group does not let go of the other one.
	for key in _mode_buttons:
		_mode_buttons[key].set_pressed_no_signal(key == value)
	if mode != Mode.PAINT and pick_armed:
		_pick_button.button_pressed = false
	_rebuild_presets()
	_rebuild_fields()
	mode_changed.emit()


## The picker's key, as set in the options (Alt or Shift).
func set_pick_key(key_name: String) -> void:
	_pick_key = key_name
	_update_hint()


func set_used(used: Dictionary) -> void:
	_used = used
	if _only_used:
		_rebuild_fields()


func set_match_count(count: int) -> void:
	_match_count = count
	_update_hint()


## Inspect: the selection's values ({field: value, or MIXED}) and how many tiles it has.
func show_selection(values: Dictionary, count: int) -> void:
	_selection = values
	_selection_count = count
	if mode == Mode.INSPECT:
		_rebuild_fields()


## What the atlas and the map show: View.MATCHES, View.NONE or a field index.
func view() -> int:
	return _view


## Whether tiles holding any custom data are marked while no field is shown.
func overview() -> bool:
	return _overview_button.button_pressed


## {field index: value} the brush writes, false included.
func brush() -> Dictionary:
	var out := {}
	if _tileset == null:
		return out
	for i in _tileset.get_custom_data_layers_count():
		var entry: Dictionary = _brush.get(_tileset.get_custom_data_layer_name(i), {})
		if entry.get("armed", false) and CustomData.editable(_tileset.get_custom_data_layer_type(i)):
			out[i] = entry.value
	return out


## Takes a configuration as the brush: its fields armed with their values, the rest left as is.
func load_values(values: Dictionary) -> void:
	for i in _tileset.get_custom_data_layers_count():
		var entry := _entry(i)
		entry.armed = values.has(i)
		if values.has(i):
			entry.value = values[i]
	_rebuild_fields()
	_rebuild_presets()
	brush_changed.emit()


func apply_preset_index(index: int) -> void:
	var list := CustomData.presets(_tileset)
	if index >= 0 and index < list.size():
		_apply_preset(list[index])


func _entry(index: int) -> Dictionary:
	var key := _tileset.get_custom_data_layer_name(index)
	if not _brush.has(key):
		var type := _tileset.get_custom_data_layer_type(index)
		_brush[key] = {armed = false, value = true if type == TYPE_BOOL else CustomData.default_for(type)}
	return _brush[key]


func _arm(index: int, armed: bool, value: Variant = null) -> void:
	var entry := _entry(index)
	entry.armed = armed
	if value != null:
		entry.value = value
	_rebuild_presets()
	_update_hint()
	brush_changed.emit()


#region Fields

func _rebuild_fields() -> void:
	for child in _fields.get_children():
		_fields.remove_child(child)
		child.queue_free()
	_use_as_brush.visible = mode == Mode.INSPECT and _selection_count > 0
	_update_hint()
	if _tileset == null:
		return
	if _tileset.get_custom_data_layers_count() == 0:
		_fields.add_child(_note("No custom data fields yet. Add one with +."))
		return
	var shown := 0
	for i in _tileset.get_custom_data_layers_count():
		var field_name := _tileset.get_custom_data_layer_name(i)
		if not _filter.is_empty() and not field_name.to_lower().contains(_filter):
			continue
		if _only_used and not _in_use(i):
			continue
		_fields.add_child(_row(i))
		shown += 1
	if shown == 0:
		_fields.add_child(_note("No field is in use yet." if _only_used and _filter.is_empty() else "No field matches."))


func _in_use(index: int) -> bool:
	if mode == Mode.PAINT:
		return _used.has(index)
	var value: Variant = _selection.get(index, null)
	return value is StringName and value == MIXED or CustomData.is_set(value, _tileset.get_custom_data_layer_type(index))


## One field: its name, its control and a ⋮ menu; an accent bar on the left while it is armed.
func _row(index: int) -> Control:
	var type := _tileset.get_custom_data_layer_type(index)
	var entry := _entry(index)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.content_margin_left = 6
	style.content_margin_right = 2
	style.border_width_left = 3
	style.border_color = _accent if mode == Mode.PAINT and entry.armed else Color.TRANSPARENT
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.mouse_entered.connect(func(): field_hovered.emit(index))
	panel.mouse_exited.connect(func(): field_hovered.emit(-1))
	var row := HBoxContainer.new()
	panel.add_child(row)
	var label := Label.new()
	var mixed := mode == Mode.INSPECT and _selection.get(index, null) is StringName
	label.text = _tileset.get_custom_data_layer_name(index) + ("  (mixed)" if mixed else "")
	label.tooltip_text = "%s (%s)" % [_tileset.get_custom_data_layer_name(index), CustomData.type_name(type)]
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	if mixed:
		label.add_theme_color_override("font_color", HINT_COLOR)
	row.add_child(label)
	if not CustomData.editable(type):
		row.add_child(_note("inspector only"))
	elif mode == Mode.PAINT:
		row.add_child(_paint_control(index, type, entry, style))
	else:
		row.add_child(_inspect_control(index, type))
	row.add_child(_field_menu(index))
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_open_field_menu(index))
	return panel


## Paint: a bool is left as is (–), set (✓) or cleared (✗); another type is armed (●) with its value.
func _paint_control(index: int, type: int, entry: Dictionary, style: StyleBoxFlat) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	if type == TYPE_BOOL:
		var group := ButtonGroup.new()
		var states := [["–", "Leave it as it is.", false, null], ["✓", "Set it to true.", true, true], ["✗", "Set it to false.", true, false]]
		for state in states:
			var b := _small_button(state[0], state[1], state[2])
			b.button_group = group
			b.button_pressed = entry.armed == state[2] and (not entry.armed or entry.value == state[3])
			b.toggled.connect(func(on: bool):
				if on:
					style.border_color = _accent if state[2] else Color.TRANSPARENT
					_arm(index, state[2], state[3]))
			box.add_child(b)
		return box
	var arm := _small_button("●" if entry.armed else "–", "● painting writes the value beside it; typing a value turns it on.\n– painting leaves this field as it is.")
	arm.button_pressed = entry.armed
	box.add_child(arm)
	var editor := _value_editor(type, entry.value, func(v: Variant):
		arm.set_pressed_no_signal(true)
		arm.text = "●"
		style.border_color = _accent
		_arm(index, true, v))
	box.add_child(editor)
	arm.toggled.connect(func(on: bool):
		arm.text = "●" if on else "–"
		style.border_color = _accent if on else Color.TRANSPARENT
		_arm(index, on))
	return box


## Inspect: the selection's value, edited on every selected tile; a bool as ✓ / ✗.
func _inspect_control(index: int, type: int) -> Control:
	var value: Variant = _selection.get(index, null)
	var mixed: bool = value is StringName
	var none := _selection_count == 0
	if type == TYPE_BOOL:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		for state in [["✓", true], ["✗", false]]:
			var b := _small_button(state[0], "Set it to %s on the selected tiles." % str(state[1]))
			b.button_pressed = not mixed and not none and bool(value) == state[1]
			b.disabled = none
			b.pressed.connect(func(): inspect_edited.emit(index, state[1]))
			box.add_child(b)
		return box
	var shown: Variant = CustomData.default_for(type) if mixed or none else value
	var editor := _value_editor(type, shown, func(v: Variant): inspect_edited.emit(index, v))
	_disable_tree(editor, none)
	return editor


func _small_button(text: String, tip: String, writes := true) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(26, 0)
	_mark_pressed(b, writes)
	return b


## A pressed toggle stands out: in the accent colour when it writes something, grey for "–".
## The default look hardly tells it from the others.
## The field rows' look: the editor's boxes with almost no padding top and bottom, so a long
## list of fields fits.
static func _compact_theme() -> Theme:
	var editor_theme := EditorInterface.get_editor_theme()
	var out := Theme.new()
	for type: StringName in [&"Button", &"LineEdit", &"SpinBox", &"OptionButton"]:
		for style: StringName in editor_theme.get_stylebox_list(type):
			var box := editor_theme.get_stylebox(style, type).duplicate() as StyleBox
			box.content_margin_top = 1
			box.content_margin_bottom = 1
			out.set_stylebox(style, type, box)
		out.set_font_size(&"font_size", type, 13)
	out.set_font_size(&"font_size", &"Label", 13)
	return out


func _mark_pressed(b: Button, writes := true) -> void:
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(_accent, 0.85) if writes else Color(0.5, 0.52, 0.56, 0.6)
	pressed.set_corner_radius_all(3)
	pressed.content_margin_left = 4
	pressed.content_margin_right = 4
	pressed.content_margin_top = 1
	pressed.content_margin_bottom = 1
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	for state in ["font_pressed_color", "font_hover_pressed_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		b.add_theme_color_override(state, Color(0.05, 0.07, 0.1))


func _value_editor(type: int, value: Variant, changed: Callable) -> Control:
	match type:
		TYPE_INT, TYPE_FLOAT:
			var spin := SpinBox.new()
			spin.allow_greater = true
			spin.allow_lesser = true
			spin.step = 1.0 if type == TYPE_INT else 0.01
			spin.custom_minimum_size.x = 80
			spin.value = float(value)
			spin.value_changed.connect(func(v: float): changed.call(int(v) if type == TYPE_INT else v))
			return spin
		TYPE_STRING:
			var line := LineEdit.new()
			line.text = str(value)
			line.custom_minimum_size.x = 90
			line.text_submitted.connect(func(t: String): changed.call(t))
			line.focus_exited.connect(func(): changed.call(line.text))
			return line
		TYPE_COLOR:
			var picker := ColorPickerButton.new()
			picker.color = value
			picker.custom_minimum_size.x = 50
			picker.popup_closed.connect(func(): changed.call(picker.color))
			return picker
		TYPE_VECTOR2, TYPE_VECTOR2I:
			var box := HBoxContainer.new()
			var spins := []
			for axis in 2:
				var spin := SpinBox.new()
				spin.allow_greater = true
				spin.allow_lesser = true
				spin.step = 1.0 if type == TYPE_VECTOR2I else 0.01
				spin.custom_minimum_size.x = 56
				spin.value = value[axis]
				box.add_child(spin)
				spins.append(spin)
			var send := func(_v: float):
				var v := Vector2(spins[0].value, spins[1].value)
				changed.call(Vector2i(v) if type == TYPE_VECTOR2I else v)
			for spin: SpinBox in spins:
				spin.value_changed.connect(send)
			return box
	return _note("")


func _disable_tree(node: Node, off: bool) -> void:
	if node is BaseButton:
		node.disabled = off
	elif node is LineEdit or node is SpinBox:
		node.editable = not off
	for child in node.get_children():
		_disable_tree(child, off)


func _field_menu(index: int) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.icon = EditorInterface.get_editor_theme().get_icon("GuiTabMenuHl", "EditorIcons")
	b.tooltip_text = "Rename, change the type, show on the atlas or delete (also a right click on the row)."
	b.pressed.connect(func(): _open_field_menu(index))
	return b


func _open_field_menu(index: int) -> void:
	var menu := PopupMenu.new()
	var types := PopupMenu.new()
	types.name = "Types"
	for type: int in CustomData.TYPES:
		types.add_radio_check_item(CustomData.type_name(type), type)
		types.set_item_checked(types.get_item_count() - 1, type == _tileset.get_custom_data_layer_type(index))
	types.id_pressed.connect(func(type: int): retype_requested.emit(index, type))
	menu.add_child(types)
	menu.add_item("Rename…", 0)
	menu.add_submenu_node_item("Change type", types)
	menu.add_item("Show on the atlas", 2)
	menu.add_separator()
	menu.add_item("Delete field", 1)
	menu.id_pressed.connect(_on_field_menu.bind(index))
	_popup_menu(menu)


func _on_field_menu(id: int, index: int) -> void:
	match id:
		0:
			_ask_name("Rename field", _tileset.get_custom_data_layer_name(index), func(fresh: String): _rename(index, fresh))
		1:
			delete_requested.emit(index)
		2:
			_show_field(index)


func _show_field(index: int) -> void:
	_view = index
	_view_pick.select(_view_pick.get_item_index(index))
	_update_hint()
	view_changed.emit()


func _rename(index: int, fresh: String) -> void:
	var old := _tileset.get_custom_data_layer_name(index)
	if fresh.is_empty() or fresh == old:
		return
	if _brush.has(old):
		_brush[fresh] = _brush[old]
		_brush.erase(old)
	rename_requested.emit(index, fresh)


func _add() -> void:
	var field_name := _name_edit.text.strip_edges()
	if field_name.is_empty():
		_name_edit.grab_focus()
		return
	add_requested.emit(field_name, _type_pick.get_selected_id())
	_name_edit.text = ""


func _selection_to_brush() -> void:
	var values := {}
	for field: int in _selection:
		var value: Variant = _selection[field]
		if not value is StringName and CustomData.is_set(value, _tileset.get_custom_data_layer_type(field)):
			values[field] = value
	set_mode(Mode.PAINT)
	load_values(values)

#endregion


#region Presets

## Chips to load presets as the brush (keys 1–9 too), "+ Save…", and Update / Save as… once the
## brush has moved away from the one loaded.
func _rebuild_presets() -> void:
	# The toggles sit by the presets in Paint; take them out of the row about to be freed.
	if _toggles.get_parent() != _filter_row:
		_toggles.reparent(_filter_row)
		_filter_row.move_child(_toggles, 1)
	for child in _presets_box.get_children():
		_presets_box.remove_child(child)
		child.queue_free()
	if _tileset == null or mode != Mode.PAINT:
		return
	var list := CustomData.presets(_tileset)
	var heading := Label.new()
	heading.text = "Presets"
	heading.add_theme_color_override("font_color", HINT_COLOR)
	heading.visible = not list.is_empty()
	_presets_box.add_child(heading)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	_presets_box.add_child(chips)
	chips.visible = not list.is_empty()
	var active: Dictionary = {}
	for i in list.size():
		var preset: Dictionary = list[i]
		var missing := _missing(preset)
		var chip := Button.new()
		var shown_name: String = preset.name if preset.name.length() <= 18 else preset.name.left(17) + "…"
		chip.text = shown_name + ("  ⚠%d" % missing.size() if not missing.is_empty() else "")
		chip.icon = _preset_swatch(preset.name)
		chip.toggle_mode = true
		chip.button_pressed = preset.name == _active_preset
		chip.focus_mode = Control.FOCUS_NONE
		_mark_pressed(chip)
		chip.tooltip_text = "Load \"%s\" as the brush%s. Right click: rename or delete.%s" % [preset.name,
			" (key %d over the atlas)" % (i + 1) if i < 9 else "",
			"\nFields no longer in the tile set: %s" % ", ".join(missing) if not missing.is_empty() else ""]
		chip.pressed.connect(func(): _apply_preset(preset))
		chip.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				_open_preset_menu(preset))
		chips.add_child(chip)
		if preset.name == _active_preset:
			active = preset
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	var save := Button.new()
	save.text = "+ Save…"
	save.tooltip_text = "Keep the brush as a named preset in the tile set."
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(func(): _ask_to_save())
	actions.add_child(save)
	_toggles.reparent(actions)
	if not active.is_empty() and CustomData.to_named(_tileset, brush()) != active.values:
		var drift := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s •" % active.name
		label.add_theme_color_override("font_color", HINT_COLOR)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		drift.add_child(label)
		var update := Button.new()
		update.text = "Update"
		update.tooltip_text = "Store the brush in \"%s\"." % active.name
		update.pressed.connect(func(): _store(CustomData.with_preset(list, active.name, CustomData.to_named(_tileset, brush())), active.name))
		drift.add_child(update)
		var save_as := Button.new()
		save_as.text = "Save as…"
		save_as.pressed.connect(func(): _ask_to_save())
		drift.add_child(save_as)
		_presets_box.add_child(drift)
	_presets_box.add_child(actions)
	_presets_box.add_child(HSeparator.new())


## Each preset's colour, from its name, so it keeps it across sessions.
static func _preset_swatch(preset_name: String) -> Texture2D:
	var img := Image.create_empty(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color.from_hsv(fposmod(float(hash(preset_name)) * 0.618034, 1.0), 0.55, 0.9))
	return ImageTexture.create_from_image(img)


## After the eyedropper: the preset holding what the brush now holds stays lit, or none does.
func follow_preset() -> void:
	var now := _set_part(brush())
	_active_preset = ""
	for preset: Dictionary in CustomData.presets(_tileset):
		if _set_part(CustomData.from_named(_tileset, preset.values)) == now:
			_active_preset = preset.name
			break
	_rebuild_presets()


# The values that change a tile; a field at its default only clears it.
func _set_part(values: Dictionary) -> Dictionary:
	var out := {}
	for field: int in values:
		if CustomData.is_set(values[field], _tileset.get_custom_data_layer_type(field)):
			out[field] = values[field]
	return out


## The names of a preset's fields the tile set no longer has, or has with another type.
func _missing(preset: Dictionary) -> Array:
	var kept := CustomData.from_named(_tileset, preset.values)
	var out := []
	for field_name: String in preset.values:
		var field := _tileset.get_custom_data_layer_by_name(field_name)
		if field < 0 or not kept.has(field):
			out.append(field_name)
	return out


func _apply_preset(preset: Dictionary) -> void:
	_active_preset = preset.name
	for i in _tileset.get_custom_data_layers_count():
		_entry(i).armed = false
	load_values(CustomData.from_named(_tileset, preset.values))


# A second preset with the very same options would only be a duplicate under another name.
func _ask_to_save() -> void:
	var values := CustomData.to_named(_tileset, brush())
	for preset: Dictionary in CustomData.presets(_tileset):
		if preset.values == values:
			var error := AcceptDialog.new()
			error.title = "Save preset"
			error.dialog_text = "There is already a preset called \"%s\" with the same options." % preset.name
			error.visibility_changed.connect(func():
				if not error.visible:
					error.queue_free())
			add_child(error)
			error.popup_centered()
			return
	_ask_name("Save preset", "", _save_preset)


func _save_preset(preset_name: String) -> void:
	var list := CustomData.presets(_tileset)
	var values := CustomData.to_named(_tileset, brush())
	if list.any(func(p): return p.name == preset_name):
		var ask := ConfirmationDialog.new()
		ask.dialog_text = "A preset called \"%s\" exists. Replace it?" % preset_name
		ask.confirmed.connect(func(): _store(CustomData.with_preset(list, preset_name, values), preset_name))
		ask.visibility_changed.connect(func():
			if not ask.visible:
				ask.queue_free())
		add_child(ask)
		ask.popup_centered()
		return
	_store(CustomData.with_preset(list, preset_name, values), preset_name)


func _store(list: Array, active: String) -> void:
	_active_preset = active
	presets_changed.emit(list)


func _open_preset_menu(preset: Dictionary) -> void:
	var menu := PopupMenu.new()
	menu.add_item("Rename…", 0)
	menu.add_item("Delete preset", 1)
	var missing := _missing(preset)
	if not missing.is_empty():
		menu.add_separator()
		menu.add_item("Recreate the missing fields", 2)
		menu.add_item("Drop the missing fields", 3)
	menu.id_pressed.connect(_on_preset_menu.bind(preset, missing))
	_popup_menu(menu)


func _on_preset_menu(id: int, preset: Dictionary, missing: Array) -> void:
	var list := CustomData.presets(_tileset)
	match id:
		0:
			_ask_name("Rename preset", preset.name, func(fresh: String): _rename_preset(list, preset, fresh))
		1:
			_store(CustomData.with_preset(list, preset.name, null), "" if _active_preset == preset.name else _active_preset)
		2:
			for field_name: String in missing:
				if _tileset.get_custom_data_layer_by_name(field_name) < 0:
					add_requested.emit(field_name, typeof(preset.values[field_name]))
		3:
			var kept := {}
			for field_name: String in preset.values:
				if not missing.has(field_name):
					kept[field_name] = preset.values[field_name]
			_store(CustomData.with_preset(list, preset.name, kept), _active_preset)


func _rename_preset(list: Array, preset: Dictionary, fresh: String) -> void:
	if fresh.is_empty() or fresh == preset.name:
		return
	var renamed := CustomData.with_preset(CustomData.with_preset(list, preset.name, null), fresh, preset.values)
	_store(renamed, fresh if _active_preset == preset.name else _active_preset)

#endregion


func _rebuild_view_pick() -> void:
	_view_pick.clear()
	_view_pick.add_item("Tiles holding the whole brush", View.MATCHES)
	_view_pick.add_item("Nothing", View.NONE)
	if _tileset != null and _tileset.get_custom_data_layers_count() > 0:
		_view_pick.add_separator()
		for i in _tileset.get_custom_data_layers_count():
			_view_pick.add_item("Field: %s" % _tileset.get_custom_data_layer_name(i), i)
	if _view >= 0 and (_tileset == null or _view >= _tileset.get_custom_data_layers_count()):
		_view = View.MATCHES
	_view_pick.select(_view_pick.get_item_index(_view))


## What a click does right now, in a line under the mode switch.
func _update_hint() -> void:
	if _hint == null:
		return
	if pick_armed:
		_hint.text = "Click a tile to copy it."
	elif mode == Mode.INSPECT:
		_hint.text = "Click: inspect · Shift+click: add · drag: box" if _selection_count == 0 \
			else "%d selected · edits apply to all" % _selection_count
	elif brush().is_empty():
		_hint.text = "Pick values below, then click tiles · %s+click: copy" % _pick_key
	else:
		_hint.text = "Click: paint · Right: clear · %s+click: copy" % _pick_key
		if _view == View.MATCHES and _match_count >= 0:
			_hint.text += " · %d match" % _match_count


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", HINT_COLOR)
	return label


func _ask_name(title_text: String, initial: String, done: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title_text
	var line := LineEdit.new()
	line.text = initial
	line.custom_minimum_size.x = 240
	dialog.add_child(line)
	dialog.register_text_enter(line)
	dialog.confirmed.connect(func(): done.call(line.text.strip_edges()))
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
	line.select_all()
	line.grab_focus()


func _popup_menu(menu: PopupMenu) -> void:
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	menu.position = Vector2i(get_screen_transform() * get_local_mouse_position())
	menu.popup()
