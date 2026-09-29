@tool
extends Window

signal config_changed

const ExemplarData := preload("res://addons/better-tile-editor/ExemplarData.gd")
const Chrome := preload("res://addons/better-tile-editor/editor/Chrome.gd")
const HELP_SCRIPT := preload("res://addons/better-tile-editor/editor/ModeHelp.gd")

const SLOT := Vector2i(74, 74)
const PALETTE_ZOOM := 2.0
const MIN_ZOOM_SETTING := "editor/better_terrain/min_zoom_amount"
const MAX_ZOOM_SETTING := "editor/better_terrain/max_zoom_amount"
const PREVIEW_ZOOM := 2

var tile_set: TileSet
var terrain_name := ""
var terrain_index := -1
var terrain_color := Color.WHITE

var _table := {}
var _selected := ""
var _slots := {}
var _grid: GridContainer
var _left: ScrollContainer
var _split: HSplitContainer
var _empty_note: Label
var _help_badge: Button
var _help_window: Window
var _status: RichTextLabel
var _preview: Control
var _palette_view: Control
var _palette_pick: Control
var _panning := false


func setup(ts: TileSet, index: int, exemplar_name: String, color: Color) -> void:
	tile_set = ts
	terrain_index = index
	terrain_name = exemplar_name
	terrain_color = color
	_table = ExemplarData.table_of(ts, exemplar_name)
	title = "Patch terrain: %s" % exemplar_name
	size = Vector2i(1060, 620)
	_build()
	if _table.roles.is_empty():
		_on_learn_pressed()
	_refresh()


func _build() -> void:
	var root_box := VBoxContainer.new()
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 6)
	add_child(root_box)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	root_box.add_child(bar)

	var learn := Button.new()
	learn.text = "Read the drawing"
	learn.tooltip_text = ("Reads the tiles this terrain already owns as one laid-out "
		+ "example (a pond drawn once) and works out every role from where each "
		+ "cell sits in it. This is the whole setup: there is nothing else to fill in.")
	learn.pressed.connect(_on_learn_pressed)
	bar.add_child(learn)

	var reset := Button.new()
	reset.text = "Back to what the drawing says"
	reset.tooltip_text = "Undoes an overruled role and takes the drawing's own answer again."
	reset.pressed.connect(_on_reset_pressed)
	bar.add_child(reset)

	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)

	_split = HSplitContainer.new()
	var split := _split
	Chrome.dress_split(split)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 0
	root_box.add_child(Chrome.rule())
	root_box.add_child(split)

	_left = ScrollContainer.new()
	_left.size_flags_horizontal = Control.SIZE_FILL
	_left.custom_minimum_size = Vector2(260, 0)
	split.add_child(_left)
	var stack := VBoxContainer.new()
	_left.add_child(stack)
	_empty_note = Label.new()
	_empty_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_note.custom_minimum_size = Vector2(240, 0)
	_empty_note.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	stack.add_child(_empty_note)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	stack.add_child(_grid)
	_build_grid()

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	_preview = Control.new()
	_preview.custom_minimum_size = Vector2(0, 300)
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.draw.connect(_draw_preview)
	right.add_child(_preview)

	right.add_child(Chrome.rule())
	var pal := ScrollContainer.new()
	pal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(pal)
	# Load after the autoload exists; TileView depends on BetterTerrain.
	_palette_view = load("res://addons/better-tile-editor/editor/TileView.gd").new()
	_palette_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_palette_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pal.add_child(_palette_view)
	_palette_view.refresh_tileset(tile_set)
	_palette_view._on_zoom_value_changed(PALETTE_ZOOM)
	_palette_view.change_zoom_level.connect(_on_palette_zoom_requested)
	_palette_pick = Control.new()
	_palette_pick.set_anchors_preset(Control.PRESET_FULL_RECT)
	_palette_pick.mouse_filter = Control.MOUSE_FILTER_STOP
	_palette_pick.gui_input.connect(_on_palette_input)
	_palette_pick.draw.connect(_draw_palette_mark)
	# Attach overlays to TileView; ScrollContainer controls sibling layout.
	_palette_view.add_child(_palette_pick)

	_help_badge = Button.new()
	_help_badge.text = "?"
	_help_badge.flat = false
	_help_badge.focus_mode = Control.FOCUS_NONE
	_help_badge.custom_minimum_size = Vector2(20, 20)
	_help_badge.size = Vector2(20, 20)
	_help_badge.tooltip_text = "Show what this square of the drawing does, step by step."
	_help_badge.pressed.connect(_on_help_pressed)
	_help_badge.visible = false

	close_requested.connect(hide)


func _build_grid() -> void:
	_detach_badge()
	for c in _grid.get_children():
		c.queue_free()
	_slots.clear()
	var block: Array = _table.get("block", [])
	var slots: Dictionary = _table.get("slots", {})
	if slots.is_empty():
		slots = _table.get("lines", {})
	if block.size() != 4 or slots.is_empty():
		_grid.columns = 1
		_empty_note.text = ("Nothing read yet.\n\nGive this terrain the tiles of one "
			+ "drawing, a pond with its bank and all, then press \"Read the drawing\". "
			+ "The squares here are that drawing, one per cell of it.")
		_empty_note.visible = true
		return
	_empty_note.visible = false
	var origin := Vector2i(int(block[0]), int(block[1]))
	_grid.columns = int(block[2])
	var gap: int = _grid.get_theme_constant("h_separation")
	_left.custom_minimum_size.x = maxf(260.0, float(block[2]) * (SLOT.x + gap) + 28.0)
	var at_cell := {}
	for role in slots:
		var run: Array = slots[role]
		for i in run.size():
			at_cell[Vector2i(int(run[i][0]), int(run[i][1]))] = [role, i]
	for y in int(block[3]):
		for x in int(block[2]):
			var cell := origin + Vector2i(x, y)
			if not at_cell.has(cell):
				var pad := Control.new()
				pad.custom_minimum_size = SLOT
				_grid.add_child(pad)
				continue
			var role: String = at_cell[cell][0]
			var index: int = at_cell[cell][1]
			var run_len: int = slots[role].size()
			var key := "%s#%d" % [role, index]
			var b := Button.new()
			b.custom_minimum_size = SLOT
			b.toggle_mode = true
			b.tooltip_text = ExemplarData.role_label(role)
			if run_len > 1:
				b.tooltip_text += " (%d of %d)" % [index + 1, run_len]
			b.pressed.connect(_on_slot_pressed.bind(key))
			b.draw.connect(_draw_slot.bind(b, key))
			_slots[key] = b
			_grid.add_child(b)
	if _split != null:
		_split.queue_sort()


static func _split_key(key: String) -> Array:
	var p := key.rsplit("#", true, 1)
	return [p[0], int(p[1])] if p.size() == 2 else [key, 0]


#region Drawing

func _draw_tile(target: CanvasItem, at: Array, rect: Rect2) -> bool:
	var src := tile_set.get_source(int(_table.source)) as TileSetAtlasSource
	if src == null:
		return false
	var coord := Vector2i(int(at[0]), int(at[1]))
	if not src.has_tile(coord):
		return false
	target.draw_texture_rect_region(src.texture, rect, src.get_tile_texture_region(coord))
	return true


func _draw_slot(b: Button, key: String) -> void:
	var parts := _split_key(key)
	var role: String = parts[0]
	var index: int = parts[1]
	var box := Rect2(5, 5, SLOT.x - 10, SLOT.y - 10)
	var run: Array = _table.lines.get(role, [])
	if index < run.size():
		if not _draw_tile(b, run[index], box):
			b.draw_rect(box, Color(1, 0.4, 0.4, 0.25))
	elif not _table.roles.has(role):
		b.draw_rect(box, Color(1, 1, 1, 0.06))
		b.draw_string(get_theme_default_font(), Vector2(8, SLOT.y * 0.5 + 4),
			role.replace("OUT_", "").replace("IN_", "") if role != "IN_C" else "C",
			HORIZONTAL_ALIGNMENT_LEFT, SLOT.x - 16, 12, Color(1, 1, 1, 0.35))
	elif not _draw_tile(b, _table.roles[role], box):
		b.draw_rect(box, Color(1, 0.4, 0.4, 0.25))

	if b.button_pressed:
		var edge := Rect2(1, 1, SLOT.x - 2, SLOT.y - 2)
		b.draw_rect(edge, Color(1.0, 0.78, 0.25, 0.22))
		b.draw_rect(edge, Color(1.0, 0.85, 0.3), false, 2.0)


static func _preview_region() -> Dictionary:
	var region := {}
	for y in range(1, 7):
		for x in range(1, 11):
			if (x == 1 or x == 10) and (y == 1 or y == 6):
				continue
			if x >= 8 and y <= 2:
				continue
			region[Vector2i(x, y)] = true
	for i in 3:
		region[Vector2i(11 + i, 4 + i)] = true
		region[Vector2i(12 + i, 4 + i)] = true
	return region


func _draw_preview() -> void:
	if _table.roles.is_empty():
		_preview.draw_string(get_theme_default_font(), Vector2(8, 24),
			"Press \"Read the drawing\".", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(1, 1, 1, 0.5))
		return
	var preview_size := tile_set.tile_size * PREVIEW_ZOOM
	var region := _preview_region()
	var seen := {}
	for c in region:
		seen[c] = true
		for off in ExemplarData.OFFSETS:
			seen[c + off] = true
	for c in seen:
		var tile := ExemplarData.tile_for(_table, region, c)
		if tile.is_empty():
			continue
		_draw_tile(_preview, [tile.coord.x, tile.coord.y],
			Rect2(Vector2(c) * Vector2(preview_size), Vector2(preview_size)))

#endregion


func _tile_at(key: String) -> Array:
	var parts := _split_key(key)
	var run: Array = _table.lines.get(parts[0], [])
	if int(parts[1]) < run.size():
		return run[parts[1]]
	return _table.roles.get(parts[0], [])


#region Marking the palette

static func palette_rect_of(ts: TileSet, zoom: float, disabled: Array,
		source_id: int, coord: Vector2i) -> Rect2:
	if ts == null:
		return Rect2()
	var offset := Vector2.ZERO
	for s in ts.get_source_count():
		var sid := ts.get_source_id(s)
		if sid in disabled:
			continue
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src == null or src.texture == null:
			continue
		if sid == source_id and src.has_tile(coord):
			var region := src.get_tile_texture_region(coord, 0)
			return Rect2(offset + zoom * region.position, zoom * region.size)
		offset.y += zoom * src.texture.get_height()
	return Rect2()


func _palette_rect_of(source_id: int, coord: Vector2i) -> Rect2:
	if _palette_view == null:
		return Rect2()
	return palette_rect_of(tile_set, _palette_view.zoom_level,
		_palette_view.disabled_sources, source_id, coord)


func _draw_palette_mark() -> void:
	if _selected == "":
		return
	var at := _tile_at(_selected)
	if at.size() != 2:
		return
	var r := _palette_rect_of(int(_table.source), Vector2i(int(at[0]), int(at[1])))
	if r.size.x <= 0.0:
		return
	_palette_pick.draw_rect(r, Color(1.0, 0.78, 0.25, 0.22))
	_palette_pick.draw_rect(r, Color(1.0, 0.85, 0.3), false, 2.0)


## Scroll only when the role changes so refreshes preserve manual panning.
func _reveal_in_palette() -> void:
	if _palette_view == null or _selected == "":
		return
	var sc := _palette_view.get_parent() as ScrollContainer
	if sc == null:
		return
	var at := _tile_at(_selected)
	if at.size() != 2:
		return
	var r := _palette_rect_of(int(_table.source), Vector2i(int(at[0]), int(at[1])))
	if r.size.x <= 0.0:
		return
	if Rect2(Vector2(sc.scroll_horizontal, sc.scroll_vertical), sc.size).encloses(r):
		return
	sc.scroll_horizontal = int(maxf(0.0, r.position.x + r.size.x * 0.5 - sc.size.x * 0.5))
	sc.scroll_vertical = int(maxf(0.0, r.position.y + r.size.y * 0.5 - sc.size.y * 0.5))

#endregion


func _detach_badge() -> void:
	if _help_badge == null:
		return
	var parent := _help_badge.get_parent()
	if is_instance_valid(parent):
		parent.remove_child(_help_badge)
	_help_badge.visible = false


func _place_badge() -> void:
	_detach_badge()
	if _help_badge == null or _selected == "" or not _slots.has(_selected):
		return
	var slot: Button = _slots[_selected]
	slot.add_child(_help_badge)
	_help_badge.position = Vector2(SLOT.x - 24, 4)
	_help_badge.visible = true


func _on_help_pressed() -> void:
	if _selected == "":
		return
	if is_instance_valid(_help_window):
		_help_window.queue_free()
	_help_window = HELP_SCRIPT.new()
	add_child(_help_window)
	_help_window.setup_square(tile_set, _table, _split_key(_selected)[0], terrain_color)
	_help_window.popup_centered()


func _refresh() -> void:
	for key in _slots:
		_slots[key].button_pressed = key == _selected
		_slots[key].queue_redraw()
	if _preview != null:
		_preview.queue_redraw()
	if _palette_pick != null:
		_palette_pick.queue_redraw()
	_place_badge()
	var read := 0
	var corners := 0
	for role in _table.roles:
		if role in ExemplarData.CORNERS:
			corners += 1
		else:
			read += 1
	var chosen := ""
	if _selected != "":
		chosen = "   selected: [b]%s[/b]" % ExemplarData.role_label(_split_key(_selected)[0])
	if read == 0:
		_status.text = "[color=#e0a34a]Nothing read yet.[/color]%s" % chosen
	else:
		_status.text = "[color=#9fd]%d[/color] of %d roles read from the drawing%s.%s" % [
			read, ExemplarData.ROLES.size(),
			(" and %d corner%s" % [corners, "" if corners == 1 else "s"]) if corners > 0 else "", chosen]


func _on_slot_pressed(key: String) -> void:
	_selected = "" if _selected == key else key
	_refresh()
	_reveal_in_palette()


func _save() -> void:
	ExemplarData.store_table(tile_set, terrain_name, _table)
	config_changed.emit()


func assign_tile(source_id: int, coord: Vector2i) -> bool:
	if _selected == "":
		return false
	if int(_table.source) < 0:
		_table.source = source_id
	if int(_table.source) != source_id:
		_status.text = "[color=#e0a34a]That tile is in another atlas; this terrain reads one.[/color]"
		return true
	var parts := _split_key(_selected)
	var role: String = parts[0]
	var index: int = parts[1]
	var run: Array = _table.lines.get(role, [])
	if index < run.size():
		run[index] = [coord.x, coord.y]
	else:
		run = [[coord.x, coord.y]]
	_table.lines[role] = run
	@warning_ignore("integer_division")
	_table.roles[role] = run[run.size() / 2]
	_save()
	_refresh()
	return true


func _on_reset_pressed() -> void:
	if _selected == "":
		_status.text = "[color=#e0a34a]Pick a role first.[/color]"
		return
	var learnt := _read()
	var role: String = _split_key(_selected)[0]
	if learnt.is_empty() or not learnt.roles.has(role):
		_status.text = "[color=#e0a34a]The drawing says nothing about that role.[/color]"
		return
	_table.roles[role] = learnt.roles[role]
	_table.lines[role] = learnt.lines[role]
	_table.slots[role] = learnt.slots[role]
	_save()
	_build_grid()
	_refresh()


func _read() -> Dictionary:
	# Try other atlases too, since the drawing may have moved to a different source.
	var source_id: int = int(_table.source)
	if source_id >= 0:
		var stored := ExemplarData.learn_from_block(tile_set, terrain_index, source_id)
		if not stored.is_empty():
			return stored
	for i in tile_set.get_source_count():
		var sid := tile_set.get_source_id(i)
		if sid == source_id:
			continue
		var learnt := ExemplarData.learn_from_block(tile_set, terrain_index, sid)
		if not learnt.is_empty():
			return learnt
	return {}


func _why_missing(missing: Array) -> String:
	var water: Array = _table.get("water", [])
	var out := ""
	if water.size() == 4:
		var w := int(water[2])
		var h := int(water[3])
		if w < 3:
			out += ("The inside of the drawing is only %d wide, so it has no middle column: "
				+ "nothing can go between the left edge and the right one, and a shape "
				+ "painted wider than %d leaves those cells empty. Draw it at least 5 wide "
				+ "(3 inside), with a straight run of bank along the top and the bottom. ") % [w, w]
		if h < 3:
			out += ("The inside is only %d tall, so it has no middle row: nothing can go "
				+ "between the top edge and the bottom one, and a shape painted taller "
				+ "than %d leaves those cells empty. Draw it at least 5 tall (3 inside), "
				+ "with a straight run of bank down the left and the right. ") % [h, h]
	if out == "":
		var names := []
		for role in missing:
			names.append(ExemplarData.role_label(role))
		out = "Read the drawing, but %d roles are not in it: %s. Those cells will be left empty. " % [
			missing.size(), ", ".join(names)]
	return out.strip_edges()


func _shape_read() -> String:
	var block: Array = _table.get("block", [])
	var water: Array = _table.get("water", [])
	if block.size() != 4 or water.size() != 4:
		return ""
	return "   [color=#888]%d tiles, block %dx%d, water %dx%d[/color]" % [
		int(_table.get("tiles", 0)), int(block[2]), int(block[3]), int(water[2]), int(water[3])]


func _on_learn_pressed() -> void:
	ExemplarData.stale(tile_set, terrain_index, _table)
	var learnt := _read()
	if learnt.is_empty():
		_status.text = ("[color=#e0a34a]Nothing to read. The drawing is the tiles marked with "
			+ "this terrain: in the atlas, with the paint-type tool, drag over the whole "
			+ "drawing, bank and all. The yellow box that appears round them is what will be "
			+ "read, and the blue one inside it is what will count as the water.[/color]")
		return
	_table = learnt
	_selected = ""
	_save()
	_build_grid()
	_refresh()
	var missing := []
	for role in ExemplarData.ROLES:
		if not _table.roles.has(role):
			missing.append(role)
	var corners := 0
	for role in ExemplarData.CORNERS:
		if _table.roles.has(role):
			corners += 1
	if missing.is_empty():
		_status.text = ("[color=#9fd]Read the drawing: all %d roles%s.[/color]" % [ExemplarData.ROLES.size(),
			(", and %d corner%s" % [corners, "" if corners == 1 else "s"]) if corners > 0 else ""]) + _shape_read()
	else:
		_status.text = "[color=#e0a34a]" + _why_missing(missing) + "[/color]" + _shape_read()


#region Palette

func _on_palette_zoom_requested(value: float) -> void:
	_palette_view._on_zoom_value_changed(clampf(value,
		ProjectSettings.get_setting(MIN_ZOOM_SETTING, 1.0),
		ProjectSettings.get_setting(MAX_ZOOM_SETTING, 8.0)))


func _on_palette_input(event: InputEvent) -> void:
	if _palette_view == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_palette_pick.accept_event()
			_palette_view._zoom_at_cursor(event.position, 1.1)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_palette_pick.accept_event()
			_palette_view._zoom_at_cursor(event.position, 1.0 / 1.1)
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_palette_pick.accept_event()
		_panning = event.pressed
		return
	if _panning and event is InputEventMouseMotion:
		_palette_pick.accept_event()
		var sc := _palette_view.get_parent() as ScrollContainer
		if sc != null:
			sc.scroll_horizontal -= int(event.relative.x)
			sc.scroll_vertical -= int(event.relative.y)
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var part: Dictionary = _palette_view.tile_part_from_position(Vector2i(event.position))
	if not part.get("valid", false):
		return
	if not assign_tile(int(part.source_id), part.coord):
		_status.text = "[color=#e0a34a]Pick a role on the left first.[/color]"

#endregion
