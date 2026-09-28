@tool
extends "res://addons/better-tile-editor/editor/TerrainGroups.gd"

var bag: HBoxContainer
var _error: Label

func _init() -> void:
	super()
	title = "Favourite groups"
	_color_option.get_parent().hide()
	_list.fixed_icon_size = Vector2i(16, 16)
	_name_edit.placeholder_text = "Group name"
	_error = Label.new()
	_error.text = "Use a unique name. General cannot be renamed or removed."
	_error.hide()
	_name_edit.get_parent().get_parent().add_child(_error)
	_remove_button.tooltip_text = "Remove the group and keep its favourites in General."

func refresh() -> void:
	var previous := selected_group()
	_list.clear()
	for group in [""] + bag._groups:
		var count: int = bag._entries.filter(func(entry): return bag._group_of(entry) == group).size()
		var index := _list.add_item("%s  (%d)" % ["General" if group.is_empty() else group, count], bag._group_thumbnail(group))
		_list.set_item_metadata(index, group)
		if group == previous:
			_list.select(index)
	if _list.get_selected_items().is_empty():
		_list.select(0)
	_sync_buttons()

func selected_group() -> String:
	var index := selected_index()
	return String(_list.get_item_metadata(index)) if index >= 0 else ""

func select_group(group: String) -> void:
	for index in _list.item_count:
		if _list.get_item_metadata(index) == group:
			_list.select(index)
			break
	_sync_buttons()

func _sync_buttons() -> void:
	var index := selected_index()
	_rename_button.disabled = index <= 0
	_remove_button.disabled = index <= 0
	_up_button.disabled = index <= 1
	_down_button.disabled = index <= 0 or index >= _list.item_count - 1

func _on_add() -> void:
	var value := _name_edit.text.strip_edges()
	if not bag._create_group(value):
		_error.show()
		return
	_finish_edit(value)

func _on_rename() -> void:
	var group := selected_group()
	if group.is_empty():
		return
	var value := _name_edit.text.strip_edges()
	if value.is_empty():
		_name_edit.text = group
		_name_edit.grab_focus()
		_name_edit.select_all()
		return
	if not bag._rename_group(group, value):
		_error.show()
		return
	_finish_edit(value)

func _finish_edit(group: String) -> void:
	_error.hide()
	_name_edit.clear()
	refresh()
	select_group(group)

func _on_remove() -> void:
	var group := selected_group()
	if group.is_empty():
		return
	bag._delete_group(group)
	_finish_edit("")

func _move(delta: int) -> void:
	var index := selected_index()
	var target := index + delta
	if index <= 0 or target <= 0 or target >= _list.item_count:
		return
	var group := selected_group()
	bag._drop({group = group}, _list.get_item_metadata(target), -1, delta > 0)
	refresh()
	select_group(group)
