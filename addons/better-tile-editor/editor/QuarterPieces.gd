@tool
extends RefCounted
## Makes missing pieces out of quarters of drawn ones: each quarter has one of a few looks
## (five in Match tiles, eight in Match vertices) and is taken from a tile with that look.

const Coverage := preload("res://addons/better-tile-editor/editor/TerrainCoverage.gd")
const Shapes := preload("res://addons/better-tile-editor/editor/CollisionShapes.gd")

## Collision modes beside CollisionShapes.Auto's (0 and up). Not negative: they are menu ids,
## where -1 means "pick one".
const SHAPES_KEEP := 100
const SHAPES_FULL := 101
## No shapes: what is there on the layer is taken away.
const SHAPES_NONE := 102
## A band some pixels deep along the open sides and round the notches, from the piece's joins.
const SHAPES_STRIP := 103

enum Look { OUTER, EDGE_V, EDGE_H, INNER, FILL }
## How a made inner corner bends the outline: two straight bands meeting in an L, bands cut
## along the diagonal like a picture frame, or the outline turned round the corner point.
enum Bend { SQUARE, MITRE, ROUND }
const LOOK_NAMES := ["outer corner", "edge", "edge", "inner corner", "fill"]

## Each quarter (TL, TR, BL, BR): the side above or below it, the side beside it, its corner.
const QUARTERS := [
	[TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER],
	[TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER],
	[TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER],
	[TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER],
]

## Match vertices: each quarter's own corner, the one along its row, the one along its column.
const VERTEX_QUARTERS := [
	[TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER],
	[TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER],
	[TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER],
	[TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER],
]

const GENERATED_META := &"_better_terrain_generated"
const COLUMNS := 8

## The made pieces' atlas template, as tile sheets are drawn: [origin, size] shapes whose cells
## join their shape-mates (3x3, column, row, lone tile), and inner corners by the corner missed.
const LAYOUT_SHAPES := [[Vector2i(0, 0), Vector2i(3, 3)], [Vector2i(7, 0), Vector2i(1, 3)],
	[Vector2i(0, 4), Vector2i(3, 1)], [Vector2i(4, 4), Vector2i(1, 1)]]
const LAYOUT_INNER := {
	Vector2i(4, 0): TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, Vector2i(5, 0): TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	Vector2i(4, 1): TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, Vector2i(5, 1): TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
}
const LAYOUT_REST_ROW := 6
const _STEPS := {
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE: Vector2i(1, 0), TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: Vector2i(1, 1),
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: Vector2i(0, 1), TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: Vector2i(-1, 1),
	TileSet.CELL_NEIGHBOR_LEFT_SIDE: Vector2i(-1, 0), TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: Vector2i(-1, -1),
	TileSet.CELL_NEIGHBOR_TOP_SIDE: Vector2i(0, -1), TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: Vector2i(1, -1),
}


## The template's cells by the mask each holds, for a terrain of this type.
static func layout_template(type: int, with_corners: bool) -> Dictionary:
	var out := {}
	var add := func(cell: Vector2i, joins: int) -> void:
		# Match vertices: a corner is the terrain's when its two sides and itself are.
		var mask := Coverage.normalize(joins, BetterTerrain.TerrainType.MATCH_TILES,
			with_corners or type == BetterTerrain.TerrainType.MATCH_VERTICES)
		mask = Coverage.normalize(mask, type, with_corners)
		if not out.has(mask):
			out[mask] = cell
	for shape: Array in LAYOUT_SHAPES:
		var box := Rect2i(shape[0], shape[1])
		for y in range(box.position.y, box.end.y):
			for x in range(box.position.x, box.end.x):
				var joins := 0
				for bit: int in _STEPS:
					if box.has_point(Vector2i(x, y) + _STEPS[bit]):
						joins |= 1 << bit
				add.call(Vector2i(x, y), joins)
	var all := 0
	for bit: int in _STEPS:
		all |= 1 << bit
	for cell: Vector2i in LAYOUT_INNER:
		add.call(cell, all & ~(1 << LAYOUT_INNER[cell]))
	return out


## Each piece's cell: its template place, or below in a row per sides joined (Ls, Ts, crosses)
## when it has none or it is taken.
@warning_ignore("integer_division")
static func layout(pieces: Array, type: int) -> Array[Vector2i]:
	var with_corners := false
	for piece: Dictionary in pieces:
		for corner in Coverage.CORNERS:
			with_corners = with_corners or int(piece.mask) & (1 << corner) != 0
	var template := layout_template(type, with_corners)
	var out: Array[Vector2i] = []
	out.resize(pieces.size())
	var taken := {}
	var rest := []
	for i in pieces.size():
		var cell: Vector2i = template.get(int(pieces[i].mask), Vector2i(-1, -1))
		if cell.x < 0 or taken.has(cell):
			rest.append(i)
			continue
		taken[cell] = true
		out[i] = cell
	rest.sort_custom(func(a: int, b: int) -> bool: return _rest_key(pieces[a].mask) < _rest_key(pieces[b].mask))
	var row := LAYOUT_REST_ROW
	var col := 0
	var group := -1
	for i: int in rest:
		var g := _rest_key(pieces[i].mask)[0] as int
		if group != -1 and (g != group or col == COLUMNS):
			row += 1
			col = 0
		group = g
		out[i] = Vector2i(col, row)
		col += 1
	return out


## Sorting the pieces with no place: by sides joined, then which sides, then corners.
static func _rest_key(mask: int) -> Array:
	var sides := 0
	var count := 0
	for side in Coverage.SIDES:
		if mask & (1 << side):
			sides |= 1 << side
			count += 1
	return [count, sides, mask & ~sides]


static func look(mask: int, quarter: int, with_corners: bool, type := BetterTerrain.TerrainType.MATCH_TILES) -> int:
	if type == BetterTerrain.TerrainType.MATCH_VERTICES:
		var out := 0
		for i in 3:
			if mask & (1 << VERTEX_QUARTERS[quarter][i]):
				out |= 1 << i
		return out
	var q: Array = QUARTERS[quarter]
	var along: bool = mask & (1 << q[0]) != 0
	var beside: bool = mask & (1 << q[1]) != 0
	if not along and not beside:
		return Look.OUTER
	if along and not beside:
		return Look.EDGE_V
	if beside and not along:
		return Look.EDGE_H
	if with_corners and mask & (1 << q[2]) == 0:
		return Look.INNER
	return Look.FILL


## The quarter rects of a tile of this size, TL, TR, BL, BR; odd sizes give the right and
## bottom quarters the extra pixel, the same in every tile.
@warning_ignore("integer_division")
static func quarter_rects(size: Vector2i) -> Array[Rect2i]:
	var half := Vector2i(size.x / 2, size.y / 2)
	return [
		Rect2i(Vector2i.ZERO, half),
		Rect2i(half.x, 0, size.x - half.x, half.y),
		Rect2i(0, half.y, half.x, size.y - half.y),
		Rect2i(half, size - half),
	]


## The tiles quarters can come from, with their allowed turns:
## {region_size, by_look: [quarter][look] -> [{source_id, coord, flags}]}.
static func catalog(ts: TileSet, report: Dictionary, turns: int) -> Dictionary:
	var sizes := {}
	for tile: Dictionary in report.tiles:
		var src := ts.get_source(tile.source_id) as TileSetAtlasSource
		if tile.alt == 0 and src.get_tile_size_in_atlas(tile.coord) == Vector2i.ONE:
			sizes[src.texture_region_size] = sizes.get(src.texture_region_size, 0) + 1
	var region := Vector2i.ZERO
	for size: Vector2i in sizes:
		if region == Vector2i.ZERO or sizes[size] > sizes[region]:
			region = size
	var by_look := []
	var count := 8 if report.type == BetterTerrain.TerrainType.MATCH_VERTICES else Look.size()
	for quarter in 4:
		var looks := []
		for _look in count:
			looks.append([])
		by_look.append(looks)
	var flags_list: Array[int] = [0]
	flags_list.append_array(Coverage.allowed_flags(turns))
	for flags in flags_list:
		for tile: Dictionary in report.tiles:
			var src := ts.get_source(tile.source_id) as TileSetAtlasSource
			if tile.alt != 0 or src.texture_region_size != region or src.get_tile_size_in_atlas(tile.coord) != Vector2i.ONE:
				continue
			var mask := Coverage.normalize(Coverage.transform_mask(tile.mask, flags), report.type, report.with_corners)
			for quarter in 4:
				by_look[quarter][look(mask, quarter, report.with_corners, report.type)].append(
					{source_id = tile.source_id, coord = tile.coord, flags = flags})
	return {region_size = region, by_look = by_look, type = report.type}


## A piece's four quarter sources (TL, TR, BL, BR), the mix with the cleanest seams, or []
## when a look is never drawn.
static func plan(ts: TileSet, found: Dictionary, mask: int, with_corners: bool, images: Dictionary) -> Array:
	var options := []
	for quarter in 4:
		var kind := look(mask, quarter, with_corners, found.get("type", BetterTerrain.TerrainType.MATCH_TILES))
		var list: Array = found.by_look[quarter][kind]
		if list.is_empty() and kind == Look.INNER and found.get("type") == BetterTerrain.TerrainType.MATCH_TILES:
			list = _inner_from_edges(found, quarter)
		if list.is_empty():
			return []
		var seen := {}
		var picked := []
		for source: Dictionary in list:
			if not seen.has(_key(source)) and picked.size() < MAX_OPTIONS:
				seen[_key(source)] = true
				picked.append(source)
		options.append(picked)
	var size: Vector2i = found.region_size
	var rects := quarter_rects(size)
	var best := []
	var best_cost := INF
	for a: Dictionary in options[0]:
		for b: Dictionary in options[1]:
			var top := _seam(ts, a, b, rects[0], true, images)
			for c: Dictionary in options[2]:
				var left := _seam(ts, a, c, rects[0], false, images)
				for d: Dictionary in options[3]:
					var cost: float = top + left + _seam(ts, c, d, rects[2], true, images) + _seam(ts, b, d, rects[1], false, images)
					var tiles := {}
					for source: Dictionary in [a, b, c, d]:
						tiles[_key(source)] = true
					cost += TILE_PENALTY * (tiles.size() - 1)
					if cost < best_cost:
						best_cost = cost
						best = [a, b, c, d]
	return best


const MAX_OPTIONS := 8
## A seam costs this much per extra tile used, so a whole tile wins when seams tie.
const TILE_PENALTY := 0.5


## How far apart the pixels meeting across a seam are: the first quarter's (rect) right or
## bottom edge against the next pixels of the quarter beside or below, from its own tile.
static func _seam(ts: TileSet, first: Dictionary, second: Dictionary, rect: Rect2i, across: bool, images: Dictionary) -> float:
	var one := _image(ts, first, images)
	var two := _image(ts, second, images)
	var cost := 0.0
	if across:
		for y in range(rect.position.y, rect.end.y):
			cost += _distance(one.get_pixel(rect.end.x - 1, y), two.get_pixel(rect.end.x, y))
	else:
		for x in range(rect.position.x, rect.end.x):
			cost += _distance(one.get_pixel(x, rect.end.y - 1), two.get_pixel(x, rect.end.y))
	return cost


static func _distance(p: Color, q: Color) -> float:
	return absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) + absf(p.a - q.a)


static func _image(ts: TileSet, source: Dictionary, images: Dictionary) -> Image:
	var key := _key(source)
	if not images.has(key):
		if not images.has(&"sheets"):
			images[&"sheets"] = {}
		images[key] = tile_image(ts, source, images[&"sheets"])
	return images[key]


static func _key(source: Dictionary) -> String:
	if source.has("synth"):
		return "inner|%d|%d|%s|%s|%s" % [source.synth, source.get("bend", Bend.ROUND), _key(source.fill), _key(source.edge_v), _key(source.edge_h)]
	return "%d|%s|%d" % [source.source_id, source.coord, source.flags]


## Made inner corner quarters: the fill with the edges bent round the corner, a few of each to
## let the seams choose: [{synth: quarter, fill, edge_v, edge_h}].
static func _inner_from_edges(found: Dictionary, quarter: int) -> Array:
	var kinds := []
	for kind in [Look.FILL, Look.EDGE_V, Look.EDGE_H]:
		var list: Array = found.by_look[quarter][kind]
		if list.is_empty():
			return []
		kinds.append(list.slice(0, 2))
	var out := []
	for fill: Dictionary in kinds[0]:
		for edge_v: Dictionary in kinds[1]:
			for edge_h: Dictionary in kinds[2]:
				out.append({synth = quarter, bend = found.get("bend", Bend.ROUND), fill = fill, edge_v = edge_v, edge_h = edge_h,
					source_id = fill.source_id, coord = fill.coord, flags = fill.flags})
	return out


## A made inner corner, as a whole tile: the fill tile with its quarter's corner replaced.
static func _inner_image(ts: TileSet, source: Dictionary, sheets: Dictionary) -> Image:
	var whole := tile_image(ts, source.fill, sheets)
	var rect: Rect2i = quarter_rects(whole.get_size())[source.synth]
	var fill := whole.get_region(rect)
	var along := tile_image(ts, source.edge_v, sheets).get_region(rect)
	var beside := tile_image(ts, source.edge_h, sheets).get_region(rect)
	# Worked out as if the corner were the top left one.
	var right: bool = source.synth in [1, 3]
	var bottom: bool = source.synth in [2, 3]
	for image: Image in [fill, along, beside]:
		if right:
			image.flip_x()
		if bottom:
			image.flip_y()
	# How deep each edge's drawing goes before it is the fill: its outline's width.
	var deep_x := 0
	while deep_x < rect.size.x and _differs(along, fill, deep_x, true):
		deep_x += 1
	var deep_y := 0
	while deep_y < rect.size.y and _differs(beside, fill, deep_y, false):
		deep_y += 1
	var out := fill.duplicate()
	match source.get("bend", Bend.ROUND):
		Bend.SQUARE:
			for y in deep_y:
				for x in deep_x:
					var p := beside.get_pixel(x, y)
					if p.is_equal_approx(fill.get_pixel(x, y)):
						p = along.get_pixel(x, y)
					out.set_pixel(x, y, p)
		Bend.MITRE:
			# Each band runs up to the corner's diagonal, where they meet.
			for y in deep_y:
				for x in deep_x:
					var upper := y * deep_x <= x * deep_y
					out.set_pixel(x, y, beside.get_pixel(x, y) if upper else along.get_pixel(x, y))
		Bend.ROUND:
			# The outline turned round the corner point: a pixel some way from it takes the colour
			# the edge has as far in from its side, so the bands' shading follows the curve.
			var radius := float(maxi(deep_x, deep_y))
			for y in rect.size.y:
				for x in rect.size.x:
					var d := Vector2(x + 0.5, y + 0.5).length()
					if d >= radius:
						continue
					var depth := d / radius
					if y <= x:
						out.set_pixel(x, y, beside.get_pixel(x, mini(int(depth * deep_y), rect.size.y - 1)))
					else:
						out.set_pixel(x, y, along.get_pixel(mini(int(depth * deep_x), rect.size.x - 1), y))
	if right:
		out.flip_x()
	if bottom:
		out.flip_y()
	whole.blit_rect(out, Rect2i(Vector2i.ZERO, rect.size), rect.position)
	return whole


## Whether a column (or row) of an edge's quarter is mostly unlike the fill's: part of its
## outline, not texture dotted over a fill.
static func _differs(edge: Image, fill: Image, at: int, column: bool) -> bool:
	var count := edge.get_height() if column else edge.get_width()
	var unlike := 0
	for i in count:
		var p := Vector2i(at, i) if column else Vector2i(i, at)
		if not edge.get_pixelv(p).is_equal_approx(fill.get_pixelv(p)):
			unlike += 1
	return unlike >= count * 0.6


## A tile's art turned the way the solver turns it: transposed first, then flipped.
static func tile_image(ts: TileSet, source: Dictionary, sheets: Dictionary) -> Image:
	if source.has("synth"):
		return _inner_image(ts, source, sheets)
	var src := ts.get_source(source.source_id) as TileSetAtlasSource
	if not sheets.has(source.source_id):
		var sheet := src.texture.get_image()
		if sheet.is_compressed():
			sheet.decompress()
		sheet.convert(Image.FORMAT_RGBA8)
		sheets[source.source_id] = sheet
	var image: Image = sheets[source.source_id].get_region(src.get_tile_texture_region(source.coord))
	var flags: int = source.flags
	if flags & Coverage.T:
		image.rotate_90(CLOCKWISE)
		image.flip_x()
	if flags & Coverage.H:
		image.flip_x()
	if flags & Coverage.V:
		image.flip_y()
	return image


static func compose(ts: TileSet, quarters: Array, size: Vector2i, sheets: Dictionary) -> Image:
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var rects := quarter_rects(size)
	for quarter in 4:
		out.blit_rect(tile_image(ts, quarters[quarter], sheets), rects[quarter], rects[quarter].position)
	return out


## A point of a tile's shapes (centred on the tile) after its turn.
static func _turned(p: Vector2, flags: int) -> Vector2:
	if flags & Coverage.T:
		p = Vector2(p.y, p.x)
	if flags & Coverage.H:
		p.x = -p.x
	if flags & Coverage.V:
		p.y = -p.y
	return p


## Where new pieces go: beside the first source's texture, named after it and the terrain.
static func file_for(ts: TileSet, terrain_name: String, source_id: int, other_name := "") -> String:
	var src := ts.get_source(source_id) as TileSetAtlasSource
	var base := src.texture.resource_path if src != null and src.texture != null else ""
	var dir := base.get_base_dir() if base.begins_with("res://") else "res://"
	var stem := base.get_file().get_basename() if not base.is_empty() else "tiles"
	var slug := (terrain_name + ("_" + other_name if not other_name.is_empty() else "")).to_snake_case().validate_filename()
	# A quick terrain is named after its sheet: don't say the sheet's name twice.
	var name := slug if slug.begins_with(stem) else "%s_%s" % [stem, slug] if not slug.is_empty() else stem
	var path := dir.path_join("%s_pieces.png" % name)
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s_pieces_%d.png" % [name, n])
		n += 1
	return path


## A new atlas with the pieces, saved as a PNG beside the source sheet (an ImageTexture when
## that fails).
static func build_source(ts: TileSet, terrain_id: int, pieces: Array, size: Vector2i, path: String) -> TileSetAtlasSource:
	var sheets := {}
	var cells := layout(pieces, BetterTerrain.get_terrain(ts, terrain_id).type)
	var extent := Vector2i.ONE
	for cell in cells:
		extent = extent.max(cell + Vector2i.ONE)
	var sheet := Image.create(size.x * extent.x, size.y * extent.y, false, Image.FORMAT_RGBA8)
	for i in pieces.size():
		var image := compose(ts, pieces[i].quarters, size, sheets)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, size), cells[i] * size)
	var texture: Texture2D = null
	if not path.is_empty() and sheet.save_png(path) == OK:
		var fs := EditorInterface.get_resource_filesystem()
		fs.update_file(path)
		fs.reimport_files(PackedStringArray([path]))
		texture = ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
	if texture == null:
		texture = ImageTexture.create_from_image(sheet)
	var src := TileSetAtlasSource.new()
	src.texture = texture
	src.texture_region_size = size
	src.set_meta(GENERATED_META, {terrain = BetterTerrain.get_terrain(ts, terrain_id).name, file = path})
	for cell in cells:
		src.create_tile(cell)
	return src


## Sets the new atlas's terrain, peering bits (open ones facing `other`) and shapes, once it is
## in the tile set. shapes: {mode, layer, only, strip, type, with_corners}.
static func fill_source(ts: TileSet, src: TileSetAtlasSource, terrain_id: int, pieces: Array, shapes := {},
		other := -1, with_corners := true) -> void:
	var sheets := {}
	var type: int = BetterTerrain.get_terrain(ts, terrain_id).type
	var facing := []
	if other >= 0:
		for bit in BetterTerrain.data.get_terrain_peering_cells(ts, type):
			if type == BetterTerrain.TerrainType.MATCH_VERTICES or Coverage.SIDES.has(bit) or with_corners:
				facing.append(bit)
	var cells := layout(pieces, type)
	for i in pieces.size():
		var td := src.get_tile_data(cells[i], 0)
		BetterTerrain.set_tile_terrain_type(ts, td, terrain_id)
		for bit in 16:
			if pieces[i].mask & (1 << bit):
				BetterTerrain.add_tile_peering_type(ts, td, bit, terrain_id)
			elif bit in facing:
				BetterTerrain.add_tile_peering_type(ts, td, bit, other)
		if shapes.get("off", false):
			continue
		# Filled again on every redo, so nothing piles up.
		for layer in ts.get_physics_layers_count():
			var mode: int = shapes.get("mode", SHAPES_KEEP)
			var picked: bool = not shapes.has("only") or pieces[i].mask in shapes.only
			var out: Array
			if mode == SHAPES_KEEP or layer != shapes.get("layer", 0) or not picked:
				out = quarter_shapes(ts, pieces[i].quarters, src.texture_region_size, layer)
			else:
				out = piece_shapes(compose(ts, pieces[i].quarters, src.texture_region_size, sheets), pieces[i].mask, shapes)
			set_shapes(ts, td, layer, out)


## Each quarter's collision cut from the tile it comes from, turned with it, centred on the tile:
## [{points, one_way, margin}].
static func quarter_shapes(ts: TileSet, quarters: Array, size: Vector2i, layer: int) -> Array:
	var out := []
	var rects := quarter_rects(size)
	var centre := Vector2(size) * 0.5
	for quarter in 4:
		var from: Dictionary = quarters[quarter]
		var from_src := ts.get_source(from.source_id) as TileSetAtlasSource
		if from_src == null or layer >= ts.get_physics_layers_count():
			continue
		var from_td := from_src.get_tile_data(from.coord, 0)
		var r := Rect2(rects[quarter].position, rects[quarter].size)
		var clip := PackedVector2Array([r.position - centre, Vector2(r.end.x, r.position.y) - centre,
			r.end - centre, Vector2(r.position.x, r.end.y) - centre])
		for p in from_td.get_collision_polygons_count(layer):
			var points := PackedVector2Array()
			for v in from_td.get_collision_polygon_points(layer, p):
				points.append(_turned(v, from.flags))
			for cut in Geometry2D.intersect_polygons(points, clip):
				out.append({points = cut, one_way = from_td.is_collision_polygon_one_way(layer, p),
					margin = from_td.get_collision_polygon_one_way_margin(layer, p)})
	return out


## A piece's shapes for a collision choice ({mode, strip, type, with_corners}), centred on it.
static func piece_shapes(image: Image, mask: int, shapes: Dictionary) -> Array:
	if shapes.get("mode") == SHAPES_STRIP:
		return strip_shapes(mask, image.get_size(), float(shapes.get("strip", 2)),
			shapes.get("type", BetterTerrain.TerrainType.MATCH_TILES), shapes.get("with_corners", true))
	return art_shapes(image, shapes.get("mode", SHAPES_FULL))


## A band depth px deep along each open side and round each notch (an inner corner), centred
## on the tile. Match vertices: along the half sides beside each corner that is not joined.
@warning_ignore("integer_division")
static func strip_shapes(mask: int, size: Vector2i, depth: float, type: int, with_corners: bool) -> Array:
	var w := float(size.x)
	var h := float(size.y)
	var d := clampf(depth, 1.0, minf(w, h))
	var rects: Array[Rect2] = []
	var joined := func(bit: int) -> bool: return mask & (1 << bit) != 0
	if type == BetterTerrain.TerrainType.MATCH_VERTICES:
		var halves := {
			TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: [Rect2(0, 0, w / 2, d), Rect2(0, 0, d, h / 2)],
			TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: [Rect2(w / 2, 0, w / 2, d), Rect2(w - d, 0, d, h / 2)],
			TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: [Rect2(0, h - d, w / 2, d), Rect2(0, h / 2, d, h / 2)],
			TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: [Rect2(w / 2, h - d, w / 2, d), Rect2(w - d, h / 2, d, h / 2)],
		}
		for corner: int in halves:
			if not joined.call(corner):
				rects.append_array(halves[corner])
	else:
		var sides := {
			TileSet.CELL_NEIGHBOR_TOP_SIDE: Rect2(0, 0, w, d), TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: Rect2(0, h - d, w, d),
			TileSet.CELL_NEIGHBOR_LEFT_SIDE: Rect2(0, 0, d, h), TileSet.CELL_NEIGHBOR_RIGHT_SIDE: Rect2(w - d, 0, d, h),
		}
		for side: int in sides:
			if not joined.call(side):
				rects.append(sides[side])
		if with_corners:
			var notches := {
				TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: Rect2(0, 0, d, d), TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: Rect2(w - d, 0, d, d),
				TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: Rect2(0, h - d, d, d), TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: Rect2(w - d, h - d, d, d),
			}
			for corner: int in notches:
				if not joined.call(corner) and Coverage.CORNERS[corner].all(func(side): return joined.call(side)):
					rects.append(notches[corner])
	var polygons := []
	for r in rects:
		polygons.append(Shapes.rect_polygon(r))
	var out := []
	for polygon: PackedVector2Array in Shapes.merge(polygons):
		var points := PackedVector2Array()
		for v in polygon:
			points.append(v - Vector2(w, h) * 0.5)
		out.append({points = points, one_way = false, margin = 1.0})
	return out


## A tile's shapes read from its art, centred on the tile: the whole tile, or a detection mode.
static func art_shapes(image: Image, mode: int) -> Array:
	var size := Vector2(image.get_size())
	var polygons := []
	if mode == SHAPES_NONE:
		return []
	if mode == SHAPES_FULL:
		polygons = [Shapes.rect_polygon(Rect2(Vector2.ZERO, size))]
	else:
		var lay := {tiles = [{coords = Vector2i.ZERO, rect = Rect2(Vector2.ZERO, size)}], size = size}
		polygons = Shapes.detect(image, lay, mode, Shapes.DEFAULTS)
	var out := []
	for polygon: PackedVector2Array in polygons:
		var points := PackedVector2Array()
		for v in polygon:
			points.append(v - size * 0.5)
		out.append({points = points, one_way = false, margin = 1.0})
	return out


## A tile's shapes on a physics layer, as [{points, one_way, margin}].
static func get_shapes(td: TileData, layer: int) -> Array:
	var out := []
	for p in td.get_collision_polygons_count(layer):
		out.append({points = td.get_collision_polygon_points(layer, p),
			one_way = td.is_collision_polygon_one_way(layer, p), margin = td.get_collision_polygon_one_way_margin(layer, p)})
	return out


## Replaces a tile's shapes on a layer; a layer the tile set no longer has is left alone.
static func set_shapes(ts: TileSet, td: TileData, layer: int, shapes: Array) -> void:
	if layer >= ts.get_physics_layers_count():
		return
	while td.get_collision_polygons_count(layer) > 0:
		td.remove_collision_polygon(layer, 0)
	for shape: Dictionary in shapes:
		var index := td.get_collision_polygons_count(layer)
		td.add_collision_polygon(layer)
		td.set_collision_polygon_points(layer, index, shape.points)
		td.set_collision_polygon_one_way(layer, index, shape.one_way)
		td.set_collision_polygon_one_way_margin(layer, index, shape.margin)

