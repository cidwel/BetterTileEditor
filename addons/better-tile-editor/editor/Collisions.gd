@tool
extends RefCounted
## Tile collisions, stored the way Godot stores them: polygons on a TileSet physics layer.

const OVERLAY_COLOR_SETTING := "editors/better_terrain/collision_overlay_color"
const OVERLAY_ON_MAP_SETTING := "editors/better_terrain/collision_overlay_on_map"
const DEFAULT_OVERLAY_COLOR := Color(1.0, 0.15, 0.15, 0.45)
const FLIP_FLAGS := TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V \
	| TileSetAtlasSource.TRANSFORM_TRANSPOSE
const ALT_SCOPE_SETTING := "editors/better_terrain/collision_alternatives"
const ALL_LAYERS_SETTING := "editors/better_terrain/collision_all_layers"

## Which alternatives of a tile get the shape given to the tile.
enum AltScope { FLIPPED, ALL, NONE }
const ALT_SCOPE_NAMES := ["Flipped alternatives", "All alternatives", "Base tile only"]
const ALT_SCOPE_HINT := "Which alternatives of a tile get its collision too.\nFlipped: those that only flip or transpose it, which Godot turns with the shape.\nAll: every alternative. Base tile only: none of them."


static func alt_scope() -> int:
	var settings := EditorInterface.get_editor_settings()
	return int(settings.get_setting(ALT_SCOPE_SETTING)) if settings.has_setting(ALT_SCOPE_SETTING) else AltScope.FLIPPED


static func set_alt_scope(scope: int) -> void:
	EditorInterface.get_editor_settings().set_setting(ALT_SCOPE_SETTING, scope)


## The base tile, plus the alternatives the scope takes in.
static func target_alts(src: TileSetAtlasSource, coords: Vector2i, scope: int) -> Array:
	var out := [0]
	for i in src.get_alternative_tiles_count(coords):
		var alt := src.get_alternative_tile_id(coords, i)
		if alt == 0:
			continue
		var td := src.get_tile_data(coords, alt)
		if scope == AltScope.ALL or (scope == AltScope.FLIPPED and (td.flip_h or td.flip_v or td.transpose)):
			out.append(alt)
	return out


## The whole tile, in the cell's shape: a square, a diamond or a hexagon.
static func full_polygon(ts: TileSet, src: TileSetAtlasSource, coords: Vector2i) -> PackedVector2Array:
	var shape: PackedVector2Array = BetterTerrain.data.cell_polygon(ts)
	var extent := Vector2(ts.tile_size * src.get_tile_size_in_atlas(coords))
	var out := PackedVector2Array()
	for p in shape:
		out.append(p * extent)
	return out


## Collision polygons of the alternatives of a tile (all of them unless listed):
## [[alt, [[points, one_way, margin], ...]], ...].
static func tile_state(src: TileSetAtlasSource, coords: Vector2i, layer: int, alts: Array = []) -> Array:
	var out := []
	var listed := alts.duplicate()
	if listed.is_empty():
		for i in src.get_alternative_tiles_count(coords):
			listed.append(src.get_alternative_tile_id(coords, i))
	for alt: int in listed:
		var td := src.get_tile_data(coords, alt)
		var polygons := []
		for p in td.get_collision_polygons_count(layer):
			polygons.append([td.get_collision_polygon_points(layer, p),
				td.is_collision_polygon_one_way(layer, p), td.get_collision_polygon_one_way_margin(layer, p)])
		out.append([alt, polygons])
	return out


static func apply_state(src: TileSetAtlasSource, coords: Vector2i, layer: int, state: Array) -> void:
	if not src.has_tile(coords):
		return
	for entry: Array in state:
		if not src.has_alternative_tile(coords, entry[0]):
			continue
		var td := src.get_tile_data(coords, entry[0])
		var polygons: Array = entry[1]
		td.set_collision_polygons_count(layer, polygons.size())
		for p in polygons.size():
			td.set_collision_polygon_points(layer, p, polygons[p][0])
			td.set_collision_polygon_one_way(layer, p, polygons[p][1])
			td.set_collision_polygon_one_way_margin(layer, p, polygons[p][2])


## A full square on the given alternatives when solid, none otherwise.
static func marked_state(ts: TileSet, src: TileSetAtlasSource, coords: Vector2i, solid: bool, alts: Array) -> Array:
	var out := []
	var full := full_polygon(ts, src, coords)
	for alt: int in alts:
		out.append([alt, [[full, false, 1.0]] if solid else []])
	return out


## The same polygons ([[points, one_way, margin], ...]) on the given alternatives.
static func shape_state(polygons: Array, alts: Array) -> Array:
	var out := []
	for alt: int in alts:
		out.append([alt, polygons.duplicate(true)])
	return out


static func is_solid(td: TileData, layer: int) -> bool:
	return td != null and layer >= 0 and td.get_collision_polygons_count(layer) > 0


## The tile's polygons as they land in a cell, with the tile's and the cell's flips applied.
static func cell_polygons(td: TileData, layer: int, flags := 0) -> Array:
	var out := []
	var flip_h := td.flip_h != bool(flags & TileSetAtlasSource.TRANSFORM_FLIP_H)
	var flip_v := td.flip_v != bool(flags & TileSetAtlasSource.TRANSFORM_FLIP_V)
	var transpose := td.transpose != bool(flags & TileSetAtlasSource.TRANSFORM_TRANSPOSE)
	for p in td.get_collision_polygons_count(layer):
		var points := td.get_collision_polygon_points(layer, p)
		if flip_h or flip_v or transpose:
			var moved := PackedVector2Array()
			for v in points:
				if transpose:
					v = Vector2(v.y, v.x)
				if flip_h:
					v.x = -v.x
				if flip_v:
					v.y = -v.y
				moved.append(v)
			points = moved
		out.append(points)
	return out


## Appends each polygon, triangulated, to a triangle mesh for one draw call.
static func add_to_mesh(mesh: Dictionary, polygon: PackedVector2Array, color: Color) -> void:
	var triangles := Geometry2D.triangulate_polygon(polygon)
	if triangles.is_empty():
		return
	var start: int = mesh.points.size()
	mesh.points.append_array(polygon)
	for i in polygon.size():
		mesh.colors.append(color)
	for i in triangles:
		mesh.indices.append(start + i)


static func new_mesh() -> Dictionary:
	return {points = PackedVector2Array(), colors = PackedColorArray(), indices = PackedInt32Array()}


static func overlay_color() -> Color:
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting(OVERLAY_COLOR_SETTING):
		return settings.get_setting(OVERLAY_COLOR_SETTING)
	return DEFAULT_OVERLAY_COLOR


static func overlay_on_map() -> bool:
	var settings := EditorInterface.get_editor_settings()
	return not settings.has_setting(OVERLAY_ON_MAP_SETTING) or bool(settings.get_setting(OVERLAY_ON_MAP_SETTING))


## Each physics layer's colour, the same in the map, the atlas and the shape editor.
static func layer_color(index: int) -> Color:
	return Color.from_hsv(fmod(0.55 + 0.29 * index, 1.0), 0.65, 1.0)


static func show_all_layers() -> bool:
	var settings := EditorInterface.get_editor_settings()
	return settings.has_setting(ALL_LAYERS_SETTING) and bool(settings.get_setting(ALL_LAYERS_SETTING))


static func set_show_all_layers(on: bool) -> void:
	EditorInterface.get_editor_settings().set_setting(ALL_LAYERS_SETTING, on)


## The collision layer bits a physics layer is on, as "1, 3", or "none".
static func bits_text(ts: TileSet, index: int) -> String:
	var bits := []
	var value := ts.get_physics_layer_collision_layer(index)
	for bit in 32:
		if value & (1 << bit):
			bits.append(str(bit + 1))
	return ", ".join(bits) if not bits.is_empty() else "none"
