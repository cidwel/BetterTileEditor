@tool
extends TileMapLayer


## Elevation level; -1 follows sibling order. An explicit level shifts subsequent levels.
@export_range(-1, 4) var cliffLevel: int = -1

## Wall height in rows; -1 follows the level. This does not change drawing order.
@export_range(-1, 16) var cliffRows: int = -1

## Bool custom data layers that open a way through the faces (stairs, ropes, vines): wherever a tile on
## the ground or any layer beside it has one set, the face here has no collision.
@export var passageData: PackedStringArray = PackedStringArray(["is_stairs", "is_rope"])

var _ground: TileMapLayer
var _watched: Array[TileMapLayer] = []


func _enter_tree() -> void:
	_ground = get_parent() as TileMapLayer
	_watched = _passage_layers()
	if _ground != null and not _watched.has(_ground):
		_watched.append(_ground)
	for layer in _watched:
		if not layer.changed.is_connected(notify_runtime_tile_data_update):
			layer.changed.connect(notify_runtime_tile_data_update)


func _exit_tree() -> void:
	for layer in _watched:
		if is_instance_valid(layer) and layer.changed.is_connected(notify_runtime_tile_data_update):
			layer.changed.disconnect(notify_runtime_tile_data_update)
	_watched.clear()
	_ground = null


# A face under ground painted on its own level is hidden by that ground, and so is its collision:
# the ground's own tile decides whether the cell blocks. A face hanging over the void blocks nothing
# either (nobody stands below it; what walks or jumps off the rim just falls), and a passage (stairs,
# a rope) on any layer beside it opens the cell too.
func collision_hidden_at(coords: Vector2i) -> bool:
	var ground := get_parent() as TileMapLayer
	if ground != null and ground.get_cell_source_id(coords) != -1:
		return true
	if _over_void(coords):
		return true
	if passageData.is_empty():
		return false
	for layer in _passage_layers():
		if _has_passage(layer, coords):
			return true
	return false


# No lower level (a layer before the ground holding faces of its own) has anything painted under the face,
# nor under the rest of its column: the upper rows of a wall standing on a lower floor have no floor of
# their own beneath them, yet they are that wall, not an edge to fall off (Cave1 13,16).
func _over_void(coords: Vector2i) -> bool:
	var ground := get_parent() as TileMapLayer
	if ground == null or ground.get_parent() == null:
		return false
	var cell := coords
	for i in 64:
		if _lower_ground_at(ground, cell):
			return false
		cell += Vector2i.DOWN
		if get_cell_source_id(cell) == -1 or ground.get_cell_source_id(cell) != -1:
			return true
	return true


func _lower_ground_at(ground: TileMapLayer, coords: Vector2i) -> bool:
	for child in ground.get_parent().get_children():
		if child == ground:
			return false
		if child is TileMapLayer and _is_level(child) and child.get_cell_source_id(coords) != -1:
			return true
	return false


func _is_level(layer: TileMapLayer) -> bool:
	for child in layer.get_children():
		if child.get_script() == get_script():
			return true
	return false


# The ground and the layers beside it (all at the same origin, so a cell means the same spot on each).
func _passage_layers() -> Array[TileMapLayer]:
	var layers: Array[TileMapLayer] = []
	var ground := get_parent() as TileMapLayer
	if ground == null:
		return layers
	var holder := ground.get_parent()
	if holder == null:
		layers.append(ground)
		return layers
	for child in holder.get_children():
		if child is TileMapLayer:
			layers.append(child)
	return layers


func _has_passage(layer: TileMapLayer, coords: Vector2i) -> bool:
	var source_id := layer.get_cell_source_id(coords)
	if layer.tile_set == null or source_id == -1 or not layer.tile_set.has_source(source_id):
		return false
	# A tile removed from its atlas but still painted would make get_cell_tile_data complain.
	var atlas := layer.tile_set.get_source(source_id) as TileSetAtlasSource
	if atlas != null and not atlas.has_tile(layer.get_cell_atlas_coords(coords)):
		return false
	var data := layer.get_cell_tile_data(coords)
	if data == null:
		return false
	for key in passageData:
		if layer.tile_set.has_custom_data_layer_by_name(key) and data.get_custom_data(key) == true:
			return true
	return false


func _use_tile_data_runtime_update(coords: Vector2i) -> bool:
	return collision_hidden_at(coords)


func _tile_data_runtime_update(_coords: Vector2i, tile_data: TileData) -> void:
	for layer in tile_set.get_physics_layers_count():
		for polygon in tile_data.get_collision_polygons_count(layer):
			tile_data.set_collision_polygon_points(layer, polygon, PackedVector2Array())
