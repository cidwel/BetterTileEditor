@tool
extends Window

## Animated walkthrough of the slope set-up using the example atlas.

const SlopeTerrain := preload("res://addons/better-tile-editor/SlopeTerrain.gd")
const TILE_TIME := 2.4
const GROUP_TIME := 3.6
const FINAL_TIME := 6.0

var _sections: Array
var _simple := true
var _describe: Callable
var _ts: TileSet
var _src: TileSetAtlasSource
var _sample := {}
var _lo := Vector2i.ZERO
var _hi := Vector2i.ZERO
var _steps := []
var _step := 0
var _time := 0.0
var _playing := true
var _canvas: Control
var _title: Label
var _text: Label
var _count: Label
var _play: Button


func _init() -> void:
	title = "How the slope set-up works"
	transient = true
	exclusive = false
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 17)
	column.add_child(_title)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.y = 44
	column.add_child(_text)
	_canvas = Control.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.draw.connect(_draw_step)
	column.add_child(_canvas)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	var back := Button.new()
	back.text = "◀ Back"
	back.pressed.connect(func() -> void: _go(_step - 1))
	bar.add_child(back)
	_play = Button.new()
	_play.pressed.connect(func() -> void:
		_playing = not _playing
		_sync_play())
	bar.add_child(_play)
	var next := Button.new()
	next.text = "Next ▶"
	next.pressed.connect(func() -> void: _go(_step + 1))
	bar.add_child(next)
	_count = Label.new()
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_count)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(hide)
	bar.add_child(close)


func open(sections: Array, simple: bool, describe: Callable) -> void:
	_sections = sections
	_simple = simple
	_describe = describe
	if _ts == null:
		_ts = TileSet.new()
		var id: int = SlopeTerrain.make_example(BetterTerrain, _ts)
		_src = _ts.get_source(id) as TileSetAtlasSource
		_sample = SlopeTerrain.sample()
		_lo = Vector2i(1 << 20, 1 << 20)
		_hi = -_lo
		for c in _sample:
			_lo = Vector2i(mini(_lo.x, c.x), mini(_lo.y, c.y))
			_hi = Vector2i(maxi(_hi.x, c.x), maxi(_hi.y, c.y))
	_steps.clear()
	_steps.append({"kind": "intro"})
	for section in _sections:
		for slot in section[1]:
			_steps.append({"kind": "tile", "section": section, "slot": slot})
	for section in _sections:
		_steps.append({"kind": "group", "section": section})
	_steps.append({"kind": "final"})
	_playing = true
	_sync_play()
	_go(0)
	var scale := EditorInterface.get_editor_scale()
	popup_centered(Vector2i(Vector2(900, 560) * scale))


func _sync_play() -> void:
	_play.text = "❚❚ Pause" if _playing else "▶ Play"


func _go(step: int) -> void:
	_step = clampi(step, 0, _steps.size() - 1)
	_time = 0.0
	var s: Dictionary = _steps[_step]
	var flip_note := "  The other side, and the ceilings, are this piece flipped." if _simple else ""
	match s.kind:
		"intro":
			_title.text = "Tip: start from the example"
			_text.text = "\"Create and set example slope map\" draws this landscape as an atlas at your tile size, with every piece " \
				+ "already set up. Paint your own art over its tiles, or copy them, and the slopes are done. The steps after this one go through each piece."
		"tile":
			_title.text = "%s  ·  %s" % [s.section[0], _describe.call(s.slot).trim_suffix(".")]
			_text.text = "Its shape is the faint outline; its tile fills it. On the right, the yellow cells are where it goes." \
				+ (flip_note if SlopeTerrain.TURNS.values().any(func(t): return t[0] == s.slot) else "") \
				+ ("  Optional: without it the tool still works." if s.section[2] else "")
		"group":
			_title.text = "Together: " + s.section[0]
			_text.text = "These pieces make that part of the land between them."
		"final":
			_title.text = "The result"
			_text.text = "Every piece in its place: this is what the slope tool paints." \
				+ ("  The cells marked with a small F are pieces flipped from the ones you picked." if _simple else "")
	_count.text = "Step %d of %d" % [_step + 1, _steps.size()]
	_canvas.queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_canvas.queue_redraw()
	var s: Dictionary = _steps[_step] if _step < _steps.size() else {}
	var length: float = TILE_TIME if s.get("kind") == "tile" else (GROUP_TIME if s.get("kind") in ["group", "intro"] else FINAL_TIME)
	if _playing and _time >= length and _step < _steps.size() - 1:
		_go(_step + 1)


# Slot for a landscape cell, and whether it is drawn flipped from the picked tile
func _cell_slot(c: Vector2i) -> Array:
	var slot: String = _sample[c]
	if slot == "ground":
		slot = SlopeTerrain.edge_of(_sample, c)
	if _simple and SlopeTerrain.TURNS.has(slot):
		return [SlopeTerrain.TURNS[slot][0], SlopeTerrain.TURNS[slot][1], SlopeTerrain.TURNS[slot][2]]
	return [slot, false, false]


func _all_slots() -> Array:
	var out := []
	for section in _sections:
		out.append_array(section[1])
	return out


func _draw_tile(rect: Rect2, slot: String, flip_h: bool, flip_v: bool, alpha := 1.0) -> void:
	var t := SlopeTerrain.slot_tile(BetterTerrain, _ts, slot)
	if t.is_empty():
		return
	_canvas.draw_set_transform(rect.get_center(), 0.0, Vector2(-1.0 if flip_h else 1.0, -1.0 if flip_v else 1.0))
	_canvas.draw_texture_rect_region(_src.texture, Rect2(-rect.size / 2.0, rect.size), _src.get_tile_texture_region(t.coord), Color(1, 1, 1, alpha))
	_canvas.draw_set_transform(Vector2.ZERO)


func _draw_shape(rect: Rect2, slot: String, fill: Color, line: Color) -> void:
	var shape := Transform2D(0.0, rect.size, 0.0, rect.position) * SlopeTerrain.blueprint(slot)
	_canvas.draw_colored_polygon(shape, fill)
	var outline := shape.duplicate()
	outline.append(shape[0])
	_canvas.draw_polyline(outline, line, 1.5)


func _draw_step() -> void:
	if _steps.is_empty():
		return
	var s: Dictionary = _steps[_step]
	var area := Rect2(Vector2.ZERO, _canvas.size)
	_canvas.draw_rect(area, Color(0.13, 0.14, 0.17))
	var fade := clampf((_time - 0.5) / 0.6, 0.0, 1.0)
	var land_rect := area
	if s.kind == "intro":
		var tex := _src.texture
		var fit := minf(area.size.x * 0.45 / tex.get_width(), (area.size.y - 24) / tex.get_height())
		var atlas := Rect2(area.position + Vector2(12, 12), Vector2(tex.get_width(), tex.get_height()) * fit)
		_canvas.draw_texture_rect(tex, atlas, false)
		_canvas.draw_rect(atlas, Color(1, 0.85, 0.2), false, 1.5)
		land_rect = Rect2(Vector2(atlas.end.x + 20, area.position.y + 12), Vector2(area.end.x - atlas.end.x - 32, area.size.y - 24))
		_draw_land(land_rect, {"kind": "final"}, 1.0, true)
		return
	if s.kind != "final":
		var left := Rect2(area.position + Vector2(12, 12), Vector2(area.size.x * 0.34, area.size.y - 24))
		land_rect = Rect2(Vector2(left.end.x + 20, area.position.y + 12), Vector2(area.end.x - left.end.x - 32, area.size.y - 24))
		var slots: Array = [s.slot] if s.kind == "tile" else s.section[1]
		var per_row := 1 if slots.size() == 1 else mini(slots.size(), 3)
		var rows := ceili(float(slots.size()) / per_row)
		var side := minf(left.size.x / per_row, left.size.y / rows) - 10.0
		side = minf(side, 140.0)
		for i in slots.size():
			var at := left.position + Vector2((i % per_row) * (side + 10.0), (i / per_row) * (side + 10.0))
			var rect := Rect2(at, Vector2(side, side))
			_canvas.draw_rect(rect, Color(0.18, 0.19, 0.23))
			_draw_shape(rect, slots[i], Color(1.0, 0.3, 0.25, 0.22), Color(1.0, 0.4, 0.35, 0.9))
			_draw_tile(rect, slots[i], false, false, fade)
			if s.kind == "group":
				_canvas.draw_string(_canvas.get_theme_default_font(), rect.position + Vector2(4, 14), _short(slots[i]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.9))
	_draw_land(land_rect, s, fade, false)


func _short(slot: String) -> String:
	if slot == "ground":
		return "G"
	if slot.begins_with("ground:"):
		return "G" + slot.get_slice(":", 1).to_upper()
	return slot.replace("arrow:", "under ").replace("thin:", "thin ").to_upper()


# Explained pieces are drawn, current ones highlighted
func _draw_land(rect: Rect2, s: Dictionary, fade: float, whole: bool) -> void:
	var cells := Vector2(_hi - _lo + Vector2i.ONE)
	var side := minf(rect.size.x / cells.x, rect.size.y / cells.y)
	var origin := rect.position + (rect.size - cells * side) / 2.0
	var current := []
	if s.kind == "tile":
		current = [s.slot]
	elif s.kind == "group":
		current = s.section[1]
	var shown := {}
	if s.kind != "final":
		for i in _step:
			var earlier: Dictionary = _steps[i]
			for slot in ([earlier.slot] if earlier.kind == "tile" else earlier.get("section", [0, []])[1]):
				shown[slot] = true
	var order := _sample.keys()
	order.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var revealed := order.size() if s.kind != "final" or whole else int(order.size() * clampf(_time / (FINAL_TIME * 0.6), 0.0, 1.0))
	for i in order.size():
		var c: Vector2i = order[i]
		var cell := Rect2(origin + Vector2(c - _lo) * side, Vector2(side, side))
		var info := _cell_slot(c)
		var slot: String = info[0]
		var covered: bool = (s.kind == "final" and i < revealed) or (s.kind != "final" and (slot in current and fade >= 1.0))
		if not covered:
			_draw_shape(cell, _sample[c] if not _sample[c].begins_with("ground") else "ground", Color(1.0, 0.3, 0.25, 0.12), Color(1.0, 0.4, 0.35, 0.35))
		if s.kind == "final":
			if i < revealed:
				_draw_tile(cell, slot, info[1], info[2])
				if _simple and not whole and (info[1] or info[2]) and _time > FINAL_TIME * 0.7:
					_canvas.draw_string(_canvas.get_theme_default_font(), cell.position + Vector2(1, 9), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.85, 0.2))
			continue
		if slot in current:
			_draw_tile(cell, slot, info[1], info[2], fade)
			_canvas.draw_rect(cell, Color(1, 0.85, 0.2), false, 2.0)
		elif shown.has(slot):
			_draw_tile(cell, slot, info[1], info[2], 0.55)
