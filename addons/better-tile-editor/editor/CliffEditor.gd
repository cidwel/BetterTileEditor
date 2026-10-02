@tool
extends Window

signal config_changed
signal clear_requested(ts: TileSet, name: String)

const CliffData := preload("res://addons/better-tile-editor/CliffData.gd")
const CliffAutoassign := preload("res://addons/better-tile-editor/editor/CliffAutoassign.gd")
const CliffPattern := preload("res://addons/better-tile-editor/CliffPattern.gd")
const Chrome := preload("res://addons/better-tile-editor/editor/Chrome.gd")

const PREVIEW_ZOOM_DEFAULT := 3.0
const SLOT_PX := 38
const SIMPLE_PX := 32
const TILE_PX := 16

var tile_set: TileSet
var terrain_name := ""
var terrain_index := -1

var _cfg := {}
var _selected := ""
var _slot_buttons := {}

var _bands: VBoxContainer
## Narrow enough that the slot table and the preview's bar both fit the window.
const CASES_PER_BAND := 6
var _preview_layer: TileMapLayer
var _preview_faces: TileMapLayer
var _preview_overlay: Control
var _missing_cells := []
var _borrowed_cells := []
var _row_labels := []
const KIND_SIMPLE := 0
const KIND_ADVANCED := 1
const KIND_PATTERN := 2
var _kind := KIND_SIMPLE
var _kind_pick: OptionButton
var _simple_mode := true
var _pattern_armed := "body"
var _pattern_box: VBoxContainer
var _pattern_rows := {}
var _col_off: SpinBox
var _row_off: SpinBox
var _offset_note: Label
var _rows_up: CheckBox
var _clear_slot_btn: Button
var _pattern_syncing := false
var _piece_by_cell := {}
var _pattern_line := {}
## What the hover line says over each wall cell of the preview.
var _hover_text := {}
var _split: HSplitContainer
var _pane: VSplitContainer
var _left_scroll: ScrollContainer
var _left_box: VBoxContainer
var _auto_button: Button
var _auto_page: Control
## The face the preview shows while Autoassign's block is being picked; {} for the real one.
var _auto_cfg := {}
var _simple_grid: GridContainer
var _simple_buttons := {}
var _slot_dots := {}
var _slot_by_cell := {}
var _puffs := []
var _puff_tex: Texture2D
var _clock := 0.0
const PUFF_TIME := 0.5
const PUFF_COUNT := 6
const MAX_PUFF_CELLS := 40
const PUFF_LOBES := 2
var _bt = null
var _palette_view: Control
var _palette_pick: Control
const PALETTE_ZOOM := 2.0
const MIN_ZOOM_SETTING := "editor/better_terrain/min_zoom_amount"
const MAX_ZOOM_SETTING := "editor/better_terrain/max_zoom_amount"
var _panning := false
var _preview_zoom := PREVIEW_ZOOM_DEFAULT
var _show_narrow := false
var _narrow_check: CheckBox
var _bottom_check: CheckBox
var _fixture_pick: OptionButton
var _fixture_index := 0
var _mask := []
var _local_button: Button
var _inherit_menu: PopupMenu
var _pick_anchor := {}
var _mark_from := Vector2i(-9999, -9999)
var _mark_to := Vector2i(-9999, -9999)
var _marking := false
var _off_mode_from := Vector2i(-9999, -9999)
var _matrix_target := {}
var _matrix_mode := false
var _matrix_button: Button
var _pick_from := Vector2(-1, -1)
var _pick_at := Vector2(-1, -1)
var _inherit_names := []
var _preview_scroll: ScrollContainer
var _preview_panning := false
var _preview_pan := Vector2.ZERO
var _tex_cache := {}
var _preview: Control
var _status: RichTextLabel
var _info: LineEdit
var _last_cell := Vector2i(-9999, -9999)
var _last_plateau := {}
var _last_faces := {}

const BUILD_MIN_W := 40
const BUILD_MIN_H := 26
var _build_w := BUILD_MIN_W
var _build_h := BUILD_MIN_H
var _build_mode := false
var _built := {}
var _painting := 0          # 1 paints, -1 erases, 0 is idle
var _build_toggle: Button
var _save_shape_btn: Button
var _edit_shape_btn: Button
var _save_new_btn: Button
var _editing_shape := ""
var _in_use := {}
var _height_spin: SpinBox
var _more: MenuButton
var _shape_menu: PopupMenu
var _inherit_banner: HBoxContainer
var _inherit_label: Label
var _options: FoldableContainer
var _build_strip: Control
var _strip_label: Label
var _hover_label: Label
var _pattern_options: Control
const ANCHOR_LABEL := "Anchor the repeat to the ground"
enum { MORE_INHERIT = 10, MORE_LOCAL, MORE_COPY, MORE_CLEAR }
enum { SHAPE_NARROW = 20, SHAPE_DRAW, SHAPE_EDIT, SHAPE_CLEAR }


var initial_height := -1


func setup(ts: TileSet, index: int, cliff_name: String, height := -1) -> void:
	initial_height = height
	_bt = get_node_or_null("/root/BetterTerrain")
	if _bt == null:
		_bt = load("res://addons/better-tile-editor/BetterTerrain.gd").new()
	tile_set = ts
	terrain_index = index
	terrain_name = cliff_name
	_cfg = CliffData.config_of(ts, cliff_name)
	if CliffPattern.is_pattern(_cfg):
		_kind = KIND_PATTERN
		_simple_mode = false
	_migrate_orphan_slots(cliff_name)
	_puff_tex = _make_puff_texture()
	_refresh_mask()
	title = "Cliff face: %s" % cliff_name
	size = Vector2i(1200, 760)
	_build()
	if not tile_set.changed.is_connected(_on_tile_set_changed):
		tile_set.changed.connect(_on_tile_set_changed)
	_refresh()
	_fit_top_pane.call_deferred()


func _build() -> void:
	var split := HSplitContainer.new()
	Chrome.dress_split(split)
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(split)
	_split = split
	# The left side holds the slots and palette, or Autoassign's page while a block is picked;
	# the preview stays on the right and shows the face the block would give.
	var left_host := VBoxContainer.new()
	split.add_child(left_host)
	_auto_page = CliffAutoassign.new()
	_auto_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_auto_page.visible = false
	_auto_page.chosen.connect(_on_autoassign_chosen)
	_auto_page.canceled.connect(_close_autoassign)
	_auto_page.block_changed.connect(_on_autoassign_block)
	left_host.add_child(_auto_page)

	var pane := VSplitContainer.new()
	_pane = pane
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Chrome.dress_split(pane)
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_host.add_child(pane)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 160
	pane.add_child(scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	scroll.add_child(left)
	_left_scroll = scroll
	_left_box = left

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	left.add_child(bar)
	var face_label := Label.new()
	face_label.text = "Face"
	bar.add_child(face_label)
	_kind_pick = OptionButton.new()
	_kind_pick.add_item("Simple", KIND_SIMPLE)
	_kind_pick.add_item("Advanced", KIND_ADVANCED)
	_kind_pick.add_item("Pattern", KIND_PATTERN)
	_kind_pick.tooltip_text = ("Simple: 18 groups, one tile each.\nAdvanced: the same slots one by one.\n"
		+ "Pattern: 12 pieces cut from one block (switching keeps the slots for later).")
	_kind_pick.select(_kind)
	_kind_pick.item_selected.connect(_on_kind_picked)
	bar.add_child(_kind_pick)
	var height_label := Label.new()
	height_label.text = "Height"
	bar.add_child(height_label)
	_height_spin = SpinBox.new()
	_height_spin.min_value = 0
	_height_spin.max_value = 8
	_height_spin.value = initial_height if initial_height > 0 else int(_cfg.get("height", 2))
	_height_spin.tooltip_text = "How many rows tall the face is, in the preview and by default on the map."
	_height_spin.value_changed.connect(_on_height_changed)
	bar.add_child(_height_spin)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_more = MenuButton.new()
	_more.icon = EditorInterface.get_editor_theme().get_icon(&"GuiTabMenuHl", &"EditorIcons")
	_more.flat = true
	_more.tooltip_text = "More: inherit, copy slot info, clear the sheet"
	bar.add_child(_more)
	var more_menu := _more.get_popup()
	_inherit_menu = PopupMenu.new()
	_inherit_menu.id_pressed.connect(_on_inherit_chosen)
	more_menu.add_submenu_node_item("Inherit from", _inherit_menu, MORE_INHERIT)
	more_menu.add_item("Make local", MORE_LOCAL)
	more_menu.add_separator()
	more_menu.add_item("Copy slot info", MORE_COPY)
	more_menu.add_separator()
	more_menu.add_item("Clear the sheet…", MORE_CLEAR)
	more_menu.about_to_popup.connect(_sync_more_menu)
	more_menu.id_pressed.connect(_on_more_pressed)

	_inherit_banner = HBoxContainer.new()
	_inherit_label = Label.new()
	_inherit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inherit_label.add_theme_color_override("font_color", Color(0.62, 0.71, 0.78))
	_inherit_banner.add_child(_inherit_label)
	_local_button = Button.new()
	_local_button.text = "Make local"
	_local_button.tooltip_text = "Keep the inherited face as this terrain's own and stop following."
	_local_button.pressed.connect(_on_make_local)
	_inherit_banner.add_child(_local_button)
	left.add_child(_inherit_banner)

	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.custom_minimum_size.y = 24
	left.add_child(_status)
	_info = LineEdit.new()
	_info.visible = false
	left.add_child(_info)

	left.add_child(Chrome.rule())
	var auto_row := CenterContainer.new()
	left.add_child(auto_row)
	_auto_button = Button.new()
	_auto_button.text = "Autoassign from tilemap"
	_auto_button.icon = EditorInterface.get_editor_theme().get_icon(&"AutoPlay", &"EditorIcons")
	_auto_button.tooltip_text = "Pick the block of wall art in the tileset and fill every slot from it."
	_auto_button.pressed.connect(_open_autoassign)
	# Drawn in the editor's accent so it doesn't blend into the background.
	var accent: Color = EditorInterface.get_editor_settings().get_setting("interface/theme/accent_color")
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(accent, {&"normal": 0.22, &"hover": 0.36, &"pressed": 0.5, &"focus": 0.22}[state])
		sb.border_color = Color(accent, 0.9 if state != &"normal" else 0.7)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		_auto_button.add_theme_stylebox_override(state, sb)
	_auto_button.add_theme_color_override(&"font_color", Color.WHITE)
	_auto_button.add_theme_color_override(&"font_hover_color", Color.WHITE)
	_auto_button.add_theme_color_override(&"icon_normal_color", Color.WHITE)
	auto_row.add_child(_auto_button)
	_bands = VBoxContainer.new()
	_bands.add_theme_constant_override("separation", 10)
	left.add_child(_bands)
	_build_simple_grid(left)
	_build_pattern_box(left)
	_build_grid()

	_options = FoldableContainer.new()
	_options.title = "Options"
	_options.folded = true
	left.add_child(_options)
	var options_box := VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 6)
	_options.add_child(options_box)
	_bottom_check = CheckBox.new()
	_bottom_check.text = ANCHOR_LABEL
	_bottom_check.tooltip_text = ("Off: a slot's block repeats down from the top row, which keeps its own tile.\n"
		+ "On: it repeats up from above the ground, so every height ends the same at the bottom;\n"
		+ "an empty top slot then borrows the body's block. Only slots holding a block of tiles change.")
	_bottom_check.toggled.connect(_on_from_bottom_toggled)
	options_box.add_child(_bottom_check)
	_build_pattern_options(options_box)

	var palette_box := VBoxContainer.new()
	palette_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.add_child(palette_box)
	var pbar := HFlowContainer.new()
	palette_box.add_child(pbar)
	var plbl := Label.new()
	plbl.text = "Palette"
	pbar.add_child(plbl)
	_clear_slot_btn = Button.new()
	_clear_slot_btn.text = "Clear slot"
	_clear_slot_btn.tooltip_text = "Empty the selected slot (or right-click it). It then borrows a neighbour's tile, or draws nothing."
	_clear_slot_btn.focus_mode = Control.FOCUS_NONE
	_clear_slot_btn.pressed.connect(_on_clear_slot)
	pbar.add_child(_clear_slot_btn)

	var pscroll2 := ScrollContainer.new()
	pscroll2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pscroll2.custom_minimum_size.y = 200
	palette_box.add_child(pscroll2)
	Chrome.open_at(pane, 0.7)

	_palette_view = load("res://addons/better-tile-editor/editor/TileView.gd").new()
	_palette_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pscroll2.add_child(_palette_view)
	_palette_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_palette_view.refresh_tileset(tile_set)
	_palette_view._on_zoom_value_changed(PALETTE_ZOOM)
	# TileView emits zoom requests; the caller must clamp and apply them.
	_palette_view.change_zoom_level.connect(_on_palette_zoom_requested)

	_palette_pick = Control.new()
	_palette_pick.set_anchors_preset(Control.PRESET_FULL_RECT)
	_palette_pick.mouse_filter = Control.MOUSE_FILTER_STOP
	_palette_pick.gui_input.connect(_on_palette_input)
	_palette_pick.draw.connect(_draw_palette_selection)
	_palette_view.add_child(_palette_pick)

	var right := VBoxContainer.new()
	split.add_child(right)
	Chrome.open_at(split, 0.30)
	var preview_bar := _build_preview_bar()
	right.add_child(preview_bar)
	# The bar never gets cut: the split gives way on the left first.
	right.custom_minimum_size.x = preview_bar.get_combined_minimum_size().x
	_build_strip = _build_drawing_strip()
	right.add_child(_build_strip)

	var pscroll := ScrollContainer.new()
	pscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(pscroll)
	_preview = Control.new()
	# Keep the input overlay panel-sized so panning works outside the painted shape.
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_scroll = pscroll
	pscroll.add_child(_preview)

	_preview_layer = TileMapLayer.new()
	_preview_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_layer.tile_set = tile_set
	_preview.add_child(_preview_layer)

	_preview_faces = TileMapLayer.new()
	_preview_faces.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_faces.tile_set = tile_set
	_preview_faces.z_as_relative = true
	_preview_faces.z_index = -1
	_preview_layer.add_child(_preview_faces)

	_preview_overlay = Control.new()
	_preview_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_overlay.draw.connect(_draw_overlay)
	_preview_overlay.gui_input.connect(_on_preview_input)
	_preview_overlay.mouse_exited.connect(func(): _hover_label.text = "")
	_preview.add_child(_preview_overlay)

	_hover_label = Label.new()
	_hover_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_hover_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	right.add_child(_hover_label)

	_apply_preview_zoom()

	close_requested.connect(queue_free)


func _build_preview_bar() -> Control:
	var shape_bar := HBoxContainer.new()
	shape_bar.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = "Preview"
	shape_bar.add_child(label)
	_fixture_pick = OptionButton.new()
	var all_shapes := CliffData.shapes()
	for i in all_shapes.size():
		_fixture_pick.add_item(all_shapes[i].name, i)
	_fixture_pick.select(_fixture_index)
	_fixture_pick.item_selected.connect(func(i: int) -> void:
		_fixture_index = i
		_refresh_mask()
		_apply_preview_zoom()
		_refresh())
	shape_bar.add_child(_fixture_pick)
	_matrix_button = Button.new()
	_matrix_button.text = "Repeating block"
	_matrix_button.toggle_mode = true
	_matrix_button.focus_mode = Control.FOCUS_NONE
	_matrix_button.tooltip_text = ("Give several slots one block of tiles that repeats along the wall:\n"
		+ "drag over the wall in the preview, then click the block's top-left tile in the palette.")
	_matrix_button.toggled.connect(_on_matrix_mode_toggled)
	shape_bar.add_child(_matrix_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shape_bar.add_child(spacer)
	var shape_more := MenuButton.new()
	shape_more.icon = EditorInterface.get_editor_theme().get_icon(&"GuiTabMenuHl", &"EditorIcons")
	shape_more.flat = true
	shape_more.tooltip_text = "Preview shapes: narrow ones, draw or edit your own"
	shape_bar.add_child(shape_more)
	_shape_menu = shape_more.get_popup()
	_shape_menu.add_check_item("Show narrow shapes", SHAPE_NARROW)
	_shape_menu.set_item_tooltip(_shape_menu.get_item_index(SHAPE_NARROW),
		"Also preview a step one cell wide and a cell standing alone (single, l_plat_end, r_plat_end).")
	_shape_menu.add_separator()
	_shape_menu.add_item("Draw a shape", SHAPE_DRAW)
	_shape_menu.add_item("Edit this shape", SHAPE_EDIT)
	_shape_menu.add_item("Clear the drawing", SHAPE_CLEAR)
	_shape_menu.about_to_popup.connect(func():
		_shape_menu.set_item_checked(_shape_menu.get_item_index(SHAPE_NARROW), _show_narrow))
	_shape_menu.id_pressed.connect(_on_shape_menu)
	# The old switches stay as the state they always held; the menu drives them.
	_narrow_check = CheckBox.new()
	_narrow_check.visible = false
	_narrow_check.button_pressed = _show_narrow
	_narrow_check.toggled.connect(func(on: bool) -> void:
		_show_narrow = on
		_refresh_mask()
		_apply_preview_zoom()
		_refresh())
	shape_bar.add_child(_narrow_check)
	return shape_bar


## Drawing a shape gets a strip of its own: what it is doing and the ways out.
func _build_drawing_strip() -> Control:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	strip.visible = false
	_strip_label = Label.new()
	_strip_label.add_theme_color_override("font_color", Color(0.45, 0.7, 0.95))
	strip.add_child(_strip_label)
	_build_toggle = Button.new()
	_build_toggle.toggle_mode = true
	_build_toggle.visible = false
	_build_toggle.toggled.connect(func(on: bool) -> void:
		_build_mode = on
		_fixture_pick.disabled = on
		strip.visible = on
		_refresh_mask()
		_refresh())
	strip.add_child(_build_toggle)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(gap)
	_save_shape_btn = Button.new()
	_save_shape_btn.text = "Save as shape"
	_save_shape_btn.tooltip_text = "Add this drawing to the shape list."
	_save_shape_btn.pressed.connect(_on_save_shape_pressed)
	strip.add_child(_save_shape_btn)
	_save_new_btn = Button.new()
	_save_new_btn.text = "Save as new"
	_save_new_btn.visible = false
	_save_new_btn.tooltip_text = "Keep the shape you are editing and save the drawing under another name."
	_save_new_btn.pressed.connect(_ask_shape_name)
	strip.add_child(_save_new_btn)
	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.tooltip_text = "Wipe the drawing. The face is untouched."
	clear_btn.pressed.connect(_clear_canvas)
	strip.add_child(clear_btn)
	_edit_shape_btn = Button.new()
	_edit_shape_btn.text = "Done"
	_edit_shape_btn.tooltip_text = "Back to the shape list. The drawing is kept until cleared."
	_edit_shape_btn.pressed.connect(_finish_drawing)
	strip.add_child(_edit_shape_btn)
	return strip


func _build_grid() -> void:
	for ch in _bands.get_children():
		ch.queue_free()
	_slot_buttons.clear()
	_slot_dots.clear()
	_row_labels.clear()

	var start := 0
	while start < CliffData.CASES.size():
		var stop: int = mini(start + CASES_PER_BAND, CliffData.CASES.size())
		var chunk: Array = CliffData.CASES.slice(start, stop)
		var g := GridContainer.new()
		g.columns = chunk.size() + 1
		_bands.add_child(g)

		g.add_child(Control.new())
		for case_name in chunk:
			var h := Label.new()
			h.text = case_name
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			h.tooltip_text = _case_hint(case_name)
			g.add_child(h)

		for row in CliffData.ROWS:
			var rl := Label.new()
			rl.text = row
			rl.tooltip_text = _row_hint(row)
			g.add_child(rl)
			_row_labels.append({"row": row, "label": rl})
			for case_name in chunk:
				var b := Button.new()
				b.custom_minimum_size = Vector2(SLOT_PX, SLOT_PX)
				b.toggle_mode = true
				b.expand_icon = true
				b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				var key := CliffData.slot_key(row, case_name)
				b.pressed.connect(_on_slot_pressed.bind(key))
				b.gui_input.connect(_on_slot_gui_input.bind(key))
				_slot_buttons[key] = b
				g.add_child(b)
				var dot := ColorRect.new()
				dot.color = Color(0.55, 0.85, 0.55, 0.95)
				dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
				dot.anchor_left = 1.0
				dot.anchor_right = 1.0
				dot.anchor_top = 0.0
				dot.anchor_bottom = 0.0
				dot.offset_left = -9
				dot.offset_right = -3
				dot.offset_top = 3
				dot.offset_bottom = 9
				dot.visible = false
				b.add_child(dot)
				_slot_dots[key] = dot
		start = stop


func _case_hint(c: String) -> String:
	return {
		"single": "alone, nothing either side",
		"l_end": "left end of a run",
		"r_end": "right end of a run",
		"mid": "middle of a run",
		"l_plat": "the plateau turns down on its left",
		"r_plat": "the plateau turns down on its right",
		"l_step_hi": "a wall on its left that starts higher up",
		"l_step_lo": "a wall on its left that starts lower down",
		"r_step_hi": "a wall on its right that starts higher up",
		"r_step_lo": "a wall on its right that starts lower down",
		"notch": "a one-cell notch, plateau both sides",
		"l_plat_end": "plateau on the left, open on the right",
		"r_plat_end": "open on the left, plateau on the right",
	}.get(c, c)


func _row_hint(r: String) -> String:
	return {
		"only": "the whole face, for a 1-level drop",
		"top": "first row under the plateau",
		"middle": "repeats for every level beyond the second",
		"base": "last row, sitting on the ground below",
	}.get(r, r)


func refresh_shapes() -> void:
	if _fixture_pick == null:
		return
	var all_shapes := CliffData.shapes()
	_fixture_pick.clear()
	for i in all_shapes.size():
		_fixture_pick.add_item(all_shapes[i].name, i)
	if CliffData.has_captured():
		_fixture_index = 0
	else:
		_fixture_index = mini(_fixture_index, maxi(0, all_shapes.size() - 1))
	_fixture_pick.select(_fixture_index)
	_refresh_mask()
	_refresh()


func _height() -> int:
	return int(_height_spin.value)


func _on_height_changed(_v: float) -> void:
	if _refuse_if_inherited():
		_height_spin.set_value_no_signal(int(_cfg.get("height", 2)))
		return
	_cfg["height"] = _height()
	_save()
	_refresh()


func _on_slot_pressed(key: String) -> void:
	_selected = "" if _selected == key else key
	_refresh()


func _save() -> void:
	CliffData.store_config(tile_set, terrain_name, _cfg)
	config_changed.emit()


func _recompute_in_use() -> void:
	_in_use = {}
	if _mask.is_empty():
		return
	var cells := CliffData.mask_cells(_mask)
	if cells.is_empty():
		return
	var plateau := {}
	for c in cells: plateau[c] = true
	var faces := CliffData.face_map(cells, _height())
	for fc in faces.keys():
		_in_use[CliffData.slot_key(faces[fc].row, CliffData.case_at(plateau, faces, fc))] = true


func _frame_empty() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.11, 0.9)
	sb.border_color = Color(0.36, 0.36, 0.38)
	sb.set_border_width_all(1)
	return sb


func _frame_urgent() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.55, 0.25, 0.14)
	sb.border_color = Color(0.95, 0.55, 0.25)
	sb.set_border_width_all(2)
	return sb


func _refresh() -> void:
	_sync_from_bottom()
	_sync_inherit_ui()
	if _palette_pick != null:
		_palette_pick.queue_redraw()
	var pending: String = _pending_unit_text()
	_recompute_in_use()
	var used := CliffData.rows_for_height(_height())
	var pattern := _kind == KIND_PATTERN
	if _bands != null:
		_bands.visible = not _simple_mode and not pattern
	if _simple_grid != null:
		_simple_grid.visible = _simple_mode and not pattern
	if _pattern_box != null:
		_pattern_box.visible = pattern
		if pattern:
			_sync_pattern_rows()
	if _pattern_options != null:
		_pattern_options.visible = pattern
	if _auto_button != null:
		_auto_button.get_parent().visible = not pattern
	for c in [_bottom_check, _matrix_button, _clear_slot_btn]:
		if c != null:
			c.visible = not pattern
	if pattern:
		if _kind_pick != null:
			_kind_pick.select(_kind)
		_selected = ""
		_status.text = _pattern_report()
		_status.tooltip_text = "Click a piece, then drag its tiles in the palette. Right-click a piece to empty it.\n" + _legend()
		_update_marker()
		_repaint_preview()
		_show_pattern_line(_last_cell)
		return
	_refresh_simple()

	for entry in _row_labels:
		entry.label.visible = used.has(entry.row)

	for row in CliffData.ROWS:
		var emitted: bool = used.has(row)
		for case_name in CliffData.CASES:
			var key := CliffData.slot_key(row, case_name)
			var b: Button = _slot_buttons[key]
			var dot: ColorRect = _slot_dots[key]
			b.visible = emitted
			if not emitted:
				continue
			var tile := CliffData.slot_tile(_cfg, row, case_name)
			var own := not tile.is_empty()
			var possible := CliffData.slot_reachable(row, case_name, _height())
			var asked: bool = _in_use.has(key)
			b.button_pressed = (key == _selected)

			if not possible:
				b.icon = null
				b.disabled = true
				b.modulate = Color(1, 1, 1, 0)
				b.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.remove_theme_stylebox_override("normal")
				b.tooltip_text = ""
				dot.visible = false
				continue

			b.disabled = false
			b.mouse_filter = Control.MOUSE_FILTER_STOP
			b.modulate = Color(1, 1, 1, 1)
			# Show only assigned artwork here; displaying a fallback would hide unfinished slots.
			b.icon = _tile_texture(tile) if own else null
			dot.visible = own and asked and _build_mode

			var borrowed := CliffData.fallback_case(case_name)
			var on_map := ("Until then it borrows %s's tile." % _case_hint(borrowed)) \
				if borrowed != "" else "Until then it draws nothing."
			var title := _slot_name(key)
			if own:
				b.remove_theme_stylebox_override("normal")
				b.tooltip_text = "%s\nHas its tile%s. Right-click to empty it." % [title, ", used by this preview" if asked else ""]
			elif asked:
				b.add_theme_stylebox_override("normal", _frame_urgent())
				b.tooltip_text = "%s\nNeeds a tile; this preview uses it. %s" % [title, on_map]
			else:
				b.add_theme_stylebox_override("normal", _frame_empty())
				b.tooltip_text = "%s\nNeeds a tile. %s" % [title, on_map]

	var inherited := _inherited_from()
	_update_info()

	var total := 0
	for r in used:
		for c in CliffData.CASES:
			if CliffData.slot_reachable(r, c, _height()):
				total += 1
	var detail := _update_marker()
	_status.tooltip_text = detail
	if _height() <= 0:
		_status.text = "Height 0 grows no face. Raise it to see one."
	elif inherited != "":
		_status.text = "Edits to %s's face show up here." % inherited
	elif _selected.begins_with("simple:"):
		var g := _selected.trim_prefix("simple:")
		var st := _simple_state(g)
		_status.text = "[b]%s[/b] · %d slots, %s · %s" % [
			_group_name(g), st.members.size(), st.state, _cells_using(st.members)] + \
			(" · pick a tile below" if st.state != "mixed" else " · a tile below makes them all one")
	elif _selected != "":
		var has := not CliffData.slot_tile(_cfg, _selected.split("/")[0], _selected.split("/")[1]).is_empty()
		_status.text = "[b]%s[/b] · %s · %s" % [_slot_name(_selected), _cells_using([_selected]),
			"pick a tile below to replace it" if has else "pick a tile below"]
	elif _build_mode:
		_status.text = "Drawing: left click paints, right click erases. It asks for %d slots (framed orange)." % _in_use.size()
	else:
		var own_count := 0
		var urgent := 0
		for r in used:
			for c in CliffData.CASES:
				if not CliffData.slot_reachable(r, c, _height()):
					continue
				if not CliffData.slot_tile(_cfg, r, c).is_empty():
					own_count += 1
				elif _in_use.has(CliffData.slot_key(r, c)):
					urgent += 1
		if own_count == total:
			_status.text = "[color=#7ec87e]All %d slots of a %d-high face have a tile.[/color]" % [total, _height()]
		elif urgent > 0:
			_status.text = "[color=#e0a34a]%d slot%s this preview uses need a tile[/color] · %d/%d done at height %d" % [
				urgent, "" if urgent == 1 else "s", own_count, total, _height()]
		else:
			_status.text = "%d/%d slots done at height %d · this preview needs none of the rest" % [own_count, total, _height()]

	if pending != "":
		_status.text = pending
	_repaint_preview()


## "Top row · middle of a run", for a slot key "top/mid".
func _slot_name(key: String) -> String:
	var parts := key.split("/")
	if parts.size() != 2:
		return key
	return "%s row · %s" % [parts[0].capitalize(), _case_hint(parts[1])]


const SIDE_NAMES := {"E": "open", "W": "wall", "G": "plateau"}

## "Wall continues · open left, wall right", for a Simple group key "wall|EW".
func _group_name(group: String) -> String:
	var parts := group.split("|")
	if parts.size() != 2 or parts[1].length() != 2:
		return group
	return "%s · %s left, %s right" % ["Wall continues" if parts[0] == "wall" else "Wall ends",
		SIDE_NAMES.get(parts[1][0], parts[1][0]), SIDE_NAMES.get(parts[1][1], parts[1][1])]


func _cells_using(keys: Array) -> String:
	var n := 0
	for c in _slot_by_cell.keys():
		if _slot_by_cell[c] in keys:
			n += 1
	return "%d cell%s in the preview" % [n, "" if n == 1 else "s"]


func _legend() -> String:
	return "Preview: red = no tile, orange = borrowing another slot's tile, gold = selected."


static func _height_of_row(row: String) -> int:
	match row:
		"only": return 1
		"middle": return 3
		_: return 2


func _sheet_totals() -> Dictionary:
	var out := {"total": 0, "done": 0, "by_row": {}}
	for row in CliffData.ROWS:
		var h := _height_of_row(row)
		var missing := 0
		for c in CliffData.CASES:
			if not CliffData.slot_reachable(row, c, h):
				continue
			out.total += 1
			if CliffData.slot_tile(_cfg, row, c).is_empty():
				missing += 1
			else:
				out.done += 1
		if missing > 0:
			out.by_row[row] = missing
	return out


const COVERAGE_MAX_HEIGHT := 8


func _shape_coverage() -> Dictionary:
	var out := {"total": 0, "covered": 0, "missing": []}
	var reachable := {}
	for row in CliffData.ROWS:
		for c in CliffData.CASES:
			if CliffData.slot_reachable(row, c, _height_of_row(row)):
				reachable[CliffData.slot_key(row, c)] = true
	out.total = reachable.size()
	var cells := CliffData.mask_cells(_mask)
	if cells.is_empty():
		out.missing = reachable.keys()
		return out
	var plateau := {}
	for c in cells: plateau[c] = true
	var produced := {}
	for h in range(1, COVERAGE_MAX_HEIGHT + 1):
		var faces := CliffData.face_map(cells, h)
		for fc in faces.keys():
			produced[CliffData.slot_key(faces[fc].row, CliffData.case_at(plateau, faces, fc))] = true
	for k in reachable.keys():
		if produced.has(k):
			out.covered += 1
		else:
			out.missing.append(k)
	return out


## The detail behind the status line, which also labels the shape's coverage where it is chosen.
func _update_marker() -> String:
	var lines := []
	var p := _sheet_totals()
	var missing: int = p.total - p.done
	if missing == 0:
		lines.append("Sheet complete: all %d slots have a tile." % p.total)
	else:
		var parts := []
		for row in CliffData.ROWS:
			if p.by_row.has(row):
				parts.append("%s %d" % [row, p.by_row[row]])
		lines.append("Sheet: %d/%d slots have a tile, at any height. To draw: %s." % [p.done, p.total, ", ".join(parts)])
	if _kind != KIND_PATTERN:
		var blank := 0
		for r in CliffData.rows_for_height(_height()):
			for c in CliffData.CASES:
				if CliffData.slot_reachable(r, c, _height()) and CliffData.resolve_tile(_cfg, r, c).is_empty():
					blank += 1
		if blank > 0:
			lines.append("%d slot%s at this height borrow nothing and draw blank." % [blank, "" if blank == 1 else "s"])
	var cov := _shape_coverage()
	var shown := "Shows %d/%d slots at heights 1-%d" % [cov.covered, cov.total, COVERAGE_MAX_HEIGHT]
	var never: Array = cov.missing.duplicate()
	never.sort()
	var cov_tip := shown + (", every one." if never.is_empty() else ". Never asks for:\n" + "\n".join(never.map(_slot_name)))
	if _kind != KIND_PATTERN:
		lines.append(("Your drawing: " if _build_mode else "This shape: ") + cov_tip)
	if _fixture_pick != null:
		_fixture_pick.tooltip_text = _fixture_base_tip() + "\n\n" + cov_tip
	if _strip_label != null:
		_strip_label.text = ("Editing \"%s\"" % _editing_shape if _editing_shape != "" else "Drawing a shape") + \
			" · shows %d/%d" % [cov.covered, cov.total]
	lines.append(_legend())
	return "\n".join(lines)


func _fixture_base_tip() -> String:
	return "The shape the face is previewed on. Captures and saved drawings are kept in\n%s" % CliffData.shapes_scene()


func _tile_texture(tile: Dictionary) -> Texture2D:
	if tile.is_empty() or tile_set == null:
		return null
	var block_size := CliffData.block_size(tile)
	var key := "%s:%s:%s" % [tile.get("source_id", -1), tile.get("coord", Vector2i.ZERO), block_size]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var src := tile_set.get_source(tile.get("source_id", -1))
	if not (src is TileSetAtlasSource):
		return null
	var coord: Vector2i = tile.get("coord", Vector2i.ZERO)
	var at := AtlasTexture.new()
	at.atlas = src.texture
	var region: Rect2i = src.get_tile_texture_region(coord)
	if block_size != Vector2i.ONE and src.has_tile(coord + block_size - Vector2i.ONE):
		region = region.merge(src.get_tile_texture_region(coord + block_size - Vector2i.ONE))
	at.region = region
	_tex_cache[key] = at
	return at


func _repaint_preview() -> void:
	if _auto_cfg.is_empty() or _kind == KIND_PATTERN:
		_paint_preview()
		return
	var real := _cfg
	_cfg = _auto_cfg
	_paint_preview()
	_cfg = real


func _paint_preview() -> void:
	if _preview_layer == null or _bt == null:
		return
	_preview_layer.clear()
	if _preview_faces != null:
		_preview_faces.clear()
		_preview_faces.scale = Vector2.ONE
	_missing_cells.clear()
	_borrowed_cells.clear()
	_hover_text.clear()

	var cells := CliffData.mask_cells(_mask)
	_last_plateau = {}
	for c in cells:
		_last_plateau[c] = true
	_last_faces = CliffData.face_map(cells, _height())
	_bt.set_cells(_preview_layer, cells, terrain_index)
	_bt.update_terrain_area(_preview_layer, Rect2i(
		0, 0, _mask[0].length(), _mask.size()), false)

	var objects = load("res://addons/better-tile-editor/ObjectTerrain.gd")
	if objects != null and objects.has_objects(tile_set):
		objects.fix_cells(_preview_layer, cells)

	var plateau := {}
	for c in cells:
		plateau[c] = true
	var had := _slot_by_cell.keys()
	_slot_by_cell.clear()
	var faces := CliffData.face_map(cells, _height())

	if not had.is_empty():
		var before := {}
		for c in had:
			before[c] = true
		for f in faces.keys():
			if not before.has(f):
				_puffs.append({"cell": f, "born": _clock, "added": true})
		for c in had:
			if not faces.has(c):
				_puffs.append({"cell": c, "born": _clock, "added": false})
		# Count existing puffs when limiting the next burst.
		if _puffs.size() > MAX_PUFF_CELLS:
			_puffs = _puffs.slice(_puffs.size() - MAX_PUFF_CELLS)

	if _kind == KIND_PATTERN:
		var pruns := CliffPattern.runs_of(plateau, faces)
		var ph := _height()
		_piece_by_cell.clear()
		_pattern_line.clear()
		_hover_text.clear()
		var pick_cfg := _pattern_pick_config()
		for f in faces.keys():
			var prise: int = int(faces[f].rise)
			var pkey := CliffPattern.key_for_cell(pick_cfg, pruns[f], ph - 1 - prise, prise, ph)
			if pkey != "":
				_piece_by_cell[f] = pkey
			var ptile := CliffPattern.tile_for(_cfg, pruns[f], ph - 1 - prise, prise, ph)
			var pdrew: String = CliffPattern.key_at(
				CliffPattern.bands_at(_cfg, pruns[f], ph - 1 - prise, prise, ph).get("row", "mid"),
				CliffPattern.bands_at(_cfg, pruns[f], ph - 1 - prise, prise, ph).get("col", "mid"))
			_pattern_line[f] = "cell=%s  piece=%s  run: col %d of %d, air left=%s right=%s  row %d of %d from the top  tile=%s" % [
				f, pkey, int(pruns[f].col), int(pruns[f].width),
				"yes" if pruns[f].open_left else "no", "yes" if pruns[f].open_right else "no",
				ph - prise, ph,
				"none" if ptile.is_empty() else "source:%d atlas:%s" % [int(ptile.source_id), ptile.coord]]
			if pdrew != pkey:
				_pattern_line[f] += "  (drawn by %s)" % pdrew
			_hover_text[f] = "%s · column %d of %d, row %d of %d%s%s" % [
				_piece_title(pkey), int(pruns[f].col) + 1, int(pruns[f].width), ph - prise, ph,
				" · drawn by %s" % _piece_title(pdrew) if pdrew != pkey else "",
				" · no tile" if ptile.is_empty() else ""]
			if ptile.is_empty():
				_missing_cells.append(f)
				continue
			var psrc := tile_set.get_source(int(ptile.source_id)) as TileSetAtlasSource
			if psrc != null and psrc.has_tile(ptile.coord):
				_preview_faces.set_cell(f, int(ptile.source_id), ptile.coord)
			else:
				_missing_cells.append(f)
		if _preview_overlay:
			_preview_overlay.queue_redraw()
		return

	var runs := CliffData.slot_runs(plateau, faces)
	for f in faces.keys():
		var case_name: String = runs[f].case
		var key := CliffData.slot_key(faces[f].row, case_name)
		_slot_by_cell[f] = key
		var tile := CliffData.resolve_tile(_cfg, faces[f].row, case_name)
		var own_tile := not CliffData.slot_tile(_cfg, faces[f].row, case_name).is_empty()
		_hover_text[f] = "%s · %s" % [_slot_name(key), "own tile" if own_tile else
			("no tile" if tile.is_empty() else "borrows %s's tile" % _case_hint(CliffData.fallback_case(case_name)))]
		if tile.is_empty():
			_missing_cells.append(f)
		else:
			var fb: bool = bool(_cfg.get("from_bottom", false))
			var vp: int = int(faces[f].rise) - CliffData.matrix_foot(tile, faces[f].row) if fb else int(faces[f].band)
			var pc := CliffData.block_coord(tile, int(runs[f].phase), vp, fb)
			var psrc := tile_set.get_source(int(tile.source_id)) as TileSetAtlasSource
			if psrc != null and not psrc.has_tile(pc):
				pc = tile.coord
			_preview_faces.set_cell(f, int(tile.source_id), pc)
			if CliffData.slot_tile(_cfg, faces[f].row, case_name).is_empty():
				_borrowed_cells.append(f)

	if _preview_overlay:
		_preview_overlay.queue_redraw()


# Empty pieces have no size, so on an empty sheet no cell maps to a piece.
# For clicking only, treat them as one tile.
func _pattern_pick_config() -> Dictionary:
	var out := _cfg.duplicate(true)
	for spec in CliffPattern.PIECES:
		if not CliffPattern.piece(_cfg, spec.key).use:
			out[spec.key] = {"use": true, "rect": Rect2i(0, 0, 1, 1)}
	return out


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_preview_overlay.accept_event()
			_zoom_preview_at(event.position, 1.1)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_preview_overlay.accept_event()
			_zoom_preview_at(event.position, 1.0 / 1.1)
			return

	# Consume the drag so the ScrollContainer does not pan at the same time.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_preview_overlay.accept_event()
		_preview_panning = event.pressed
		return
	if _preview_panning and event is InputEventMouseMotion:
		_preview_overlay.accept_event()
		_preview_pan += event.relative
		_apply_preview_pan()
		return

	if event is InputEventMouseMotion and _hover_label != null:
		_hover_label.text = _hover_text.get(_cell_at(event.position), "")

	if _build_mode:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_painting = 1 if event.pressed else 0
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_painting = -1 if event.pressed else 0
			else:
				return
			_preview_overlay.accept_event()
			if _painting != 0:
				_paint_at(event.position)
			return
		if event is InputEventMouseMotion and _painting != 0:
			_preview_overlay.accept_event()
			_paint_at(event.position)
		return

	if _kind == KIND_PATTERN:
		if event is InputEventMouseMotion:
			var hc := _cell_at(event.position)
			if hc != _last_cell:
				_last_cell = hc
				_show_pattern_line(hc)
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var pc := _cell_at(event.position)
			_last_cell = pc
			if _piece_by_cell.has(pc):
				var hit: String = _piece_by_cell[pc]
				_pattern_armed = "" if _pattern_armed == hit else hit
				_refresh()
				_preview_overlay.accept_event()
			else:
				_show_pattern_line(pc)
		return

	if not _matrix_mode:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_off_mode_from = _cell_at(event.position)
				_select_at(event.position)
			elif _off_mode_from.x > -9000 and _cell_at(event.position) != _off_mode_from:
				_off_mode_from = Vector2i(-9999, -9999)
				_status.text = "[color=#e0a34a]To mark a block that repeats, turn on [b]Repeating block[/b] in the preview bar first.[/color]"
			else:
				_off_mode_from = Vector2i(-9999, -9999)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var c := _cell_at(event.position)
			if _slot_by_cell.has(c):
				_marking = true
				_mark_from = c
				_mark_to = c
				_preview_overlay.accept_event()
			return
		if not _marking:
			return
		_marking = false
		_preview_overlay.accept_event()
		var lo := Vector2i(mini(_mark_from.x, _mark_to.x), mini(_mark_from.y, _mark_to.y))
		var hi := Vector2i(maxi(_mark_from.x, _mark_to.x), maxi(_mark_from.y, _mark_to.y))
		if lo == hi:
			_mark_from = Vector2i(-9999, -9999)
			_matrix_target = {}
			_select_at(event.position)
			return
		_set_matrix_target(lo, hi)
		return
	if _marking and event is InputEventMouseMotion:
		var c2 := _cell_at(event.position)
		if c2 != _mark_to:
			_mark_to = c2
			_preview_overlay.queue_redraw()
		_preview_overlay.accept_event()
		return


func _cell_at(pos: Vector2) -> Vector2i:
	var step := TILE_PX * _preview_zoom
	var local: Vector2 = (pos - _preview_pan) / step
	return Vector2i(floori(local.x), floori(local.y))


func _set_matrix_target(lo: Vector2i, hi: Vector2i) -> void:
	var span := hi - lo + Vector2i.ONE
	var slots := {}
	var rows := {}
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if _slot_by_cell.has(c):
				slots[_slot_by_cell[c]] = true
				rows[String(_slot_by_cell[c]).split("/")[0]] = true
	if slots.is_empty():
		return
	var foot := 9999
	for x in range(lo.x, hi.x + 1):
		var c := Vector2i(x, hi.y)
		if _last_faces.has(c):
			foot = mini(foot, int(_last_faces[c].rise))
	if foot == 9999:
		foot = 0
	_matrix_target = {"size": span, "slots": slots.keys(), "foot": foot}
	_status.text = _pending_unit_text()
	_preview_overlay.queue_redraw()


func _select_at(pos: Vector2) -> bool:
	var step := TILE_PX * _preview_zoom
	var local: Vector2 = (pos - _preview_pan) / step
	var cell := Vector2i(floori(local.x), floori(local.y))
	if not _slot_by_cell.has(cell):
		return false
	var key: String = _slot_by_cell[cell]
	if _simple_mode:
		var pk: PackedStringArray = key.split("/")
		key = "simple:" + CliffData.simple_group(pk[0], pk[1])
	_last_cell = cell
	_selected = "" if _selected == key else key
	_refresh()
	return true


func _process(delta: float) -> void:
	if _puffs.is_empty():
		return
	_clock += delta
	var alive := []
	for p in _puffs:
		if _clock - p.born < PUFF_TIME:
			alive.append(p)
	_puffs = alive
	if _preview_overlay != null:
		_preview_overlay.queue_redraw()


func _draw_overlay() -> void:
	var step := TILE_PX * _preview_zoom
	_preview_overlay.draw_set_transform(_preview_pan, 0.0, Vector2.ONE)

	if _build_mode:
		var canvas_w := _build_w * step
		var canvas_h := _build_h * step
		_preview_overlay.draw_rect(Rect2(0, 0, canvas_w, canvas_h), Color(1, 1, 1, 0.05))
		if step > 6.0:
			for gx in range(_build_w + 1):
				_preview_overlay.draw_line(Vector2(gx * step, 0), Vector2(gx * step, canvas_h),
					Color(1, 1, 1, 0.07), 1.0)
			for gy in range(_build_h + 1):
				_preview_overlay.draw_line(Vector2(0, gy * step), Vector2(canvas_w, gy * step),
					Color(1, 1, 1, 0.07), 1.0)
		_preview_overlay.draw_rect(Rect2(0, 0, canvas_w, canvas_h), Color(0.45, 0.7, 0.95, 0.6), false, 2.0)

	for p in _puffs:
		_draw_puff(p, step)


	for f in _borrowed_cells:
		var br := Rect2(f.x * step, f.y * step, step, step)
		_preview_overlay.draw_rect(br, Color(0.95, 0.55, 0.25, 0.22))
		_preview_overlay.draw_rect(br, Color(0.95, 0.55, 0.25), false, 2.0)

	for f in _missing_cells:
		var rect := Rect2(f.x * step, f.y * step, step, step)
		_preview_overlay.draw_rect(rect, Color(0.75, 0.18, 0.18, 0.35))
		_preview_overlay.draw_rect(rect, Color(0.9, 0.25, 0.25), false, 1.0)
		_preview_overlay.draw_line(rect.position, rect.end, Color(0.9, 0.25, 0.25), 1.0)
		_preview_overlay.draw_line(Vector2(rect.end.x, rect.position.y),
			Vector2(rect.position.x, rect.end.y), Color(0.9, 0.25, 0.25), 1.0)

	if _selected != "":
		var mine := {}
		for k in _selected_slots():
			mine[k] = true
		for c in _slot_by_cell.keys():
			if not mine.has(_slot_by_cell[c]):
				continue
			var hr := Rect2(c.x * step, c.y * step, step, step)
			_preview_overlay.draw_rect(hr, Color(1.0, 0.78, 0.25, 0.30))
			_preview_overlay.draw_rect(hr, Color(1.0, 0.85, 0.3), false, 2.0)

	if _kind == KIND_PATTERN:
		for c in _piece_by_cell:
			if _piece_by_cell[c] != _pattern_armed:
				continue
			var pr := Rect2(c.x * step, c.y * step, step, step)
			_preview_overlay.draw_rect(pr, Color(0.35, 0.9, 1.0, 0.28))
			_preview_overlay.draw_rect(pr, Color(0.35, 0.9, 1.0, 0.9), false, 2.0)

	_draw_unit(step)


func _draw_unit(step: float) -> void:
	if _mark_from.x < -9000:
		return
	if not _marking and _matrix_target.is_empty():
		return
	var lo := Vector2i(mini(_mark_from.x, _mark_to.x), mini(_mark_from.y, _mark_to.y))
	var span := Vector2i(absi(_mark_to.x - _mark_from.x) + 1, absi(_mark_to.y - _mark_from.y) + 1)
	var r := Rect2(Vector2(lo) * step, Vector2(span) * step).grow(-2.0)
	var bright := Color(0.35, 0.9, 1.0)
	_preview_overlay.draw_rect(r, Color(0.2, 0.75, 1.0, 0.22), true)
	_preview_overlay.draw_rect(r.grow(1.5), Color(0, 0, 0, 0.8), false, 5.0)
	_preview_overlay.draw_rect(r, bright, false, 3.0)
	for i in range(1, span.x):
		var x := r.position.x + i * step
		_preview_overlay.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.55), 3.0)
		_preview_overlay.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), bright, 1.0)
	for j in range(1, span.y):
		var y := r.position.y + j * step
		_preview_overlay.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(0, 0, 0, 0.55), 3.0)
		_preview_overlay.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), bright, 1.0)
	var f := get_theme_default_font()
	var label := "%dx%d" % [span.x, span.y]
	var at := r.position + Vector2(5, 16)
	_preview_overlay.draw_string(f, at + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.9))
	_preview_overlay.draw_string(f, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, bright)


func _build_pattern_box(parent: Control) -> void:
	_pattern_box = VBoxContainer.new()
	_pattern_box.visible = false
	_pattern_box.add_theme_constant_override("separation", 6)
	parent.add_child(_pattern_box)
	var how := Label.new()
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.text = "Press a piece, then drag its tiles in the palette below. Right-click a piece to empty it."
	how.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_pattern_box.add_child(how)

	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 12)
	_pattern_box.add_child(pair)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	pair.add_child(grid)
	var tower := VBoxContainer.new()
	tower.add_theme_constant_override("separation", 4)
	pair.add_child(tower)
	var tl := Label.new()
	tl.text = "Lone column"
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.tooltip_text = "A run with open air on both sides: a tower, not a wall with ends."
	tl.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	tower.add_child(tl)
	for spec in CliffPattern.PIECES:
		var key: String = spec.key
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.tooltip_text = _piece_hint(spec)
		var wide: bool = spec.col == "mid"
		var tall: bool = spec.row == "mid"
		b.custom_minimum_size = Vector2(96 if wide else 64, 82 if tall else 50)
		if wide:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if tall:
			b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _pattern_armed = "" if _pattern_armed == key else key; _refresh())
		b.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
				_clear_piece(key))
		if spec.col == "alone":
			b.custom_minimum_size = Vector2(84, 82 if spec.row == "mid" else 46)
			b.size_flags_horizontal = Control.SIZE_FILL
			tower.add_child(b)
		else:
			grid.add_child(b)
		_pattern_rows[key] = {"button": b}



## Pattern's rarer settings, in Options: where the body's repeat starts, and its anchor.
func _build_pattern_options(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	_pattern_options = box
	var offs := GridContainer.new()
	offs.columns = 2
	box.add_child(offs)
	var cl := Label.new()
	cl.text = "Column offset"
	offs.add_child(cl)
	_col_off = SpinBox.new()
	_col_off.max_value = 32
	_col_off.value_changed.connect(func(v):
		if _pattern_syncing: return
		if _refuse_if_inherited():
			_sync_pattern_rows()
			return
		var before := _cfg.duplicate(true)
		_pattern_piece("body")["col_offset"] = int(v)
		_save(); _commit("Change cliff column offset", before); _refresh())
	offs.add_child(_col_off)
	var rl := Label.new()
	rl.text = "Row offset"
	offs.add_child(rl)
	_row_off = SpinBox.new()
	_row_off.max_value = 32
	_row_off.value_changed.connect(func(v):
		if _pattern_syncing: return
		if _refuse_if_inherited():
			_sync_pattern_rows()
			return
		var before := _cfg.duplicate(true)
		_pattern_piece("body")["row_offset"] = int(v)
		_save(); _commit("Change cliff row offset", before); _refresh())
	offs.add_child(_row_off)
	_rows_up = CheckBox.new()
	_rows_up.text = ANCHOR_LABEL
	_rows_up.tooltip_text = ("Off: the middle repeats down from under the top row, so the row above the ground\n"
		+ "depends on the height. On: it builds up from above the ground row, so every height\n"
		+ "ends the same. The top and ground rows are anchored already.")
	_rows_up.toggled.connect(func(v):
		if _pattern_syncing: return
		if _refuse_if_inherited():
			_sync_pattern_rows()
			return
		var before := _cfg.duplicate(true)
		_cfg["rows_up"] = v
		_save(); _commit("Change cliff anchor", before); _refresh())
	box.add_child(_rows_up)
	_offset_note = Label.new()
	_offset_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_offset_note.add_theme_color_override("font_color", Color(1, 0.72, 0.35))
	box.add_child(_offset_note)


func _pattern_report() -> String:
	var body := CliffPattern.piece(_cfg, "body")
	if not body.use:
		return "[color=#e0a34a]No body yet[/color] · it is the block that repeats"
	var own := []
	var borrowed := []
	for spec in CliffPattern.PIECES:
		if spec.key == "body":
			continue
		if CliffPattern.piece(_cfg, spec.key).use:
			own.append(String(spec.key).replace("_", " "))
		else:
			borrowed.append(String(spec.key).replace("_", " "))
	return "Body [b]%d×%d[/b] · %d of %d other pieces have their own tiles%s" % [
		body.rect.size.x, body.rect.size.y, own.size(), own.size() + borrowed.size(),
		"" if _pattern_armed != "" else " · click a piece to set it"]


func _show_pattern_line(cell: Vector2i) -> void:
	if _info == null:
		return
	if _pattern_line.has(cell):
		_info.text = "%s  %s" % [terrain_name, _pattern_line[cell]]
	elif cell.x > -9000:
		_info.text = "%s  cell=%s  no wall here" % [terrain_name, cell]
	else:
		_info.text = terrain_name


func _piece_title(key: String) -> String:
	if key.begins_with("alone"):
		return "Lone column" + key.trim_prefix("alone").replace("_", " ")
	return key.replace("_", " ").capitalize()


func _piece_name(spec: Dictionary) -> String:
	return String(spec.label).capitalize()


## The piece an empty one draws with, by the fallback order, or "" when none has tiles.
func _stand_in(key: String) -> String:
	for other: String in CliffPattern.FALLBACK.get(key, []):
		if CliffPattern.piece(_cfg, other).use:
			return other.replace("_", " ")
	return "body" if CliffPattern.piece(_cfg, "body").use and key != "body" else ""


func _piece_hint(spec: Dictionary) -> String:
	var where := "%s %s" % [spec.row, spec.col]
	var falls: Array = CliffPattern.FALLBACK.get(spec.key, [])
	var tail := "" if falls.is_empty() else "\n\nLeft empty it uses the %s." % String(falls[0]).replace("_", " ")
	return "The %s of the wall, %s tiles.\nDrag its tiles in the palette; right-click to empty it.%s" % [where, spec.shape, tail]


func _clear_piece(key: String) -> void:
	if _refuse_if_inherited(): return
	if key == "body":
		_status.text = "[color=#e0a34a]The body cannot be emptied.[/color]  Every other piece falls back to it."
		return
	var before := _cfg.duplicate(true)
	var p := _pattern_piece(key)
	p["use"] = false
	p["rect"] = Rect2i()
	_save()
	_commit("Clear cliff piece", before)
	_refresh()


func _pattern_piece(key: String) -> Dictionary:
	if not CliffPattern.is_pattern(_cfg):
		var fresh := CliffPattern.default_config()
		for k in fresh:
			if not _cfg.has(k):
				_cfg[k] = fresh[k]
		_cfg["mode"] = CliffPattern.MODE
	if not (_cfg.get(key) is Dictionary):
		_cfg[key] = CliffPattern.default_config()[key]
	return _cfg[key]


func _on_kind_picked(which: int) -> void:
	if _refuse_if_inherited():
		_kind_pick.select(_kind)
		return
	_kind = which
	_simple_mode = which == KIND_SIMPLE
	_selected = ""
	if which == KIND_PATTERN:
		_pattern_piece("body")
	else:
		_cfg.erase("mode")
	_save()
	_refresh()
	_fit_top_pane.call_deferred()


func _sync_pattern_rows() -> void:
	_pattern_syncing = true
	var source := int(_cfg.get("source_id", -1))
	for spec in CliffPattern.PIECES:
		var key: String = spec.key
		var p := CliffPattern.piece(_cfg, key)
		var b: Button = _pattern_rows[key].button
		var armed: bool = _pattern_armed == key
		b.button_pressed = armed
		if p.use:
			b.text = "%s\n%dx%d" % [_piece_name(spec), p.rect.size.x, p.rect.size.y]
			b.icon = _rect_texture(source, p.rect)
			b.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		else:
			var stand_in := _stand_in(key)
			b.text = "%s\n%s" % [_piece_name(spec), "empty" if stand_in == "" else "uses " + stand_in]
			b.icon = null
			b.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	var body: Dictionary = _cfg.get("body", {}) if _cfg.get("body") is Dictionary else {}
	_col_off.value = int(body.get("col_offset", 0))
	_row_off.value = int(body.get("row_offset", 0))
	var tall := []
	for spec in CliffPattern.PIECES:
		var pp := CliffPattern.piece(_cfg, spec.key)
		if not pp.use:
			continue
		if pp.rect.size.y > 1:
			tall.append(String(spec.key).replace("_", " "))
	var bod2 := CliffPattern.piece(_cfg, "body")
	var col_moves: bool = bod2.use and bod2.rect.size.x > 1
	_col_off.tooltip_text = "Which column of the body the repeat starts on, from the left of each run.\n" + \
		("It moves the body." if col_moves else "It moves nothing while the body is one column wide.")
	_row_off.tooltip_text = "Which row of the body the repeat starts on, down from under the top row.\n" + \
		("It moves nothing while every piece is one row tall." if tall.is_empty() else "It moves: %s." % ", ".join(PackedStringArray(tall)))
	var idle := []
	if int(body.get("col_offset", 0)) != 0 and not col_moves:
		idle.append("the column offset (the body is one column wide)")
	if int(body.get("row_offset", 0)) != 0 and tall.is_empty():
		idle.append("the row offset (every piece is one row tall)")
	_offset_note.text = "No effect yet: %s." % " and ".join(PackedStringArray(idle))
	_offset_note.visible = not idle.is_empty()
	_rows_up.button_pressed = bool(_cfg.get("rows_up", false))
	_pattern_syncing = false


func _rect_texture(source_id: int, rect: Rect2i) -> Texture2D:
	if source_id < 0 or rect.size.x <= 0 or tile_set == null:
		return null
	var src := tile_set.get_source(source_id) as TileSetAtlasSource
	if src == null or not src.has_tile(rect.position):
		return null
	var region: Rect2i = src.get_tile_texture_region(rect.position, 0)
	var last := rect.position + rect.size - Vector2i.ONE
	if src.has_tile(last):
		region = region.merge(src.get_tile_texture_region(last, 0))
	var at := AtlasTexture.new()
	at.atlas = src.texture
	at.region = region
	return at


func assign_tile(source_id: int, coord: Vector2i, tile_size := Vector2i.ONE) -> bool:
	if _refuse_if_inherited(): return true
	var before := _cfg.duplicate(true)
	if _kind == KIND_PATTERN:
		if _pattern_armed == "":
			_status.text = "[color=#e0a34a]No piece armed.[/color]  Press one, or click the part of the wall you want to change."
			return true
		var have := int(_cfg.get("source_id", -1))
		if have != -1 and have != source_id:
			_status.text = "[color=#e0a34a]That tile is in another source.[/color]  A pattern comes from one of them."
			return true
		_cfg["source_id"] = source_id
		var piece := _pattern_piece(_pattern_armed)
		piece["rect"] = Rect2i(coord, tile_size)
		if _pattern_armed != "body":
			piece["use"] = true
		_save()
		_commit("Assign cliff piece", before)
		_refresh()
		_status.text = "%s set (%d×%d)." % [String(_pattern_armed).replace("_", " ").capitalize(), tile_size.x, tile_size.y]
		return true
	if not _matrix_target.is_empty():
		var target: Dictionary = _matrix_target
		_matrix_target = {}
		_mark_from = Vector2i(-9999, -9999)
		var msize: Vector2i = target.size
		var tile2 := {"source_id": source_id, "coord": coord}
		if msize.x > 1 or msize.y > 1:
			tile2["size"] = msize
			tile2["foot"] = int(target.get("foot", 0))
		if msize.y > 1:
			_cfg["from_bottom"] = true
		for k in target.slots:
			var kp: PackedStringArray = String(k).split("/")
			CliffData.set_slot_tile(_cfg, kp[0], kp[1], tile2.duplicate())
		_save()
		_commit("Assign cliff block", before)
		_refresh()
		_status.text = "%d×%d block given to %d slot%s." % [msize.x, msize.y, target.slots.size(), "" if target.slots.size() == 1 else "s"]
		return true
	if _selected == "": return false
	var tile := {"source_id": source_id, "coord": coord}
	if tile_size.x > 1 or tile_size.y > 1:
		tile["size"] = tile_size
	for k in _selected_slots():
		var parts: PackedStringArray = str(k).split("/")
		CliffData.set_slot_tile(_cfg, parts[0], parts[1], tile.duplicate())
	_save()
	_commit("Assign cliff tile", before)
	_refresh()
	return true


func _draw_pattern_pieces() -> void:
	var source := int(_cfg.get("source_id", -1))
	if source < 0:
		return
	var f := get_theme_default_font()
	for spec in CliffPattern.PIECES:
		var p := CliffPattern.piece(_cfg, spec.key)
		if not p.use:
			continue
		var r := _palette_rect_of(source, p.rect.position, p.rect.size)
		if r.size.x <= 0.0:
			continue
		var armed: bool = _pattern_armed == spec.key
		var col := Color(0.35, 0.9, 1.0) if armed else Color(1, 0.85, 0.3, 0.7)
		_palette_pick.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.7), false, 4.0)
		_palette_pick.draw_rect(r, col, false, 3.0 if armed else 2.0)
		_palette_pick.draw_string(f, r.position + Vector2(3, -3), String(spec.label),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _palette_rect_of(source_id: int, coord: Vector2i, tile_size: Vector2i) -> Rect2:
	var tv = _palette_view
	if tv == null or tv.tileset == null:
		return Rect2()
	var ts2: TileSet = tv.tileset
	var src := ts2.get_source(source_id) as TileSetAtlasSource if ts2.has_source(source_id) else null
	if src == null or not src.has_tile(coord):
		return Rect2()
	var r: Rect2i = src.get_tile_texture_region(coord, 0)
	var last := coord + tile_size - Vector2i.ONE
	if tile_size != Vector2i.ONE and src.has_tile(last):
		r = r.merge(src.get_tile_texture_region(last, 0))
	return tv.atlas_rect(source_id, Rect2(r))


func _draw_palette_current() -> void:
	if _palette_view == null:
		return
	if _kind == KIND_PATTERN:
		_draw_pattern_pieces()
		return
	if _selected == "":
		return
	var ks := _selected_slots()
	if ks.is_empty():
		return
	var parts: PackedStringArray = String(ks[0]).split("/")
	var tile := CliffData.slot_tile(_cfg, parts[0], parts[1])
	var borrowed := false
	if tile.is_empty():
		tile = CliffData.resolve_tile(_cfg, parts[0], parts[1])
		borrowed = true
	if tile.is_empty():
		return
	var block_size := CliffData.block_size(tile)
	var r := _palette_rect_of(int(tile.source_id), tile.coord, block_size)
	if r.size.x <= 0.0:
		return
	var col := Color(1, 0.85, 0.3, 0.9) if not borrowed else Color(1, 0.85, 0.3, 0.45)
	_palette_pick.draw_rect(r, Color(col.r, col.g, col.b, 0.12), true)
	_palette_pick.draw_rect(r, col, false, 2.0)
	var f := get_theme_default_font()
	var label := "%dx%d" % [block_size.x, block_size.y] if block_size != Vector2i.ONE else ""
	if borrowed:
		label = ("borrowed " + label).strip_edges()
	if label != "":
		_palette_pick.draw_string(f, r.position + Vector2(4, -4), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _draw_palette_selection() -> void:
	if _palette_view == null:
		return
	if _pick_from.x < 0.0:
		_draw_palette_current()
		return
	var a: Rect2 = _palette_view.tile_rect_from_position(Vector2i(_pick_from))
	if a.size.x <= 0.0:
		return
	var b: Rect2 = _palette_view.tile_rect_from_position(Vector2i(_pick_at))
	var r: Rect2 = a.merge(b) if b.size.x > 0.0 else a
	_palette_pick.draw_rect(r, Color(0.45, 0.85, 1.0, 0.20), true)
	_palette_pick.draw_rect(r, Color(0.45, 0.85, 1.0, 0.95), false, 2.0)
	var step := a.size
	var nx := int(round(r.size.x / step.x))
	var ny := int(round(r.size.y / step.y))
	for i in range(1, nx):
		var x := r.position.x + i * step.x
		_palette_pick.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0.45, 0.85, 1.0, 0.55), 1.0)
	for j in range(1, ny):
		var y := r.position.y + j * step.y
		_palette_pick.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(0.45, 0.85, 1.0, 0.55), 1.0)
	if nx > 1 or ny > 1:
		var f := get_theme_default_font()
		_palette_pick.draw_string(f, r.position + Vector2(4, 14), "%dx%d" % [nx, ny],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.95))


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
	if _pick_from.x >= 0.0 and event is InputEventMouseMotion and not _panning:
		_pick_at = event.position
		_palette_pick.queue_redraw()
		return
	if _panning and event is InputEventMouseMotion:
		_palette_pick.accept_event()
		var sc := _palette_view.get_parent() as ScrollContainer
		if sc != null:
			sc.scroll_horizontal -= int(event.relative.x)
			sc.scroll_vertical -= int(event.relative.y)
		return

	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var part: Dictionary = _palette_view.tile_part_from_position(Vector2i(event.position))
	if event.pressed:
		_pick_anchor = part if part.get("valid", false) else {}
		_pick_from = event.position if not _pick_anchor.is_empty() else Vector2(-1, -1)
		_pick_at = _pick_from
		_palette_pick.queue_redraw()
		return
	if _pick_anchor.is_empty():
		_pick_from = Vector2(-1, -1)
		_palette_pick.queue_redraw()
		return
	var anchor: Dictionary = _pick_anchor
	_pick_anchor = {}
	if not part.get("valid", false) or int(part.source_id) != int(anchor.source_id):
		part = anchor
	var lo := Vector2i(mini(anchor.coord.x, part.coord.x), mini(anchor.coord.y, part.coord.y))
	var hi := Vector2i(maxi(anchor.coord.x, part.coord.x), maxi(anchor.coord.y, part.coord.y))
	_pick_from = Vector2(-1, -1)
	_palette_pick.queue_redraw()
	_on_palette_pressed(int(anchor.source_id), lo, hi - lo + Vector2i.ONE)


func _on_palette_pressed(source_id: int, coord: Vector2i, tile_size := Vector2i.ONE) -> void:
	if not assign_tile(source_id, coord, tile_size):
		_status.text = "[color=#e0a34a]Pick a slot in the sheet first.[/color]"


func _on_clear_slot() -> void:
	if _selected == "":
		_status.text = "[color=#e0a34a]Pick a slot first.[/color]"
		return
	_clear_slots(_selected_slots())


## Empties slots: the Clear slot button, or a right click on a slot or group.
func _clear_slots(keys: Array) -> void:
	if _refuse_if_inherited(): return
	var before := _cfg.duplicate(true)
	for k in keys:
		var parts: PackedStringArray = str(k).split("/")
		CliffData.set_slot_tile(_cfg, parts[0], parts[1], {})
	_save()
	_commit("Clear cliff slot", before)
	_refresh()


func _on_slot_gui_input(event: InputEvent, key: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_clear_slots(CliffData.simple_members(key.trim_prefix("simple:")) if key.begins_with("simple:") else [key])


func _clamp_zoom(v: float) -> float:
	return clampf(v,
		ProjectSettings.get_setting(MIN_ZOOM_SETTING, 1.0),
		ProjectSettings.get_setting(MAX_ZOOM_SETTING, 8.0))


const PREVIEW_MIN_ZOOM := 0.2

func _clamp_preview_zoom(v: float) -> float:
	return clampf(v, PREVIEW_MIN_ZOOM,
		ProjectSettings.get_setting(MAX_ZOOM_SETTING, 8.0))


func _on_palette_zoom_requested(value: float) -> void:
	_palette_view._on_zoom_value_changed(_clamp_zoom(value))


func _apply_preview_pan() -> void:
	if _preview_layer != null:
		_preview_layer.position = _preview_pan
	if _preview_overlay != null:
		_preview_overlay.queue_redraw()


func _apply_preview_zoom() -> void:
	if _preview == null or _preview_layer == null:
		return
	_preview_layer.scale = Vector2(_preview_zoom, _preview_zoom)
	_preview_layer.position = _preview_pan


func _zoom_preview_at(mouse_local: Vector2, factor: float) -> void:
	var old_zoom := _preview_zoom
	_preview_zoom = _clamp_preview_zoom(old_zoom * factor)
	if is_equal_approx(_preview_zoom, old_zoom):
		return
	var ratio := _preview_zoom / old_zoom
	_preview_pan = mouse_local - (mouse_local - _preview_pan) * ratio
	_apply_preview_zoom()
	_apply_preview_pan()


func _inherited_from() -> String:
	return CliffData.inherits_from(tile_set, terrain_name)


## Inherited sheets are read-only until detached.
func _on_matrix_mode_toggled(on: bool) -> void:
	_matrix_mode = on
	_matrix_target = {}
	_mark_from = Vector2i(-9999, -9999)
	_marking = false
	# Build mode owns preview drags; matrix selection must stay off.
	if on and _build_mode and _build_toggle != null:
		_build_toggle.button_pressed = false
	if _preview_overlay != null:
		_preview_overlay.queue_redraw()
	if on:
		_status.text = "Drag over the wall to mark the block that repeats, then pick its top-left tile below."
	else:
		_refresh()


func _on_from_bottom_toggled(on: bool) -> void:
	if _syncing_bottom:
		return
	if _refuse_if_inherited():
		_sync_from_bottom()
		return
	_cfg["from_bottom"] = on
	_save()
	_refresh()


var _syncing_bottom := false

func _sync_from_bottom() -> void:
	if _bottom_check == null:
		return
	_syncing_bottom = true
	_bottom_check.button_pressed = bool(_cfg.get("from_bottom", false))
	_syncing_bottom = false


func _pending_unit_text() -> String:
	if _matrix_target.is_empty():
		return ""
	var target_size: Vector2i = _matrix_target.size
	var count: int = _matrix_target.slots.size()
	var note := ""
	if target_size.y > 1 and not bool(_cfg.get("from_bottom", false)):
		note = " [color=#e0a34a](turns on “%s”)[/color]" % ANCHOR_LABEL
	return "[b]%d×%d block[/b] over %d slot%s%s · pick its top-left tile below" % [
		target_size.x, target_size.y, count, "" if count == 1 else "s", note]

func _refuse_if_inherited() -> bool:
	var src := _inherited_from()
	if src == "":
		return false
	_status.text = "[color=#e0a34a]This sheet is inherited from [b]%s[/b].[/color]  Edit that terrain, or press “Make local” to start your own." % src
	return true


## Opens the slots' pane tall enough to show them all and Options, taking room from the
## palette and, when that runs short, making the window taller.
func _fit_top_pane() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if _left_box == null or not is_inside_tree():
		return
	var want := _left_box.get_combined_minimum_size().y + 8.0
	var palette_min := (_pane.get_child(1) as Control).get_combined_minimum_size().y
	var room := _pane.size.y - palette_min - _pane.get_theme_constant(&"separation")
	if want > room:
		var screen := DisplayServer.screen_get_usable_rect(current_screen).size.y
		size.y = mini(screen - 40, size.y + int(want - room))
		await get_tree().process_frame
	if want > _left_scroll.size.y:
		# The panes share the height by their stretch ratios (Chrome.open_at); set the top's.
		var share := clampf(want / maxf(1.0, _pane.size.y - _pane.get_theme_constant(&"separation")), 0.05, 0.95)
		Chrome.open_at(_pane, share)


func _open_autoassign() -> void:
	if _refuse_if_inherited():
		return
	_pane.visible = false
	_auto_page.visible = true
	Chrome.open_at(_split, 0.62)
	_auto_page.open(tile_set, _bt, terrain_index)


func _close_autoassign() -> void:
	_auto_page.visible = false
	_pane.visible = true
	Chrome.open_at(_split, 0.30)
	_auto_cfg = {}
	_repaint_preview()


# The preview shows the face the picked block would give, without touching the real one.
func _on_autoassign_block(source_id: int, block: Rect2i) -> void:
	_auto_cfg = {}
	if block.size != Vector2i.ZERO:
		_auto_cfg = _cfg.duplicate(true)
		CliffData.autoassign(_auto_cfg, source_id, block)
	_repaint_preview()


func _on_autoassign_chosen(source_id: int, block: Rect2i) -> void:
	_close_autoassign()
	var before := _cfg.duplicate(true)
	var count := CliffData.autoassign(_cfg, source_id, block)
	_selected = ""
	_save()
	_commit("Autoassign cliff face", before)
	_refresh()
	_status.text = "[color=#7ec87e]%d slots filled from the %d×%d block.[/color] Ctrl+Z undoes it." % [count, block.size.x, block.size.y]


func _sync_more_menu() -> void:
	_inherit_names = CliffData.inheritable_sources(tile_set, terrain_name)
	var current := _inherited_from()
	_inherit_menu.clear()
	if _inherit_names.is_empty():
		_inherit_menu.add_item("(no other terrain has a face)", -1)
		_inherit_menu.set_item_disabled(0, true)
	else:
		for i in _inherit_names.size():
			_inherit_menu.add_check_item(_inherit_names[i], i)
			_inherit_menu.set_item_checked(i, _inherit_names[i] == current)
	var menu := _more.get_popup()
	menu.set_item_disabled(menu.get_item_index(MORE_LOCAL), current == "")


func _on_more_pressed(id: int) -> void:
	match id:
		MORE_LOCAL:
			_on_make_local()
		MORE_COPY:
			DisplayServer.clipboard_set(_info.text)
		MORE_CLEAR:
			_on_clear_all()


func _on_shape_menu(id: int) -> void:
	match id:
		SHAPE_NARROW:
			_narrow_check.button_pressed = not _show_narrow
		SHAPE_DRAW:
			if not _build_mode:
				_build_toggle.button_pressed = true
		SHAPE_EDIT:
			_edit_selected_shape()
		SHAPE_CLEAR:
			_clear_canvas()


## Done: leave the drawing (kept until cleared) and any shape being edited.
func _finish_drawing() -> void:
	_editing_shape = ""
	_refresh_shape_buttons()
	_build_toggle.button_pressed = false


## The inherited line and the ⋮ state, for every kind (Pattern refreshes return early).
func _sync_inherit_ui() -> void:
	var inherited := _inherited_from()
	if _inherit_banner != null:
		_inherit_banner.visible = inherited != ""
		_inherit_label.text = "Uses %s's face (read-only)" % inherited


## Edits to the face go through the editor's undo, against the tile set it is kept in.
func _commit(action: String, before: Dictionary) -> void:
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action(action, UndoRedo.MERGE_DISABLE, tile_set)
	undo.add_do_method(CliffData, &"store_config", tile_set, terrain_name, _cfg.duplicate(true))
	undo.add_undo_method(CliffData, &"store_config", tile_set, terrain_name, before)
	undo.commit_action(false)


# Undo and redo write the face back into the tile set; follow them, keeping the selection.
func _on_tile_set_changed() -> void:
	if _inherited_from() != "":
		return
	var now := CliffData.config_of(tile_set, terrain_name)
	if now == _cfg:
		return
	_cfg = now
	config_changed.emit()
	_refresh()


# The editor's shortcuts don't reach this window, so undo and redo are taken here.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_Z and event.keycode != KEY_Y:
		return
	if not (event.ctrl_pressed or event.meta_pressed):
		return
	var undo := EditorInterface.get_editor_undo_redo()
	var history := undo.get_history_undo_redo(undo.get_object_history_id(tile_set))
	if event.keycode == KEY_Y or event.shift_pressed:
		history.redo()
	else:
		history.undo()
	set_input_as_handled()


func _on_inherit_chosen(id: int) -> void:
	if id < 0 or id >= _inherit_names.size():
		return
	CliffData.set_inherit(tile_set, terrain_name, _inherit_names[id])
	_cfg = CliffData.config_of(tile_set, terrain_name)
	config_changed.emit()
	_refresh()


func _on_make_local() -> void:
	if _inherited_from() == "":
		return
	CliffData.make_local(tile_set, terrain_name)
	_cfg = CliffData.config_of(tile_set, terrain_name)
	config_changed.emit()
	_refresh()


func _make_puff_texture() -> Texture2D:
	var swatch := 32
	var img := Image.create(swatch, swatch, false, Image.FORMAT_RGBA8)
	var centre := (swatch - 1) * 0.5
	for y in swatch:
		for x in swatch:
			var d: float = Vector2(x - centre, y - centre).length() / (swatch * 0.5)
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a * a
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


func _draw_puff(p: Dictionary, step: float) -> void:
	var age: float = (_clock - p.born) / PUFF_TIME
	if age < 0.0 or age > 1.0:
		return
	var cell: Vector2i = p.cell
	var added: bool = p.added
	var origin := Vector2(cell.x * step + step * 0.5, cell.y * step + step * 0.9)

	for i in PUFF_COUNT:
		# Seed each puff so redrwws animate the same cloud.
		var h := hash(Vector2i(cell.x * 73 + i * 17, cell.y * 31 + i * 7))
		var ang: float = float(h % 628) / 100.0
		var spread: float = 0.5 + float((h >> 8) % 140) / 100.0
		var delay: float = float((h >> 16) % 32) / 100.0
		var t: float = clampf((age - delay) / maxf(0.05, 1.0 - delay), 0.0, 1.0)
		if t <= 0.0:
			continue

		var dir := Vector2(cos(ang), sin(ang)) * step * spread * t
		dir.y += (-step * 1.05 * t) if added else (step * 0.8 * t * t)
		var centre := origin + dir

		var bulk: float = 5.0 + float((h >> 22) % 7)
		var radius: float = bulk * (0.65 + 0.9 * t)
		var alpha: float = pow(1.0 - t, 1.6) * (0.85 if added else 0.78)
		var shade: float = 0.84 + float((h >> 26) % 16) / 100.0
		var col := Color(shade, shade * 0.94, shade * 0.76, alpha) if added \
			else Color(shade * 0.72, shade * 0.70, shade * 0.67, alpha)

		for j in PUFF_LOBES:
			var lh := hash(Vector2i(h % 9973 + j * 131, j * 57 + 11))
			var la: float = float(lh % 628) / 100.0
			var ld: float = radius * (0.25 + float((lh >> 8) % 45) / 100.0)
			var lr: float = radius * (0.55 + float((lh >> 14) % 50) / 100.0)
			var lp := centre + Vector2(cos(la), sin(la)) * ld
			_preview_overlay.draw_texture_rect(
				_puff_tex, Rect2(lp - Vector2(lr, lr), Vector2(lr * 2.0, lr * 2.0)), false, col)


func _paint_at(pos: Vector2) -> void:
	var step := TILE_PX * _preview_zoom
	var local: Vector2 = (pos - _preview_pan) / step
	var c := Vector2i(floori(local.x), floori(local.y))
	if c.x < 0 or c.y < 0 or c.x >= _build_w or c.y >= _build_h:
		return
	if _painting > 0:
		if _built.has(c): return
		_built[c] = true
	else:
		if not _built.has(c): return
		_built.erase(c)
	_refresh_mask()
	_refresh()


func _on_save_shape_pressed() -> void:
	if _editing_shape != "":
		_save_as_shape(_editing_shape)
	else:
		_ask_shape_name()


func _exit_shape_edit() -> void:
	var was := _editing_shape
	_editing_shape = ""
	_refresh_shape_buttons()
	if _build_mode and _build_toggle != null:
		_build_toggle.button_pressed = false
	else:
		_refresh_mask()
		_refresh()
	if was != "":
		_status.text = "Stopped editing [b]%s[/b]. The drawing is kept until cleared." % was


func _refresh_shape_buttons() -> void:
	if _save_shape_btn == null:
		return
	var editing := _editing_shape != ""
	_save_shape_btn.text = "Overwrite \"%s\"" % _editing_shape if editing else "Save as shape"
	_save_new_btn.visible = editing


func _ask_shape_name() -> void:
	if _built.is_empty():
		_status.text = "[color=#e0a34a]Nothing drawn yet.[/color]  Turn on Build and paint something first."
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Save as shape"
	var box := VBoxContainer.new()
	var lab := Label.new()
	lab.text = "Name for the new shape:"
	box.add_child(lab)
	var field := LineEdit.new()
	field.text = _editing_shape if _editing_shape != "" else "My shape"
	field.custom_minimum_size.x = 280
	box.add_child(field)
	dialog.add_child(box)
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		_save_as_shape(field.text.strip_edges())
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
	field.grab_focus()
	field.select_all()


func _save_as_shape(shape_name: String) -> void:
	if shape_name == "" or _built.is_empty():
		return
	var root: Node2D
	var scene_path := CliffData.shapes_scene()
	var ps = load(scene_path) if ResourceLoader.exists(scene_path) else null
	if ps != null:
		root = ps.instantiate()
	else:
		root = Node2D.new()
		root.name = "CliffPreviewShapes"

	# Use a valid tile even though preview masks only inspect occupied coordinates.
	var src := -1
	var atlas := Vector2i.ZERO
	for ch in root.get_children():
		if ch is TileMapLayer and not ch.get_used_cells().is_empty():
			var c0: Vector2i = ch.get_used_cells()[0]
			src = ch.get_cell_source_id(c0)
			atlas = ch.get_cell_atlas_coords(c0)
			break
	if src < 0:
		var tiles: Array = _bt.get_tile_sources_in_terrain(tile_set, terrain_index)
		if tiles.is_empty():
			_status.text = "[color=#e0a34a]This terrain has no tiles, so there is nothing to write the shape with.[/color]"
			root.free()
			return
		for i in tile_set.get_source_count():
			var sid := tile_set.get_source_id(i)
			if tile_set.get_source(sid) == tiles[0].source:
				src = sid
				atlas = tiles[0].coord
				break

	var old = root.get_node_or_null(NodePath(shape_name))
	if old != null:
		root.remove_child(old)
		old.free()

	var layer := TileMapLayer.new()
	layer.name = shape_name
	layer.tile_set = tile_set
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.visible = false
	root.add_child(layer)
	layer.owner = root
	for c: Vector2i in _built.keys():
		layer.set_cell(c, src, atlas)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		scene_path = CliffData.ensure_shapes_dir()
		err = ResourceSaver.save(packed, scene_path)
	root.free()
	if err != OK:
		_status.text = "[color=#e0a34a]Could not save the shape to [b]%s[/b] (error %d).[/color]\nSet %s in the project settings to put it somewhere else." % [
			scene_path, err, CliffData.SHAPES_SETTING]
		return

	# Invalidate the cached shapes scene so the newly saved shape appears immediately.
	ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	refresh_shapes()
	_exit_shape_edit()
	_select_shape_named(shape_name)
	_status.text = "[color=#7ec87e]Saved as \"%s\".[/color]  It is in the shape list, and editing is closed." % shape_name


func _select_shape_named(shape_name: String) -> void:
	if _fixture_pick == null:
		return
	var all_shapes := CliffData.shapes()
	for i in all_shapes.size():
		if str(all_shapes[i].name) == shape_name:
			_fixture_index = i
			_fixture_pick.select(i)
			_refresh_mask()
			_refresh()
			return


func _edit_selected_shape() -> void:
	var all_shapes := CliffData.shapes()
	if all_shapes.is_empty():
		return
	var entry: Dictionary = all_shapes[clampi(_fixture_index, 0, all_shapes.size() - 1)]
	var cells: Array = CliffData.mask_cells(entry.mask)
	_built.clear()
	_build_w = maxi(BUILD_MIN_W, entry.mask[0].length() if not entry.mask.is_empty() else 0)
	_build_h = maxi(BUILD_MIN_H, entry.mask.size())
	for c: Vector2i in cells:
		_built[c] = true
	_editing_shape = "" if CliffData.has_captured() and _fixture_index == 0 else str(entry.name)
	_refresh_shape_buttons()
	if not _build_mode:
		_build_toggle.button_pressed = true
	else:
		_refresh_mask()
		_refresh()
	_status.text = "Editing \"%s\".  Paint, then Save as shape to replace it or save it under another name." % entry.name


func _clear_canvas() -> void:
	_built.clear()
	_editing_shape = ""
	_build_w = BUILD_MIN_W
	_build_h = BUILD_MIN_H
	_refresh_shape_buttons()
	_refresh_mask()
	_refresh()


func _refresh_mask() -> void:
	if _build_mode:
		_mask = _build_mask()
		return
	_mask = CliffData.fixture(_fixture_index, _show_narrow)


## Keep canvas bounds fixed while painting so added cells cannot move its origin.
func _build_mask() -> Array:
	var out := []
	for y in _build_h:
		var row_text := ""
		for x in _build_w:
			row_text += "X" if _built.has(Vector2i(x, y)) else "."
		out.append(row_text)
	return out


func _build_simple_grid(parent: Control) -> void:
	_simple_grid = GridContainer.new()
	_simple_grid.columns = 1
	parent.add_child(_simple_grid)
	var shape_name := SIDE_NAMES
	var titles := {"wall": "Wall continues below", "ground": "Wall ends on the ground"}
	var tips := {"wall": "Rows: top, middle", "ground": "Rows: base, only"}
	for band in CliffData.SIMPLE_ROWS:
		var t := Label.new()
		t.text = titles[band]
		t.tooltip_text = tips[band]
		t.mouse_filter = Control.MOUSE_FILTER_PASS
		t.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		_simple_grid.add_child(t)
		var g := GridContainer.new()
		g.columns = CliffData.SIMPLE_SIDES.size() + 1
		_simple_grid.add_child(g)
		var corner := Label.new()
		corner.text = "left ↓  right →"
		corner.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		g.add_child(corner)
		for r in CliffData.SIMPLE_SIDES:
			var h := Label.new()
			h.text = shape_name[r]
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			# Every column as wide as the widest name, so the squares sit evenly apart.
			h.custom_minimum_size.x = _simple_column_width()
			g.add_child(h)
		for l in CliffData.SIMPLE_SIDES:
			var rl := Label.new()
			rl.text = shape_name[l]
			g.add_child(rl)
			for r in CliffData.SIMPLE_SIDES:
				var key := "%s|%s%s" % [band, l, r]
				var b := Button.new()
				b.custom_minimum_size = Vector2(SIMPLE_PX, SIMPLE_PX)
				b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				b.toggle_mode = true
				b.expand_icon = true
				b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				b.pressed.connect(_on_slot_pressed.bind("simple:" + key))
				b.gui_input.connect(_on_slot_gui_input.bind("simple:" + key))
				_simple_buttons[key] = b
				g.add_child(b)


func _simple_column_width() -> float:
	var font := EditorInterface.get_editor_theme().get_font(&"font", &"Label")
	var size := EditorInterface.get_editor_theme().get_font_size(&"font_size", &"Label")
	var widest := 0.0
	for name: String in SIDE_NAMES.values():
		widest = maxf(widest, font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	return ceilf(widest) + 8.0


func _simple_state(group: String) -> Dictionary:
	var members := CliffData.simple_members(group)
	var tiles := {}
	var empty_count := 0
	var asked := false
	for k in members:
		var p: PackedStringArray = str(k).split("/")
		var t := CliffData.slot_tile(_cfg, p[0], p[1])
		if t.is_empty():
			empty_count += 1
			if _in_use.has(k):
				asked = true
		else:
			tiles["%d:%s" % [int(t.source_id), t.coord]] = t
	var state := "empty"
	if tiles.size() >= 2:
		state = "mixed"
	elif tiles.size() == 1:
		state = "filled" if empty_count == 0 else "partial"
	return {"members": members, "tiles": tiles, "empty_count": empty_count, "state": state, "asked": asked}


func _frame_mixed() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.35, 0.75, 0.16)
	sb.border_color = Color(0.6, 0.5, 0.9)
	sb.set_border_width_all(2)
	return sb


func _refresh_simple() -> void:
	if _simple_grid == null:
		return
	for g in _simple_buttons.keys():
		var b: Button = _simple_buttons[g]
		var st := _simple_state(g)
		b.button_pressed = (_selected == "simple:" + g)
		b.text = ""
		b.icon = null
		b.remove_theme_stylebox_override("normal")
		match st.state:
			"filled":
				b.icon = _tile_texture(st.tiles.values()[0])
				b.tooltip_text = "%s\nOne tile in all %d slots. Right-click to empty them." % [_group_name(g), st.members.size()]
			"partial":
				b.icon = _tile_texture(st.tiles.values()[0])
				b.add_theme_stylebox_override("normal", _frame_urgent() if st.asked else _frame_empty())
				b.tooltip_text = "%s\n%d of %d slots still empty. A tile here fills them all." % [
					_group_name(g), st.empty_count, st.members.size()]
			"mixed":
				# Too small for words: one of its tiles, in the purple frame that says "mixed".
				b.icon = _tile_texture(st.tiles.values()[0])
				b.add_theme_stylebox_override("normal", _frame_mixed())
				b.tooltip_text = "%s\nIts %d slots hold %d different tiles (set in Advanced). A tile here replaces them all." % [
					_group_name(g), st.members.size(), st.tiles.size()]
			_:
				b.add_theme_stylebox_override("normal", _frame_urgent() if st.asked else _frame_empty())
				b.tooltip_text = "%s\nEmpty, %d slots. Pick a tile below." % [_group_name(g), st.members.size()]


func _selected_slots() -> Array:
	if _selected == "":
		return []
	if _selected.begins_with("simple:"):
		return CliffData.simple_members(_selected.trim_prefix("simple:"))
	return [_selected]


func _useless_slots() -> Array:
	var out := []
	for k in _cfg.get("slots", {}).keys():
		var p: PackedStringArray = str(k).split("/")
		if p.size() != 2 or not (p[0] in CliffData.ROWS) or not (p[1] in CliffData.CASES):
			out.append(str(k))
			continue
		if not CliffData.slot_reachable(p[0], p[1], _height_of_row(p[0])):
			out.append(str(k))
	out.sort()
	return out


## Remove obsolete slots only from owned sheets; inherited data belongs to another terrain.
func _migrate_orphan_slots(cliff_name: String) -> void:
	if _inherited_from() != "":
		return
	var orphans := _useless_slots()
	if orphans.is_empty():
		return
	for k in orphans:
		_cfg["slots"].erase(k)
	_save()
	print("[BetterTerrain] %s: dropped %d slot(s) no version of the table can use: %s" % [
		cliff_name, orphans.size(), ", ".join(orphans)])


func _on_clear_all() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = tr("Remove the cliff configuration for '%s'?\n\nThis clears the sheet, its height settings and any inheritance link. You can undo this change.") % terrain_name
	dialog.title = tr("Clear the sheet")
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		clear_requested.emit(tile_set, terrain_name)
		reload_config()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


## Re-read the sheet after it was cleared or restored from outside.
func reload_config() -> void:
	_cfg = CliffData.config_of(tile_set, terrain_name)
	if CliffPattern.is_pattern(_cfg):
		_kind = KIND_PATTERN
	elif _kind == KIND_PATTERN:
		_kind = KIND_SIMPLE
	_simple_mode = _kind == KIND_SIMPLE
	_kind_pick.select(_kind)
	_height_spin.set_value_no_signal(int(_cfg.get("height", 2)))
	_selected = ""
	_pattern_armed = ""
	_refresh_mask()
	_refresh()


func _update_info() -> void:
	if _info == null:
		return
	if _selected == "":
		_info.text = "%s  height=%d  (no slot selected)" % [terrain_name, _height()]
		return
	var group := ""
	var concrete := _selected
	if _selected.begins_with("simple:"):
		group = _selected.trim_prefix("simple:")
		concrete = _slot_by_cell.get(_last_cell, "")
		if concrete == "":
			_info.text = "%s  group=%s  height=%d  (click a cell of the preview for its slot)" % [
				terrain_name, group, _height()]
			return
	var parts := concrete.split("/")
	var tile := CliffData.slot_tile(_cfg, parts[0], parts[1])
	if tile.is_empty():
		tile = CliffData.resolve_tile(_cfg, parts[0], parts[1])
	var where := "cell=%s  " % _last_cell if _last_cell.x > -9000 else ""
	if _last_faces.has(_last_cell):
		where += "left=%s right=%s  hangs from y=%d  " % [
			CliffData._side(_last_plateau, _last_faces, _last_cell, -1),
			CliffData._side(_last_plateau, _last_faces, _last_cell, 1),
			_last_faces[_last_cell].edge]
	var what := "tile=EMPTY"
	if not tile.is_empty():
		var bs := CliffData.block_size(tile)
		what = "tile=source:%d atlas:%s" % [int(tile.source_id), tile.coord]
		if bs != Vector2i.ONE:
			what += " block=%dx%d" % [bs.x, bs.y]
	_info.text = "%s  %sslot=%s  %s%s  height=%d" % [
		terrain_name, ("group=%s  " % group) if group != "" else "", concrete, where, what, _height()]
