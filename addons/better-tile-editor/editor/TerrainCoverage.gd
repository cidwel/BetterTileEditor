@tool
extends RefCounted
## Which pieces a Match terrain has and lacks, and which a turned tile can stand in for. A piece
## is a mask of the neighbours it joins (1 << CellNeighbor).

const H := TileSetAtlasSource.TRANSFORM_FLIP_H
const V := TileSetAtlasSource.TRANSFORM_FLIP_V
const T := TileSetAtlasSource.TRANSFORM_TRANSPOSE

const SIDES: Array[int] = [
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_SIDE,
]
## Each corner with the two sides it lies between.
const CORNERS := {
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: [TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE],
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: [TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE],
	TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE],
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_RIGHT_SIDE],
}

enum Turns { MIRROR = 1, FLIP = 2, ROTATE = 4 }

## Tried in this order, so the gentlest turn that fits wins.
const FLAG_ORDER: Array[int] = [H, V, H | V, T | H, T | V, T, T | H | V]


static func flag_name(flags: int) -> String:
	match flags:
		H: return "mirrored"
		V: return "flipped"
		H | V: return "turned 180°"
		T | H: return "turned right"
		T | V: return "turned left"
		T: return "mirrored on the diagonal"
		T | H | V: return "mirrored on the other diagonal"
	return "as drawn"


## The flags a set of allowed turns (Turns bits) lets through.
static func allowed_flags(turns: int) -> Array[int]:
	var out: Array[int] = []
	for flags in FLAG_ORDER:
		var needs := 0
		if flags & T:
			needs |= Turns.ROTATE
		else:
			if flags & H:
				needs |= Turns.MIRROR
			if flags & V:
				needs |= Turns.FLIP
		if turns & needs == needs:
			out.append(flags)
	return out


## Why a terrain can't be read, or "" when it can.
static func unsupported(ts: TileSet, terrain_id: int) -> String:
	if ts == null:
		return "No tile set."
	if ts.tile_shape != TileSet.TILE_SHAPE_SQUARE:
		return "Only square tiles are read for now."
	var terrain := BetterTerrain.get_terrain(ts, terrain_id)
	if not terrain.valid or not terrain.type in [BetterTerrain.TerrainType.MATCH_TILES, BetterTerrain.TerrainType.MATCH_VERTICES]:
		return "Only Match tiles and Match vertices terrains have pieces to count."
	return ""


static func transform_mask(mask: int, flags: int) -> int:
	var out := 0
	for bit in 16:
		if mask & (1 << bit):
			out |= 1 << BetterTerrain.data.peering_bit_after_symmetry(bit, flags)
	return out


## The pieces a full set has: 16 for Match vertices or sides only, 47 for a blob.
static func required(type: int, with_corners: bool) -> Array[int]:
	var out: Array[int] = []
	if type == BetterTerrain.TerrainType.MATCH_VERTICES:
		var corners: Array = CORNERS.keys()
		for set_bits in 16:
			out.append(_mask_of(corners, set_bits))
		return out
	for side_bits in 16:
		var sides := _mask_of(SIDES, side_bits)
		if not with_corners:
			out.append(sides)
			continue
		var open := []
		for corner in CORNERS:
			if CORNERS[corner].all(func(side): return sides & (1 << side)):
				open.append(corner)
		for corner_bits in 1 << open.size():
			out.append(sides | _mask_of(open, corner_bits))
	return out


static func _mask_of(bits: Array, pick: int) -> int:
	var out := 0
	for i in bits.size():
		if pick & (1 << i):
			out |= 1 << bits[i]
	return out


## A piece as the set reads it: corners off the blob's grid (beside an open side) dropped.
static func normalize(mask: int, type: int, with_corners: bool) -> int:
	if type == BetterTerrain.TerrainType.MATCH_VERTICES:
		var out := 0
		for corner in CORNERS:
			out |= mask & (1 << corner)
		return out
	var sides := 0
	for side in SIDES:
		sides |= mask & (1 << side)
	if not with_corners:
		return sides
	var out := sides
	for corner in CORNERS:
		if mask & (1 << corner) and CORNERS[corner].all(func(side): return sides & (1 << side)):
			out |= 1 << corner
	return out


## The neighbours a tile joins: peering bits naming the terrain or one of its categories.
static func tile_mask(ts: TileSet, td: TileData, terrain_id: int) -> int:
	var joins := [terrain_id]
	joins.append_array(BetterTerrain.get_terrain(ts, terrain_id).get("categories", []))
	var out := 0
	for bit in 16:
		var types: Array = BetterTerrain.tile_peering_types(td, bit)
		if types.any(func(t): return t in joins):
			out |= 1 << bit
	return out


## The piece joined all round: the fill.
static func full_mask(type: int, with_corners: bool) -> int:
	var out := 0
	if type != BetterTerrain.TerrainType.MATCH_VERTICES:
		for side in SIDES:
			out |= 1 << side
	if with_corners:
		for corner in CORNERS:
			out |= 1 << corner
	return out


## Whether a tile's open bits face what is asked: nothing (no type, or empty), or the other
## terrain. A tile of the terrain bordering a third one belongs to neither set.
static func _faces(ts: TileSet, td: TileData, terrain_id: int, joined: int, other: int) -> bool:
	var type: int = BetterTerrain.get_terrain(ts, terrain_id).type
	for bit in BetterTerrain.data.get_terrain_peering_cells(ts, type):
		if joined & (1 << bit):
			continue
		# A corner beside an open side doesn't count in a blob, and often has no bits.
		if type == BetterTerrain.TerrainType.MATCH_TILES and CORNERS.has(bit) \
				and not CORNERS[bit].all(func(side): return joined & (1 << side)):
			continue
		var types: Array = BetterTerrain.tile_peering_types(td, bit)
		# A Match tiles corner with no bits isn't read (a terrain of sides only).
		if type == BetterTerrain.TerrainType.MATCH_TILES and CORNERS.has(bit) and types.is_empty():
			continue
		if other < 0:
			if types.any(func(t): return t >= 0):
				return false
		elif not other in types:
			return false
	return true


## The other terrains a terrain's tiles face across open bits, {id: tiles}, for transitions.
static func neighbours(ts: TileSet, terrain_id: int) -> Dictionary:
	var out := {}
	for s in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
		if src == null:
			continue
		for t in src.get_tiles_count():
			var td := src.get_tile_data(src.get_tile_id(t), 0)
			if BetterTerrain.get_tile_terrain_type(td) != terrain_id:
				continue
			var seen := {}
			for bit in 16:
				for other: int in BetterTerrain.tile_peering_types(td, bit):
					if other >= 0 and other != terrain_id:
						seen[other] = true
			for other: int in seen:
				out[other] = out.get(other, 0) + 1
	return out


## {error, type, required, pieces, missing, tiles, turns, fill, variety, upgrade, ...}; a source
## is {source_id, coord, alt, flags}. corners: read a sides-only terrain as a blob.
static func analyse(ts: TileSet, terrain_id: int, other := -1, corners := false) -> Dictionary:
	var error := unsupported(ts, terrain_id)
	if not error.is_empty():
		return {error = error}
	var type: int = BetterTerrain.get_terrain(ts, terrain_id).type
	var tiles := []
	var with_corners := type == BetterTerrain.TerrainType.MATCH_VERTICES
	for s in ts.get_source_count():
		var source_id := ts.get_source_id(s)
		var src := ts.get_source(source_id) as TileSetAtlasSource
		if src == null:
			continue
		for t in src.get_tiles_count():
			var coord := src.get_tile_id(t)
			for a in src.get_alternative_tiles_count(coord):
				var alt := src.get_alternative_tile_id(coord, a)
				var td := src.get_tile_data(coord, alt)
				if BetterTerrain.get_tile_terrain_type(td) != terrain_id:
					continue
				var mask := tile_mask(ts, td, terrain_id)
				if not _faces(ts, td, terrain_id, mask, other):
					continue
				tiles.append({source_id = source_id, coord = coord, alt = alt, mask = mask,
					symmetry = BetterTerrain.get_tile_symmetry_type(td),
					transforms = BetterTerrain.get_tile_transforms(td)})
				for corner in CORNERS:
					if mask & (1 << corner):
						with_corners = true
	var drawn_corners := with_corners
	var upgrade := []
	if corners and not with_corners and type == BetterTerrain.TerrainType.MATCH_TILES:
		with_corners = true
		for tile: Dictionary in tiles:
			var bits := []
			for corner in CORNERS:
				if CORNERS[corner].all(func(side): return tile.mask & (1 << side)):
					bits.append(corner)
			for bit: int in bits:
				tile.mask |= 1 << bit
			if not bits.is_empty():
				upgrade.append({source_id = tile.source_id, coord = tile.coord, alt = tile.alt, bits = bits})
	var fill := full_mask(type, with_corners)
	var pieces := {}
	var turns := []
	var variety := []
	var fill_tiles := []
	for tile: Dictionary in tiles:
		if tile.alt == 0 and normalize(tile.mask, type, with_corners) == fill:
			fill_tiles.append(tile)
		var flags_list: Array = BetterTerrain.data.symmetry_mapping[tile.symmetry].duplicate()
		for flags: int in tile.transforms:
			if not flags in flags_list:
				flags_list.append(flags)
		for flags: int in flags_list:
			var mask := normalize(transform_mask(tile.mask, flags), type, with_corners)
			var source := {source_id = tile.source_id, coord = tile.coord, alt = tile.alt, flags = flags}
			if not pieces.has(mask):
				pieces[mask] = []
			pieces[mask].append(source)
			if flags in tile.transforms:
				# Turns of a fill tile are variety, not a stand-in for a missing piece.
				(variety if mask == fill and normalize(tile.mask, type, with_corners) == fill else turns).append(source.merged({mask = mask}))
	var need := required(type, with_corners)
	var missing := need.filter(func(mask): return not pieces.has(mask))
	return {error = "", type = type, other = other, with_corners = with_corners, drawn_corners = drawn_corners, upgrade = upgrade, required = need,
		pieces = pieces, missing = missing, tiles = tiles, turns = turns, fill = fill,
		fill_tiles = fill_tiles, variety = variety}


## A turned piece that a drawn tile now covers too: it only competes with the drawing.
static func redundant(report: Dictionary, turn: Dictionary) -> bool:
	return (report.pieces[turn.mask] as Array).any(func(source): return source.flags == 0)


## For each missing piece an existing tile can stand in for: [{mask, source_id, coord, alt,
## flags}]. Tiles placed as drawn are tried first, then the order of FLAG_ORDER.
static func suggest(report: Dictionary, turns: int) -> Array:
	var out := []
	var flags_list := allowed_flags(turns)
	for mask: int in report.missing:
		var found := {}
		for flags in flags_list:
			for tile: Dictionary in report.tiles:
				if normalize(transform_mask(tile.mask, flags), report.type, report.with_corners) == mask:
					found = {mask = mask, source_id = tile.source_id, coord = tile.coord, alt = tile.alt, flags = flags}
					break
			if not found.is_empty():
				break
		if not found.is_empty():
			out.append(found)
	return out
