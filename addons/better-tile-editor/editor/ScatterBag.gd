@tool
extends PanelContainer


const ScatterTerrain := preload("res://addons/better-tile-editor/ScatterTerrain.gd")
const Chrome := preload("res://addons/better-tile-editor/editor/Chrome.gd")

signal config_changed(cfg: Dictionary)
signal reroll_requested()
signal apply_requested()

var _tileset: TileSet
var _terrain_id := -1
var _cfg := {}

var _title: Label
var _rows: VBoxContainer
var _empty_spin: SpinBox
var _edge: SpinBox
var _live: CheckBox
var _apply: Button
var _syncing := false


func _init() -> void:
	name = "ScatterBag"
	custom_minimum_size.x = 210
	size_flags_horizontal = Control.SIZE_FILL

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	_title = Label.new()
	_title.text = "Bag"
	_title.clip_text = true
	outer.add_child(_title)

	var how := Label.new()
	how.text = "Click to add, drag for one piece, right-click to remove."
	how.tooltip_text = "Clicking a tile in the atlas puts it in the bag. Dragging a box over several adds the whole box as one piece. The right button takes out whatever entry covers the tile."
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	outer.add_child(how)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)

	outer.add_child(Chrome.rule())

	var nothing := HBoxContainer.new()
	var nothing_label := Label.new()
	nothing_label.text = "Empty tiles"
	nothing_label.tooltip_text = "How many cells out of a hundred are left bare. The bag shares out the rest."
	nothing_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nothing.add_child(nothing_label)
	_empty_spin = SpinBox.new()
	_empty_spin.min_value = 0.0
	_empty_spin.max_value = 100.0
	_empty_spin.step = 1.0
	_empty_spin.suffix = "%"
	_empty_spin.custom_minimum_size.x = 80
	_empty_spin.value_changed.connect(func(v: float): _set_empty(v))
	nothing.add_child(_empty_spin)
	outer.add_child(nothing)

	var rim := HBoxContainer.new()
	var rim_label := Label.new()
	rim_label.text = "Keep off the edge"
	rim_label.tooltip_text = "Cells of the region's rim to leave empty. Art drawn to the edge of its tile hangs over whatever the region ends against, and one cell of rim stops it. Each piece's base must fit entirely inside what is left."
	rim_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rim.add_child(rim_label)
	_edge = SpinBox.new()
	_edge.min_value = 0
	_edge.max_value = 16
	_edge.step = 1
	_edge.suffix = "cells"
	_edge.custom_minimum_size.x = 96
	_edge.tooltip_text = rim_label.tooltip_text
	_edge.value_changed.connect(func(v: float): _set_edge(v))
	rim.add_child(_edge)
	outer.add_child(rim)

	_live = CheckBox.new()
	_live.text = "Live change"
	_live.tooltip_text = "Repaint every region painted with this terrain as the weights are edited."
	_live.toggled.connect(func(on: bool): _set_live(on))
	outer.add_child(_live)

	var buttons := HBoxContainer.new()
	_apply = Button.new()
	_apply.text = "Apply"
	_apply.tooltip_text = "Repaint the regions with the weights as they stand."
	_apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply.pressed.connect(func(): apply_requested.emit())
	buttons.add_child(_apply)
	var reroll := Button.new()
	reroll.text = "Reroll"
	var theme := EditorInterface.get_editor_theme()
	if theme != null and theme.has_icon(&"RandomNumberGenerator", &"EditorIcons"):
		reroll.icon = theme.get_icon(&"RandomNumberGenerator", &"EditorIcons")
	reroll.tooltip_text = "Same weights, another throw of the dice."
	reroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll.pressed.connect(func(): reroll_requested.emit())
	buttons.add_child(reroll)
	outer.add_child(buttons)


func _weight_spin() -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = 0.0
	sp.max_value = 9999.0
	sp.step = 1.0
	sp.allow_greater = true
	sp.custom_minimum_size.x = 72
	return sp


func setup(ts: TileSet, terrain_id: int, terrain_name: String, color: Color) -> void:
	_tileset = ts
	_terrain_id = terrain_id
	_cfg = ScatterTerrain.config_of(ts, terrain_id) if terrain_id >= 0 else {}
	_title.text = terrain_name
	_title.add_theme_color_override("font_color", color)
	_refresh()


#region The rows

func _refresh() -> void:
	_syncing = true
	for c in _rows.get_children():
		c.queue_free()
	var bag: Array = _cfg.get("bag", [])
	for i in bag.size():
		_rows.add_child(_make_row(i, ScatterTerrain.normalise_entry(bag[i])))
	if bag.is_empty():
		var hint := Label.new()
		hint.text = "The bag is empty."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		_rows.add_child(hint)
	_empty_spin.set_value_no_signal(float(_cfg.get("empty_pct", 0.0)))
	_edge.set_value_no_signal(float(_cfg.get("edge", 0)))
	_live.set_pressed_no_signal(bool(_cfg.get("live", false)))
	_apply.disabled = bool(_cfg.get("live", false))
	_syncing = false


func _make_row(index: int, entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(34, 34)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.texture = entry_texture(_tileset, entry)
	art.tooltip_text = "%dx%d at %s" % [entry.size.x, entry.size.y, entry.origin]
	row.add_child(art)

	var spin := _weight_spin()
	spin.custom_minimum_size.x = 64
	spin.set_value_no_signal(entry.weight)
	spin.value_changed.connect(func(v: float): _set_weight(index, v))
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)

	var base := Button.new()
	base.text = "Base"
	base.tooltip_text = "Choose the area of this piece that must fit inside the region. Defaults to the whole sprite."
	base.pressed.connect(func(): _open_base(index))
	row.add_child(base)

	var drop := Button.new()
	drop.text = "x"
	drop.tooltip_text = "Take it out of the bag"
	drop.pressed.connect(func(): _remove(index))
	row.add_child(drop)
	return row


func _open_base(index: int) -> void:
	var entry := ScatterTerrain.entry_at(_cfg, index)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Placement base"
	add_child(dialog)
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var hint := Label.new()
	hint.text = "The yellow area must fit. The rest of the sprite may extend outside."
	box.add_child(hint)
	var preview := Control.new()
	var px: float = minf(40.0, 256.0 / maxi(entry.size.x, entry.size.y))
	preview.custom_minimum_size = Vector2(entry.size) * px
	box.add_child(preview)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	var spins: Array[SpinBox] = []
	var values := [entry.base.position.x, entry.base.position.y, entry.base.size.x, entry.base.size.y]
	for i in 4:
		var label := Label.new()
		label.text = ["Offset X", "Offset Y", "Width", "Height"][i]
		grid.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = 0 if i < 2 else 1
		spin.max_value = (entry.size.x if i % 2 == 0 else entry.size.y) - (1 if i < 2 else 0)
		spin.value = values[i]
		grid.add_child(spin)
		spins.append(spin)
	var update := func():
		spins[2].max_value = entry.size.x - spins[0].value
		spins[3].max_value = entry.size.y - spins[1].value
		preview.queue_redraw()
	for spin in spins:
		spin.value_changed.connect(func(_v): update.call())
	var texture := entry_texture(_tileset, entry)
	preview.draw.connect(func():
		var art := Rect2(Vector2.ZERO, Vector2(entry.size) * px)
		preview.draw_rect(art, Color(0.15, 0.15, 0.15))
		if texture != null:
			preview.draw_texture_rect(texture, art, false)
		var rect := Rect2(Vector2(spins[0].value, spins[1].value) * px,
			Vector2(spins[2].value, spins[3].value) * px)
		preview.draw_rect(rect, Color(1.0, 0.75, 0.2, 0.3))
		preview.draw_rect(rect, Color(1.0, 0.75, 0.2), false, 2.0)
	)
	var reset := Button.new()
	reset.text = "Whole sprite"
	reset.pressed.connect(func():
		spins[0].value = 0
		spins[1].value = 0
		spins[2].value = entry.size.x
		spins[3].value = entry.size.y
	)
	box.add_child(reset)
	dialog.confirmed.connect(func():
		_set_base(index, Rect2i(int(spins[0].value), int(spins[1].value),
			int(spins[2].value), int(spins[3].value)))
	)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	update.call()
	dialog.popup_centered()


func _set_base(index: int, base: Rect2i) -> void:
	var bag: Array = _cfg.get("bag", []).duplicate(true)
	bag[index]["base"] = [base.position.x, base.position.y, base.size.x, base.size.y]
	_commit({bag = bag})


static func entry_texture(ts: TileSet, entry: Dictionary) -> Texture2D:
	if ts == null or entry.is_empty():
		return null
	var src := ts.get_source(entry.source) as TileSetAtlasSource
	if src == null or src.texture == null:
		return null
	var first := src.get_tile_texture_region(entry.origin) if src.get_tile_at_coords(entry.origin) == entry.origin else Rect2i()
	if first.size == Vector2i.ZERO:
		first = Rect2i(entry.origin * src.texture_region_size, src.texture_region_size)
	var at := AtlasTexture.new()
	at.atlas = src.texture
	at.region = Rect2(first.position, Vector2(src.texture_region_size) * Vector2(entry.size))
	return at

#endregion


#region Editing

func _set_weight(index: int, value: float) -> void:
	if _syncing:
		return
	var bag: Array = _cfg.get("bag", []).duplicate(true)
	if index < 0 or index >= bag.size():
		return
	bag[index]["weight"] = value
	_commit({bag = bag})


func _set_empty(value: float) -> void:
	if _syncing:
		return
	_commit({empty_pct = value})


func _set_edge(value: float) -> void:
	if _syncing:
		return
	_commit({edge = int(value)})


func _set_live(on: bool) -> void:
	if _syncing:
		return
	_commit({live = on})


func _remove(index: int) -> void:
	var bag: Array = _cfg.get("bag", []).duplicate(true)
	if index < 0 or index >= bag.size():
		return
	bag.remove_at(index)
	_commit({bag = bag})


## Duplicate tiles are allowed as separate weighted entries.
func add_entry(source: int, origin: Vector2i, size: Vector2i) -> void:
	if _terrain_id < 0:
		return
	var bag: Array = _cfg.get("bag", []).duplicate(true)
	bag.push_back(ScatterTerrain.make_entry(source, origin, size, 1.0))
	_commit({bag = bag})


func remove_at(source: int, coord: Vector2i) -> bool:
	var index := ScatterTerrain.entry_covering(_cfg, source, coord)
	if index < 0:
		return false
	_remove(index)
	return true


func current_config() -> Dictionary:
	return _cfg.duplicate(true)


func _commit(changes: Dictionary) -> void:
	for k in changes:
		_cfg[k] = changes[k]
	_refresh()
	config_changed.emit(_cfg.duplicate(true))


#endregion
