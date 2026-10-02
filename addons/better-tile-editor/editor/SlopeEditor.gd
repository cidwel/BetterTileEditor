@tool
extends PanelContainer

## Slope set-up, shown over the dock: pick a piece card, then its tile in the atlas.
## Simple mode asks for the pieces rising right and flips them for the rest.

signal roles_changed

const SlopeTerrain := preload("res://addons/better-tile-editor/SlopeTerrain.gd")
const RULES_TEXT := "Adds the rules that let peaks, valleys and the ground under a slope pick the right tiles. Undo takes them back."
const TILE_VIEW := preload("res://addons/better-tile-editor/editor/TileView.gd")
const GUIDE := preload("res://addons/better-tile-editor/editor/SlopeGuide.gd")
const MIN_ZOOM_SETTING := "editor/better_terrain/min_zoom_amount"
const MAX_ZOOM_SETTING := "editor/better_terrain/max_zoom_amount"
const CARD := 44

# [title, slots, optional]
const SIMPLE_SECTIONS := [
	["Ground", ["ground"], false],
	["Ground edges, left side (the right side is flipped)", ["ground:tl", "ground:t", "ground:l", "ground:bl", "ground:b"], false],
	["Inner corners, left side", ["ground:itl", "ground:ibl"], true],
	["Floor rising right", ["steep_tl", "g1_tl", "g2_tl"], false],
	["Ground under it", ["arrow:steep_tl", "arrow:g1_tl", "arrow:g2_tl"], false],
	["Thin diagonal, top and underside", ["thin:steep_tl", "thin:g1_tl", "thin:g2_tl", "thin:steep_br", "thin:g1_br", "thin:g2_br"], true],
]
const ADVANCED_SECTIONS := [
	["Ground", ["ground"], false],
	["Ground edges and corners", ["ground:tl", "ground:t", "ground:tr", "ground:l", "ground:r", "ground:bl", "ground:b", "ground:br"], false],
	["Inner corners", ["ground:itl", "ground:itr", "ground:ibl", "ground:ibr"], true],
	["Steep", ["steep_tl", "steep_tr", "steep_bl", "steep_br"], false],
	["Gentle, low half", ["g1_tl", "g1_tr", "g1_bl", "g1_br"], false],
	["Gentle, high half", ["g2_tl", "g2_tr", "g2_bl", "g2_br"], false],
	["Ground under or over each slope", ["arrow:steep_tl", "arrow:steep_tr", "arrow:steep_bl", "arrow:steep_br",
		"arrow:g1_tl", "arrow:g1_tr", "arrow:g1_bl", "arrow:g1_br", "arrow:g2_tl", "arrow:g2_tr", "arrow:g2_bl", "arrow:g2_br"], false],
	["Thin diagonals", ["thin:steep_tl", "thin:steep_tr", "thin:steep_bl", "thin:steep_br", "thin:g1_tl", "thin:g1_tr",
		"thin:g1_bl", "thin:g1_br", "thin:g2_tl", "thin:g2_tr", "thin:g2_bl", "thin:g2_br"], true],
]
const SHORT := {"steep": "S", "g1": "G1", "g2": "G2"}

var tileset: TileSet
var undo_manager: EditorUndoRedoManager
var dock: Node

var _sample := {}
var _tiles := {}
var _layer: TileMapLayer
var _selected := "ground"
var _hover_rect := Rect2()
var _panning := false
var _cards: VBoxContainer
var _card_buttons := {}
var _cards_mode := ""
var _preview: Control
var _preview_lo := Vector2i.ZERO
var _preview_side := 1.0
var _preview_hover := Vector2i(1 << 20, 0)
var _preview_clicked := Vector2i(1 << 20, 0)
var _preview_info: Label
var _palette: Control
var _pick: Control
var _slot_label: Label
var _picking := false
var _banner: PanelContainer
var _banner_label: Label
var _guide: Window
var _message: Label
var _status: Label
var _rules: Button
var _simple: Button
var _advanced: Button
var _ground_choice: OptionButton


func open(ts: TileSet, undo: EditorUndoRedoManager, owner_dock: Node) -> void:
	tileset = ts
	undo_manager = undo
	dock = owner_dock
	if _cards == null:
		_build()
	# Pin the mode now; filling in pieces would otherwise switch it to advanced
	if not tileset.has_meta(SlopeTerrain.MODE_META):
		tileset.set_meta(SlopeTerrain.MODE_META, SlopeTerrain.mode(tileset))
	var found_now := SlopeTerrain.roles(tileset)
	var chosen: int = dock.selected_entry
	if not found_now.has("ground") and chosen >= 0 and not chosen in found_now.values() \
			and BetterTerrain.get_terrain(tileset, chosen).type == BetterTerrain.TerrainType.MATCH_TILES:
		found_now.ground = chosen
		SlopeTerrain.save_roles(tileset, found_now)
	# Rules get lost when tiles are re-picked, so a complete set gets them back here
	_apply_rules()
	_sample = SlopeTerrain.sample()
	_palette.refresh_tileset(tileset)
	_palette._on_zoom_value_changed(_clamp_zoom(2.0))
	_message.text = ""
	var found := SlopeTerrain.roles(tileset)
	if not found.has("ground") and found.size() > 0:
		_message.text = "%d slope pieces are left from an earlier set-up (their terrains are hidden in the list). " % found.size() \
			+ "Pick Ground to go on with them, or Clear slopes to start over."
	_refresh()
	var missing := _next_missing()
	_select(missing, _tiles.get(missing, {}).is_empty())
	show()


func close() -> void:
	hide()
	var content := dock.get_node_or_null("VBox") as Control
	if content != null:
		content.show()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", EditorInterface.get_editor_theme().get_stylebox("panel", "Panel"))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)

	var top := HBoxContainer.new()
	column.add_child(top)
	var title := Label.new()
	title.text = "Slopes"
	title.add_theme_font_size_override("font_size", 16)
	top.add_child(title)
	var group := ButtonGroup.new()
	_simple = Button.new()
	_simple.text = "Simple"
	_simple.tooltip_text = "Pick the pieces rising right; the other directions and the ceilings are them flipped."
	_advanced = Button.new()
	_advanced.text = "Advanced"
	_advanced.tooltip_text = "Pick every piece yourself."
	for b in [_simple, _advanced]:
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		top.add_child(b)
	_simple.pressed.connect(_set_mode.bind("simple"))
	_advanced.pressed.connect(_set_mode.bind("advanced"))
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.clip_text = true
	top.add_child(_status)
	_rules = Button.new()
	_rules.text = "Add slope rules"
	_rules.tooltip_text = RULES_TEXT
	_rules.pressed.connect(_on_rules_pressed)
	top.add_child(_rules)
	var clear := Button.new()
	clear.text = "Clear slopes"
	clear.tooltip_text = "Take every slope piece off its tile and remove the slope terrains. Ground stays as it is."
	clear.pressed.connect(_on_clear_pressed)
	top.add_child(clear)
	top.add_child(_help_button())
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	top.add_child(close_button)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var cards_scroll := ScrollContainer.new()
	cards_scroll.custom_minimum_size = Vector2(250, 120)
	cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(cards_scroll)
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_scroll.add_child(_cards)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.size_flags_stretch_ratio = 2.0
	body.add_child(middle)
	_slot_label = Label.new()
	_slot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	middle.add_child(_slot_label)
	_banner = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.36, 0.29, 0.06)
	box.border_color = Color(1, 0.85, 0.2)
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(6)
	_banner.add_theme_stylebox_override("panel", box)
	var banner_row := HBoxContainer.new()
	_banner.add_child(banner_row)
	_banner_label = Label.new()
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner_label.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	banner_row.add_child(_banner_label)
	banner_row.add_child(_help_button())
	middle.add_child(_banner)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(200, 100)
	middle.add_child(scroll)
	scroll.gui_input.connect(func(event: InputEvent) -> void:
		if _picking and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_log("click beside the atlas at %s" % event.position)
			_message.text = "That spot has no tile. Click on a tile of the atlas.")
	_palette = TILE_VIEW.new()
	_palette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_palette.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_palette.show_terrain_marks = false
	scroll.add_child(_palette)
	_palette.change_zoom_level.connect(func(value: float) -> void: _palette._on_zoom_value_changed(_clamp_zoom(value)))
	_pick = Control.new()
	_pick.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pick.mouse_filter = Control.MOUSE_FILTER_STOP
	_pick.gui_input.connect(_atlas_input)
	_pick.draw.connect(_draw_atlas)
	_palette.add_child(_pick)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", Color(1, 0.75, 0.4))
	middle.add_child(_message)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var preview_title := Label.new()
	preview_title.text = "Preview, as the slope tool paints it. Click a cell to pick its piece."
	right.add_child(preview_title)
	var example := Button.new()
	example.text = "Create and set example slope map"
	example.tooltip_text = "Draws this preview as a new atlas at your tile size, every piece where it is here,\nand sets the selected terrain up with it as the slopes' ground. Undo takes it all back."
	example.pressed.connect(_on_example_pressed)
	right.add_child(example)
	# Above the preview so it never covers a cell
	_preview_info = Label.new()
	_preview_info.clip_text = true
	_preview_info.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	_preview_info.text = " "
	right.add_child(_preview_info)
	_preview = Control.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(200, 100)
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_preview.draw.connect(_draw_preview)
	_preview.resized.connect(_preview.queue_redraw)
	_preview.gui_input.connect(_preview_input)
	right.add_child(_preview)


func _help_button() -> Button:
	var help := Button.new()
	help.text = "?"
	help.tooltip_text = "A step-by-step guide to what each piece is, with the example tiles."
	help.focus_mode = Control.FOCUS_NONE
	help.pressed.connect(_open_guide)
	return help


func _open_guide() -> void:
	if _guide == null:
		_guide = GUIDE.new()
		add_child(_guide)
	_guide.open(_sections(), _mode() == "simple", _describe)


func _clamp_zoom(value: float) -> float:
	return clampf(value, ProjectSettings.get_setting(MIN_ZOOM_SETTING, 1.0), ProjectSettings.get_setting(MAX_ZOOM_SETTING, 8.0))


func _mode() -> String:
	return SlopeTerrain.mode(tileset)


func _sections() -> Array:
	return SIMPLE_SECTIONS if _mode() == "simple" else ADVANCED_SECTIONS


func _all_slots() -> Array:
	var out := []
	for section in _sections():
		out.append_array(section[1])
	return out


func _optional(slot: String) -> bool:
	return slot.begins_with("thin:") or slot.begins_with("ground:i")


func _next_missing() -> String:
	for slot in _all_slots():
		if not _optional(slot) and _tiles.get(slot, {}).is_empty():
			return slot
	return _selected if _selected in _all_slots() else "ground"


func _refresh() -> void:
	_tiles.clear()
	for slot in ADVANCED_SECTIONS.map(func(s): return s[1]).reduce(func(a, b): return a + b, []):
		_tiles[slot] = SlopeTerrain.slot_tile(BetterTerrain, tileset, slot)
	(_simple if _mode() == "simple" else _advanced).set_pressed_no_signal(true)
	# Rebuild only on mode change: a card created under the mouse ignores clicks until it moves
	if _cards_mode != _mode():
		_build_cards()
	for slot in _card_buttons:
		_card_buttons[slot].queue_redraw()
	var found := SlopeTerrain.roles(tileset)
	var needed := _all_slots().filter(func(slot): return not _optional(slot))
	var done := needed.filter(func(slot): return not _tiles[slot].is_empty()).size()
	var is_ready := SlopeTerrain.is_complete(found)
	_status.text = "%d of %d pieces  ·  %s" % [done, needed.size(), "the slope tool is ready" if is_ready else "the slope tool shows once every piece has a tile"]
	if found.has("ground") and not SlopeTerrain.has_edges(BetterTerrain, tileset, found.ground):
		_status.text += "  ·  Ground has no edge tiles yet: set its edges and corners as for any terrain"
	_rules.disabled = not is_ready
	_sync_ground_choice(found)
	_slot_label.text = _describe(_selected)
	_render(found)
	_preview.queue_redraw()
	_pick.queue_redraw()


func _build_cards() -> void:
	_cards_mode = _mode()
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	_card_buttons.clear()
	for section in _sections():
		var label := Label.new()
		label.text = section[0] + ("  (optional)" if section[2] else "")
		label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.76))
		_cards.add_child(label)
		var row := HFlowContainer.new()
		_cards.add_child(row)
		if section[1] == ["ground"]:
			_ground_choice = OptionButton.new()
			_ground_choice.focus_mode = Control.FOCUS_NONE
			_ground_choice.tooltip_text = "The terrain the slopes belong to, with its own edges and corners. Any Match Tiles terrain can be it."
			_ground_choice.item_selected.connect(func(item: int) -> void: _choose_ground(_ground_choice.get_item_id(item)))
			_cards.add_child(_ground_choice)
			_cards.move_child(_ground_choice, label.get_index() + 1)
		for slot in section[1]:
			# Not a toggle, so clicking the selected card again still starts picking
			var card := Button.new()
			card.focus_mode = Control.FOCUS_NONE
			card.custom_minimum_size = Vector2(CARD, CARD) * EditorInterface.get_editor_scale()
			card.tooltip_text = _describe(slot)
			card.pressed.connect(func() -> void:
				_log("card " + slot)
				_select(slot, true))
			card.draw.connect(_draw_card.bind(card, slot))
			row.add_child(card)
			_card_buttons[slot] = card
	if _mode() == "simple":
		var note := Label.new()
		note.text = "Rising left and the ceilings are these pieces flipped."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
		_cards.add_child(note)


func _sync_ground_choice(found: Dictionary) -> void:
	if _ground_choice == null:
		return
	_ground_choice.clear()
	for i in SlopeTerrain.ground_choices(BetterTerrain, tileset):
		_ground_choice.add_item("Terrain: " + String(BetterTerrain.get_terrain(tileset, i).name), i)
	if not found.has("ground"):
		_ground_choice.add_item("A new terrain, made with the first tile", -1)
	_ground_choice.select(_ground_choice.get_item_index(found.get("ground", -1)))


func _choose_ground(index: int) -> void:
	if index < 0 or index == SlopeTerrain.roles(tileset).get("ground", -100):
		return
	var before := _snapshot()
	SlopeTerrain.set_ground(BetterTerrain, tileset, index)
	_apply_rules()
	_message.text = "Ground is now the terrain %s." % BetterTerrain.get_terrain(tileset, index).name
	_commit("Choose the slopes' ground", before)


func _log(what: String) -> void:
	print("[Slopes] ", what)


func _select(slot: String, picking := false) -> void:
	_log("select %s picking=%s" % [slot, picking])
	_selected = slot
	_picking = picking
	for s in _card_buttons:
		_card_buttons[s].queue_redraw()
	_slot_label.text = _describe(slot)
	_slot_label.visible = not picking
	_banner.visible = picking
	_banner_label.text = "Pick the tile for:  %s\nClick it in the atlas below.   Esc or right-click cancels." % _describe(slot).trim_suffix(".")
	if not picking:
		_slot_label.text += "\nClick a piece on the left to pick its tile, or a tile below to see its piece."
	_pick.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if picking else Control.CURSOR_ARROW
	_pick.queue_redraw()
	_preview.queue_redraw()


func _input(event: InputEvent) -> void:
	if visible and _picking and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_select(_selected, false)


func _describe(slot: String) -> String:
	if slot == "ground":
		return "Ground: the tile for plain ground, the solid block inside the land."
	if slot.begins_with("ground:"):
		return "Ground, %s." % SlopeTerrain.EDGE_LABELS[slot.get_slice(":", 1)]
	var role := slot.get_slice(":", slot.get_slice_count(":") - 1)
	var what: String = SlopeTerrain.ROLE_LABELS[role]
	if slot.begins_with("arrow:"):
		return "Ground %s this slope: %s." % ["under" if role.ends_with("_tl") or role.ends_with("_tr") else "over", what.to_lower()]
	if slot.begins_with("thin:"):
		return "Thin diagonal, %s." % what.to_lower()
	return what + "."


func _card_text(slot: String) -> String:
	if slot == "ground":
		return "G"
	if slot.begins_with("ground:"):
		return "G" + slot.get_slice(":", 1).to_upper()
	var role := slot.get_slice(":", slot.get_slice_count(":") - 1)
	return SHORT[role.get_slice("_", 0)] + role.get_slice("_", 1).to_upper()


func _draw_card(card: Button, slot: String) -> void:
	var inner := Rect2(Vector2(4, 4), card.size - Vector2(8, 8))
	var picked: Dictionary = _tiles.get(slot, {})
	if picked.is_empty():
		var shape := Transform2D(0.0, inner.size, 0.0, inner.position) * SlopeTerrain.blueprint(slot)
		card.draw_colored_polygon(shape, Color(0.45, 0.7, 1.0, 0.25))
		card.draw_string(card.get_theme_default_font(), inner.position + Vector2(1, 11), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(0.6, 0.62, 0.66) if _optional(slot) else Color(1, 0.85, 0.5))
	else:
		_draw_tile(card, inner, picked.source, picked.coord, picked.get("alt", 0))
	card.draw_string(card.get_theme_default_font(), Vector2(3, card.size.y - 3), _card_text(slot), HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
		Color(1, 1, 1, 0.8))
	if slot == _selected:
		card.draw_rect(Rect2(Vector2.ZERO, card.size), Color(1, 0.85, 0.2), false, 3.0 if _picking else 2.0)


func _draw_tile(canvas: CanvasItem, rect: Rect2, source_id: int, coord: Vector2i, alt: int) -> void:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	if src == null or not src.has_alternative_tile(coord, alt):
		return
	var td := src.get_tile_data(coord, alt)
	var flip := Vector2(-1.0 if td.flip_h else 1.0, -1.0 if td.flip_v else 1.0)
	canvas.draw_set_transform(rect.get_center(), 0.0, flip)
	canvas.draw_texture_rect_region(src.texture, Rect2(-rect.size / 2.0, rect.size), src.get_tile_texture_region(coord))
	canvas.draw_set_transform(Vector2.ZERO)


# Painted on a layer outside the tree so the real matching picks the tiles
func _render(found: Dictionary) -> void:
	if _layer == null:
		_layer = TileMapLayer.new()
	_layer.tile_set = tileset
	_layer.clear()
	var painted := []
	for c in _sample:
		var slot: String = _sample[c]
		var role := "ground" if slot == "ground" or slot.begins_with("arrow:") else slot.get_slice(":", slot.get_slice_count(":") - 1)
		if found.has(role):
			BetterTerrain.set_cell(_layer, c, found[role])
			painted.append(c)
	BetterTerrain.update_terrain_cells(_layer, painted)


func _draw_preview() -> void:
	_preview.draw_rect(Rect2(Vector2.ZERO, _preview.size), Color(0.13, 0.14, 0.17))
	if tileset == null or _sample.is_empty():
		return
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for c in _sample:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var cells := Vector2(hi - lo + Vector2i.ONE)
	var side := maxf(minf(_preview.size.x / cells.x, _preview.size.y / cells.y), 1.0)
	_preview_lo = lo
	_preview_side = side
	for c in _sample:
		var rect := Rect2(Vector2(c - lo) * side, Vector2(side, side))
		# Missing pieces show their outline, not whatever the matching substitutes
		var piece := _preview_slot(c)
		var set_up: bool = not piece.is_empty() and not _tiles.get(piece, {}).is_empty()
		if set_up and _layer.get_cell_source_id(c) >= 0:
			_draw_tile(_preview, rect, _layer.get_cell_source_id(c), _layer.get_cell_atlas_coords(c), _layer.get_cell_alternative_tile(c))
		else:
			var shape := Transform2D(0.0, rect.size, 0.0, rect.position) * SlopeTerrain.blueprint(_sample[c])
			_preview.draw_colored_polygon(shape, Color(1.0, 0.3, 0.25, 0.35))
			var outline := shape.duplicate()
			outline.append(shape[0])
			_preview.draw_polyline(outline, Color(1.0, 0.45, 0.4, 0.8), 1.0)
	# Hover and click coords, to name a cell when something looks wrong
	var lines := []
	for pair in [["mouse", _preview_hover], ["clicked", _preview_clicked]]:
		var c: Vector2i = pair[1]
		if _sample.has(c):
			var tile := "no tile yet" if _layer.get_cell_source_id(c) < 0 or _tiles.get(_preview_slot(c), {}).is_empty() else "tile %s%s" % [_layer.get_cell_atlas_coords(c),
				" flipped" if _layer.get_cell_alternative_tile(c) >= SlopeTerrain.TURN_ID_BASE else ""]
			lines.append("%s %s: %s, %s" % [pair[0], c - lo, _describe(_preview_slot(c)).trim_suffix(".").to_lower(), tile])
	var info := "   ·   ".join(lines) if not lines.is_empty() else " "
	if _preview_info.text != info:
		_preview_info.set_deferred("text", info)
	for c in _sample:
		var rect := Rect2(Vector2(c - lo) * side, Vector2(side, side))
		if _preview_slot(c) == _selected:
			_preview.draw_rect(rect, Color(1, 0.85, 0.2), false, 2.0)
		elif c == _preview_hover:
			_preview.draw_rect(rect, Color(1, 1, 1, 0.7), false, 1.0)


# In simple mode a flipped piece maps back to the card it comes from
func _preview_slot(c: Vector2i) -> String:
	var slot: String = _sample.get(c, "")
	if slot == "ground":
		slot = SlopeTerrain.edge_of(_sample, c)
	if not slot.is_empty() and not slot in _all_slots() and SlopeTerrain.TURNS.has(slot):
		slot = SlopeTerrain.TURNS[slot][0]
	return slot if slot in _all_slots() else ""


func _preview_input(event: InputEvent) -> void:
	if not (event is InputEventMouse):
		return
	var c := _preview_lo + Vector2i((event.position / _preview_side).floor())
	if event is InputEventMouseMotion:
		var hover := c if _sample.has(c) else Vector2i(1 << 20, 0)
		if hover != _preview_hover:
			_preview_hover = hover
			_preview.tooltip_text = _describe(_preview_slot(c)) if not _preview_slot(c).is_empty() else ""
			_preview.queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var slot := _preview_slot(c)
		_preview_clicked = c
		_log("preview click %s -> %s" % [c - _preview_lo, slot])
		_preview.queue_redraw()
		if not slot.is_empty():
			_preview.accept_event()
			_select(slot, true)
			_preview.queue_redraw()


func _tile_rect(source_id: int, coord: Vector2i) -> Rect2:
	var src := tileset.get_source(source_id) as TileSetAtlasSource if tileset.has_source(source_id) else null
	if src == null or not src.has_tile(coord):
		return Rect2()
	return _palette.atlas_rect(source_id, Rect2(src.get_tile_texture_region(coord)))


func _draw_atlas() -> void:
	var labels := {}
	for slot in _tiles:
		var t: Dictionary = _tiles[slot]
		if t.is_empty() or int(t.get("alt", 0)) != 0 or not slot in _all_slots():
			continue
		var key := Vector3i(t.source, t.coord.x, t.coord.y)
		labels[key] = labels.get(key, []) + [_card_text(slot)]
	var font := _pick.get_theme_default_font()
	for key in labels:
		var r := _tile_rect(key.x, Vector2i(key.y, key.z))
		_pick.draw_rect(r, Color(0.3, 0.6, 1.0, 0.3))
		_pick.draw_rect(r, Color(0.3, 0.6, 1.0, 0.8), false, 1.0)
		_pick.draw_string(font, r.position + Vector2(2, 10), " ".join(labels[key]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 2, 9,
			Color(1, 1, 1, 0.95))
	var mine: Dictionary = _tiles.get(_selected, {})
	if not mine.is_empty() and int(mine.get("alt", 0)) == 0:
		var r := _tile_rect(mine.source, mine.coord)
		_pick.draw_rect(r, Color(1, 0.85, 0.2, 0.15))
		_pick.draw_rect(r, Color(1, 0.85, 0.2), false, 3.0)
	if _hover_rect.size.x > 0.0:
		_pick.draw_rect(_hover_rect, Color(1, 0.85, 0.2) if _picking else Color(1, 1, 1, 0.8), false, 2.0)
	if _picking:
		_pick.draw_rect(Rect2(Vector2.ZERO, _pick.size), Color(1, 0.85, 0.2), false, 3.0)


func _atlas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_log("atlas button %d pressed=%s at %s picking=%s part=%s" % [event.button_index, event.pressed, event.position, _picking,
			_palette.tile_part_from_position(Vector2i(event.position))])
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_pick.accept_event()
		_palette._zoom_at_cursor(event.position, 1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1)
		_pick.queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_pick.accept_event()
		_panning = event.pressed
	elif event is InputEventMouseMotion and _panning:
		_pick.accept_event()
		var scroll := _palette.get_parent() as ScrollContainer
		scroll.scroll_horizontal -= int(event.relative.x)
		scroll.scroll_vertical -= int(event.relative.y)
	elif event is InputEventMouseMotion:
		var rect: Rect2 = _palette.tile_rect_from_position(Vector2i(event.position))
		if rect != _hover_rect:
			_hover_rect = rect
			_pick.queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and _picking:
		_pick.accept_event()
		_select(_selected, false)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var part: Dictionary = _palette.tile_part_from_position(Vector2i(event.position))
		if not part.get("valid", false):
			if _picking:
				_message.text = "That spot has no tile. Click on a tile of the atlas."
			return
		if _picking:
			# Deferred: rebuilding mid-click left the editor ignoring the mouse
			_pick.accept_event()
			_assign.call_deferred(int(part.source_id), part.coord)
			return
		for slot in _all_slots():
			var t: Dictionary = _tiles.get(slot, {})
			if not t.is_empty() and t.source == int(part.source_id) and t.coord == part.coord and int(t.get("alt", 0)) == 0:
				_select(slot)
				return


# Tiles stored by position, not reference: flipped pieces get removed and recreated
func _snapshot() -> Array:
	var metas := {}
	for s in tileset.get_source_count():
		var src := tileset.get_source(tileset.get_source_id(s)) as TileSetAtlasSource
		if src == null:
			continue
		for i in src.get_tiles_count():
			var coord := src.get_tile_id(i)
			for a in src.get_alternative_tiles_count(coord):
				var alt := src.get_alternative_tile_id(coord, a)
				var td := src.get_tile_data(coord, alt)
				metas[[tileset.get_source_id(s), coord, alt]] = td.get_meta(BetterTerrain.TERRAIN_META).duplicate(true) \
					if td.has_meta(BetterTerrain.TERRAIN_META) else null
	var saved := []
	for key in [BetterTerrain.TERRAIN_META, SlopeTerrain.META, SlopeTerrain.TAKEN_META, SlopeTerrain.MODE_META, SlopeTerrain.GROUND_PICK_META]:
		# get_meta with a null default still complains about a missing key
		var value = tileset.get_meta(key) if tileset.has_meta(key) else null
		saved.append(value.duplicate(true) if value is Dictionary or value is Array else value)
	return [metas, saved]


func _restore(snapshot: Array) -> void:
	var keys := [BetterTerrain.TERRAIN_META, SlopeTerrain.META, SlopeTerrain.TAKEN_META, SlopeTerrain.MODE_META, SlopeTerrain.GROUND_PICK_META]
	for i in keys.size():
		var value = snapshot[1][i]
		if value == null:
			tileset.remove_meta(keys[i])
		else:
			tileset.set_meta(keys[i], value.duplicate(true) if value is Dictionary or value is Array else value)
	for key in snapshot[0]:
		var td: TileData = SlopeTerrain._tile_data(tileset, key[0], key[1], key[2])
		if td == null:
			continue
		if snapshot[0][key] == null:
			td.remove_meta(BetterTerrain.TERRAIN_META)
		else:
			td.set_meta(BetterTerrain.TERRAIN_META, snapshot[0][key].duplicate(true))
	# Flipped pieces are alternative tiles, regenerated from their sources
	if _mode() == "simple":
		SlopeTerrain.turn(BetterTerrain, tileset)
	_changed()


func _commit(label: String, before: Array) -> void:
	var after := _snapshot()
	undo_manager.create_action(label, UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(self, &"_restore", after)
	undo_manager.add_undo_method(self, &"_restore", before)
	undo_manager.commit_action(false)
	dock.rebuild_terrain_list()
	_changed()


func _assign(source_id: int, tile: Vector2i) -> void:
	var before := _snapshot()
	var slot := _selected
	_log("assign %s <- source %d tile %s (had %s)" % [slot, source_id, tile, _tiles.get(slot, {})])
	var mine: Dictionary = _tiles.get(slot, {})
	# Swap: a piece that already had this tile gets this piece's old one
	var other := ""
	for s in _tiles:
		var t: Dictionary = _tiles[s]
		if s != slot and not t.is_empty() and t.source == source_id and t.coord == tile and int(t.get("alt", 0)) == 0:
			other = s
	var error: String = SlopeTerrain.assign(BetterTerrain, tileset, slot, source_id, tile)
	_log("  result '%s', now %s" % [error, SlopeTerrain.slot_tile(BetterTerrain, tileset, slot)])
	if not error.is_empty():
		_message.text = error
		return
	_message.text = "Set: %s." % _describe(slot).trim_suffix(".").to_lower()
	if slot == "ground":
		_message.text = "Plain ground is drawn with this tile now."
	if slot == "ground" and not other.is_empty() and other != "ground":
		_message.text += " It was %s, which needs another tile now." % _describe(other).trim_suffix(".").to_lower()
	if not other.is_empty() and other != "ground" and slot != "ground" and other in _all_slots():
		if not mine.is_empty() and int(mine.get("alt", 0)) == 0:
			SlopeTerrain.assign(BetterTerrain, tileset, other, mine.source, mine.coord)
			_message.text = "Swapped with %s." % _describe(other).trim_suffix(".").to_lower()
		else:
			_message.text = "Taken from %s, which needs another tile now." % _describe(other).trim_suffix(".").to_lower()
	if _mode() == "simple":
		SlopeTerrain.turn(BetterTerrain, tileset)
	_apply_rules()
	_commit("Set slope piece", before)
	var next := _next_missing()
	_select(next, _tiles.get(next, {}).is_empty())


func _set_mode(value: String, confirmed := false) -> void:
	if tileset == null or value == _mode():
		return
	var replaced: Array = SlopeTerrain.hand_made(BetterTerrain, tileset) if value == "simple" else []
	if not replaced.is_empty() and not confirmed:
		(_advanced if _mode() == "advanced" else _simple).set_pressed_no_signal(true)
		var ask := ConfirmationDialog.new()
		ask.dialog_text = ("Simple mode draws rising left and the ceilings by flipping your rising-right pieces.\n"
			+ "%d pieces you set to tiles of their own will be replaced by flips, and their tiles freed.\n"
			+ "You can undo this.") % replaced.size()
		ask.ok_button_text = "Replace them"
		ask.confirmed.connect(_set_mode.bind(value, true))
		ask.visibility_changed.connect(func() -> void:
			if not ask.visible:
				ask.queue_free())
		add_child(ask)
		ask.popup_centered()
		return
	var before := _snapshot()
	SlopeTerrain.set_mode(BetterTerrain, tileset, value)
	_apply_rules()
	_message.text = "The other directions and the ceilings are now these pieces flipped." if value == "simple" \
		else "Every piece can be picked now; the flipped ones stay until you change them."
	_commit("Slope set-up mode", before)
	_select(_next_missing(), false)


# Rules fix the ground under slopes, peaks and valleys; applied as soon as the set is complete
func _apply_rules() -> void:
	if SlopeTerrain.is_complete(SlopeTerrain.roles(tileset)):
		SlopeTerrain.add_rules(BetterTerrain, tileset)


func _changed() -> void:
	BetterTerrain._purge_cache(tileset)
	tileset.emit_changed()
	_palette.refresh_tileset(tileset)
	roles_changed.emit()
	if visible:
		_refresh()


func _on_clear_pressed() -> void:
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Take every slope piece off its tile and remove the slope terrains?\nGround stays as it is. You can undo this."
	confirm.confirmed.connect(func() -> void:
		var before := _snapshot()
		SlopeTerrain.clear(BetterTerrain, tileset)
		_commit("Clear slopes", before))
	confirm.visibility_changed.connect(func() -> void:
		if not confirm.visible:
			confirm.queue_free())
	add_child(confirm)
	confirm.popup_centered()


func _example_ground() -> int:
	var found := SlopeTerrain.roles(tileset)
	var chosen: int = dock.selected_entry
	if chosen >= 0 and chosen in SlopeTerrain.ground_choices(BetterTerrain, tileset):
		return chosen
	return found.get("ground", -1)


func _on_example_pressed() -> void:
	var before: Array = SlopeTerrain.snapshot(tileset)
	var ground := _example_ground()
	var id: int = SlopeTerrain.make_example(BetterTerrain, tileset, ground)
	undo_manager.create_action("Create example slope map", UndoRedo.MERGE_DISABLE, tileset)
	var box := [id]
	undo_manager.add_do_method(self, &"_redo_example", box, ground)
	undo_manager.add_undo_method(self, &"_undo_example", box, before)
	undo_manager.commit_action(false)
	var ground_name := String(BetterTerrain.get_terrain(tileset, SlopeTerrain.roles(tileset).ground).name)
	_after_example("Example atlas added as source %d; %s is set up with it." % [id, ground_name])


# Redo recreates the atlas; keep its new id for the next undo
func _redo_example(id_box: Array, ground: int) -> void:
	id_box[0] = SlopeTerrain.make_example(BetterTerrain, tileset, ground)
	_after_example("")


func _undo_example(id_box: Array, before: Array) -> void:
	if tileset.has_source(id_box[0]):
		tileset.remove_source(id_box[0])
	SlopeTerrain.restore(BetterTerrain, tileset, before)
	_after_example("")


func _after_example(text: String) -> void:
	_palette.refresh_tileset(tileset)
	dock.rebuild_terrain_list()
	_changed()
	_message.text = text
	_select(_next_missing(), false)


func _on_rules_pressed() -> void:
	undo_manager.create_action("Add slope rules", UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(dock, &"_add_slope_rules")
	undo_manager.add_undo_method(dock, &"_restore_tile_metas", dock._tile_metas())
	undo_manager.add_do_method(self, &"_changed")
	undo_manager.add_undo_method(self, &"_changed")
	undo_manager.commit_action()
