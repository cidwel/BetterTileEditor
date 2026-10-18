@tool
extends RefCounted
## A wall one column wide, open on both sides, has no art in a block drawn as left end, middle
## and right end. These pieces are made for it: the left half of the left end beside the right
## half of the right end, one per row of the block, in a small atlas of their own.

const CliffData := preload("res://addons/better-tile-editor/CliffData.gd")
const QuarterPieces := preload("res://addons/better-tile-editor/editor/QuarterPieces.gd")


## Points the lone-column slots of [param cfg] at pieces made from [param block]. Returns how
## many slots it set; 0 when the block has no separate ends.
static func fill(ts: TileSet, terrain_name: String, cfg: Dictionary, source_id: int, block: Rect2i) -> int:
	return assign(cfg, make(ts, terrain_name, source_id, block), block)


## The atlas with the pieces for [param block], made or brought up to date; -1 when the block
## has no separate ends. Adding it changes the tile set, so make it before editing a config.
static func make(ts: TileSet, terrain_name: String, source_id: int, block: Rect2i) -> int:
	return _source_for(ts, terrain_name, source_id, block) if block.size.x >= 2 else -1


static func assign(cfg: Dictionary, made: int, block: Rect2i) -> int:
	if made < 0:
		return 0
	var count := 0
	for row in CliffData.ROWS:
		var rows := CliffData.autoassign_rows(block, row)
		for c in CliffData.CASES:
			if not lone(c) or not CliffData.slot_reachable(row, c, 1 if row == "only" else (3 if row == "middle" else 2)):
				continue
			var tile := {"source_id": made, "coord": Vector2i(0, rows.x - block.position.y)}
			if rows.y > 1:
				tile["size"] = Vector2i(1, rows.y)
			CliffData.set_slot_tile(cfg, row, c, tile)
			count += 1
	return count


## Both sides of the case end the wall, so the column stands alone.
static func lone(case_name: String) -> bool:
	var sides := CliffData.case_sides(case_name)
	return sides.size() == 2 and CliffData.side_class(sides[0]) == "E" and CliffData.side_class(sides[1]) == "E"


## The id of the atlas holding the pieces for this block, made (or remade) now.
static func _source_for(ts: TileSet, terrain_name: String, source_id: int, block: Rect2i) -> int:
	var from := ts.get_source(source_id) as TileSetAtlasSource
	if from == null or from.texture == null:
		return -1
	var size := from.texture_region_size
	var art := from.texture.get_image()
	if art == null:
		return -1
	if art.is_compressed():
		art.decompress()
	art.convert(Image.FORMAT_RGBA8)
	var sheet := Image.create(size.x, size.y * block.size.y, false, Image.FORMAT_RGBA8)
	var half := size.x / 2
	for r in block.size.y:
		var left := Vector2i(block.position.x, block.position.y + r)
		var right := Vector2i(block.end.x - 1, block.position.y + r)
		if not from.has_tile(left) or not from.has_tile(right):
			continue
		var lp := from.get_tile_texture_region(left).position
		var rp := from.get_tile_texture_region(right).position
		sheet.blit_rect(art, Rect2i(lp, Vector2i(half, size.y)), Vector2i(0, r * size.y))
		sheet.blit_rect(art, Rect2i(rp + Vector2i(half, 0), Vector2i(size.x - half, size.y)), Vector2i(half, r * size.y))

	var key := [source_id, block.position.x, block.position.y, block.size.x, block.size.y]
	var id := -1
	for i in ts.get_source_count():
		var sid := ts.get_source_id(i)
		var s := ts.get_source(sid)
		if s is TileSetAtlasSource and s.get_meta(QuarterPieces.GENERATED_META, {}).get("lone_of", []) == key:
			id = sid
	var path := ""
	var src: TileSetAtlasSource
	if id >= 0:
		src = ts.get_source(id)
		path = str(src.get_meta(QuarterPieces.GENERATED_META).get("file", ""))
	else:
		path = QuarterPieces.file_for(ts, terrain_name + " lone", source_id)
		src = TileSetAtlasSource.new()
		src.texture_region_size = size
		src.set_meta(QuarterPieces.GENERATED_META, {terrain = terrain_name, file = path, lone_of = key})
	src.texture = QuarterPieces._save_sheet(sheet, path)
	if id < 0:
		id = ts.add_source(src)
	for r in block.size.y:
		var at := Vector2i(0, r)
		if not src.has_tile(at):
			src.create_tile(at)
		_copy_data(ts, from, Vector2i(block.position.x, block.position.y + r),
			Vector2i(block.end.x - 1, block.position.y + r), src.get_tile_data(at, 0), size)
	return id


## Everything but the collision comes from the left end; the collision is each end's own half.
static func _copy_data(ts: TileSet, from: TileSetAtlasSource, left: Vector2i, right: Vector2i, to: TileData, size: Vector2i) -> void:
	if not from.has_tile(left) or not from.has_tile(right):
		return
	var l := from.get_tile_data(left, 0)
	var r := from.get_tile_data(right, 0)
	for p in l.get_property_list():
		if p.usage & PROPERTY_USAGE_STORAGE and p.name != "script":
			to.set(p.name, l.get(p.name))
	for m in l.get_meta_list():
		to.set_meta(m, l.get_meta(m))
	var h := Vector2(size) / 2.0
	var left_half := PackedVector2Array([Vector2(-h.x, -h.y), Vector2(0, -h.y), Vector2(0, h.y), Vector2(-h.x, h.y)])
	var right_half := PackedVector2Array([Vector2(0, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(0, h.y)])
	for layer in ts.get_physics_layers_count():
		var shapes := []
		for i in l.get_collision_polygons_count(layer):
			shapes.append_array(Geometry2D.intersect_polygons(l.get_collision_polygon_points(layer, i), left_half))
		for i in r.get_collision_polygons_count(layer):
			shapes.append_array(Geometry2D.intersect_polygons(r.get_collision_polygon_points(layer, i), right_half))
		to.set_collision_polygons_count(layer, shapes.size())
		for i in shapes.size():
			to.set_collision_polygon_points(layer, i, shapes[i])
