@tool
extends RefCounted
## Collision polygons for a tile or a group of tiles, worked out in "block space": the
## group's pixels laid side by side (atlas separation left out), top-left at (0, 0).

enum Auto { CONTOUR, CONVEX, BOX, BASE, BASE_BOX, RIM }
enum Mirror { LEFT_TO_RIGHT, RIGHT_TO_LEFT, TOP_TO_BOTTOM, BOTTOM_TO_TOP }

## The copied shape, shared by the shape editor and the Collisions tool until the editor closes:
## {cells, region, normal, one_way, margin}, shapes in the copied block's px.
static var clipboard := {}

const DEFAULTS := {
	smoothness = 1.0, ## Douglas-Peucker tolerance, in pixels: higher means fewer points.
	alpha = 0.5, ## A pixel counts as painted above this alpha.
	specks = 4.0, ## Pieces smaller than this many square pixels are dropped.
	grow = 0.0, ## Pixels to push the outline out (negative pulls it in).
	base = 8.0, ## Height of the Base band, in pixels from the bottom of the drawing.
	rim = 1.0, ## Width of the Border band, in pixels in from the outline.
	rim_auto = true, ## Until the width is set by hand, it is a sixteenth of a tile.
	per_tile = false, ## Each tile of a group detected on its own.
}


## The tiles whose origin lies in the block: [{coords, rect (block px)}], and the block size in px.
static func layout(src: TileSetAtlasSource, origin: Vector2i, cells: Vector2i) -> Dictionary:
	var region := Vector2(src.texture_region_size)
	var tiles := []
	var seen := {}
	for y in cells.y:
		for x in cells.x:
			var at := src.get_tile_at_coords(origin + Vector2i(x, y))
			if at == Vector2i(-1, -1) or seen.has(at):
				continue
			seen[at] = true
			var offset := at - origin
			tiles.append({coords = at, rect = Rect2(Vector2(offset) * region, Vector2(src.get_tile_size_in_atlas(at)) * region)})
	return {tiles = tiles, size = Vector2(cells) * region, region = region}


## The block's pixels as one image, each tile's first frame at its place.
static func block_image(src: TileSetAtlasSource, lay: Dictionary) -> Image:
	var out := Image.create_empty(int(lay.size.x), int(lay.size.y), false, Image.FORMAT_RGBA8)
	if src.texture == null:
		return out
	var sheet := src.texture.get_image()
	if sheet == null:
		return out
	if sheet.is_compressed():
		sheet.decompress()
	sheet.convert(Image.FORMAT_RGBA8)
	for t: Dictionary in lay.tiles:
		var from := src.get_tile_texture_region(t.coords)
		out.blit_rect(sheet, from, Vector2i(t.rect.position))
	return out


static func area(polygon: PackedVector2Array) -> float:
	var sum := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5


static func bounds(polygons: Array) -> Rect2:
	var box := Rect2()
	var first := true
	for polygon: PackedVector2Array in polygons:
		for p in polygon:
			if first:
				box = Rect2(p, Vector2.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box


static func rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


## Outlines of the painted pixels inside a rect of the image, in block px.
static func contour(image: Image, rect: Rect2i, settings: Dictionary) -> Array:
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image, float(settings.alpha))
	var out := []
	# opaque_to_polygons needs a positive tolerance; a tiny one keeps every pixel step.
	# Its points come back relative to the rect, so a tile past the first is moved into place.
	var shift := Transform2D(0.0, Vector2(rect.position))
	for polygon: PackedVector2Array in bitmap.opaque_to_polygons(rect, maxf(0.01, float(settings.smoothness))):
		if polygon.size() >= 3 and area(polygon) >= float(settings.specks):
			out.append(shift * polygon)
	return out


## Runs one detection over the whole block, or over each tile when per_tile is set.
static func detect(image: Image, lay: Dictionary, mode: int, settings: Dictionary) -> Array:
	var zones: Array = []
	if bool(settings.per_tile) and lay.tiles.size() > 1:
		for t: Dictionary in lay.tiles:
			zones.append(Rect2i(t.rect))
	else:
		zones.append(Rect2i(Vector2i.ZERO, Vector2i(lay.size)))
	var out := []
	for zone: Rect2i in zones:
		out.append_array(_detect_zone(image, zone, mode, settings))
	return out


static func _detect_zone(image: Image, zone: Rect2i, mode: int, settings: Dictionary) -> Array:
	var outline := contour(image, zone, settings)
	if outline.is_empty():
		return []
	var result := []
	match mode:
		Auto.CONTOUR:
			result = outline
		Auto.CONVEX:
			var points := PackedVector2Array()
			for polygon: PackedVector2Array in outline:
				points.append_array(polygon)
			var hull := Geometry2D.convex_hull(points)
			# convex_hull repeats the first point at the end.
			if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
				hull.remove_at(hull.size() - 1)
			result = [hull]
		Auto.BOX:
			result = [rect_polygon(bounds(outline))]
		Auto.BASE, Auto.BASE_BOX:
			var box := bounds(outline)
			var height := clampf(float(settings.base), 1.0, box.size.y)
			var band := rect_polygon(Rect2(box.position.x - 1, box.end.y - height, box.size.x + 2, height))
			for polygon: PackedVector2Array in outline:
				result.append_array(_solid(Geometry2D.intersect_polygons(polygon, band)))
			# The basic base is the rectangle around what the precise one keeps.
			if mode == Auto.BASE_BOX and not result.is_empty():
				result = [rect_polygon(bounds(result))]
		Auto.RIM:
			result = rim(outline, float(settings.get("rim", 1.0)))
	return grow(result, float(settings.grow))


## A band width px deep along the inside of each outline. A ring has a hole, which tile
## shapes can't have, so it is cut through the hole into pieces that have none.
static func rim(polygons: Array, width: float) -> Array:
	var out := []
	for polygon: PackedVector2Array in polygons:
		var pieces := [polygon]
		# Outlines come back clockwise and so does their shrunk copy: take it as it is.
		var shrunk := Geometry2D.offset_polygon(polygon, -maxf(0.5, width), Geometry2D.JOIN_MITER)
		for hole: PackedVector2Array in shrunk.filter(func(p: PackedVector2Array): return p.size() >= 3):
			var next := []
			for piece: PackedVector2Array in pieces:
				next.append_array(_minus(piece, hole))
			pieces = next
		out.append_array(pieces)
	return out


## A piece with an inner shape taken out; when that would leave a hole, the piece is cut in
## two through the hole first, so each side comes out open.
static func _minus(piece: PackedVector2Array, hole: PackedVector2Array) -> Array:
	var result := Geometry2D.clip_polygons(piece, hole)
	if not result.any(func(p: PackedVector2Array): return Geometry2D.is_polygon_clockwise(p)):
		return _solid(result)
	var cut := bounds([hole]).get_center().x
	var around := bounds([piece]).grow(1.0)
	var out := []
	for side in [Rect2(around.position, Vector2(cut - around.position.x, around.size.y)),
			Rect2(Vector2(cut, around.position.y), Vector2(around.end.x - cut, around.size.y))]:
		for part: PackedVector2Array in _solid(Geometry2D.intersect_polygons(piece, rect_polygon(side))):
			out.append_array(_solid(Geometry2D.clip_polygons(part, hole)))
	return out


## Holes come back clockwise from Geometry2D; tile collisions can't use them.
static func _solid(polygons: Array) -> Array:
	return polygons.filter(func(p: PackedVector2Array): return p.size() >= 3 and not Geometry2D.is_polygon_clockwise(p))


static func grow(polygons: Array, by: float) -> Array:
	if is_zero_approx(by):
		return polygons
	var out := []
	for polygon: PackedVector2Array in polygons:
		out.append_array(_solid(Geometry2D.offset_polygon(polygon, by, Geometry2D.JOIN_MITER)))
	return out


## Mirror images across the block's centre line; point order reversed so they stay counter-clockwise.
static func reflect(polygons: Array, size: Vector2, horizontal: bool) -> Array:
	var out := []
	for polygon: PackedVector2Array in polygons:
		var flipped := PackedVector2Array()
		for i in range(polygon.size() - 1, -1, -1):
			var p := polygon[i]
			flipped.append(Vector2(size.x - p.x, p.y) if horizontal else Vector2(p.x, size.y - p.y))
		out.append(flipped)
	return out


static func clip(polygons: Array, rect: Rect2) -> Array:
	var out := []
	for polygon: PackedVector2Array in polygons:
		out.append_array(_solid(Geometry2D.intersect_polygons(polygon, rect_polygon(rect))))
	return out


## The shapes drawn in one half (or quarter) with their mirror images, as one set.
static func symmetric(polygons: Array, size: Vector2, horizontal: bool, vertical: bool) -> Array:
	var out := polygons.duplicate()
	if horizontal:
		out = merge(out + reflect(out, size, true))
	if vertical:
		out = merge(out + reflect(out, size, false))
	return out


## The part that can be edited under live symmetry: the left and/or top half.
static func editable_rect(size: Vector2, horizontal: bool, vertical: bool) -> Rect2:
	return Rect2(Vector2.ZERO, size * Vector2(0.5 if horizontal else 1.0, 0.5 if vertical else 1.0))


## Copies one half over the other: the kept half, and its mirror image, merged.
static func mirror(polygons: Array, size: Vector2, how: int) -> Array:
	var horizontal := how in [Mirror.LEFT_TO_RIGHT, Mirror.RIGHT_TO_LEFT]
	var half := size * (Vector2(0.5, 1.0) if horizontal else Vector2(1.0, 0.5))
	var keep := Rect2(Vector2.ZERO, half)
	if how == Mirror.RIGHT_TO_LEFT:
		keep.position.x = half.x
	elif how == Mirror.BOTTOM_TO_TOP:
		keep.position.y = half.y
	var kept := []
	for polygon: PackedVector2Array in polygons:
		kept.append_array(_solid(Geometry2D.intersect_polygons(polygon, rect_polygon(keep))))
	var both := kept.duplicate()
	for polygon: PackedVector2Array in kept:
		var flipped := PackedVector2Array()
		for i in range(polygon.size() - 1, -1, -1):
			var p := polygon[i]
			flipped.append(Vector2(size.x - p.x, p.y) if horizontal else Vector2(p.x, size.y - p.y))
		both.append(flipped)
	return merge(both)


## Joins polygons that touch or overlap, so a group reads as one shape again.
static func merge(polygons: Array) -> Array:
	var pending := polygons.duplicate()
	var out := []
	while not pending.is_empty():
		var current: PackedVector2Array = pending.pop_back()
		var joined := true
		while joined:
			joined = false
			for i in range(pending.size() - 1, -1, -1):
				var box_a := bounds([current]).grow(0.01)
				if not box_a.intersects(bounds([pending[i]]).grow(0.01), true):
					continue
				var union := Geometry2D.merge_polygons(current, pending[i])
				var result := _solid(union)
				# A join that leaves a hole (a ring closing) is not made: tile shapes can't have
				# holes, and dropping it filled the ring in, a border strip becoming a solid block.
				if result.size() == 1 and union.size() == 1:
					current = result[0]
					pending.remove_at(i)
					joined = true
		out.append(current)
	return out


## Block px → tile-local collision coordinates, and back.
static func to_local(p: Vector2, tile_rect: Rect2, ts: TileSet, lay: Dictionary, td: TileData) -> Vector2:
	var scale := Vector2(ts.tile_size) / Vector2(lay.region)
	return (p - tile_rect.get_center()) * scale - Vector2(td.texture_origin)


static func from_local(p: Vector2, tile_rect: Rect2, ts: TileSet, lay: Dictionary, td: TileData) -> Vector2:
	var scale := Vector2(ts.tile_size) / Vector2(lay.region)
	return (p + Vector2(td.texture_origin)) / scale + tile_rect.get_center()


## Cuts block polygons into each tile: {coords: [local polygons]}.
static func split(polygons: Array, src: TileSetAtlasSource, ts: TileSet, lay: Dictionary) -> Dictionary:
	var out := {}
	for t: Dictionary in lay.tiles:
		var td := src.get_tile_data(t.coords, 0)
		var pieces := []
		for polygon: PackedVector2Array in polygons:
			for piece: PackedVector2Array in _solid(Geometry2D.intersect_polygons(polygon, rect_polygon(t.rect))):
				if area(piece) < 0.01:
					continue
				var local := PackedVector2Array()
				for p in piece:
					local.append(to_local(p, t.rect, ts, lay, td))
				pieces.append(local)
		out[t.coords] = pieces
	return out


## The tiles' current polygons in block px, merged across tile seams, one-way ones kept apart:
## {normal, one_way, margin} (the first one-way margin found, 1.0 if none).
static func gather(src: TileSetAtlasSource, ts: TileSet, lay: Dictionary, layer: int) -> Dictionary:
	var normal := []
	var one_way := []
	var margin := 1.0
	var found_margin := false
	if layer >= 0 and layer < ts.get_physics_layers_count():
		for t: Dictionary in lay.tiles:
			var td := src.get_tile_data(t.coords, 0)
			for i in td.get_collision_polygons_count(layer):
				var block := PackedVector2Array()
				for p in td.get_collision_polygon_points(layer, i):
					block.append(from_local(p, t.rect, ts, lay, td))
				if td.is_collision_polygon_one_way(layer, i):
					one_way.append(block)
					if not found_margin:
						margin = td.get_collision_polygon_one_way_margin(layer, i)
						found_margin = true
				else:
					normal.append(block)
	return {normal = merge(normal), one_way = merge(one_way), margin = margin}


static func make_clip(normal: Array, one_way: Array, margin: float, lay: Dictionary, cells: Vector2i) -> Dictionary:
	return {cells = cells, region = lay.region, normal = normal.duplicate(true),
		one_way = one_way.duplicate(true), margin = margin}


## The copied shapes fitted to another block: scaled if its tiles are another size, cut to it.
static func fit_clip(copied: Dictionary, lay: Dictionary) -> Array:
	var scale := Vector2(lay.region) / Vector2(copied.region)
	var groups := []
	for key in ["normal", "one_way"]:
		var scaled := []
		for polygon: PackedVector2Array in copied[key]:
			var moved := PackedVector2Array()
			for p in polygon:
				moved.append(p * scale)
			scaled.append(moved)
		groups.append(clip(scaled, Rect2(Vector2.ZERO, lay.size)))
	return groups


## What a paste writes: {coords: [[points, one_way, margin], ...]} for each tile of the block.
static func clip_per_tile(copied: Dictionary, src: TileSetAtlasSource, ts: TileSet, lay: Dictionary) -> Dictionary:
	var groups := fit_clip(copied, lay)
	var normal := split(groups[0], src, ts, lay)
	var one_way := split(groups[1], src, ts, lay)
	var out := {}
	for coords in normal:
		out[coords] = normal[coords].map(func(p): return [p, false, 1.0]) \
			+ one_way[coords].map(func(p): return [p, true, float(copied.margin)])
	return out


static func describe_clip(copied: Dictionary) -> String:
	if copied.is_empty():
		return "Nothing copied"
	var count: int = copied.normal.size() + copied.one_way.size()
	var what := "tile" if copied.cells == Vector2i.ONE else "%d×%d tiles" % [copied.cells.x, copied.cells.y]
	return "Copied: %s, %s" % [what, "no shape" if count == 0 else "%d shape%s" % [count, "" if count == 1 else "s"]]
