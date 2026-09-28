@tool
extends ConfirmationDialog

var category_icon := load("res://addons/better-tile-editor/icons/NonModifying.svg")
var object_icon := load("res://addons/better-tile-editor/icons/ObjectTerrain.svg")
var exemplar_icon := load("res://addons/better-tile-editor/icons/Exemplar.svg")
var scatter_icon := load("res://addons/better-tile-editor/icons/Scatter.svg")
var single_icon := load("res://addons/better-tile-editor/icons/SingleTile.svg")

const CATEGORY_CHECK_ID = &"category_check_id"

var accepted := false

var terrain_name : String:
	set(value): %NameEdit.text = value
	get: return %NameEdit.text

var terrain_color : Color:
	set(value): %ColorPicker.color = value
	get: return %ColorPicker.color

var terrain_icon : String:
	set(value): %IconEdit.text = value
	get: return %IconEdit.text


var terrain_icon_tile : Dictionary:
	set(value):
		_icon_tile = value.duplicate() if value.has("source_id") else {}
		_sync_icon_row()
	get: return _icon_tile


func terrain_icon_data() -> Dictionary:
	if _icon_tile.has("source_id"):
		return _icon_tile.duplicate()
	return {path = terrain_icon}

# Use item IDs; dropdown order differs from TerrainType values.
var terrain_type : int:
	set(value):
		for i in %TypeOption.item_count:
			if %TypeOption.get_item_id(i) == value:
				%TypeOption.selected = i
				break
		_on_type_option_item_selected(%TypeOption.selected)
	get: return %TypeOption.get_selected_id()


var terrain_object : Dictionary:
	set(value):
		_pending_object = value
		_sync_object_row()
	get:
		if !_size_spin[0]:
			return {}
		var size := Vector2i(int(_size_spin[0].value), int(_size_spin[1].value))
		if terrain_type != BetterTerrain.TerrainType.OBJECT:
			return {}
		return ObjectTerrain.make_config(size, _lone_coord,
				_object_preview != null and _object_preview.mass, _base_rect())

var terrain_categories : Array: set = set_categories, get = get_categories

var terrain_group : String:
	set(value):
		_pending_group = value
		_sync_group_option()
	get:
		if !_group_option or _group_option.selected < 0:
			return _pending_group
		return _group_option.get_item_metadata(_group_option.selected)

const ObjectTerrain := preload("res://addons/better-tile-editor/ObjectTerrain.gd")
var _object_preview: Control = null
var _base_editor: Control = null
const ObjectBaseEditor := preload("res://addons/better-tile-editor/editor/ObjectBaseEditor.gd")
const ObjectPreview := preload("res://addons/better-tile-editor/editor/ObjectPreview.gd")

var _icon_tile := {}
var _icon_button : Button
var _icon_clear : Button
var _icon_picker : PopupPanel
var _icon_terrain_id := -1

var _tileset : TileSet
var _type_row : Control
var _help_button : Button
var _help_window : Window
var _pending_group := ""
var _pending_object := {}
var _obj_rows := []
var _size_spin := [null, null]
var _base_selection := Rect2i(0, 0, 2, 2)
var _base_rows := []
var _base_drawing_size := Vector2i(2, 2)
var _lone_coord := Vector2i(-1, -1)
var _obj_status : Label
var _terrain_id := -1
var _group_option : OptionButton
var _group_manager


func set_group_data(ts: TileSet) -> void:
	_tileset = ts

	if !_group_option:
		var grid := _rows_grid()

		var label := Label.new()
		label.text = "Group"
		grid.add_child(label)

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 4)
		grid.add_child(row)

		_group_option = OptionButton.new()
		_group_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_group_option)

		var manage := Button.new()
		manage.text = "..."
		manage.tooltip_text = "Create, rename, reorder and delete groups"
		manage.pressed.connect(_on_manage_groups_pressed)
		row.add_child(manage)

		var type_position := _type_cell().get_index()
		grid.move_child(label, type_position + 1)
		grid.move_child(row, type_position + 2)

	_sync_group_option()


func _sync_group_option() -> void:
	if !_group_option:
		return

	_group_option.clear()
	_group_option.add_item("Default")
	_group_option.set_item_metadata(0, "")

	var selected := 0
	for g in BetterTerrain.get_terrain_groups(_tileset):
		var item := _group_option.item_count
		_group_option.add_item(g.name)
		_group_option.set_item_metadata(item, g.name)
		if g.name == _pending_group:
			selected = item

	if selected == 0:
		_pending_group = ""

	_group_option.selected = selected


func _on_manage_groups_pressed() -> void:
	if !_group_manager:
		_group_manager = load("res://addons/better-tile-editor/editor/TerrainGroups.gd").new()
		_group_manager.tileset = _tileset
		_group_manager.groups_changed.connect(func():
			_pending_group = terrain_group
			_sync_group_option()
		)
		add_child(_group_manager)

	_group_manager.refresh()
	_group_manager.popup_centered()


func set_icon_data(ts: TileSet, terrain_id: int, icon: Dictionary) -> void:
	_tileset = ts
	_icon_terrain_id = terrain_id

	if !_icon_button:
		var grid := %IconEdit.get_parent()

		var label := Label.new()
		label.text = "Tile preview"
		grid.add_child(label)

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 4)
		grid.add_child(row)

		_icon_button = Button.new()
		_icon_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_icon_button.expand_icon = true
		_icon_button.custom_minimum_size.y = 28
		_icon_button.tooltip_text = "Use one of this terrain's own tiles as its icon, instead of an image on disk."
		_icon_button.pressed.connect(_on_pick_icon_tile_pressed)
		row.add_child(_icon_button)

		_icon_clear = Button.new()
		_icon_clear.text = "x"
		_icon_clear.tooltip_text = "Back to no tile icon"
		_icon_clear.pressed.connect(func():
			_icon_tile = {}
			_sync_icon_row())
		row.add_child(_icon_clear)

		%IconEdit.text_changed.connect(func(text: String):
			if not text.is_empty() and not _icon_tile.is_empty():
				_icon_tile = {}
				_sync_icon_row())

		var position := %IconEdit.get_index()
		grid.move_child(label, position + 1)
		grid.move_child(row, position + 2)

	terrain_icon_tile = icon


static func _tile_texture(ts: TileSet, source_id: int, coord: Vector2i) -> Texture2D:
	if ts == null or not ts.has_source(source_id):
		return null
	var source := ts.get_source(source_id) as TileSetAtlasSource
	if source == null or source.texture == null:
		return null
	var tex := AtlasTexture.new()
	tex.atlas = source.texture
	tex.region = source.get_tile_texture_region(coord)
	return tex


func _sync_icon_row() -> void:
	if !_icon_button:
		return
	var tex: Texture2D = null
	if _icon_tile.has("source_id"):
		tex = _tile_texture(_tileset, int(_icon_tile.source_id), _icon_tile.coord)
	_icon_button.icon = tex
	_icon_button.text = "" if tex else "Pick a tile..."
	_icon_clear.disabled = _icon_tile.is_empty()
	if not _icon_tile.is_empty():
		%IconEdit.text = ""


func _terrain_tiles() -> Array:
	var out := []
	if _tileset == null or _icon_terrain_id < 0:
		return out
	var source_ids := {}
	for i in _tileset.get_source_count():
		var id := _tileset.get_source_id(i)
		source_ids[_tileset.get_source(id)] = id
	for t in BetterTerrain.get_tile_sources_in_terrain(_tileset, _icon_terrain_id):
		if source_ids.has(t.source):
			out.push_back({source_id = source_ids[t.source], coord = t.coord})
	return out


func _on_pick_icon_tile_pressed() -> void:
	var tiles := _terrain_tiles()
	if tiles.is_empty():
		var dialog := AcceptDialog.new()
		dialog.dialog_text = "This terrain has no tiles yet.\n\nSave it, mark some tiles in the atlas, then come back and one of them can be its icon."
		add_child(dialog)
		dialog.popup_centered()
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		return

	if _icon_picker:
		_icon_picker.queue_free()
	_icon_picker = PopupPanel.new()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(8 * 40 + 24, min(6, ceili(tiles.size() / 8.0)) * 40 + 8)
	var grid := GridContainer.new()
	grid.columns = 8
	scroll.add_child(grid)
	_icon_picker.add_child(scroll)
	for t in tiles:
		var b := Button.new()
		b.custom_minimum_size = Vector2(36, 36)
		b.expand_icon = true
		b.icon = _tile_texture(_tileset, t.source_id, t.coord)
		b.tooltip_text = "source %d, %s" % [t.source_id, t.coord]
		b.pressed.connect(func():
			_icon_tile = {source_id = t.source_id, coord = t.coord}
			_sync_icon_row()
			_icon_picker.hide())
		grid.add_child(b)
	add_child(_icon_picker)
	_icon_picker.popup_centered()


# category is name, color, id
func set_category_data(options: Array) -> void:
	if !options.is_empty():
		%CategoryLabel.show()
		%CategoryContainer.show()
	
	for o in options:
		var c = CheckBox.new()
		c.text = o.name
		c.icon = category_icon
		c.add_theme_color_override(&"icon_normal_color", o.color)
		c.add_theme_color_override(&"icon_disabled_color", Color(o.color, 0.4))
		c.add_theme_color_override(&"icon_focus_color", o.color)
		c.add_theme_color_override(&"icon_hover_color", o.color)
		c.add_theme_color_override(&"icon_hover_pressed_color", o.color)
		c.add_theme_color_override(&"icon_normal_color", o.color)
		c.add_theme_color_override(&"icon_pressed_color", o.color)
		
		c.set_meta(CATEGORY_CHECK_ID, o.id)
		%CategoryLayout.add_child(c)


func set_categories(ids : Array):
	for c in %CategoryLayout.get_children():
		c.button_pressed = c.get_meta(CATEGORY_CHECK_ID) in ids


func get_categories() -> Array:
	var result := []
	if terrain_type == BetterTerrain.TerrainType.CATEGORY:
		return result
	for c in %CategoryLayout.get_children():
		if c.button_pressed:
			result.push_back(c.get_meta(CATEGORY_CHECK_ID))
	return result


func _on_confirmed() -> void:
	# confirm valid name
	if terrain_name.is_empty():
		var dialog := AcceptDialog.new()
		dialog.dialog_text = "Name cannot be empty"
		EditorInterface.popup_dialog_centered(dialog)
		await dialog.visibility_changed
		dialog.queue_free()
		return
	if _name_taken(terrain_name):
		var dialog := AcceptDialog.new()
		dialog.dialog_text = "There is already a terrain called \"%s\" in this tileset. Give this one another name." % terrain_name
		EditorInterface.popup_dialog_centered(dialog)
		await dialog.visibility_changed
		dialog.queue_free()
		return
	
	# New object terrains have no marked blocks yet, so do not require them here.

	accepted = true
	hide()


func _on_type_option_item_selected(index: int) -> void:
	var id : int = %TypeOption.get_item_id(index) if index >= 0 else 0
	var categories_available = (id != BetterTerrain.TerrainType.CATEGORY)
	_sync_help_button()
	for c in %CategoryLayout.get_children():
		c.disabled = !categories_available
	_sync_object_row()


func set_object_data(ts: TileSet, terrain_id: int = -1) -> void:
	_tileset = ts
	_terrain_id = terrain_id
	if not _name_watch:
		_name_watch = true
		%NameEdit.text_changed.connect(func(_t: String): _check_name())
	_check_name()

	_add_type_option(BetterTerrain.TerrainType.OBJECT, "Object (NxM)", object_icon)
	_add_type_option(BetterTerrain.TerrainType.EXEMPLAR, "Patch", exemplar_icon)
	_add_type_option(BetterTerrain.TerrainType.SCATTER, "Scatter", scatter_icon)
	_wrap_type_row()

	if _obj_rows.is_empty():
		var grid := _rows_grid()
		_add_object_row(grid, "Drawing size (w, h)", _make_size_row(),
			"How many cells one object spans. A 2x2 tree covers four cells of the map.")
		_object_preview = ObjectPreview.new()
		_object_preview.mode_picked.connect(func(_mass: bool): _refresh_blocks())
		_add_object_row(grid, "Mode", _object_preview,
			"Objects: each block is placed on its own grid, which is how a tree or a rock works. Area: painting a shape fills it with the lone drawing stacked on a lattice, which is how a wood or a hedge works. Click a card to pick.")
		_base_editor = ObjectBaseEditor.new()
		_base_editor.base_changed.connect(func(rect: Rect2i):
			_base_selection = rect
			_refresh_blocks())
		_add_object_row(grid, "Placement base", _base_editor)
		_base_rows.append(_obj_rows.back())
		_obj_status = Label.new()
		_obj_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_obj_status.custom_minimum_size.x = 260
		_add_object_row(grid, "", _obj_status)

	_sync_object_row()


func _wrap_type_row() -> void:
	if _type_row != null:
		return
	var option: Control = %TypeOption
	var grid := option.get_parent()
	var at := option.get_index()
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)
	grid.add_child(row)
	# Preserve the packed scene owner when reparenting the type dropdown.
	if grid.owner != null:
		row.owner = grid.owner
	grid.move_child(row, at)

	var keeper: Node = option.owner
	option.owner = null
	grid.remove_child(option)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	option.owner = keeper

	_help_button = Button.new()
	_help_button.text = "?"
	_help_button.focus_mode = Control.FOCUS_NONE
	_help_button.custom_minimum_size = Vector2(26, 0)
	_help_button.tooltip_text = "Show what this mode does, step by step."
	_help_button.pressed.connect(_on_help_pressed)
	row.add_child(_help_button)
	_type_row = row
	_sync_help_button()


func _type_cell() -> Control:
	return _type_row if _type_row != null else %TypeOption


## The dropdown is nested in a help row; its immediate parent is not the grid.
func _rows_grid() -> Node:
	return _type_cell().get_parent()


func _sync_help_button() -> void:
	if _help_button != null:
		_help_button.visible = true


func _on_help_pressed() -> void:
	var ExemplarData = load("res://addons/better-tile-editor/ExemplarData.gd")
	var table: Dictionary = ExemplarData.table_of(_tileset, terrain_name) if _tileset else {}
	if is_instance_valid(_help_window):
		_help_window.queue_free()
	_help_window = load("res://addons/better-tile-editor/editor/ModeHelp.gd").new()
	add_child(_help_window)
	_help_window.setup_mode(_tileset, table, terrain_type, terrain_color)
	_help_window.popup_centered()


var _name_watch := false

func _name_taken(name: String) -> bool:
	if _tileset == null or name.is_empty():
		return false
	for i in BetterTerrain.terrain_count(_tileset):
		if i == _terrain_id:
			continue
		if BetterTerrain.get_terrain(_tileset, i).get("name", "") == name:
			return true
	return false


func _check_name() -> void:
	var taken := _name_taken(terrain_name)
	get_ok_button().disabled = taken
	if taken:
		%NameEdit.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		%NameEdit.tooltip_text = "Already used by another terrain in this tileset."
	else:
		%NameEdit.remove_theme_color_override("font_color")
		%NameEdit.tooltip_text = ""


func _add_type_option(id: int, label: String, icon: Texture2D) -> void:
	for i in %TypeOption.item_count:
		if %TypeOption.get_item_id(i) == id:
			return
	%TypeOption.add_item(label)
	var at: int = %TypeOption.item_count - 1
	%TypeOption.set_item_id(at, id)
	if icon != null:
		%TypeOption.set_item_icon(at, icon)


func _add_object_row(grid: Node, text: String, control: Control, tooltip: String = "") -> void:
	var label := Label.new()
	label.text = text
	label.tooltip_text = tooltip
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	control.tooltip_text = tooltip
	grid.add_child(label)
	grid.add_child(control)
	var base : int = _type_cell().get_index() + 1 + _obj_rows.size() * 2
	grid.move_child(label, base)
	grid.move_child(control, base + 1)
	_obj_rows.push_back([label, control])


func _make_size_row() -> Control:
	var box := HBoxContainer.new()
	for i in 2:
		var sp := SpinBox.new()
		sp.min_value = 1
		sp.max_value = 64
		sp.value = 2
		sp.value_changed.connect(func(_v): _refresh_blocks())
		box.add_child(sp)
		_size_spin[i] = sp
	return box


func _base_rect() -> Rect2i:
	return _base_selection


func _sync_object_row() -> void:
	if _obj_rows.is_empty():
		return
	var visible_rows: bool = terrain_type == BetterTerrain.TerrainType.OBJECT
	for row in _obj_rows:
		row[0].visible = visible_rows
		row[1].visible = visible_rows

	min_size = Vector2i(430, 0) if visible_rows else Vector2i(0, 0)
	reset_size()

	if !_pending_object.is_empty():
		var cfg := _pending_object
		_pending_object = {}
		var sz: Array = cfg.get("size", [2, 2])
		_size_spin[0].set_value_no_signal(sz[0])
		_size_spin[1].set_value_no_signal(sz[1])
		_base_drawing_size = Vector2i(sz[0], sz[1])
		_base_selection = ObjectTerrain.base_rect(_base_drawing_size, cfg)
		var at: Array = cfg.get("lone", [])
		_lone_coord = Vector2i(at[0], at[1]) if at.size() == 2 else Vector2i(-1, -1)
		if _object_preview != null:
			_object_preview.mass = bool(cfg.get("mass", false))
	if visible_rows:
		_refresh_blocks()


func _refresh_blocks() -> void:
	if _obj_status == null or _tileset == null:
		return
	var size := Vector2i(int(_size_spin[0].value), int(_size_spin[1].value))
	var blocks := ObjectTerrain.detect_blocks(_tileset, _terrain_id, size) if _terrain_id >= 0 else []
	if _terrain_id >= 0:
		var t = BetterTerrain.get_terrain(_tileset, _terrain_id)
		var lone: Array = t.get("object", {}).get("lone", []) if t.valid else []
		if lone.size() == 2:
			_lone_coord = Vector2i(lone[0], lone[1])


	if _object_preview != null:
		if size != _base_drawing_size and _base_rect() == Rect2i(Vector2i.ZERO, _base_drawing_size):
			_base_selection = Rect2i(Vector2i.ZERO, size)
		_base_drawing_size = size
		var cfg := {base = [_base_selection.position.x, _base_selection.position.y,
			_base_selection.size.x, _base_selection.size.y]}
		_base_selection = ObjectTerrain.base_rect(size, cfg)
		_object_preview.setup(_tileset, blocks if blocks.size() == 2 else [], _lone_coord, size, terrain_object)
		var source_id := -1
		for block in blocks:
			if block.rect.position == _lone_coord:
				source_id = block.source_id
				break
		_base_editor.setup(_tileset, source_id, _lone_coord, size, _base_rect())

	var as_area: bool = _object_preview != null and _object_preview.mass
	for row in _base_rows:
		row[0].visible = as_area and terrain_type == BetterTerrain.TerrainType.OBJECT
		row[1].visible = row[0].visible
	var tall: bool = size.y > size.x
	if _terrain_id < 0:
		_obj_status.text = "Save the terrain, then pick it in the list and mark its drawing in the atlas with the Lone button."
	elif blocks.is_empty():
		_obj_status.text = "No drawing marked yet. Press Lone in the toolbar and click the top-left tile of the drawing in the atlas."
	elif as_area and blocks.size() == 1:
		_obj_status.text = "Ready to paint. Bake in the toolbar is optional: it makes a filler for the inside of the area out of this drawing, so the trees overlap without gaps."
	elif blocks.size() == 1 and not as_area:
		_obj_status.text = "1 drawing marked at %s. Each object is drawn whole; mark a joined block with the Joined button to let neighbours fuse." % blocks[0]["rect"].position
	elif blocks.size() != 2:
		_obj_status.text = "Found %d block%s of %dx%d; this needs 1 or 2. Check the size, or re-mark them." % [
			blocks.size(), "" if blocks.size() == 1 else "s", size.x, size.y]
	else:
		_obj_status.text = "2 blocks marked: %s and %s. Lone is %s." % [blocks[0]["rect"].position, blocks[1]["rect"].position, _lone_coord]
	if tall and not as_area:
		_obj_status.text += "\n\nThis drawing is %dx%d. Placed one by one it can only step %d cells at a time, so it tiles into bands and the wood has no edge. Tall art usually wants Area." % [
			size.x, size.y, size.y]
