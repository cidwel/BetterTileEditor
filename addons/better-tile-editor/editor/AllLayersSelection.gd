@tool
extends RefCounted

const MASS := &"_better_terrain_mass_placements"
const SCATTER := &"_better_terrain_scatter"

var reference: TileMapLayer
var scene: Node
var selection: Dictionary = {}
var clipboard: Array = []

func clear_selection() -> void:
	selection.clear()

func capture(active: TileMapLayer, root: Node, area: Rect2i, mode: int) -> void:
	if reference != active or scene != root:
		selection.clear()
	reference = active
	scene = root
	if mode == 0:
		selection.clear()
	var layers: Array = root.find_children("*", "TileMapLayer", true, false)
	if root is TileMapLayer:
		layers.push_front(root)
	for layer: TileMapLayer in layers:
		if layer.tile_set == null:
			continue
		var cells: Dictionary = selection.get(layer, {}).duplicate()
		var candidates := {}
		for c in layer.get_used_cells():
			candidates[c] = true
		for zone in layer.get_meta(SCATTER, {}).values():
			for c in zone:
				candidates[Vector2i(c)] = true
		for c in candidates:
			var projected := reference.local_to_map(reference.to_local(layer.to_global(layer.map_to_local(c))))
			if area.has_point(projected):
				if mode < 0:
					cells.erase(c)
				else:
					cells[c] = true
		if cells.is_empty():
			selection.erase(layer)
		else:
			selection[layer] = cells

func projected_cells() -> Array:
	var cells := {}
	for layer in selection:
		if not is_instance_valid(layer):
			continue
		for c in selection[layer]:
			cells[reference.local_to_map(reference.to_local(layer.to_global(layer.map_to_local(c))))] = true
	return cells.keys()

func copy(origin: Vector2i) -> void:
	clipboard.clear()
	if selection.is_empty() or not is_instance_valid(reference):
		return
	var anchor := reference.to_global(reference.map_to_local(origin))
	for layer in selection:
		if not is_instance_valid(layer):
			continue
		var data := []
		for c in selection[layer]:
			data.append({coord = c, offset = layer.to_global(layer.map_to_local(c)) - anchor,
				tile = _read(layer, c)})
		clipboard.append({layer = layer, data = data, meta = _metadata(layer)})

func paste(undo: EditorUndoRedoManager, origin: Vector2i, moving: bool, label: String) -> void:
	if clipboard.is_empty() or not is_instance_valid(reference):
		return
	var anchor := reference.to_global(reference.map_to_local(origin))
	var changes := []
	var next_selection := {}
	for packet in clipboard:
		var layer = packet.layer
		if not _available(layer):
			continue
		var after := {}
		var mapping := {}
		for cell in packet.data:
			var target: Vector2i = layer.local_to_map(layer.to_local(anchor + cell.offset))
			mapping[cell.coord] = target
			if moving:
				after[cell.coord] = [-1, Vector2i(-1, -1), 0]
		var selected := {}
		for cell in packet.data:
			var target: Vector2i = mapping[cell.coord]
			after[target] = cell.tile
			selected[target] = true
		var before := {}
		for c in after:
			before[c] = _read(layer, c)
		var before_meta := _metadata(layer)
		var after_meta := _transfer_metadata(before_meta, packet.meta, mapping, moving)
		changes.append({layer = layer, before = before, after = after, before_meta = before_meta, after_meta = after_meta})
		next_selection[layer] = selected
	_commit(undo, changes, label)
	selection = next_selection

func delete(undo: EditorUndoRedoManager, label: String) -> void:
	var changes := []
	for layer in selection:
		if not _available(layer):
			continue
		var before := {}
		var after := {}
		for c in selection[layer]:
			before[c] = _read(layer, c)
			after[c] = [-1, Vector2i(-1, -1), 0]
		var meta := _metadata(layer)
		changes.append({layer = layer, before = before, after = after,
			before_meta = meta, after_meta = _without_cells(meta, selection[layer])})
	_commit(undo, changes, label)
	selection.clear()

func _available(layer: Variant) -> bool:
	return is_instance_valid(layer) and is_instance_valid(scene) and (layer == scene or scene.is_ancestor_of(layer)) and layer.tile_set != null

func _read(layer: TileMapLayer, c: Vector2i) -> Array:
	return [layer.get_cell_source_id(c), layer.get_cell_atlas_coords(c), layer.get_cell_alternative_tile(c)]

func _metadata(layer: TileMapLayer) -> Dictionary:
	var meta := {}
	for key in [MASS, SCATTER]:
		if layer.has_meta(key):
			meta[key] = layer.get_meta(key).duplicate(true)
	return meta

func _origin_cell(state: Dictionary, origin: Vector2i, cells: Dictionary) -> Vector2i:
	if cells.has(origin):
		return origin
	var signature: Array = state.get("signature", [])
	if signature.size() > 1:
		var base: Rect2i = signature[1]
		for y in range(base.position.y, base.end.y):
			for x in range(base.position.x, base.end.x):
				var c := origin + Vector2i(x, y)
				if cells.has(c):
					return c
	return origin

func _without_cells(meta: Dictionary, cells: Dictionary) -> Dictionary:
	var result := meta.duplicate(true)
	for state in result.get(MASS, {}).values():
		var region := PackedVector2Array()
		for c in state.get("cells", PackedVector2Array()):
			if not cells.has(Vector2i(c)):
				region.append(c)
		state.cells = region
		var origins := PackedVector2Array()
		for c in state.get("origins", PackedVector2Array()):
			if not cells.has(_origin_cell(state, Vector2i(c), cells)):
				origins.append(c)
		state.origins = origins
	for id in result.get(SCATTER, {}):
		var region := PackedVector2Array()
		for c in result[SCATTER][id]:
			if not cells.has(Vector2i(c)):
				region.append(c)
		result[SCATTER][id] = region
	return result

func _transfer_metadata(current: Dictionary, source: Dictionary, mapping: Dictionary, moving: bool) -> Dictionary:
	var replaced := {}
	for c in mapping:
		if moving:
			replaced[c] = true
		replaced[mapping[c]] = true
	var result := _without_cells(current, replaced)
	for key in source:
		if not result.has(key):
			result[key] = {}
		for id in source[key]:
			if key == SCATTER:
				var region: PackedVector2Array = result[key].get(id, PackedVector2Array())
				for c in source[key][id]:
					if mapping.has(Vector2i(c)) and not Vector2(mapping[Vector2i(c)]) in region:
						region.append(mapping[Vector2i(c)])
				result[key][id] = region
			else:
				var state: Dictionary = source[key][id]
				var dest: Dictionary = result[key].get(id, state.duplicate(true))
				for field in ["cells", "origins"]:
					var values: PackedVector2Array = dest.get(field, PackedVector2Array()) if result[key].has(id) else PackedVector2Array()
					for c in state.get(field, PackedVector2Array()):
						var coord := Vector2i(c)
						var anchor := _origin_cell(state, coord, mapping) if field == "origins" else coord
						if mapping.has(anchor):
							var moved: Vector2 = Vector2(coord + mapping[anchor] - anchor)
							if not moved in values:
								values.append(moved)
					dest[field] = values
				result[key][id] = dest
	return result

func _commit(undo: EditorUndoRedoManager, changes: Array, label: String) -> void:
	if changes.is_empty():
		return
	undo.create_action(label, UndoRedo.MERGE_DISABLE, reference)
	var instances := {}
	for change in changes:
		var node: Node = change.layer
		while node != scene:
			if not node.scene_file_path.is_empty() and not scene.is_editable_instance(node):
				instances[node] = true
			node = node.get_parent()
	for instance in instances:
		undo.add_do_method(scene, &"set_editable_instance", instance, true)
		undo.add_undo_method(scene, &"set_editable_instance", instance, false)
	undo.add_do_method(self, &"_apply", changes, false)
	undo.add_undo_method(self, &"_apply", changes, true)
	undo.commit_action()

func _apply(changes: Array, restoring: bool) -> void:
	for change in changes:
		var layer = change.layer
		if not is_instance_valid(layer):
			continue
		var cells: Dictionary = change.before if restoring else change.after
		for c in cells:
			var tile: Array = cells[c]
			layer.set_cell(c, tile[0], tile[1], tile[2])
		var meta: Dictionary = change.before_meta if restoring else change.after_meta
		for key in [MASS, SCATTER]:
			if meta.has(key):
				layer.set_meta(key, meta[key].duplicate(true))
			else:
				layer.remove_meta(key)
