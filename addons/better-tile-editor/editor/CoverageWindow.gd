@tool
extends ConfirmationDialog
## Complete terrain: the pieces a Match terrain lacks, made from turned tiles or quarters, plus
## fill variety and collision. Applying is one undo step.

const Coverage := preload("res://addons/better-tile-editor/editor/TerrainCoverage.gd")
const Quarters := preload("res://addons/better-tile-editor/editor/QuarterPieces.gd")
const Shapes := preload("res://addons/better-tile-editor/editor/CollisionShapes.gd")
const Collisions := preload("res://addons/better-tile-editor/editor/Collisions.gd")
const PreviewMap := preload("res://addons/better-tile-editor/editor/PreviewMap.gd")
const TURNS_SETTING := "editors/better_terrain/coverage_turns"
const QUARTERS_SETTING := "editors/better_terrain/coverage_quarters"
const SHAPES_SETTING := "editors/better_terrain/coverage_shapes"
const ART_SETTING := "editors/better_terrain/coverage_shapes_art"
const CORNERS_SETTING := "editors/better_terrain/coverage_inner_corners"
const BEND_SETTING := "editors/better_terrain/coverage_inner_bend"
enum Scope { NEW, EVERY }
## Which pieces the collision reaches: all, those with an open side or a notch, the fill.
enum Where { ALL, EDGES, INSIDE }
## Menu id of "From art"; the kind of reading is picked beside it.
const SHAPES_ART := 104
const SHAPE_NAMES := {
	Quarters.SHAPES_KEEP: "Keep current", Quarters.SHAPES_FULL: "Full tile",
	Quarters.SHAPES_STRIP: "Border strip", SHAPES_ART: "From art", Quarters.SHAPES_NONE: "Remove",
}
const ART_NAMES := {
	Shapes.Auto.CONTOUR: "Outline", Shapes.Auto.CONVEX: "Convex", Shapes.Auto.BOX: "Box", Shapes.Auto.BASE: "Base",
}
const WHERE_NAMES := {Where.ALL: "All pieces", Where.EDGES: "Edge pieces", Where.INSIDE: "Inner pieces"}
const TURN_ICONS := [[Coverage.Turns.MIRROR, "MirrorX", "Mirror"], [Coverage.Turns.FLIP, "MirrorY", "Flip"],
	[Coverage.Turns.ROTATE, "RotateRight", "Rotate"]]
const FACE_NOTHING := 1000
const DIAGRAM := 36.0
const PREVIEW := 48.0
## A map to paint with the pieces: a big block with a notch, corridors, ends, Ts, a cross, a ring.
const SAMPLE := [
	"................",
	".#######....#...",
	".#######...###..",
	".#######....#...",
	".#######........",
	".#######.######.",
	".##.####.#....#.",
	"........##.##.#.",
	".######..#.#..#.",
	".#.......#.####.",
	".#.#####.#......",
	".#...#...######.",
	"................",
]

## {added, removed, built, variety, collision, other, with_corners}; a collision layer equal to
## the layer count means a new one.
signal applied(plan: Dictionary)

var _ts: TileSet
var _terrain_id := -1
var _report := {}
var _summary: Label
var _summary_detail: Label
var _turn_checks := {}
var _light_warning: TextureRect
var _quarters_check: CheckBox
var _corners_check: CheckBox
## Each section is part of what Apply does only while its title's tick is on; collision
## starts off every time, so nothing gets shapes unasked.
var _make_on: CheckBox
var _variety_on: CheckBox
var _collision_on: CheckBox
var _bend_pick: OptionButton
var _other_row: HBoxContainer
var _other_pick: OptionButton
## What open sides border: nothing (-1) or another terrain, for transitions.
var _other := -1
var _other_fill := {}
var _lists: VBoxContainer
## How many missing pieces have a card, for tests and the summary.
var _missing_cards := 0
## Card checks and what they stand for: {CheckBox: source} for additions, removals, builds.
var _adds := {}
var _removes := {}
var _builds := {}
var _variety_section: Section
var _variety_checks := {}
var _variety_weight: SpinBox
var _variety_note: Label
var _collision_section: Section
var _shape_mode: OptionButton
var _strip_px: SpinBox
var _art_kind: OptionButton
var _apply_row: HBoxContainer
var _shape_where: OptionButton
var _shape_layer: OptionButton
var _replace_check: CheckBox
var _shape_cache := {}
var _sample: PreviewMap
var _show_shapes: CheckBox
var _shuffle_button: Button
## Reseeds the preview's random picks.
var _shuffle := 0
var _where: Label


func _init() -> void:
	title = "Complete terrain"
	ok_button_text = "Apply"
	min_size = Vector2i(760, 520)
	# The card flow is one card wide until laid out; growing to that would never shrink back.
	wrap_controls = false
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	add_child(main)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(box)
	main.add_child(VSeparator.new())
	main.add_child(_build_preview())

	_summary = Label.new()
	_summary.theme_type_variation = &"HeaderMedium"
	box.add_child(_summary)
	_summary_detail = Label.new()
	_summary_detail.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_summary_detail)
	var make := _build_make_section()
	box.add_child(make)
	box.add_child(_build_variety_section())
	box.add_child(_build_collision_section())
	# The cards take the free height while open; folded, the sections stack at the top.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.visible = false
	box.add_child(spacer)
	make.folding_changed.connect(func(folded: bool):
		make.size_flags_vertical = Control.SIZE_FILL if folded else Control.SIZE_EXPAND_FILL
		spacer.visible = folded)
	_where = Label.new()
	_where.modulate = Color(1, 1, 1, 0.6)
	_where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_where)
	confirmed.connect(_on_confirmed)


func _build_preview() -> Control:
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 300
	var head := HBoxContainer.new()
	side.add_child(head)
	var heading := Label.new()
	heading.text = "Preview"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	_show_shapes = CheckBox.new()
	_show_shapes.text = "Collision"
	_show_shapes.tooltip_text = "Show the collision shapes"
	_show_shapes.toggled.connect(func(_on): _sample.queue_redraw())
	head.add_child(_show_shapes)
	_shuffle_button = Button.new()
	_shuffle_button.icon = _icon("RandomNumberGenerator")
	_shuffle_button.flat = true
	_shuffle_button.pressed.connect(func(): _shuffle += 1; _sample.queue_redraw())
	head.add_child(_shuffle_button)
	var fit := Button.new()
	fit.icon = _icon("ZoomReset")
	fit.flat = true
	fit.tooltip_text = "Fit the map (or double-click it)"
	fit.pressed.connect(func(): _sample.fit())
	head.add_child(fit)
	_sample = PreviewMap.new()
	_sample.grid = Vector2i(SAMPLE[0].length(), SAMPLE.size())
	_sample.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sample.draw.connect(_draw_sample)
	side.add_child(_sample)
	var legend := Label.new()
	legend.text = "Red = no piece yet"
	legend.modulate = Color(1, 1, 1, 0.6)
	side.add_child(legend)
	return side


func _build_make_section() -> Control:
	var section := Section.new()
	section.title = "Missing pieces"
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.set_body(column)
	_make_on = _section_tick(section, true, func(_on): _fill())
	var turns := _row(column, "Transform")
	for entry: Array in TURN_ICONS:
		var toggle := _icon_toggle(entry[1], "%s a drawn tile into a missing piece" % entry[2])
		toggle.toggled.connect(func(_on): _store_turns(); _sync_warning(); _fill())
		turns.add_child(toggle)
		_turn_checks[entry[0]] = toggle
	_light_warning = TextureRect.new()
	_light_warning.texture = _icon("StatusWarning")
	_light_warning.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_light_warning.tooltip_text = "Flipped or rotated art moves its shading."
	_light_warning.mouse_filter = Control.MOUSE_FILTER_PASS
	turns.add_child(_light_warning)
	_quarters_check = CheckBox.new()
	_quarters_check.text = "Build from quarters"
	_quarters_check.tooltip_text = "Put the rest together from quarters of your drawn tiles, saved as a new sheet."
	_quarters_check.toggled.connect(func(on): EditorInterface.get_editor_settings().set_setting(QUARTERS_SETTING, on); _fill())
	column.add_child(_quarters_check)
	_corners_check = CheckBox.new()
	_corners_check.text = "Inner corners"
	_corners_check.tooltip_text = ("This terrain has no inner corner drawn. Make them from its edges, bent round\n"
		+ "the corner, so junctions get a notch; its drawn tiles get their corner bits.")
	_corners_check.toggled.connect(func(on): EditorInterface.get_editor_settings().set_setting(CORNERS_SETTING, on); _fill())
	var corners_row := HBoxContainer.new()
	corners_row.add_theme_constant_override("separation", 8)
	corners_row.add_child(_corners_check)
	_bend_pick = OptionButton.new()
	_bend_pick.add_item("Round", Quarters.Bend.ROUND)
	_bend_pick.add_item("Mitre", Quarters.Bend.MITRE)
	_bend_pick.add_item("Square", Quarters.Bend.SQUARE)
	_bend_pick.tooltip_text = ("How a made inner corner bends the outline. Round: turned round the corner,\n"
		+ "keeping the edge's shading. Mitre: the two bands meet on the diagonal. Square: they cross in an L.")
	_bend_pick.item_selected.connect(func(_i): EditorInterface.get_editor_settings().set_setting(BEND_SETTING, _bend_pick.get_selected_id()); _fill())
	corners_row.add_child(_bend_pick)
	column.add_child(corners_row)
	_other_row = _row(column, "Open sides border")
	_other_pick = OptionButton.new()
	_other_pick.tooltip_text = "Empty, or another terrain for a transition (grass into dirt)."
	_other_pick.item_selected.connect(func(_i): _set_other(_other_pick.get_selected_id()))
	_other_row.add_child(_other_pick)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 120
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_lists = VBoxContainer.new()
	_lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lists.add_theme_constant_override("separation", 6)
	scroll.add_child(_lists)
	return section


func _build_variety_section() -> Control:
	_variety_section = Section.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_variety_section.set_body(row)
	_variety_section.folded = true
	_variety_on = _section_tick(_variety_section, false, func(_on): _sync_sections())
	var label := Label.new()
	label.text = "Transform"
	row.add_child(label)
	for entry: Array in TURN_ICONS:
		var toggle := _icon_toggle(entry[1], "%s the fill at random, so large areas don't repeat" % entry[2])
		toggle.toggled.connect(func(_on): _sync_titles(); _sync_warning(); _sample.queue_redraw())
		row.add_child(toggle)
		_variety_checks[entry[0]] = toggle
	var chance := Label.new()
	chance.text = "Chance"
	row.add_child(chance)
	_variety_weight = SpinBox.new()
	_variety_weight.min_value = 5
	_variety_weight.max_value = 100
	_variety_weight.step = 5
	_variety_weight.value = 50
	_variety_weight.suffix = "%"
	_variety_weight.tooltip_text = "How likely each transformed copy is, against the fill as drawn."
	_variety_weight.value_changed.connect(func(_v): _sync_titles(); _sample.queue_redraw())
	row.add_child(_variety_weight)
	_variety_note = Label.new()
	_variety_note.modulate = Color(1, 1, 1, 0.6)
	row.add_child(_variety_note)
	return _variety_section


func _build_collision_section() -> Control:
	_collision_section = Section.new()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_collision_section.set_body(column)
	_collision_section.folded = true
	_collision_on = _section_tick(_collision_section, false, func(on):
		# Turning collision on is wanting to see it.
		if on:
			_show_shapes.button_pressed = true
		_sync_sections())
	var shape_row := _row(column, "Shape")
	_shape_mode = OptionButton.new()
	for id: int in SHAPE_NAMES:
		_shape_mode.add_item(SHAPE_NAMES[id], id)
	_shape_mode.tooltip_text = ("Keep current: drawn tiles keep theirs; new pieces get their quarters' shapes.\n"
		+ "Border strip: a band along the open sides and round the notches.\nFrom art: read from the drawing.")
	_shape_mode.item_selected.connect(func(_i):
		# Picking a shape is wanting to see it.
		if _shape_mode.get_selected_id() != Quarters.SHAPES_KEEP:
			_show_shapes.button_pressed = true
		EditorInterface.get_editor_settings().set_setting(SHAPES_SETTING, _shape_mode.get_selected_id())
		_sync_shapes())
	shape_row.add_child(_shape_mode)
	_strip_px = SpinBox.new()
	_strip_px.min_value = 1
	_strip_px.max_value = 64
	_strip_px.value = 2
	_strip_px.suffix = "px"
	_strip_px.tooltip_text = "How deep the band is"
	_strip_px.value_changed.connect(func(_v): _sync_shapes())
	shape_row.add_child(_strip_px)
	_art_kind = OptionButton.new()
	for id: int in ART_NAMES:
		_art_kind.add_item(ART_NAMES[id], id)
	_art_kind.item_selected.connect(func(_i): EditorInterface.get_editor_settings().set_setting(ART_SETTING, _art_kind.get_selected_id()); _sync_shapes())
	shape_row.add_child(_art_kind)
	_apply_row = _row(column, "Apply to")
	_shape_where = OptionButton.new()
	for id: int in WHERE_NAMES:
		_shape_where.add_item(WHERE_NAMES[id], id)
	_shape_where.tooltip_text = "Edge pieces have an open side or a notch; inner pieces are the fill."
	_shape_where.item_selected.connect(func(_i): _sync_shapes())
	_apply_row.add_child(_shape_where)
	var layer_label := Label.new()
	layer_label.text = "Layer"
	_apply_row.add_child(layer_label)
	_shape_layer = OptionButton.new()
	_shape_layer.item_selected.connect(func(_i): _sync_shapes())
	_apply_row.add_child(_shape_layer)
	_replace_check = CheckBox.new()
	_replace_check.text = "Also replace drawn tiles' shapes"
	_replace_check.button_pressed = true
	_replace_check.toggled.connect(func(_on): _sync_shapes())
	column.add_child(_replace_check)
	return _collision_section


func _section_tick(section: Section, on: bool, toggled: Callable) -> CheckBox:
	section.tick.button_pressed = on
	section.tick.toggled.connect(toggled)
	return section.tick


func _sync_sections() -> void:
	# Collision in the preview only means something when collision is being made.
	_show_shapes.visible = _collision_on.button_pressed
	_shape_cache.clear()
	_sync_titles()
	_sync_warning()
	_sample.queue_redraw()


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = text
	row.add_child(label)
	parent.add_child(row)
	return row


func _icon_toggle(icon_name: String, tip: String) -> Button:
	var toggle := Button.new()
	toggle.icon = _icon(icon_name)
	toggle.toggle_mode = true
	toggle.tooltip_text = tip
	return toggle


static func _icon(icon_name: String) -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(icon_name, &"EditorIcons")


func setup(ts: TileSet, terrain_id: int) -> void:
	_ts = ts
	_terrain_id = terrain_id
	var settings := EditorInterface.get_editor_settings()
	var stored := int(settings.get_setting(TURNS_SETTING)) if settings.has_setting(TURNS_SETTING) else Coverage.Turns.MIRROR
	for bit: int in _turn_checks:
		_turn_checks[bit].set_pressed_no_signal(stored & bit != 0)
	_quarters_check.set_pressed_no_signal(not settings.has_setting(QUARTERS_SETTING) or bool(settings.get_setting(QUARTERS_SETTING)))
	_corners_check.set_pressed_no_signal(not settings.has_setting(CORNERS_SETTING) or bool(settings.get_setting(CORNERS_SETTING)))
	if settings.has_setting(BEND_SETTING):
		_bend_pick.select(maxi(0, _bend_pick.get_item_index(int(settings.get_setting(BEND_SETTING)))))
	title = "Complete terrain: %s" % BetterTerrain.get_terrain(ts, terrain_id).name
	_shape_layer.clear()
	for layer in ts.get_physics_layers_count():
		_shape_layer.add_item("Layer %d" % layer, layer)
	_shape_layer.add_item("New layer", ts.get_physics_layers_count())
	var stored_shape := int(settings.get_setting(SHAPES_SETTING)) if settings.has_setting(SHAPES_SETTING) else Quarters.SHAPES_KEEP
	# Before the art kinds had their own menu, they were stored as the mode.
	if ART_NAMES.has(stored_shape):
		settings.set_setting(ART_SETTING, stored_shape)
		stored_shape = SHAPES_ART
	_shape_mode.select(maxi(0, _shape_mode.get_item_index(stored_shape)))
	if settings.has_setting(ART_SETTING):
		_art_kind.select(maxi(0, _art_kind.get_item_index(int(settings.get_setting(ART_SETTING)))))
	_other_pick.clear()
	_other_pick.add_item("Empty", FACE_NOTHING)
	var others := Coverage.neighbours(ts, terrain_id)
	for other: int in others:
		_other_pick.add_item("%s (%d tile%s)" % [BetterTerrain.get_terrain(ts, other).name, others[other], "" if others[other] == 1 else "s"], other)
	_other_row.visible = not others.is_empty()
	_fill()
	# A border strip starts a sixteenth of the tile deep: 1 px on 16 px tiles.
	_strip_px.set_value_no_signal(maxi(1, int(_region_size().x / 16.0)))
	_load_variety()
	_sync_shapes()
	_sync_sections()


func _set_other(id: int) -> void:
	_other = -1 if id == FACE_NOTHING else id
	_other_fill = {}
	if _other >= 0:
		var other_report := Coverage.analyse(_ts, _other)
		if other_report.get("error", "").is_empty() and not other_report.fill_tiles.is_empty():
			var tile: Dictionary = other_report.fill_tiles[0]
			_other_fill = {source_id = tile.source_id, coord = tile.coord, alt = 0, flags = 0}
	_shape_cache.clear()
	_fill()
	_load_variety()


## The collision choice as the pieces take it: the mode (an art kind for "From art") and its settings.
func _shape_choice() -> Dictionary:
	var mode := _shape_mode.get_selected_id()
	if mode == SHAPES_ART:
		mode = _art_kind.get_selected_id()
	return {mode = mode, strip = _strip_px.value, type = _report.get("type", 0), with_corners = _report.get("with_corners", true)}


func _sync_shapes() -> void:
	var id := _shape_mode.get_selected_id()
	var keep := id == Quarters.SHAPES_KEEP
	_strip_px.visible = id == Quarters.SHAPES_STRIP
	_art_kind.visible = id == SHAPES_ART
	_apply_row.visible = not keep
	_replace_check.visible = not keep
	_shape_cache.clear()
	_sync_titles()
	_sample.queue_redraw()


func _sync_warning() -> void:
	var turns := _turns() | (_variety_turns() if _variety_on.button_pressed else 0)
	var moved := turns & (Coverage.Turns.FLIP | Coverage.Turns.ROTATE) != 0
	_light_warning.visible = moved


## The section titles carry their state, so a folded one still says what it will do.
func _sync_titles() -> void:
	var names := []
	for entry: Array in TURN_ICONS:
		if _variety_checks[entry[0]].button_pressed:
			names.append(entry[2])
	_variety_section.title = "Vary the fill · " + ("off" if names.is_empty() or not _variety_on.button_pressed else "%s · %d%%" % [", ".join(names), int(_variety_weight.value)])
	var id := _shape_mode.get_selected_id()
	var shape: String = SHAPE_NAMES[id]
	if id == Quarters.SHAPES_STRIP:
		shape += " %d px" % int(_strip_px.value)
	elif id == SHAPES_ART:
		shape += ": " + ART_NAMES[_art_kind.get_selected_id()]
	if id != Quarters.SHAPES_KEEP:
		shape += " · " + WHERE_NAMES[_shape_where.get_selected_id()].to_lower()
	_collision_section.title = "Collision · " + (shape if _collision_on.button_pressed else "off")


# The variety toggles start as the fill tiles have them.
func _load_variety() -> void:
	if _report.is_empty() or not _report.error.is_empty():
		return
	var turns := 0
	var weight := 0.5
	for source: Dictionary in _report.variety:
		turns |= Coverage.Turns.ROTATE if source.flags & Coverage.T else 0
		turns |= Coverage.Turns.MIRROR if source.flags & Coverage.H else 0
		turns |= Coverage.Turns.FLIP if source.flags & Coverage.V else 0
		var src := _ts.get_source(source.source_id) as TileSetAtlasSource
		weight = BetterTerrain.get_tile_transform_weight(src.get_tile_data(source.coord, source.alt))
	for bit: int in _variety_checks:
		_variety_checks[bit].set_pressed_no_signal(turns & bit != 0)
	_variety_weight.set_value_no_signal(weight * 100.0)
	var none: bool = _report.fill_tiles.is_empty()
	for bit: int in _variety_checks:
		_variety_checks[bit].disabled = none
	_variety_weight.editable = not none
	_variety_note.text = "No fill tile" if none else ""
	_sync_titles()


func _variety_turns() -> int:
	var out := 0
	for bit: int in _variety_checks:
		if _variety_checks[bit].button_pressed:
			out |= bit
	return out


func _turns() -> int:
	var out := 0
	for bit: int in _turn_checks:
		if _turn_checks[bit].button_pressed:
			out |= bit
	return out


func _store_turns() -> void:
	EditorInterface.get_editor_settings().set_setting(TURNS_SETTING, _turns())


func _fill() -> void:
	for child in _lists.get_children():
		child.queue_free()
	_adds.clear()
	_removes.clear()
	_builds.clear()
	_missing_cards = 0
	# Off, Missing pieces changes nothing, inner corners included: the terrain shows as it is.
	_report = Coverage.analyse(_ts, _terrain_id, _other, _corners_check.button_pressed and _make_on.button_pressed)
	_corners_check.get_parent().visible = _report.get("type") == BetterTerrain.TerrainType.MATCH_TILES and not _report.get("drawn_corners", true)
	_bend_pick.disabled = not _corners_check.button_pressed
	if not _report.error.is_empty():
		_summary.text = _report.error
		_summary_detail.text = ""
		_sample.queue_redraw()
		get_ok_button().disabled = true
		_sync_apply()
		return
	var need: int = _report.required.size()
	var missing: Array = _report.missing
	var making := _make_on.button_pressed
	var suggestions := Coverage.suggest(_report, _turns()) if making else []
	var by_mask := {}
	for found: Dictionary in suggestions:
		by_mask[found.mask] = found
	var built := {}
	if making and _quarters_check.button_pressed:
		var found := Quarters.catalog(_ts, _report, _turns())
		found.bend = _bend_pick.get_selected_id()
		var sheets := {}
		var images := {}
		for mask: int in missing:
			if by_mask.has(mask):
				continue
			var quarters := Quarters.plan(_ts, found, mask, _report.with_corners, images)
			if not quarters.is_empty():
				built[mask] = {mask = mask, quarters = quarters, size = found.region_size,
					image = ImageTexture.create_from_image(Quarters.compose(_ts, quarters, found.region_size, sheets))}
	var shape := "blob" if _report.with_corners and _report.type == BetterTerrain.TerrainType.MATCH_TILES else "sides only"
	if _report.type == BetterTerrain.TerrainType.MATCH_VERTICES:
		shape = "corners"
	_summary.text = "%d / %d pieces (%s)" % [need - missing.size(), need, shape]
	var draw := missing.size() - suggestions.size() - built.size()
	if _report.tiles.is_empty():
		_summary_detail.text = "No tile has this terrain yet."
	elif missing.is_empty():
		_summary_detail.text = "Nothing missing"
	elif not making:
		_summary_detail.text = "%d missing" % missing.size()
	else:
		var parts := ["%d missing" % missing.size()]
		if not suggestions.is_empty():
			parts.append("%d by transform" % suggestions.size())
		if not built.is_empty():
			parts.append("%d can be built" % built.size())
		if draw > 0:
			parts.append("%d need drawing" % draw)
		_summary_detail.text = " · ".join(parts)
	var transformed := missing.filter(func(m): return by_mask.has(m))
	var from_quarters := missing.filter(func(m): return built.has(m))
	var to_draw := missing.filter(func(m): return not by_mask.has(m) and not built.has(m))
	_group("Transformed", transformed.map(func(m): return _card(m, by_mask[m], true)))
	_group("From quarters", from_quarters.map(func(m): return _card(m, built[m], true)))
	_group("Needs drawing", to_draw.map(func(m): return _card(m, {}, true)))
	_group("Transforms in use", (_report.turns as Array).map(func(t): return _card(t.mask, t, false)))
	_missing_cards = missing.size()
	get_ok_button().disabled = false
	_sync_apply()
	_sample.queue_redraw()
	_settle.call_deferred()


## A titled group of cards, with All and None when they have ticks.
func _group(heading: String, cards: Array) -> void:
	if cards.is_empty():
		return
	var head := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s (%d)" % [heading, cards.size()]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	var checks := []
	for card: Control in cards:
		checks.append_array(card.find_children("*", "CheckBox", true, false))
	if not checks.is_empty():
		for entry in [["All", true], ["None", false]]:
			var button := Button.new()
			button.text = entry[0]
			button.flat = true
			button.pressed.connect(func():
				for check: CheckBox in checks:
					check.button_pressed = entry[1])
			head.add_child(button)
	_lists.add_child(head)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for card: Control in cards:
		flow.add_child(card)
	_lists.add_child(flow)


# The dialog sizes its content while the card flow is still one card wide, and keeps that
# height; a resize lays it out again to fit the window.
func _settle() -> void:
	if visible:
		size += Vector2i(0, 1)
		size -= Vector2i(0, 1)


## The OK button says what it adds; the footer, where new art is saved.
func _sync_apply() -> void:
	var count := 0
	var building := false
	for checks: Dictionary in [_adds, _builds]:
		for check: CheckBox in checks:
			if check.button_pressed:
				count += 1
				building = building or checks == _builds
	ok_button_text = ("Add %d piece%s" % [count, "" if count == 1 else "s"]) if count > 0 else "Apply"
	_where.text = ""
	if building:
		var first: Dictionary = _builds.values()[0].quarters[0]
		_where.text = "Saves to %s" % Quarters.file_for(_ts, BetterTerrain.get_terrain(_ts, _terrain_id).name,
			first.source_id, BetterTerrain.get_terrain(_ts, _other).name if _other >= 0 else "")


func _card(mask: int, source: Dictionary, adding: bool) -> Control:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	card.add_child(row)
	var diagram := Control.new()
	diagram.custom_minimum_size = Vector2(DIAGRAM, DIAGRAM)
	diagram.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	diagram.draw.connect(func(): _draw_diagram(diagram, mask))
	diagram.tooltip_text = "The neighbours this piece joins"
	row.add_child(diagram)
	var preview := Control.new()
	preview.custom_minimum_size = Vector2(PREVIEW, PREVIEW)
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.draw.connect(func(): _draw_preview(preview, source))
	row.add_child(preview)
	if source.is_empty():
		card.tooltip_text = "No drawn tile makes this piece: draw it"
		return card
	var check := CheckBox.new()
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if source.has("quarters"):
		var parts := []
		for quarter in 4:
			var from: Dictionary = source.quarters[quarter]
			var corner_name: String = ["top left", "top right", "bottom left", "bottom right"][quarter]
			if from.has("synth"):
				parts.append("%s: inner corner, made from the edges" % corner_name)
			else:
				parts.append("%s: %d,%d %s" % [corner_name, from.coord.x, from.coord.y, Coverage.flag_name(from.flags)])
		check.tooltip_text = "Built from 4 quarters:\n" + "\n".join(parts)
		check.button_pressed = true
		_builds[check] = {mask = source.mask, quarters = source.quarters, size = source.size, image = source.image}
	elif adding:
		check.tooltip_text = "Tile %d,%d %s" % [source.coord.x, source.coord.y, Coverage.flag_name(source.flags)]
		check.button_pressed = true
		_adds[check] = source
	else:
		var spare := Coverage.redundant(_report, source)
		check.text = "Remove (now drawn)" if spare else "Remove"
		check.button_pressed = spare
		check.tooltip_text = "Tile %d,%d %s. %s" % [source.coord.x, source.coord.y, Coverage.flag_name(source.flags),
			"A drawn tile has these joins now; this only competes with it." if spare else "Stop using this transform."]
		_removes[check] = source
	check.toggled.connect(func(_on): _sync_apply(); _sample.queue_redraw())
	preview.tooltip_text = check.tooltip_text
	row.add_child(check)
	return card


func _draw_diagram(canvas: Control, mask: int) -> void:
	var cell := DIAGRAM / 3.0
	var colour: Color = BetterTerrain.get_terrain(_ts, _terrain_id).color
	var empty := Color(1, 1, 1, 0.08)
	var places := {
		-1: Vector2i(1, 1),
		TileSet.CELL_NEIGHBOR_RIGHT_SIDE: Vector2i(2, 1), TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: Vector2i(1, 2),
		TileSet.CELL_NEIGHBOR_LEFT_SIDE: Vector2i(0, 1), TileSet.CELL_NEIGHBOR_TOP_SIDE: Vector2i(1, 0),
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: Vector2i(2, 2), TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: Vector2i(0, 2),
		TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: Vector2i(0, 0), TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: Vector2i(2, 0),
	}
	for bit: int in places:
		var r := Rect2(Vector2(places[bit]) * cell, Vector2(cell, cell)).grow(-1)
		var on := bit == -1 or mask & (1 << bit) != 0
		canvas.draw_rect(r, colour if on else empty)
	canvas.draw_rect(Rect2(Vector2(cell, cell), Vector2(cell, cell)).grow(-1), Color.WHITE, false, 1.0)


func _draw_preview(canvas: Control, source: Dictionary) -> void:
	var area := Rect2(Vector2.ZERO, Vector2(PREVIEW, PREVIEW))
	canvas.draw_rect(area, Color(0, 0, 0, 0.25))
	if source.is_empty():
		canvas.draw_string(canvas.get_theme_default_font(), Vector2(PREVIEW * 0.5 - 4, PREVIEW * 0.5 + 6), "?",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.4))
		return
	_draw_tile(canvas, source, area)


## A piece fitted in a rect: a made image, or a tile turned as its flags say.
func _draw_tile(canvas: Control, source: Dictionary, area: Rect2) -> void:
	if source.has("image"):
		var image: Texture2D = source.image
		var fit_size := image.get_size() * minf(area.size.x / image.get_width(), area.size.y / image.get_height())
		canvas.draw_texture_rect(image, Rect2(area.position + (area.size - fit_size) * 0.5, fit_size), false)
		return
	var src := _ts.get_source(source.source_id) as TileSetAtlasSource
	if src == null or src.texture == null or not src.has_tile(source.coord):
		return
	var region := Rect2(src.get_tile_texture_region(source.coord))
	var fit := minf(area.size.x / region.size.x, area.size.y / region.size.y)
	var flags: int = source.flags
	canvas.draw_set_transform_matrix(Transform2D(_turned(Vector2.RIGHT, flags) * fit, _turned(Vector2.DOWN, flags) * fit, area.get_center()))
	canvas.draw_texture_rect_region(src.texture, Rect2(-region.size * 0.5, region.size), region)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## The pieces the preview may pick per mask, weighted as the solver does: {mask: [[source, weight]]}.
func _sample_choices() -> Dictionary:
	var dropped := []
	for check: CheckBox in _removes:
		if check.button_pressed:
			dropped.append(_removes[check])
	var out := {}
	for mask: int in _report.pieces:
		var choices := []
		for source: Dictionary in _report.pieces[mask]:
			if dropped.any(func(d): return d.source_id == source.source_id and d.coord == source.coord and d.flags == source.flags):
				continue
			var td := (_ts.get_source(source.source_id) as TileSetAtlasSource).get_tile_data(source.coord, source.alt)
			var weight := td.probability * (1.0 if source.flags == 0 else BetterTerrain.get_tile_transform_weight(td))
			choices.append([source, weight])
		if not choices.is_empty():
			out[mask] = choices
	if not _report.fill_tiles.is_empty() and _variety_on.button_pressed:
		out[_report.fill] = _fill_choices()
	for checks: Dictionary in [_adds, _builds]:
		for check: CheckBox in checks:
			if check.button_pressed and not out.has(checks[check].mask):
				out[checks[check].mask] = [[checks[check], 1.0]]
	return out


func _draw_sample() -> void:
	var area := Rect2(Vector2.ZERO, _sample.size)
	_sample.draw_rect(area, Color(0, 0, 0, 0.25))
	if _report.is_empty() or not _report.error.is_empty():
		return
	var choices := _sample_choices()
	var rng := RandomNumberGenerator.new()
	var random := false
	var rows := SAMPLE.size()
	var cols: int = SAMPLE[0].length()
	var view := _sample.current()
	var cell: float = view.cell
	var origin: Vector2 = view.origin
	var steps := {
		TileSet.CELL_NEIGHBOR_RIGHT_SIDE: Vector2i(1, 0), TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: Vector2i(0, 1),
		TileSet.CELL_NEIGHBOR_LEFT_SIDE: Vector2i(-1, 0), TileSet.CELL_NEIGHBOR_TOP_SIDE: Vector2i(0, -1),
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: Vector2i(1, 1), TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: Vector2i(-1, 1),
		TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: Vector2i(-1, -1), TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: Vector2i(1, -1),
	}
	var other_colour: Color = BetterTerrain.get_terrain(_ts, _other).color if _other >= 0 else Color.TRANSPARENT
	for y in rows:
		for x in cols:
			var r := Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell))
			if not _painted(x, y):
				if _other >= 0:
					if _other_fill.is_empty():
						_sample.draw_rect(r, Color(other_colour, 0.5))
					else:
						_draw_tile(_sample, _other_fill, r)
				continue
			var mask := Coverage.normalize(_cell_mask(x, y, steps), _report.type, _report.with_corners)
			var options: Array = choices.get(mask, [])
			if options.is_empty():
				_sample.draw_rect(r.grow(-1), Color(0.9, 0.2, 0.2, 0.55))
				continue
			random = random or options.size() > 1
			rng.seed = hash(Vector3i(x, y, _shuffle))
			var piece := _pick(options, rng)
			_draw_tile(_sample, piece, r)
			if _show_shapes.button_pressed and _collision_on.button_pressed:
				_draw_shapes(piece, mask, r)
	_sync_shuffle.call_deferred(random)


func _sync_shuffle(random: bool) -> void:
	_shuffle_button.disabled = not random
	_shuffle_button.tooltip_text = "Re-roll random tiles" if random else "Nothing random to pick: vary the fill, or draw variants of a piece"


func _draw_shapes(piece: Dictionary, mask: int, r: Rect2) -> void:
	var size := Vector2(_region_size())
	var scale := r.size / size
	var colour := Collisions.overlay_color()
	for shape: Dictionary in _piece_shapes(piece, mask):
		var points := PackedVector2Array()
		for v: Vector2 in shape.points:
			points.append(r.get_center() + v * scale)
		if points.size() >= 3 and not Geometry2D.triangulate_polygon(points).is_empty():
			_sample.draw_colored_polygon(points, colour)
		points.append(points[0])
		_sample.draw_polyline(points, Color(colour, 1.0), 1.0)


func _region_size() -> Vector2i:
	for tile: Dictionary in _report.tiles:
		return (_ts.get_source(tile.source_id) as TileSetAtlasSource).texture_region_size
	return _ts.tile_size


## The shapes a piece would have once applied, centred on it, as the collision section says.
func _piece_shapes(piece: Dictionary, mask: int) -> Array:
	var choice := _shape_choice()
	var keep := _shape_mode.get_selected_id() == Quarters.SHAPES_KEEP or not _collision_on.button_pressed
	var layer := _shape_layer.get_selected_id()
	var made := piece.has("quarters")
	var key := "%d|%s" % [mask, str(piece.quarters) if made else Quarters._key(piece)]
	if _shape_cache.has(key):
		return _shape_cache[key]
	var out := []
	if not keep and (made or _replace_check.button_pressed) and _reaches(mask):
		var image: Image = (piece.image as Texture2D).get_image() if made else Quarters.tile_image(_ts, piece, {})
		out = Quarters.piece_shapes(image, mask, choice)
	elif made and _collision_on.button_pressed:
		out = Quarters.quarter_shapes(_ts, piece.quarters, _region_size(), 0 if keep else layer)
	elif made:
		out = []
	else:
		var shown := 0 if keep else layer
		if shown < _ts.get_physics_layers_count():
			var src := _ts.get_source(piece.source_id) as TileSetAtlasSource
			for shape: Dictionary in Quarters.get_shapes(src.get_tile_data(piece.coord, 0), shown):
				var points := PackedVector2Array()
				for v in shape.points:
					points.append(Quarters._turned(v, piece.flags))
				out.append({points = points})
	_shape_cache[key] = out
	return out


## Whether the collision section reaches a piece with these joins.
func _reaches(mask: int) -> bool:
	match _shape_where.get_selected_id():
		Where.EDGES:
			return mask != _report.fill
		Where.INSIDE:
			return mask == _report.fill
	return true


## The fill tiles as drawn and, with variety ticked, their transformed copies: [[source, weight]].
func _fill_choices() -> Array:
	var out := []
	var flags_list := Coverage.allowed_flags(_variety_turns())
	for tile: Dictionary in _report.fill_tiles:
		var src := _ts.get_source(tile.source_id) as TileSetAtlasSource
		var probability := src.get_tile_data(tile.coord, 0).probability
		out.append([{source_id = tile.source_id, coord = tile.coord, alt = 0, flags = 0}, probability])
		for flags in flags_list:
			out.append([{source_id = tile.source_id, coord = tile.coord, alt = 0, flags = flags}, probability * _variety_weight.value / 100.0])
	return out


static func _pick(choices: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for choice: Array in choices:
		total += choice[1]
	var at := rng.randf() * total
	for choice: Array in choices:
		if at < choice[1]:
			return choice[0]
		at -= choice[1]
	return choices.back()[0]


## A sample cell's joins, read as the solver reads them: Match tiles by its neighbours, Match
## vertices by each corner, whose four cells must all be the terrain.
func _cell_mask(x: int, y: int, steps: Dictionary) -> int:
	var mask := 0
	for bit: int in steps:
		var step: Vector2i = steps[bit]
		if _report.type == BetterTerrain.TerrainType.MATCH_VERTICES:
			if Coverage.CORNERS.has(bit) and _painted(x + step.x, y) and _painted(x, y + step.y) and _painted(x + step.x, y + step.y):
				mask |= 1 << bit
		elif _painted(x + step.x, y + step.y):
			mask |= 1 << bit
	return mask


static func _painted(x: int, y: int) -> bool:
	return y >= 0 and y < SAMPLE.size() and x >= 0 and x < SAMPLE[y].length() and SAMPLE[y][x] == "#"


## A direction after a tile's transform: transposed first, then flipped, as the peering bits are.
static func _turned(v: Vector2, flags: int) -> Vector2:
	if flags & Coverage.T:
		v = Vector2(v.y, v.x)
	if flags & Coverage.H:
		v.x = -v.x
	if flags & Coverage.V:
		v.y = -v.y
	return v


func _on_confirmed() -> void:
	var added := []
	var removed := []
	var built := []
	for check: CheckBox in _builds:
		if check.button_pressed:
			built.append(_builds[check])
	for check: CheckBox in _adds:
		if check.button_pressed:
			added.append(_adds[check])
	for check: CheckBox in _removes:
		if check.button_pressed:
			removed.append(_removes[check])
	var variety := {}
	if not _report.fill_tiles.is_empty() and _variety_on.button_pressed:
		variety = {tiles = _report.fill_tiles, flags = Coverage.allowed_flags(_variety_turns()), weight = _variety_weight.value / 100.0}
	var collision := {}
	if _collision_on.button_pressed and _shape_mode.get_selected_id() != Quarters.SHAPES_KEEP:
		collision = _shape_choice().merged({layer = _shape_layer.get_selected_id(),
			scope = Scope.EVERY if _replace_check.button_pressed else Scope.NEW,
			tiles = _report.tiles.filter(func(t): return t.alt == 0 and _reaches(Coverage.normalize(t.mask, _report.type, _report.with_corners))),
			masks = built.map(func(b): return b.mask).filter(func(m): return _reaches(m))})
	applied.emit({added = added, removed = removed, built = built, variety = variety, collision = collision,
		other = _other, with_corners = _report.with_corners, corners = _report.upgrade if _make_on.button_pressed else [],
		shapes_off = not _collision_on.button_pressed})


## A folding section whose header has its on/off tick before its name, where it is seen:
## the header's arrow or empty space folds it, the tick says whether Apply does it.
class Section extends VBoxContainer:
	signal folding_changed(is_folded: bool)

	var tick := CheckBox.new()
	var title := "":
		set(value):
			title = value
			tick.text = value
	var folded := false:
		set(value):
			folded = value
			if _body != null:
				_body.visible = not value
			_arrow.icon = _theme().get_icon(&"arrow_collapsed" if value else &"arrow", &"Tree")
			folding_changed.emit(value)
	var _arrow := Button.new()
	var _body: Control

	func _init() -> void:
		add_theme_constant_override("separation", 0)
		var head := PanelContainer.new()
		head.add_theme_stylebox_override("panel", _theme().get_stylebox(&"title_panel", &"FoldableContainer"))
		head.mouse_filter = Control.MOUSE_FILTER_STOP
		head.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				folded = not folded)
		add_child(head)
		var row := HBoxContainer.new()
		head.add_child(row)
		_arrow.flat = true
		_arrow.focus_mode = Control.FOCUS_NONE
		_arrow.icon = _theme().get_icon(&"arrow", &"Tree")
		_arrow.pressed.connect(func(): folded = not folded)
		row.add_child(_arrow)
		tick.tooltip_text = "Include this in what Apply does"
		tick.toggled.connect(func(on: bool): folded = not on)
		tick.add_theme_font_override(&"font", _theme().get_font(&"bold", &"EditorFonts"))
		row.add_child(tick)

	func set_body(body: Control) -> void:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _theme().get_stylebox(&"panel", &"FoldableContainer"))
		panel.size_flags_vertical = body.size_flags_vertical
		panel.add_child(body)
		add_child(panel)
		_body = panel

	func expand() -> void:
		folded = false

	func fold() -> void:
		folded = true

	static func _theme() -> Theme:
		return EditorInterface.get_editor_theme()
