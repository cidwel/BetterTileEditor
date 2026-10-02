@tool
extends RefCounted
## Reads a Match tiles terrain's joins from its drawing: a side or corner joins where the fill
## (the opaque pixels, or the middle's colours on opaque art) reaches it.

const SIDES := {
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE: Vector2i(1, 0),
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: Vector2i(0, 1),
	TileSet.CELL_NEIGHBOR_LEFT_SIDE: Vector2i(-1, 0),
	TileSet.CELL_NEIGHBOR_TOP_SIDE: Vector2i(0, -1),
}
## Each corner with the two sides it lies between.
const CORNERS := {
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: [TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE],
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: [TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE],
	TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE],
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE],
}
const ALPHA := 0.5
## Stands for "fill is whatever is opaque" in place of a palette.
const OPAQUE := {-1: true}
## Share of an edge's middle that must be fill for the side to join.
const SIDE_SHARE := 0.5
## On transparency an edge must be opaque all along: a wavy outline that touches the tile's
## edge (a cloud's) leaves gaps between its waves, a shape going on leaves none.
const OPAQUE_SIDE_SHARE := 0.95
const CORNER_SHARE := 0.75
## Share of an edge's middle in the outline's colours that makes it an outline, open, even
## though it is opaque: an outline drawn inside the tile, on its edge pixels.
const OUTLINE_SHARE := 0.5


## {coords: [peering bits]} from the drawing; corners only when the selection has an inner
## corner. {} if the texture can't be read.
static func read(src: TileSetAtlasSource, tiles: Array) -> Dictionary:
	if src.texture == null:
		return {}
	var sheet := src.texture.get_image()
	if sheet == null:
		return {}
	if sheet.is_compressed():
		sheet.decompress()
	sheet.convert(Image.FORMAT_RGBA8)
	var found := {}
	var inner := false
	var inside := {}
	for c: Vector2i in tiles:
		inside[c] = true
	var hint := false
	var regions := {}
	var transparent := false
	for c: Vector2i in tiles:
		regions[c] = sheet.get_region(src.get_tile_texture_region(c))
		transparent = transparent or regions[c].detect_alpha() != Image.ALPHA_NONE and _has_clear(regions[c])
	# The outline is what borders the transparency, in colours the middles hardly use.
	var outline := _outline_colours(regions.values()) if transparent else {}
	for c: Vector2i in tiles:
		var tile: Image = regions[c]
		# On transparency being opaque is enough; the middle's colours would split banded shading.
		var fill := OPAQUE if transparent else _fill_colours(tile)
		var sides := []
		var needed := OPAQUE_SIDE_SHARE if fill == OPAQUE else SIDE_SHARE
		for side in SIDES:
			var direction: Vector2i = SIDES[side]
			if _edge_share(tile, fill, direction) >= needed \
					and (outline.is_empty() or _edge_share(tile, outline, direction) < OUTLINE_SHARE):
				sides.append(side)
		if sides.size() < SIDES.size():
			hint = true
		var corners := []
		for corner in CORNERS:
			if CORNERS[corner].all(func(s): return sides.has(s)):
				if _corner_share(tile, corner) >= CORNER_SHARE:
					corners.append(corner)
				else:
					inner = true
		found[c] = [sides, corners]
	hint = hint or inner
	var single := _one_shape(found, inside)
	var out := {}
	for c: Vector2i in found:
		var sides: Array = found[c][0]
		if not hint or single:
			sides = sides.filter(func(side): return inside.has(c + SIDES[side]))
		out[c] = sides + (found[c][1] if inner and hint else [])
	return out


## The outline's colours: at least 5% of the border pixels and three times as common there as
## in the tiles' middles.
@warning_ignore("integer_division")
static func _outline_colours(tiles: Array) -> Dictionary:
	var border := {}
	var border_total := 0
	var middle := {}
	var middle_total := 0
	for tile: Image in tiles:
		var size := tile.get_size()
		for y in size.y:
			for x in size.x:
				var p := tile.get_pixel(x, y)
				if p.a < ALPHA:
					continue
				var key := _key(p)
				if x >= size.x / 3 and x < size.x - size.x / 3 and y >= size.y / 3 and y < size.y - size.y / 3:
					middle[key] = middle.get(key, 0) + 1
					middle_total += 1
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var q := Vector2i(x, y) + d
					if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y and tile.get_pixelv(q).a < ALPHA:
						border[key] = border.get(key, 0) + 1
						border_total += 1
						break
	var out := {}
	for key: int in border:
		var at_border := float(border[key]) / border_total
		if at_border >= 0.05 and float(middle.get(key, 0)) / maxi(1, middle_total) * 3.0 < at_border:
			out[key] = true
	return out


## Whether the selection is one shape (a full rectangle with no edge drawn inside), so its
## rim is the shape's: a 3x3 is a 9-slice.
static func _one_shape(found: Dictionary, inside: Dictionary) -> bool:
	var box := Rect2i()
	for c: Vector2i in found:
		box = Rect2i(c, Vector2i.ONE) if box.size == Vector2i.ZERO else box.merge(Rect2i(c, Vector2i.ONE))
	if box.size.x < 2 or box.size.y < 2 or found.size() != box.size.x * box.size.y:
		return false
	for c: Vector2i in found:
		for side in SIDES:
			if inside.has(c + SIDES[side]) and not (found[c][0] as Array).has(side):
				return false
	return true


## Colours of the tile's middle third, opaque ones, a little coarsened so shading noise matches.
@warning_ignore("integer_division")
static func _fill_colours(tile: Image) -> Dictionary:
	var size := tile.get_size()
	var colours := {}
	for y in range(size.y / 3, size.y - size.y / 3):
		for x in range(size.x / 3, size.x - size.x / 3):
			var p := tile.get_pixel(x, y)
			if p.a >= ALPHA:
				colours[_key(p)] = true
	return colours


static func _key(p: Color) -> int:
	return (int(p.r * 15.0) << 8) | (int(p.g * 15.0) << 4) | int(p.b * 15.0)


static func _is_fill(p: Color, fill: Dictionary) -> bool:
	return p.a >= ALPHA and (fill == OPAQUE or fill.has(_key(p)))


static func _has_clear(tile: Image) -> bool:
	for y in tile.get_height():
		for x in tile.get_width():
			if tile.get_pixel(x, y).a < ALPHA:
				return true
	return false


## The share of fill along the middle half of one edge (its outermost row or column).
@warning_ignore("integer_division")
static func _edge_share(tile: Image, fill: Dictionary, direction: Vector2i) -> float:
	var size := tile.get_size()
	var along := size.y if direction.x != 0 else size.x
	var from := along / 4
	var to := along - along / 4
	var hits := 0
	for i in range(from, to):
		var at := Vector2i(size.x - 1 if direction.x > 0 else 0, i) if direction.x != 0 \
			else Vector2i(i, size.y - 1 if direction.y > 0 else 0)
		if _is_fill(tile.get_pixelv(at), fill):
			hits += 1
	return float(hits) / maxf(1.0, float(to - from))


## The share of a corner's small square with the colours of its two joined sides: inner
## corners are often painted, not cut out.
@warning_ignore("integer_division")
static func _corner_share(tile: Image, corner: int) -> float:
	var size := tile.get_size()
	var palette := {}
	for side in CORNERS[corner]:
		var direction: Vector2i = SIDES[side]
		var along := size.y if direction.x != 0 else size.x
		for i in range(along / 4, along - along / 4):
			var at := Vector2i(size.x - 1 if direction.x > 0 else 0, i) if direction.x != 0 \
				else Vector2i(i, size.y - 1 if direction.y > 0 else 0)
			var p := tile.get_pixelv(at)
			if p.a >= ALPHA:
				palette[_key(p)] = true
	var side_px := maxi(1, mini(size.x, size.y) / 8)
	var right := corner in [TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER]
	var bottom := corner in [TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER]
	var x0 := size.x - side_px if right else 0
	var y0 := size.y - side_px if bottom else 0
	var hits := 0
	for y in range(y0, y0 + side_px):
		for x in range(x0, x0 + side_px):
			if _is_fill(tile.get_pixel(x, y), palette):
				hits += 1
	return float(hits) / float(side_px * side_px)


## Whether a tile has nothing drawn: a gap between shapes, not a piece of the terrain.
static func blank(src: TileSetAtlasSource, coords: Vector2i) -> bool:
	if src.texture == null:
		return false
	var sheet := src.texture.get_image()
	if sheet == null:
		return false
	if sheet.is_compressed():
		sheet.decompress()
	var tile := sheet.get_region(src.get_tile_texture_region(coords))
	return tile.is_invisible()


## A colour that stands out on these tiles, for the terrain's marks: the opposite hue of their
## average colour, dark on light art and light on dark art; a strong magenta on grey art.
static func contrast_color(src: TileSetAtlasSource, tiles: Array) -> Color:
	var fallback := Color.from_hsv(0.85, 0.9, 0.95)
	if src.texture == null or tiles.is_empty():
		return fallback
	var sheet := src.texture.get_image()
	if sheet == null:
		return fallback
	if sheet.is_compressed():
		sheet.decompress()
	var sum := Color(0, 0, 0, 0)
	var count := 0
	for c: Vector2i in tiles:
		var region := src.get_tile_texture_region(c)
		# Every other pixel is plenty for an average.
		for y in range(region.position.y, region.end.y, 2):
			for x in range(region.position.x, region.end.x, 2):
				var p := sheet.get_pixel(x, y)
				if p.a >= ALPHA:
					sum += Color(p.r, p.g, p.b, 0)
					count += 1
	if count == 0:
		return fallback
	var average := Color(sum.r / count, sum.g / count, sum.b / count)
	var light := average.get_luminance() > 0.55
	if average.s < 0.15:
		return Color.from_hsv(0.85, 0.9, 0.7 if light else 0.95)
	return Color.from_hsv(fmod(average.h + 0.5, 1.0), 0.9, 0.7 if light else 1.0)

