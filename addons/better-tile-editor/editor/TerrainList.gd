@tool
extends HFlowContainer

signal context_requested(group_name: String)
signal terrain_dropped(terrain_id: int, group_name: String)
signal group_dropped(source_group: String, target_group: String, after: bool)
signal scene_dropped(scene_key: String, from_group: String, to_group: String)

const GROUP_META := &"better_terrain_group"
## Group key of the Scenes section; it cannot clash with a named group.
const SCENES_GROUP := "::scenes"

var _hint_group := ""
var _has_hint := false
var _insertion_hint := {}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		context_requested.emit(_group_at(event.position))
		accept_event()


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if data is Dictionary and data.has("better_terrain_scene"):
		var group := _group_at(at)
		var can_move: bool = not group.is_empty() and group != data.from_group
		_set_hint(can_move, group if can_move else "")
		return can_move
	if data is Dictionary and data.has("better_terrain_group_drag"):
		_set_hint(false, "")
		_set_insertion_hint(_group_insertion(at, data))
		return not _insertion_hint.is_empty()
	var ok: bool = data is Dictionary and data.has("better_terrain_entry") and _group_at(at) != SCENES_GROUP
	_set_hint(ok, _group_at(at) if ok else "")
	return ok


func _drop_data(at: Vector2, data: Variant) -> void:
	if data.has("better_terrain_scene"):
		_set_hint(false, "")
		scene_dropped.emit(data.better_terrain_scene, data.from_group, _group_at(at))
		return
	if data.has("better_terrain_group_drag"):
		var insertion := _group_insertion(at, data)
		_set_insertion_hint({})
		if not insertion.is_empty():
			group_dropped.emit(data.better_terrain_group_drag, insertion.group, insertion.after)
		return
	var group := _group_at(at)
	_set_hint(false, "")
	terrain_dropped.emit(int(data["better_terrain_entry"]), group)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_DRAG_END, NOTIFICATION_MOUSE_EXIT]:
		_set_insertion_hint({})
		_set_hint(false, "")


func _group_insertion(at: Vector2, data: Dictionary) -> Dictionary:
	var headers := get_children().filter(func(c): return c.visible and c.has_method("setup_reordering") and c.tileset_id != 0)
	if not headers.any(func(c): return c.group_name == data.better_terrain_group_drag and c.tileset_id == data.get("tileset_id")):
		return {}
	for i in headers.size():
		var header = headers[i]
		var bottom: float = header.position.y + header.size.y
		for child in get_children():
			if child.visible and child.get_meta(GROUP_META, "") == header.group_name:
				bottom = maxf(bottom, child.position.y + child.size.y)
		if at.y < (header.position.y + bottom) / 2.0:
			return {"group": header.group_name, "after": false, "y": maxf(1.0, header.position.y - 2.0)}
		if i == headers.size() - 1:
			return {"group": header.group_name, "after": true, "y": minf(size.y - 1.0, bottom + 2.0)}
	return {}


func _set_insertion_hint(insertion: Dictionary) -> void:
	if _insertion_hint == insertion:
		return
	_insertion_hint = insertion
	queue_redraw()


func _group_at(at: Vector2) -> String:
	var best := ""
	var best_y := -1.0e20
	for c in get_children():
		if not (c is Control) or not c.visible:
			continue
		var top: float = c.position.y
		var bottom: float = top + c.size.y
		if at.y >= top and at.y <= bottom:
			return String(c.get_meta(GROUP_META, ""))
		if top <= at.y and top > best_y:
			best_y = top
			best = String(c.get_meta(GROUP_META, ""))
	return best


func _set_hint(on: bool, group: String) -> void:
	if _has_hint == on and _hint_group == group:
		return
	_has_hint = on
	_hint_group = group
	queue_redraw()


func _draw() -> void:
	if not _insertion_hint.is_empty():
		var y: float = _insertion_hint.y
		var color := Color(0.35, 0.9, 1.0)
		draw_line(Vector2(3, y), Vector2(size.x - 3, y), color, 2.0)
		draw_circle(Vector2(3, y), 3.0, color)
		draw_circle(Vector2(size.x - 3, y), 3.0, color)
	if not _has_hint:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in get_children():
		if not (c is Control) or not c.visible:
			continue
		if String(c.get_meta(GROUP_META, "")) != _hint_group:
			continue
		lo = Vector2(minf(lo.x, c.position.x), minf(lo.y, c.position.y))
		hi = Vector2(maxf(hi.x, c.position.x + c.size.x), maxf(hi.y, c.position.y + c.size.y))
	var r: Rect2
	if lo.x > hi.x:
		r = Rect2(Vector2.ZERO, size)
	else:
		r = Rect2(Vector2(0.0, lo.y), Vector2(size.x, hi.y - lo.y))
	draw_rect(r, Color(0.35, 0.9, 1.0, 0.12), true)
	draw_rect(r, Color(0.35, 0.9, 1.0, 0.85), false, 2.0)
