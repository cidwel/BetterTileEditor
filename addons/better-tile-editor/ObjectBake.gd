@tool
extends RefCounted


const TERRAIN_META = &"_better_terrain"


#region The lattice

## The pitch must divide the unit exactly or wrapping changes the lattice phase.
static func closes(unit_px: int, pitch_px: int) -> bool:
	return pitch_px > 0 and unit_px > 0 and unit_px % pitch_px == 0


static func unit_cells_for(pitch_px: int, tile_px: int, limit := 8) -> Array:
	var out := []
	if pitch_px <= 0 or tile_px <= 0:
		return out
	for cells in range(1, limit + 1):
		if closes(cells * tile_px, pitch_px):
			out.push_back(cells)
	return out


static func stamps(unit_px: Vector2i, art_px: Vector2i, pitch_px: Vector2i, stagger_px := 0,
		offset_px := Vector2i.ZERO) -> Array:
	var out := []
	if unit_px.x <= 0 or unit_px.y <= 0:
		return out
	var sx: int = maxi(1, pitch_px.x)
	var sy: int = maxi(1, pitch_px.y)
	var first_row: int = -int(ceil(float(art_px.y + absi(offset_px.y)) / float(sy)))
	var last_row: int = int(ceil(float(unit_px.y + art_px.y + absi(offset_px.y)) / float(sy)))
	for row in range(first_row, last_row + 1):
		var y: int = row * sy + offset_px.y
		var phase: int = stagger_px if posmod(row, 2) == 1 else 0
		var first_col: int = -int(ceil(float(art_px.x + phase + absi(offset_px.x)) / float(sx)))
		var last_col: int = int(ceil(float(unit_px.x + art_px.x + absi(offset_px.x)) / float(sx)))
		for col in range(first_col, last_col + 1):
			var x: int = col * sx + phase + offset_px.x
			out.push_back(Vector2i(posmod(x, unit_px.x), posmod(y, unit_px.y)))
	return out

#endregion


#region Baking

static func bake_unit(art: Image, unit_px: Vector2i, pitch_px: Vector2i, stagger_px := 0,
		offset_px := Vector2i.ZERO) -> Image:
	var out := Image.create_empty(maxi(1, unit_px.x), maxi(1, unit_px.y), false, Image.FORMAT_RGBA8)
	if art == null:
		return out
	var src := art
	if src.get_format() != Image.FORMAT_RGBA8:
		src = art.duplicate()
		src.convert(Image.FORMAT_RGBA8)
	var art_px := Vector2i(src.get_width(), src.get_height())
	for at in stamps(unit_px, art_px, pitch_px, stagger_px, offset_px):
		_blend_wrapped(out, src, at)
	return out


static func bake_piece(art: Image, unit_px: Vector2i, pitch_px: Vector2i, stagger_px := 0,
		offset_px := Vector2i.ZERO) -> Image:
	return grow_into_holes(bake_unit(art, unit_px, pitch_px, stagger_px, offset_px))


static func _blend_wrapped(dst: Image, src: Image, at: Vector2i) -> void:
	var w := dst.get_width()
	var h := dst.get_height()
	var sw := src.get_width()
	var sh := src.get_height()
	var x := 0
	while x < sw:
		var dx: int = posmod(at.x + x, w)
		var run_x: int = mini(sw - x, w - dx)
		var y := 0
		while y < sh:
			var dy: int = posmod(at.y + y, h)
			var run_y: int = mini(sh - y, h - dy)
			dst.blend_rect(src, Rect2i(x, y, run_x, run_y), Vector2i(dx, dy))
			y += run_y
		x += run_x


static func art_of(src: TileSetAtlasSource, origin: Vector2i, size: Vector2i) -> Image:
	if src == null or src.texture == null:
		return null
	var tile := src.texture_region_size
	var atlas_image := src.texture.get_image()
	if atlas_image == null:
		return null
	if atlas_image.is_compressed():
		atlas_image = atlas_image.duplicate()
		atlas_image.decompress()
	var out := Image.create_empty(maxi(1, size.x * tile.x), maxi(1, size.y * tile.y), false, Image.FORMAT_RGBA8)
	for dy in size.y:
		for dx in size.x:
			var coord := origin + Vector2i(dx, dy)
			if src.get_tile_at_coords(coord) != coord:
				continue
			var region := src.get_tile_texture_region(coord, 0)
			out.blit_rect(atlas_image, region, Vector2i(dx * tile.x, dy * tile.y))
	return out


static func reboxed(art: Image, box_px: Vector2i, at := Vector2i(-1, -1)) -> Image:
	var out := Image.create_empty(maxi(1, box_px.x), maxi(1, box_px.y), false, Image.FORMAT_RGBA8)
	if art == null:
		return out
	var put := at
	if put.x < 0:
		@warning_ignore("integer_division")
		put.x = (box_px.x - art.get_width()) / 2
	if put.y < 0:
		put.y = box_px.y - art.get_height()
	out.blend_rect(art, Rect2i(0, 0, art.get_width(), art.get_height()), put)
	return out


static func crown(art: Image, keep: int) -> Image:
	if art == null or keep <= 0 or keep >= art.get_height():
		return art
	var out := Image.create_empty(art.get_width(), keep, false, Image.FORMAT_RGBA8)
	out.blit_rect(art, Rect2i(0, 0, art.get_width(), keep), Vector2i.ZERO)
	return out


static func grow_into_holes(img: Image) -> Image:
	if img == null:
		return img
	var out: Image = img.duplicate()
	var w := out.get_width()
	var h := out.get_height()
	var look := [Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1),
		Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]
	for pass_n in h:
		var open_pixels := 0
		var next: Image = out.duplicate()
		for y in h:
			for x in w:
				if out.get_pixel(x, y).a > 0.5:
					continue
				open_pixels += 1
				for d in look:
					var c: Color = out.get_pixel(posmod(x + d.x, w), posmod(y + d.y, h))
					if c.a > 0.5:
						next.set_pixel(x, y, c)
						break
		out = next
		if open_pixels == 0:
			break
	return out


static func holes(img: Image) -> int:
	if img == null:
		return 0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a < 0.5:
				n += 1
	return n


static func mass_end(art: Image, share := 0.6) -> int:
	if art == null:
		return 0
	var h := art.get_height()
	var w := art.get_width()
	var ink := PackedInt32Array()
	ink.resize(h)
	var widest := 0
	for y in h:
		var n := 0
		for x in w:
			if art.get_pixel(x, y).a > 0.5:
				n += 1
		ink[y] = n
		widest = maxi(widest, n)
	if widest == 0:
		return h
	var floor_ink: int = int(ceil(widest * share))
	@warning_ignore("integer_division")
	for y in range(h / 3, h):
		if ink[y] < floor_ink:
			return y
	return h


static func default_crop(art: Image, unit_px: Vector2i, pitch_px: Vector2i, stagger_px := 0) -> int:
	if art == null:
		return 0
	var h := art.get_height()
	var low: int = clampi(pitch_px.y, 1, h)
	@warning_ignore("integer_division")
	var high: int = clampi(mini(mass_end(art), low + h / 4), low, h)
	var best := low
	var brightest := -1.0
	var keep := low
	while keep <= high:
		var lit := _lit(grow_into_holes(bake_unit(crown(art, keep), unit_px, pitch_px, stagger_px)))
		if lit > brightest:
			brightest = lit
			best = keep
		keep += 2
	return best


static func _lit(img: Image) -> float:
	var t := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			t += (c.r + c.g + c.b) / 3.0
	return t / maxi(1, img.get_width() * img.get_height())


static func mass_preview(art: Image, piece: Image, unit_px: Vector2i, pitch_px: Vector2i,
		stagger_px := 0, times := Vector2i(3, 3)) -> Image:
	if art == null:
		return tiled(piece, times)
	# Render on a larger sheet and crop; wrapping stamps here changes their drawing order.
	var pad := Vector2i(2, 2)
	var big := tiled(piece, times + pad * 2)
	var w := big.get_width()
	var h := big.get_height()
	var sx: int = maxi(1, pitch_px.x)
	var sy: int = maxi(1, pitch_px.y)
	var row := -int(ceil(float(art.get_height()) / float(sy)))
	while row * sy < h:
		var y: int = row * sy
		var phase: int = stagger_px if posmod(row, 2) == 1 else 0
		var col := -1
		while col * sx + phase < w:
			_blend_clipped(big, art, Vector2i(col * sx + phase, y))
			col += 1
		row += 1
	var from := Vector2i(pad.x * unit_px.x, pad.y * unit_px.y)
	var out := Image.create_empty(unit_px.x * times.x, unit_px.y * times.y, false, Image.FORMAT_RGBA8)
	out.blit_rect(big, Rect2i(from, out.get_size()), Vector2i.ZERO)
	return out


static func _blend_clipped(dst: Image, src: Image, at: Vector2i) -> void:
	var area := Rect2i(Vector2i.ZERO, dst.get_size()).intersection(Rect2i(at, src.get_size()))
	if area.size.x <= 0 or area.size.y <= 0:
		return
	dst.blend_rect(src, Rect2i(area.position - at, area.size), area.position)


static func tiled(unit: Image, times: Vector2i) -> Image:
	var w: int = maxi(1, unit.get_width())
	var h: int = maxi(1, unit.get_height())
	var out := Image.create_empty(w * maxi(1, times.x), h * maxi(1, times.y), false, Image.FORMAT_RGBA8)
	for ty in maxi(1, times.y):
		for tx in maxi(1, times.x):
			out.blit_rect(unit, Rect2i(0, 0, w, h), Vector2i(tx * w, ty * h))
	return out

#endregion


#region Putting it in the tileset

const SOURCE_META = &"_better_terrain_baked"

## Keep both blocks in one atlas source: object configuration stores only the lone coordinate.
static func sheet(art: Image, unit_px: Vector2i, pitch_px: Vector2i, stagger_px := 0,
		offset_px := Vector2i.ZERO, mass_art: Image = null) -> Image:
	var lone := reboxed(art, unit_px)
	var joined := bake_piece(mass_art if mass_art != null else art, unit_px, pitch_px, stagger_px, offset_px)
	var out := Image.create_empty(unit_px.x * 2, unit_px.y, false, Image.FORMAT_RGBA8)
	out.blend_rect(lone, Rect2i(Vector2i.ZERO, unit_px), Vector2i.ZERO)
	out.blend_rect(joined, Rect2i(Vector2i.ZERO, unit_px), Vector2i(unit_px.x, 0))
	return out


## Capture all terrain marks before baking so undo restores every previous block.
static func marked_tiles(ts: TileSet, terrain_id: int) -> Array:
	var out := []
	if ts == null:
		return out
	for i in ts.get_source_count():
		var sid := ts.get_source_id(i)
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src == null:
			continue
		for t in src.get_tiles_count():
			var coord := src.get_tile_id(t)
			if _type_of(src.get_tile_data(coord, 0)) == terrain_id:
				out.push_back([sid, coord])
	return out


static func install(ts: TileSet, terrain_id: int, sheet_image: Image, unit_cells: Vector2i,
		tile_px: Vector2i, previous: Array) -> int:
	if ts == null or sheet_image == null or terrain_id < 0:
		return -1
	var old := source_of(ts, terrain_id)
	if old >= 0:
		ts.remove_source(old)

	for entry in previous:
		var src0 := ts.get_source(entry[0]) as TileSetAtlasSource
		if src0 != null and src0.get_tile_at_coords(entry[1]) == entry[1]:
			_mark(ts, src0.get_tile_data(entry[1], 0), -2)  # TileCategory.NON_TERRAIN

	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(sheet_image)
	src.texture_region_size = tile_px
	for y in unit_cells.y:
		for x in unit_cells.x * 2:
			src.create_tile(Vector2i(x, y))
	var id := ts.get_next_source_id()
	ts.add_source(src, id)
	var marks: Dictionary = ts.get_meta(SOURCE_META, {})
	marks[terrain_id] = id
	ts.set_meta(SOURCE_META, marks)

	for y in unit_cells.y:
		for x in unit_cells.x * 2:
			_mark(ts, src.get_tile_data(Vector2i(x, y), 0), terrain_id)
	ts.emit_changed()
	return id


static func source_of(ts: TileSet, terrain_id: int) -> int:
	if ts == null:
		return -1
	var marks: Dictionary = ts.get_meta(SOURCE_META, {})
	var id: int = int(marks.get(terrain_id, -1))
	return id if id >= 0 and ts.has_source(id) else -1


static func _mark(_ts: TileSet, td: TileData, type: int) -> void:
	if td == null:
		return
	if type == -2:
		if td.has_meta(TERRAIN_META):
			td.remove_meta(TERRAIN_META)
		return
	var meta: Dictionary = td.get_meta(TERRAIN_META, {}) if td.has_meta(TERRAIN_META) else {}
	meta["type"] = type
	td.set_meta(TERRAIN_META, meta)


static func _type_of(td: TileData) -> int:
	if td == null or not td.has_meta(TERRAIN_META):
		return -2
	var meta = td.get_meta(TERRAIN_META)
	return int(meta.get("type", -2)) if typeof(meta) == TYPE_DICTIONARY else -2

#endregion


static func uninstall(ts: TileSet, terrain_id: int, previous: Array) -> void:
	if ts == null:
		return
	var id := source_of(ts, terrain_id)
	if id >= 0:
		ts.remove_source(id)
	var marks: Dictionary = ts.get_meta(SOURCE_META, {})
	marks.erase(terrain_id)
	if marks.is_empty():
		if ts.has_meta(SOURCE_META):
			ts.remove_meta(SOURCE_META)
	else:
		ts.set_meta(SOURCE_META, marks)

	for entry in previous:
		var src := ts.get_source(entry[0]) as TileSetAtlasSource
		if src != null and src.get_tile_at_coords(entry[1]) == entry[1]:
			_mark(ts, src.get_tile_data(entry[1], 0), terrain_id)
	ts.emit_changed()
