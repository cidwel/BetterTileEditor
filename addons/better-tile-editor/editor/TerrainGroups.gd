@tool
extends AcceptDialog


signal groups_changed

var tileset : TileSet

var _list : ItemList
var _name_edit : LineEdit
var _add_button : Button
var _rename_button : Button
var _remove_button : Button
var _up_button : Button
var _down_button : Button
var _color_option : OptionButton


func _init() -> void:
	title = "Terrain groups"
	min_size = Vector2i(420, 320)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 8)
	root.add_child(columns)

	_list = ItemList.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(_i): _sync_buttons())
	columns.add_child(_list)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	columns.add_child(side)

	_up_button = _add_side_button(side, "Move up", func(): _move(-1))
	_down_button = _add_side_button(side, "Move down", func(): _move(1))
	side.add_child(HSeparator.new())
	_rename_button = _add_side_button(side, "Rename", _on_rename)
	_remove_button = _add_side_button(side, "Remove", _on_remove)

	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 6)
	root.add_child(color_row)

	var color_label := Label.new()
	color_label.text = "Shown as"
	color_row.add_child(color_label)

	_color_option = OptionButton.new()
	_color_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_option.item_selected.connect(_on_icon_terrain_selected)
	color_row.add_child(_color_option)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	root.add_child(add_row)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "New group name"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t): _on_add())
	add_row.add_child(_name_edit)

	_add_button = Button.new()
	_add_button.text = "Add"
	_add_button.pressed.connect(_on_add)
	add_row.add_child(_add_button)


func _add_side_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func refresh() -> void:
	var previous := selected_group()

	_list.clear()
	for g in BetterTerrain.get_terrain_groups(tileset):
		var count := BetterTerrain.get_terrains_in_group(tileset, g.name).size()
		var index := _list.add_item("%s  (%d)" % [g.name, count])
		_list.set_item_custom_fg_color(index, g.color)
		if g.name == previous:
			_list.select(index)

	if _list.item_count > 0 and _list.get_selected_items().is_empty():
		_list.select(0)

	_sync_buttons()


func selected_index() -> int:
	var selection := _list.get_selected_items()
	return selection[0] if !selection.is_empty() else -1


func selected_group() -> String:
	var index := selected_index()
	if index < 0:
		return ""
	var groups := BetterTerrain.get_terrain_groups(tileset)
	return groups[index].name if index < groups.size() else ""


func _sync_buttons() -> void:
	var index := selected_index()
	var has_selection := index >= 0

	_rename_button.disabled = !has_selection
	_remove_button.disabled = !has_selection
	_up_button.disabled = !has_selection or index == 0
	_down_button.disabled = !has_selection or index >= _list.item_count - 1

	_sync_color_option()


func _sync_color_option() -> void:
	_color_option.clear()
	var index := selected_index()
	if index < 0:
		_color_option.disabled = true
		return

	var groups := BetterTerrain.get_terrain_groups(tileset)
	if index >= groups.size():
		_color_option.disabled = true
		return

	var group : Dictionary = groups[index]
	var members := BetterTerrain.get_terrains_in_group(tileset, group.name)

	_color_option.disabled = members.is_empty()
	_color_option.add_item("First terrain of the group")
	_color_option.set_item_metadata(0, -1)
	if !members.is_empty():
		var first := BetterTerrain.get_terrain_icon_texture(tileset, members[0])
		_color_option.set_item_icon(0, first if first else _swatch(group.color))

	var selected := 0
	for id in members:
		var terrain := BetterTerrain.get_terrain(tileset, id)
		var item := _color_option.item_count
		_color_option.add_item(terrain.name)
		var texture := BetterTerrain.get_terrain_icon_texture(tileset, id)
		_color_option.set_item_icon(item, texture if texture else _swatch(terrain.color))
		_color_option.set_item_metadata(item, id)
		if id == group.icon_terrain:
			selected = item

	_color_option.selected = selected


func _swatch(color: Color) -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _on_add() -> void:
	var group_name := _name_edit.text.strip_edges()
	if group_name.is_empty():
		return

	if BetterTerrain.add_terrain_group(tileset, group_name):
		_name_edit.text = ""
		refresh()
		groups_changed.emit()


func _on_rename() -> void:
	var index := selected_index()
	if index < 0:
		return

	var group_name := _name_edit.text.strip_edges()
	if group_name.is_empty():
		_name_edit.text = selected_group()
		_name_edit.grab_focus()
		return

	if BetterTerrain.rename_terrain_group(tileset, index, group_name):
		_name_edit.text = ""
		refresh()
		groups_changed.emit()


func _on_remove() -> void:
	var group_name := selected_group()
	if group_name.is_empty():
		return
	var count := BetterTerrain.get_terrains_in_group(tileset, group_name).size()
	if count == 0:
		_remove_group(group_name)
		return
	var confirmation := ConfirmationDialog.new()
	confirmation.title = "Remove terrain group"
	confirmation.dialog_text = "Remove '%s'?\n\nIts %d terrain(s) will move to General. The terrains and their tiles will not be deleted." % [group_name, count]
	add_child(confirmation)
	confirmation.confirmed.connect(func():
		_remove_group(group_name)
		confirmation.queue_free())
	confirmation.canceled.connect(confirmation.queue_free)
	confirmation.popup_centered()


func _remove_group(group_name: String) -> void:
	var groups := BetterTerrain.get_terrain_groups(tileset)
	var index := groups.find_custom(func(group): return group.name == group_name)
	if index >= 0 and BetterTerrain.remove_terrain_group(tileset, index):
		refresh()
		groups_changed.emit()


func _move(delta: int) -> void:
	var index := selected_index()
	if index < 0:
		return

	var target := index + delta
	if target < 0 or target >= _list.item_count:
		return

	if BetterTerrain.move_terrain_group(tileset, index, target):
		refresh()
		_list.select(target)
		_sync_buttons()
		groups_changed.emit()


func _on_icon_terrain_selected(item: int) -> void:
	var index := selected_index()
	if index < 0:
		return

	if BetterTerrain.set_terrain_group_icon_terrain(tileset, index, _color_option.get_item_metadata(item)):
		refresh()
		groups_changed.emit()
